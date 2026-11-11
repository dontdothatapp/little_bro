import AppKit
import LittleBroCore

/// Decides what Little Bro does and when: Claude cards first, then YouTube peeks,
/// then idle visits. Owns the panel and the frame loop.
final class Presenter {
    let director = Director()
    let panel = NotchPanel()
    let view: CharacterView
    let claude = ClaudeBridge()
    let activity = ActivityMonitor()
    let video = VideoWatcher()
    let settings: Settings

    private var idlePlanner = IdleVisitPlanner()
    private var peekPlanner = PeekPlanner()
    private var picker = VariantPicker()
    private var rng = SeededRandom(seed: UInt64(Date().timeIntervalSince1970 * 1000))
    private var timer: Timer?
    private var cardSession: String?
    private let launchedAt = CACurrentMediaTime()

    /// Re-show an unseen session this long after it last tucked away.
    static let reminderInterval: TimeInterval = 60
    /// "Needs you" must last this long before it shows (auto-approved prompts vanish sooner).
    static let settle: TimeInterval = 1.2

    var onStateChange: (() -> Void)?
    /// Debug: treat the user as present (for testing while away from the keyboard).
    var forcePresentUntil: Date?

    init(settings: Settings) {
        self.settings = settings
        view = CharacterView(director: director)
        panel.contentView = view
        director.onHidden = { [weak self] act in self?.actEnded(act) }
        view.onClick = { [weak self] in self?.clicked() }
        view.onRightClick = { [weak self] e in self?.rightClicked(e) }
        view.onHidden = { [weak self] in self?.tuckedAway() }
        claude.onChange = { [weak self] in
            self?.tick()
            self?.onStateChange?()
        }
    }

    func start() {
        warmUp()
        claude.start()
        video.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.1
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.tick() }
    }

    /// Loads fonts and exercises the path code once, so the first real frame doesn't hitch.
    private func warmUp() {
        let raster = TextRasterizer.shared
        for style in [TextStyle.status, .title, .badge, .recap] {
            _ = raster.lineHeight(style)
            _ = raster.render("Warm up 0123", style: style, color: .white, maxWidth: 200, maxLines: 2, scale: 2)
        }
        let scratch = Director(seed: 1)
        scratch.play(.card(Card(kind: .needsInput, status: "x", title: "y"), intro: true))
        for _ in 0..<90 { _ = scratch.update(dt: 1.0 / 60, input: FrameInput()) }
    }

    // MARK: - Showing things

    /// Plays an act, moving the panel to the screen with the cursor if Little Bro is tucked away.
    func present(_ act: Act) {
        if director.isHidden || !view.isRunning {
            guard let screen = NSScreen.withMouse else { return }
            panel.place(on: screen)
            view.screenFrame = screen.frame
            director.character.profile = screen.notchProfile
            panel.orderFrontRegardless()
            view.start()
        }
        Log.info("play \(describe(act))")
        director.play(act)
    }

    private func describe(_ act: Act) -> String {
        switch act {
        case .card(let c, let intro): return "card \(c.kind) '\(c.title)' intro=\(intro)"
        case .idle(let v): return "idle \(v.rawValue)"
        case .peek: return "peek"
        }
    }

    private func tuckedAway() {
        Log.info("hidden · \(view.stats.summary)")
        panel.orderOut(nil)
    }

    private func actEnded(_ act: Act?) {
        if let sid = cardSession, act?.isCard == true {
            // Reminder interval counts from when it went away.
            claude.tracker.markShown(sid, at: Date())
        }
        if act?.isCard == true || act == nil { cardSession = nil }
        DispatchQueue.main.async { [weak self] in self?.tick() }
    }

    // MARK: - The loop

    func tick() {
        let now = Date()
        let mono = CACurrentMediaTime() - launchedAt
        let userHere = activity.userPresent || (forcePresentUntil ?? .distantPast) > now

        if claude.refreshSeen(now: now, claudeFrontmost: ClaudeBridge.claudeIsFrontmost, userActive: activity.inputIdle < 20) {
            onStateChange?()
        }

        // The card on screen belongs to a session that no longer needs anything: tuck away.
        if let sid = cardSession, sid != Self.setupSession, claude.tracker.items[sid] == nil,
           director.act?.isCard == true {
            director.retract()
        }
        // Keep the badge count and title fresh.
        if let sid = cardSession, let item = claude.tracker.items[sid], director.act?.isCard == true {
            director.updateCard(claude.card(for: item, pendingCount: claude.tracker.pending.count))
        }

        if settings.isPaused { return }

        // Not connected to Claude Code yet: offer it (again) once someone is here.
        if settings.claudeEnabled, !settings.setupCardDismissed, userHere, director.isHidden,
           now.timeIntervalSince(lastSetupOffer) > 20 * 60, !ClaudeHooks.isInstalled() {
            offerSetup()
            return
        }

        if settings.claudeEnabled, userHere,
           let item = claude.tracker.due(now: now, settle: Self.settle, interval: Self.reminderInterval),
           item.sessionId != cardSession {
            if case .card(let showing, _)? = director.act {
                // A card is already out: only a "needs you" may cut in front of a "done".
                if item.kind.isNeedsInput && showing.kind == .done {
                    showCard(item)
                    return
                }
            } else {
                // Nothing, or an idle visit / peek, is out: the card takes over (morphing if visible).
                showCard(item)
                return
            }
        }

        let ambientBlocked = director.act != nil || director.isRetracting || !activity.screenAvailable
        if settings.peeksEnabled,
           peekPlanner.update(now: mono, watching: video.isWatching, blocked: ambientBlocked, rng: &rng) {
            present(.peek)
            return
        }
        if settings.idleEnabled,
           idlePlanner.update(now: mono, mouseIdle: activity.mouseIdle, inputIdle: activity.inputIdle,
                              blocked: ambientBlocked || video.videoPlaying, rng: &rng) {
            present(.idle(picker.next(&rng)))
        }
    }

    private func showCard(_ item: AttentionItem) {
        let card = claude.card(for: item, pendingCount: claude.tracker.pending.count)
        let intro = item.lastShownAt == nil
        cardSession = item.sessionId
        claude.tracker.markShown(item.sessionId, at: Date())
        present(.card(card, intro: intro))
        onStateChange?()
    }

    // MARK: - Interaction

    static let setupSession = "littlebro.setup"

    /// A one-time card asking to connect to Claude Code. Clicking it is the consent.
    private var lastSetupOffer = Date.distantPast

    func offerSetup() {
        lastSetupOffer = Date()
        cardSession = Self.setupSession
        present(.card(Card(kind: .done, status: "Hi! One-time setup", title: "Click to connect me to Claude Code",
                           recap: "Adds a tiny hook to ~/.claude/settings.json so I know when a session finishes or needs you. Right-click to dismiss."),
                      intro: true))
    }

    private func clicked() {
        guard let act = director.act else { return }
        if cardSession == Self.setupSession {
            cardSession = nil
            do {
                try ClaudeHooks.install()
                settings.setupCardDismissed = true
            } catch {
                Log.info("hook install failed: \(error)")
            }
            director.acknowledge()
            onStateChange?()
            return
        }
        if act.isCard, let sid = cardSession, let item = claude.tracker.items[sid] {
            claude.open(item)
            cardSession = nil
            onStateChange?()
        }
        director.acknowledge()
    }

    private func rightClicked(_ event: NSEvent) {
        let menu = NSMenu()
        if director.act?.isCard == true, cardSession != nil {
            menu.addItem(withTitle: "Open Session", action: #selector(MenuTarget.openCurrent), keyEquivalent: "")
            menu.addItem(withTitle: "Dismiss", action: #selector(MenuTarget.dismissCurrent), keyEquivalent: "")
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Pause for 1 Hour", action: #selector(MenuTarget.pause), keyEquivalent: "")
        for item in menu.items { item.target = menuTarget }
        menuTarget.presenter = self
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private let menuTarget = MenuTarget()

    func openCurrent() { clicked() }

    func dismissCurrent() {
        if cardSession == Self.setupSession { settings.setupCardDismissed = true }
        if let sid = cardSession { claude.tracker.clear(sid) }
        cardSession = nil
        director.retract(fast: true)
        onStateChange?()
    }

    func pause(for seconds: TimeInterval) {
        settings.pausedUntil = Date().addingTimeInterval(seconds)
        if director.act != nil { director.retract() }
        onStateChange?()
    }

    func resume() {
        settings.pausedUntil = nil
        onStateChange?()
        tick()
    }

    func open(_ item: AttentionItem) {
        claude.open(item)
        if cardSession == item.sessionId {
            cardSession = nil
            director.acknowledge()
        }
        onStateChange?()
    }
}

final class MenuTarget: NSObject {
    weak var presenter: Presenter?
    @objc func openCurrent() { presenter?.openCurrent() }
    @objc func dismissCurrent() { presenter?.dismissCurrent() }
    @objc func pause() { presenter?.pause(for: 3600) }
}
