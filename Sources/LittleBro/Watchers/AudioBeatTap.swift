import AudioToolbox
import CoreAudio
import Foundation
import LittleBroCore
import QuartzCore

/// Which apps are making sound right now — Core Audio knows, no permission needed.
enum AudioProcesses {
    struct Process {
        let id: AudioObjectID
        let bundleID: String
        let isOutputting: Bool
    }

    static func all() -> [Process] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { id in
            Process(id: id, bundleID: string(id, kAudioProcessPropertyBundleID) ?? "",
                    isOutputting: (uint32(id, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0)
        }
    }

    /// Audio process objects whose bundle id starts with one of `prefixes` and that are playing sound.
    static func playing(prefixes: [String]) -> [AudioObjectID] {
        all().filter { p in p.isOutputting && prefixes.contains { p.bundleID.hasPrefix($0) } }.map(\.id)
    }

    /// Where the sound of a moment's source comes from (browsers play audio from helper processes).
    static func prefixes(for source: MomentWatcher.Source) -> [String] {
        switch source {
        case .app(let id): return [id]
        case .web(let browser):
            if browser.hasPrefix("com.apple.Safari") { return [browser, "com.apple.WebKit"] }
            return [browser]
        }
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let err = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0) }
        guard err == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func defaultOutputUID() -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr
        else { return nil }
        return string(device, kAudioDevicePropertyDeviceUID)
    }
}

/// Listens to one app's audio through a Core Audio process tap, only to find the beat.
/// Nothing is stored or sent anywhere: samples go straight into the beat detector.
/// The first use asks for macOS's "system audio recording" permission; if it's refused,
/// Little Bro simply grooves at a standard tempo.
final class AudioBeatTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var detector: BeatDetector?
    private let queue = DispatchQueue(label: "littlebro.beat", qos: .userInitiated)
    private var lastEstimate = 0.0
    private var mono: [Float] = []

    /// Called on the main thread with fresh tempo/phase measurements.
    var onEstimate: ((BeatDetector.Estimate) -> Void)?
    var isRunning: Bool { procID != nil }

    @discardableResult
    func start(processes: [AudioObjectID]) -> Bool {
        stop()
        guard !processes.isEmpty else { return false }
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        var err = AudioHardwareCreateProcessTap(description, &tap)
        guard err == noErr else {
            Log.info("beat tap: could not create tap (\(err)) — grooving at a standard tempo")
            return false
        }
        tapID = tap

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &format)
        let rate = format.mSampleRate > 0 ? format.mSampleRate : 48000
        let channels = Int(max(format.mChannelsPerFrame, 1))
        let interleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        let det = BeatDetector(sampleRate: rate)
        detector = det

        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Little Bro beat listener",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        if let output = AudioProcesses.defaultOutputUID() {
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = output
            aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: output]]
        }
        var agg = AudioObjectID(kAudioObjectUnknown)
        err = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &agg)
        guard err == noErr else {
            Log.info("beat tap: could not create aggregate device (\(err))")
            stop()
            return false
        }
        aggregateID = agg

        var proc: AudioDeviceIOProcID?
        err = AudioDeviceCreateIOProcIDWithBlock(&proc, agg, queue) { [weak self] _, input, _, _, _ in
            self?.consume(input, channels: channels, interleaved: interleaved)
        }
        guard err == noErr, let proc else {
            Log.info("beat tap: could not create IO proc (\(err))")
            stop()
            return false
        }
        procID = proc
        err = AudioDeviceStart(agg, proc)
        guard err == noErr else {
            Log.info("beat tap: could not start (\(err))")
            stop()
            return false
        }
        Log.info("beat tap: listening at \(Int(rate)) Hz, \(channels) ch")
        return true
    }

    func stop() {
        if let proc = procID {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
            procID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        queue.async { [weak self] in
            self?.detector = nil
            self?.lastEstimate = 0
        }
    }

    /// Runs on the audio queue.
    private func consume(_ input: UnsafePointer<AudioBufferList>, channels: Int, interleaved: Bool) {
        guard let detector else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        mono.removeAll(keepingCapacity: true)
        if interleaved, let buf = buffers.first, let data = buf.mData {
            let count = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            let ch = max(1, Int(buf.mNumberChannels))
            let frames = count / ch
            let p = data.assumingMemoryBound(to: Float.self)
            for f in 0..<frames {
                var s: Float = 0
                for c in 0..<ch { s += p[f * ch + c] }
                mono.append(s / Float(ch))
            }
        } else if let first = buffers.first, first.mData != nil {
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            mono = [Float](repeating: 0, count: frames)
            var used = 0
            for buf in buffers {
                guard let data = buf.mData else { continue }
                let p = data.assumingMemoryBound(to: Float.self)
                for f in 0..<min(frames, Int(buf.mDataByteSize) / MemoryLayout<Float>.size) { mono[f] += p[f] }
                used += 1
            }
            if used > 1 { for f in 0..<frames { mono[f] /= Float(used) } }
        }
        guard !mono.isEmpty else { return }
        detector.process(mono)
        let now = CACurrentMediaTime()
        if now - lastEstimate > 0.5, let e = detector.estimate() {
            lastEstimate = now
            DispatchQueue.main.async { [weak self] in self?.onEstimate?(e) }
        }
        _ = channels
    }
}
