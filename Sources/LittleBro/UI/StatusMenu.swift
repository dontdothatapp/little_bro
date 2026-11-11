import AppKit
import LittleBroCore
import ServiceManagement

/// The menu bar item: pending sessions, previews, toggles.
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let presenter: Presenter
    private let settings: Settings
    private let menu = NSMenu()

    init(presenter: Presenter, settings: Settings) {
        self.presenter = presenter
        self.settings = settings
        super.init()
        menu.delegate = self
        item.menu = menu
        item.button?.toolTip = "Little Bro"
        refreshIcon()
    }

    func refreshIcon() {
        let pending = !presenter.claude.tracker.items.isEmpty
        item.button?.image = Self.icon(alert: pending, paused: settings.isPaused)
    }

    static func icon(alert: Bool, paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            let eyeW: CGFloat = 4.2
            let eyeH: CGFloat = paused ? 1.6 : 7.4
            let y: CGFloat = paused ? 8.2 : 5.3
            for x in [4.6, 9.2] as [CGFloat] {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: eyeW, height: eyeH), xRadius: min(eyeW, eyeH) / 2,
                             yRadius: min(eyeW, eyeH) / 2).fill()
            }
            if alert {
                NSBezierPath(ovalIn: NSRect(x: 14.2, y: 12.6, width: 3.6, height: 3.6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let pending = presenter.claude.tracker.pending
        let header = NSMenuItem(title: pending.isEmpty ? "Little Bro · all quiet" : "Little Bro · \(pending.count) waiting",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for p in pending.prefix(8) {
            let card = presenter.claude.card(for: p, pendingCount: 1)
            let mi = NSMenuItem(title: "\(card.title) — \(p.kind.status)", action: #selector(openPending(_:)),
                                keyEquivalent: "")
            mi.target = self
            mi.representedObject = p.sessionId
            mi.image = NSImage(systemSymbolName: p.kind.isNeedsInput ? "exclamationmark.circle" : "checkmark.circle",
                               accessibilityDescription: nil)
            menu.addItem(mi)
        }
        menu.addItem(.separator())

        let preview = NSMenuItem(title: "Preview", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, key) in [("Finished", "done"), ("Finished (reminder)", "done-reminder"), ("Needs your input", "needs"),
                             ("Needs your input (reminder)", "needs-reminder"), ("YouTube peek", "peek")] {
            sub.addItem(previewItem(title, key))
        }
        sub.addItem(.separator())
        for v in IdleVariant.allCases {
            sub.addItem(previewItem("Idle visit: \(Self.name(v))", "idle-\(v.rawValue)"))
        }
        sub.addItem(.separator())
        for (title, key) in [("Spotify: vibing", "vibe"), ("Hackerman: shades", "hacker-shades"),
                             ("Hackerman: code rain", "hacker-rain"), ("Gaming: paddle ball", "game")] {
            sub.addItem(previewItem(title, key))
        }
        preview.submenu = sub
        menu.addItem(preview)
        menu.addItem(.separator())

        let moments = NSMenuItem(title: "App Moments", action: nil, keyEquivalent: "")
        let msub = NSMenu()
        for f in MomentFrequency.allCases {
            let mi = NSMenuItem(title: f.title, action: #selector(setFrequency(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = f.rawValue
            mi.state = settings.momentFrequency == f ? .on : .off
            msub.addItem(mi)
        }
        msub.addItem(.separator())
        for m in Moment.allCases {
            let mi = NSMenuItem(title: m.title, action: #selector(toggleMoment(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = m.rawValue
            mi.state = settings.momentEnabled(m) ? .on : .off
            msub.addItem(mi)
        }
        msub.addItem(.separator())
        let score = settings.paddleScore
        let scoreItem = NSMenuItem(title: "Paddle ball score: \(score.left) – \(score.right)", action: nil, keyEquivalent: "")
        scoreItem.isEnabled = false
        msub.addItem(scoreItem)
        let reset = NSMenuItem(title: "Reset Score", action: #selector(resetScore), keyEquivalent: "")
        reset.target = self
        msub.addItem(reset)
        moments.submenu = msub
        menu.addItem(moments)

        menu.addItem(toggle("Claude Code sessions", settings.claudeEnabled, #selector(toggleClaude)))
        menu.addItem(toggle("Idle visits", settings.idleEnabled, #selector(toggleIdle)))
        menu.addItem(toggle("YouTube peeks", settings.peeksEnabled, #selector(togglePeeks)))
        if settings.isPaused {
            let until = DateFormatter.localizedString(from: settings.pausedUntil ?? Date(), dateStyle: .none, timeStyle: .short)
            let mi = NSMenuItem(title: "Resume (paused until \(until))", action: #selector(resume), keyEquivalent: "")
            mi.target = self
            menu.addItem(mi)
        } else {
            let mi = NSMenuItem(title: "Pause for 1 Hour", action: #selector(pause), keyEquivalent: "")
            mi.target = self
            menu.addItem(mi)
        }
        menu.addItem(.separator())

        let hooks = ClaudeHooks.isInstalled()
        let hookItem = NSMenuItem(title: hooks ? "Connected to Claude Code" : "Connect to Claude Code…",
                                  action: #selector(toggleHooks), keyEquivalent: "")
        hookItem.target = self
        hookItem.state = hooks ? .on : .off
        if hooks { hookItem.toolTip = "Click to remove Little Bro's hooks from ~/.claude/settings.json" }
        menu.addItem(hookItem)
        menu.addItem(toggle("Launch at Login", SMAppService.mainApp.status == .enabled, #selector(toggleLogin)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Little Bro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    static func name(_ v: IdleVariant) -> String {
        switch v {
        case .lookAround: "Look around"
        case .sleepy: "Sleepy"
        case .hello: "Hello"
        case .curious: "Curious"
        case .shy: "Shy"
        }
    }

    private func previewItem(_ title: String, _ key: String) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: #selector(playPreview(_:)), keyEquivalent: "")
        mi.target = self
        mi.representedObject = key
        return mi
    }

    private func toggle(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self
        mi.state = on ? .on : .off
        return mi
    }

    @objc private func openPending(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String, let item = presenter.claude.tracker.items[sid] else { return }
        presenter.open(item)
    }

    @objc private func playPreview(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        // Let the menu close first so the animation isn't hidden behind it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.presenter.preview(key) }
    }

    @objc private func setFrequency(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let f = MomentFrequency(rawValue: raw) else { return }
        settings.momentFrequency = f
    }

    @objc private func toggleMoment(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = Moment(rawValue: raw) else { return }
        settings.setMoment(m, enabled: !settings.momentEnabled(m))
    }

    @objc private func resetScore() { settings.paddleScore = (0, 0) }

    @objc private func toggleClaude() { settings.claudeEnabled.toggle() }
    @objc private func toggleIdle() { settings.idleEnabled.toggle() }
    @objc private func togglePeeks() { settings.peeksEnabled.toggle() }
    @objc private func pause() { presenter.pause(for: 3600); refreshIcon() }
    @objc private func resume() { presenter.resume(); refreshIcon() }

    @objc private func toggleHooks() {
        do {
            if ClaudeHooks.isInstalled() { try ClaudeHooks.uninstall() } else { try ClaudeHooks.install() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't update ~/.claude/settings.json"
            alert.informativeText = "\(error)"
            alert.runModal()
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Log.info("login item: \(error)")
        }
    }
}

enum Previews {
    static func act(_ key: String) -> Act? {
        let done = Card(kind: .done, status: "Finished", title: "Mac notch companion app",
                        recap: "This is a preview of a finished session. Hover me to read the recap; click to open it.")
        let needs = Card(kind: .needsInput, status: "Needs your OK", title: "Mac notch companion app")
        switch key {
        case "done": return .card(done, intro: true)
        case "done-reminder": return .card(done, intro: false)
        case "needs": return .card(needs, intro: true)
        case "needs-reminder": return .card(needs, intro: false)
        case "peek": return .peek
        case "vibe": return .vibe
        case "hacker-shades": return .hacker(.shades)
        case "hacker-rain": return .hacker(.rain)
        case "game": return .game(left: 0, right: 0)
        default:
            if key.hasPrefix("idle-"), let v = IdleVariant(rawValue: String(key.dropFirst(5))) { return .idle(v) }
            return nil
        }
    }
}
