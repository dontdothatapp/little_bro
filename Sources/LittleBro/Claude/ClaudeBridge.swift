import AppKit
import LittleBroCore

/// Everything Claude-related: the hook inbox, the desktop app's session files,
/// "has the user seen it?" and opening a session.
final class ClaudeBridge {
    let tracker = AttentionTracker()
    let transcripts = TranscriptTasks()
    let sessions = DesktopSessionIndex(root: AppPaths.desktopSessions)
    var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    static let claudeBundleId = "com.anthropic.claudefordesktop"

    func start() {
        try? FileManager.default.createDirectory(at: AppPaths.inbox, withIntermediateDirectories: true)
        ClaudeHooks.ensureScript()
        drainInbox(startup: true)
        fd = Darwin.open(AppPaths.inbox.path, O_EVTONLY)
        guard fd >= 0 else {
            Log.info("could not watch inbox")
            return
        }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .link],
                                                          queue: .main)
        s.setEventHandler { [weak self] in self?.drainInbox(startup: false) }
        s.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { Darwin.close(fd) }
        }
        s.resume()
        source = s
    }

    private func drainInbox(startup: Bool) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: AppPaths.inbox.path) else { return }
        var events: [HookEvent] = []
        for name in names.sorted() where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let url = AppPaths.inbox.appendingPathComponent(name)
            let mtime = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
            if let data = try? Data(contentsOf: url), let e = HookEvent.parse(data, receivedAt: mtime) {
                events.append(e)
            }
            try? fm.removeItem(at: url)
        }
        // Clean up stale temp files left by an interrupted hook.
        for name in names where name.hasPrefix(".") && name.hasSuffix(".tmp") {
            let url = AppPaths.inbox.appendingPathComponent(name)
            if let m = try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, Date().timeIntervalSince(m) > 60 {
                try? fm.removeItem(at: url)
            }
        }
        guard !events.isEmpty else { return }
        var changed = false
        for e in events.sorted(by: { $0.receivedAt < $1.receivedAt }) {
            if startup && Date().timeIntervalSince(e.receivedAt) > 10 * 60 { continue }
            // Sessions spawned by another session report to their parent; only the parent notifies.
            let child = sessions.session(forCliId: e.sessionId)?.isChild ?? false
            transcripts.note(session: e.sessionId, transcript: e.transcriptPath)
            // A turn can end while background tasks or helper sessions are still working:
            // that isn't "finished" yet.
            let busy = e.name == "Stop" && !child && isBusy(e.sessionId, logging: true)
            let change = tracker.handle(e, raiseAttention: !child, busy: busy)
            if child && ["Stop", "StopFailure", "PermissionRequest"].contains(e.name) {
                Log.info("hook \(e.name) from helper session \(e.sessionId.prefix(8)) → ignored (its parent will notify)")
            }
            if change != .none {
                changed = true
                Log.info("hook \(e.name) \(e.toolName ?? "") \(e.sessionId.prefix(8)) → \(change)")
            }
        }
        if changed { onChange?() }
    }

    /// Drops attention items the user has already dealt with. Returns true if anything changed.
    @discardableResult
    func refreshSeen(now: Date, claudeFrontmost: Bool, userActive: Bool) -> Bool {
        guard !tracker.items.isEmpty else { return false }
        sessions.refresh()
        let mostRecent = sessions.mostRecentlyFocused
        var changed = false
        for item in tracker.pending {
            guard let s = sessions.session(forCliId: item.sessionId) else { continue }
            let sinceMs = item.since.timeIntervalSince1970 * 1000
            var reason: String?
            if s.isArchived {
                reason = "archived"
            } else if s.lastFocusedAt > sinceMs + 300 {
                reason = "opened in Claude"
            } else if claudeFrontmost, userActive, mostRecent?.localId == s.localId,
                      now.timeIntervalSince(item.since) > 0.8 {
                reason = "visible in Claude"
            }
            if let reason {
                tracker.clear(item.sessionId)
                Log.info("seen \(item.sessionId.prefix(8)): \(reason)")
                changed = true
            }
        }
        return changed
    }

    func card(for item: AttentionItem, pendingCount: Int) -> Card {
        let s = sessions.session(forCliId: item.sessionId)
        let fallback = item.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude Code"
        let title = (s?.title?.isEmpty == false ? s?.title : nil) ?? fallback
        let badge = pendingCount > 1 ? "+\(pendingCount - 1)" : nil
        let recap = item.kind == .done ? s?.recap : nil
        return Card(kind: item.kind.isNeedsInput || item.kind == .failed ? .needsInput : .done,
                    status: item.kind.status, title: title, badge: badge, recap: recap)
    }

    func open(_ item: AttentionItem) {
        sessions.refresh(force: true)
        if let url = sessions.session(forCliId: item.sessionId)?.openURL {
            Log.info("open \(url.absoluteString)")
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.claudeBundleId) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
        tracker.clear(item.sessionId)
    }

    /// Background tasks still running in this session, or helper sessions it spawned still working.
    func isBusy(_ sid: String, logging: Bool = false) -> Bool {
        let tasks = transcripts.running(sid)
        if !tasks.isEmpty {
            if logging { Log.info("hold finish of \(sid.prefix(8)): \(tasks.count) background task(s) running") }
            return true
        }
        guard let me = sessions.session(forCliId: sid) else { return false }
        for other in tracker.workingSessions(now: Date()) where other != sid {
            if let root = sessions.root(of: sessions.session(forCliId: other)), root.localId == me.localId {
                if logging { Log.info("hold finish of \(sid.prefix(8)): a helper session is still working") }
                return true
            }
        }
        return false
    }

    /// Lets held finishes through once their background work is really done.
    @discardableResult
    func releaseHeld(now: Date) -> Bool {
        guard !tracker.held.isEmpty else { return false }
        let changes = tracker.releaseHeld(now: now, isBusy: { [weak self] in self?.isBusy($0) ?? false })
        for c in changes { Log.info("released held finish → \(c)") }
        return !changes.isEmpty
    }

    /// Whether the user opened this session in Claude after `date`.
    func userLooked(at cliId: String, since date: Date) -> Bool {
        guard let s = sessions.session(forCliId: cliId) else { return false }
        return s.lastFocusedAt > date.timeIntervalSince1970 * 1000 + 300
    }

    /// The top-level session a session belongs to (itself, unless it was spawned by another).
    func rootSession(forCliId id: String) -> DesktopSession? {
        sessions.root(of: sessions.session(forCliId: id))
    }

    func openSession(localId: String) {
        var c = URLComponents()
        c.scheme = "claude"
        c.host = "code"
        c.path = "/continue"
        c.queryItems = [URLQueryItem(name: "session", value: localId)]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    /// Opens a session by its Claude Code id (falls back to just activating Claude).
    func openSession(cliId: String) {
        sessions.refresh(force: true)
        if let url = sessions.session(forCliId: cliId)?.openURL {
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.claudeBundleId) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static var claudeIsFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == claudeBundleId
    }
}

/// Reads the desktop app's per-session JSON files, re-parsing only files that changed.
final class DesktopSessionIndex {
    private let root: URL
    private var byPath: [String: (mtime: Date, session: DesktopSession)] = [:]
    private var byCli: [String: DesktopSession] = [:]
    private var lastRefresh = Date.distantPast

    init(root: URL) { self.root = root }

    func refresh(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastRefresh) > 1.0 else { return }
        lastRefresh = Date()
        let fm = FileManager.default
        var alive = Set<String>()
        guard let accounts = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        for account in accounts {
            guard let orgs = try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: nil) else { continue }
            for org in orgs {
                guard let files = try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: [.contentModificationDateKey])
                else { continue }
                for f in files where f.lastPathComponent.hasPrefix("local_") && f.pathExtension == "json" {
                    alive.insert(f.path)
                    let mtime = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    if let cached = byPath[f.path], cached.mtime == mtime { continue }
                    if let data = try? Data(contentsOf: f), let s = DesktopSession.parse(data) {
                        byPath[f.path] = (mtime, s)
                    }
                }
            }
        }
        byPath = byPath.filter { alive.contains($0.key) }
        var map: [String: DesktopSession] = [:]
        for (_, entry) in byPath {
            for id in entry.session.cliIds { map[id] = entry.session }
        }
        byCli = map
    }

    func session(forCliId id: String) -> DesktopSession? {
        if byCli[id] == nil { refresh() }
        return byCli[id]
    }

    func session(forLocalId id: String) -> DesktopSession? {
        byPath.values.first { $0.session.localId == id }?.session
    }

    /// Follows `parentLocalId` up to the top-level session.
    func root(of session: DesktopSession?) -> DesktopSession? {
        var current = session
        var hops = 0
        while let parent = current?.parentLocalId, hops < 8, let p = self.session(forLocalId: parent) {
            current = p
            hops += 1
        }
        return current
    }

    var mostRecentlyFocused: DesktopSession? {
        byPath.values.map(\.session).filter { !$0.isArchived }.max { $0.lastFocusedAt < $1.lastFocusedAt }
    }
}

/// Installs Little Bro's hooks into `~/.claude/settings.json`.
enum ClaudeHooks {
    static var command: String { "'\(AppPaths.hookScript.path)'" }

    static func ensureScript() {
        let fm = FileManager.default
        let url = AppPaths.hookScript
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = HookInstaller.script(inbox: AppPaths.inbox.path)
        if (try? String(contentsOf: url, encoding: .utf8)) != script {
            try? script.write(to: url, atomically: true, encoding: .utf8)
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    enum Failure: Error, CustomStringConvertible {
        case unreadable(String)
        var description: String {
            switch self { case .unreadable(let s): s }
        }
    }

    static func readSettings() throws -> [String: Any] {
        let url = AppPaths.claudeSettings
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadable("settings.json is not a JSON object")
        }
        return obj
    }

    static func isInstalled() -> Bool {
        guard let s = try? readSettings() else { return false }
        return HookInstaller.isInstalled(in: s)
    }

    static func install() throws {
        ensureScript()
        let settings = try readSettings()
        backupOnce()
        try write(HookInstaller.install(into: settings, command: command))
        Log.info("installed Claude Code hooks")
    }

    static func uninstall() throws {
        let settings = try readSettings()
        try write(HookInstaller.uninstall(from: settings))
        Log.info("removed Claude Code hooks")
    }

    private static func backupOnce() {
        let src = AppPaths.claudeSettings
        let dst = src.deletingLastPathComponent().appendingPathComponent("settings.json.before-littlebro")
        let fm = FileManager.default
        if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: dst.path) {
            try? fm.copyItem(at: src, to: dst)
        }
    }

    private static func write(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: AppPaths.claudeSettings.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: AppPaths.claudeSettings, options: .atomic)
    }
}
