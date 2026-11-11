import AppKit
import CoreAudio
import IOKit
import IOKit.hid
import IOKit.ps
import LittleBroCore

// MARK: - Power: charger plugged in, battery low

/// Watches the power source. No permission needed.
final class PowerWatcher {
    var onCharging: (() -> Void)?
    var onLow: (() -> Void)?
    static let lowThreshold = 15

    private var source: CFRunLoopSource?
    private var onAC: Bool?
    private var warnedLow = false

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PowerWatcher>.fromOpaque(ctx).takeUnretainedValue().changed()
        }, context)?.takeRetainedValue() else { return }
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        let s = state()
        onAC = s.onAC
        warnedLow = (s.percent ?? 100) <= Self.lowThreshold
    }

    private func state() -> (onAC: Bool, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (true, nil) }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let ac = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 100
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            return (ac, max > 0 ? cur * 100 / max : nil)
        }
        return (true, nil) // no battery (desktop Mac)
    }

    private func changed() {
        let s = state()
        if let was = onAC, !was, s.onAC {
            Log.info("power: charger plugged in")
            warnedLow = false
            onCharging?()
        }
        if s.onAC { warnedLow = false }
        if !s.onAC, let p = s.percent, p <= Self.lowThreshold, !warnedLow {
            warnedLow = true
            Log.info("power: battery low (\(p)%)")
            onLow?()
        }
        onAC = s.onAC
    }
}

// MARK: - Downloads

/// Notices new finished files in ~/Downloads (partial browser downloads are ignored).
/// macOS asks once for access to the Downloads folder.
final class DownloadsWatcher {
    var onDownloaded: (([URL]) -> Void)?

    private let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private var known = Set<String>()
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pending: DispatchWorkItem?
    static let partialSuffixes = [".crdownload", ".download", ".part", ".partial", ".tmp", ".opdownload", ".icloud"]

    func start() {
        known = Set(listing())
        fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.info("downloads: can't watch \(folder.path) (no access?)")
            return
        }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .link],
                                                          queue: .main)
        s.setEventHandler { [weak self] in self?.scheduleScan() }
        s.setCancelHandler { [weak self] in if let fd = self?.fd, fd >= 0 { Darwin.close(fd) } }
        s.resume()
        source = s
    }

    private func listing() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private func scheduleScan() {
        pending?.cancel()
        // Wait for things to settle (browsers rename the finished file at the very end).
        let item = DispatchWorkItem { [weak self] in self?.scan() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    private func scan() {
        let now = Set(listing())
        let added = now.subtracting(known)
        known = now
        let fresh = added.filter { name in
            guard !name.hasPrefix("."), !Self.partialSuffixes.contains(where: { name.lowercased().hasSuffix($0) })
            else { return false }
            let url = folder.appendingPathComponent(name)
            // Only things that just arrived, not files moved in from elsewhere long ago.
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return Date().timeIntervalSince(created) < 15 * 60
        }
        guard !fresh.isEmpty else { return }
        Log.info("downloads: \(fresh.count) new")
        onDownloaded?(fresh.sorted().map { folder.appendingPathComponent($0) })
    }
}

// MARK: - Sound: mute / unmute

/// Watches the default output device's mute switch. No permission needed.
final class SoundWatcher {
    var onMute: ((Bool) -> Void)?
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var muted: Bool?
    private var muteListener: AudioObjectPropertyListenerBlock?
    private var defaultListener: AudioObjectPropertyListenerBlock?

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.attachToDefaultDevice() }
        }
        defaultListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main, block)
        attachToDefaultDevice()
    }

    private func attachToDefaultDevice() {
        if device != kAudioObjectUnknown, let l = muteListener {
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, l)
        }
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, 0, nil,
                                         &size, &id) == noErr else { return }
        device = id
        muted = readMute()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.muteChanged() }
        muteListener = block
        AudioObjectAddPropertyListenerBlock(id, &Self.muteAddress, .main, block)
    }

    private func readMute() -> Bool? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &Self.muteAddress, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private func muteChanged() {
        guard let now = readMute(), now != muted else { return }
        muted = now
        Log.info("sound: \(now ? "muted" : "unmuted")")
        onMute?(now)
    }
}

// MARK: - Devices: Bluetooth headphones, controllers, mice, keyboards

/// Notices Bluetooth devices connecting, without the Bluetooth permission: headphones
/// appear as new Core Audio devices (with their names); input devices as new HID
/// services in the I/O Registry (with their usage and product name).
final class DeviceWatcher {
    var onConnect: ((DeviceKind, String) -> Void)?

    private var audioDevices = Set<AudioObjectID>()
    private var audioListener: AudioObjectPropertyListenerBlock?
    private var notifyPort: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private var lastAnnounced: [String: Date] = [:]

    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        audioDevices = Set(currentAudioDevices())
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.audioDevicesChanged() }
        }
        audioListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.devicesAddress, .main, block)
        startHID()
    }

    // Audio

    private func currentAudioDevices() -> [AudioObjectID] {
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &Self.devicesAddress, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &Self.devicesAddress, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func audioDevicesChanged() {
        let now = Set(currentAudioDevices())
        let added = now.subtracting(audioDevices)
        audioDevices = now
        for id in added {
            guard isBluetooth(id), hasOutput(id), let name = AudioProcesses.string(id, kAudioObjectPropertyName) else {
                continue
            }
            announce(DeviceClassifier.audioKind(name: name), name: DeviceClassifier.displayName(name))
        }
    }

    private func isBluetooth(_ id: AudioObjectID) -> Bool {
        let t = AudioProcesses.uint32(id, kAudioDevicePropertyTransportType) ?? 0
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    private func hasOutput(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    // HID

    private func startHID() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        let matching = IOServiceMatching(kIOHIDDeviceKey)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matching, { ctx, iterator in
            guard let ctx else { return }
            Unmanaged<DeviceWatcher>.fromOpaque(ctx).takeUnretainedValue().hidAdded(iterator, announce: true)
        }, context, &iterator)
        guard result == KERN_SUCCESS else { return }
        // Drain what's already connected (arms the notification) without announcing it.
        hidAdded(iterator, announce: false)
    }

    private func hidAdded(_ iterator: io_iterator_t, announce shouldAnnounce: Bool) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard shouldAnnounce else { continue }
            func prop(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            let transport = (prop(kIOHIDTransportKey) as? String ?? "").lowercased()
            guard transport.contains("bluetooth") else { continue }
            let product = prop(kIOHIDProductKey) as? String ?? ""
            let page = prop(kIOHIDPrimaryUsagePageKey) as? Int ?? 0
            let usage = prop(kIOHIDPrimaryUsageKey) as? Int ?? 0
            guard let kind = DeviceClassifier.hidKind(usagePage: page, usage: usage, product: product) else { continue }
            announce(kind, name: product.isEmpty ? "Bluetooth device" : product)
        }
    }

    // Shared

    private func announce(_ kind: DeviceKind, name: String) {
        // One device often shows up as several services; and flaky links reconnect. Ten minutes' grace.
        if let last = lastAnnounced[name], Date().timeIntervalSince(last) < 10 * 60 { return }
        lastAnnounced[name] = Date()
        Log.info("device connected: \(kind.rawValue) \(name)")
        onConnect?(kind, name)
    }
}
