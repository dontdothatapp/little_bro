import AppKit
import Darwin
import IOKit.pwr_mgt

/// "Is the user watching YouTube right now?"
///
/// 1. Cheap, permission-free: is a browser process holding a "keep the display awake"
///    power assertion? Browsers take one while a video plays.
/// 2. Only then ask the browser (AppleScript) whether a front tab is on YouTube. If macOS
///    automation permission is refused, any playing browser video counts.
final class VideoWatcher {
    private(set) var isWatching = false
    private(set) var videoPlaying = false
    private var lastURLCheck = Date.distantPast
    private var urlSaysYouTube = false
    private var automationDenied = false
    private let queue = DispatchQueue(label: "littlebro.video", qos: .utility)
    private var timer: Timer?
    private var busy = false

    static let chromium = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.brave.Browser",
                           "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
                           "org.chromium.Chromium", "com.operasoftware.Opera"]
    static let safari = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static let processHints = ["Google Chrome", "Safari", "WebKit", "Brave", "Microsoft Edge", "Arc.app", "Vivaldi",
                               "Chromium", "Opera", "Firefox", "Orion", "Zen"]

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.poll() }
        timer?.tolerance = 1
        poll()
    }

    private func poll() {
        guard !busy else { return }
        busy = true
        let runningIds = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        queue.async { [weak self] in
            guard let self else { return }
            let playing = Self.browserHoldsDisplayAssertion()
            var youtube = self.urlSaysYouTube
            if playing, Date().timeIntervalSince(self.lastURLCheck) > 20 {
                self.lastURLCheck = Date()
                let result = Self.frontTabsAreYouTube(running: runningIds)
                switch result {
                case .some(let yes):
                    youtube = yes
                    self.automationDenied = false
                case .none:
                    self.automationDenied = true
                }
            }
            if !playing { self.lastURLCheck = .distantPast }
            DispatchQueue.main.async {
                self.videoPlaying = playing
                self.urlSaysYouTube = youtube
                let watching = playing && (youtube || self.automationDenied)
                if watching != self.isWatching { Log.info("video watching: \(watching) (assertion \(playing), url \(youtube))") }
                self.isWatching = watching
                self.busy = false
            }
        }
    }

    static func browserHoldsDisplayAssertion() -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let dict = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        for (pid, assertions) in dict {
            let display = assertions.contains { a in
                let type = a["AssertType"] as? String ?? ""
                return type == "PreventUserIdleDisplaySleep" || type == "NoDisplaySleepAssertion"
            }
            guard display else { continue }
            let path = processPath(pid.int32Value)
            if processHints.contains(where: { path.contains($0) }) { return true }
        }
        return false
    }

    private static func processPath(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard n > 0 else { return "" }
        return String(cString: buffer)
    }

    /// true/false when a browser answered; nil when automation is not allowed (or nothing answered).
    private static func frontTabsAreYouTube(running: Set<String>) -> Bool? {
        var answered = false
        var denied = false
        for id in chromium where running.contains(id) {
            switch AppleScript.run("tell application id \"\(id)\" to get URL of active tab of every window") {
            case .success(let out):
                answered = true
                if isYouTube(out) { return true }
            case .denied: denied = true
            case .failed: break
            }
        }
        for id in safari where running.contains(id) {
            switch AppleScript.run("tell application id \"\(id)\" to get URL of current tab of every window") {
            case .success(let out):
                answered = true
                if isYouTube(out) { return true }
            case .denied: denied = true
            case .failed: break
            }
        }
        if answered { return false }
        return denied ? nil : false
    }

    static func isYouTube(_ urls: String) -> Bool {
        let s = urls.lowercased()
        if s.contains("music.youtube.com") && !s.contains("www.youtube.com") { return false }
        return s.contains("youtube.com/watch") || s.contains("youtube.com/shorts") || s.contains("youtube.com/live")
            || s.contains("youtube.com/embed") || s.contains("youtu.be/") || s.contains("youtube-nocookie.com")
    }
}
