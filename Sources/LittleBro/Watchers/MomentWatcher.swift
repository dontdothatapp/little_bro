import AppKit
import LittleBroCore

/// Notices when you open (switch to) an app or site that has a moment:
/// Spotify, terminals and IDEs, game stores and games.
final class MomentWatcher {
    enum Source: Equatable {
        /// A native app, by bundle id.
        case app(String)
        /// A browser tab; the browser's bundle id.
        case web(String)
    }

    /// Called on the main thread.
    var onMoment: ((Moment, Source) -> Void)?
    /// Whether a moment could play right now (enabled and not on cooldown). Polling browsers
    /// is skipped entirely when no web moment could play.
    var isWanted: ((Moment) -> Bool)?

    private var timer: Timer?
    private var lastTabMoment: (browser: String, moment: Moment?)?
    private var polling = false
    private let queue = DispatchQueue(label: "littlebro.moments", qos: .utility)
    private static let browsers = Set(VideoWatcher.chromium + VideoWatcher.safari)

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.activated(app)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.pollFrontTab() }
        timer?.tolerance = 0.8
    }

    private func activated(_ app: NSRunningApplication) {
        lastTabMoment = nil
        let category = app.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["LSApplicationCategoryType"] as? String }
        guard let id = app.bundleIdentifier ?? app.bundleURL?.path,
              let m = MomentCatalog.moment(bundleId: app.bundleIdentifier, bundlePath: app.bundleURL?.path,
                                           category: category) else {
            if let id = app.bundleIdentifier, Self.browsers.contains(id) { pollFrontTab() }
            return
        }
        Log.info("moment \(m.rawValue) from app \(id)")
        onMoment?(m, .app(id))
    }

    /// While a browser is in front, check its front tab now and then (only if a web moment could play).
    private func pollFrontTab() {
        guard !polling, let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              Self.browsers.contains(front) else { return }
        guard MomentCatalog.webMoments.contains(where: { isWanted?($0) == true }) else { return }
        polling = true
        let script = VideoWatcher.safari.contains(front)
            ? "tell application id \"\(front)\" to get URL of current tab of front window"
            : "tell application id \"\(front)\" to get URL of active tab of front window"
        queue.async { [weak self] in
            let result = AppleScript.run(script)
            DispatchQueue.main.async {
                guard let self else { return }
                self.polling = false
                guard case .success(let url) = result else { return }
                let m = MomentCatalog.moment(url: url)
                // Fire when the tab *becomes* a match, not on every poll while it stays one.
                if let last = self.lastTabMoment, last.browser == front, last.moment == m { return }
                self.lastTabMoment = (front, m)
                if let m {
                    Log.info("moment \(m.rawValue) from tab in \(front)")
                    self.onMoment?(m, .web(front))
                }
            }
        }
    }
}
