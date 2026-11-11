import AppKit
import CoreAudio
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
    let moments = MomentWatcher()
    let beatTap = AudioBeatTap()
    let power = PowerWatcher()
    let downloads = DownloadsWatcher()
    let sound = SoundWatcher()
    let devices = DeviceWatcher()
    let settings: Settings
    /// A Mac event waiting for a free moment on screen, and what a click on it does.
    private var pendingSystem: (act: Act, deadline: Date, click: (() -> Void)?)?
    private var clickAction: (() -> Void)?
    private var awaySince: Date?
    private var lastCharging = Date.distantPast
    private var workingSession: String?
    private var pendingMoment: (moment: Moment, source: MomentWatcher.Source?, deadline: Date)?
    /// Previews don't count towards the real paddle score.
    private var rallyCounts = true

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
        director.onActEnded = { [weak self] act in self?.actEnded(act) }
        view.onClick = { [weak self] in self?.clicked() }
        view.onRightClick = { [weak self] e in self?.rightClicked(e) }
        view.onHidden = { [weak self] in self?.tuckedAway() }
        claude.onChange = { [weak self] in
            self?.tick()
            self?.onStateChange?()
        }
        director.onRallyPoint = { [weak self] winner in self?.rallyPoint(winner) }
        beatTap.onEstimate = { [weak self] e in
            guard let self, self.director.act == .vibe else { return }
            self.director.syncBeat(bpm: e.bpm, phase: e.phase)
        }
        moments.onMoment = { [weak self] m, source in self?.momentTriggered(m, source) }
        moments.isWanted = { [weak self] m in self?.momentWanted(m) ?? false }
        power.onCharging = { [weak self] in
            guard let self, Date().timeIntervalSince(self.lastCharging) > 5 * 60 else { return }
            self.lastCharging = Date()
            self.systemEvent(.charging, wait: 6, reaction: .power)
        }
        power.onLow = { [weak self] in self?.systemEvent(.lowBattery, wait: 20, reaction: .power) }
        downloads.onDownloaded = { [weak self] urls in
            guard let first = urls.first else { return }
            self?.systemEvent(.download(name: first.lastPathComponent, count: urls.count), wait: 10, reaction: .downloads,
                              click: { NSWorkspace.shared.activateFileViewerSelecting(urls) })
        }
        sound.onMute = { [weak self] muted in self?.systemEvent(.sound(muted: muted), wait: 1.5, reaction: .sound) }
        devices.onConnect = { [weak self] kind, name in
            self?.systemEvent(.device(kind, name: name), wait: 10, reaction: .devices)
        }
    }

    func start() {
        warmUp()
        claude.start()
        video.start()
        moments.start()
        power.start()
        downloads.start()
        sound.start()
        devices.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.1
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.tick() }
    }

    /// Loads fonts and exercises the path code once, so the first real frame doesn't hitch.
    private func warmUp() {
        let raster = TextRasterizer.shared
        for style in [TextStyle.status, .title, .badge, .recap, .mono, .monoBold, .rain, .score, .micro] {
            _ = raster.lineHeight(style)
            _ = raster.render("Warm up 0123 █░", style: style, color: .white, maxWidth: 200, maxLines: 2, scale: 2)
        }
        CodeRainOverlay.warmUp(scale: 2)
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
        if act != .vibe && beatTap.isRunning { beatTap.stop() }
        director.play(act)
    }

    private func describe(_ act: Act) -> String {
        switch act {
        case .card(let c, let intro): return "card \(c.kind) '\(c.title)' intro=\(intro)"
        case .idle(let v): return "idle \(v.rawValue)"
        case .peek: return "peek"
        case .vibe: return "vibe"
        case .hacker(let style): return "hacker \(style.rawValue)"
        case .game(let l, let r): return "game \(l):\(r)"
        case .working(let n): return "working \(n)"
        case .system(let e): return "system \(e)"
        }
    }

    private func tuckedAway() {
        Log.info("hidden · \(view.stats.summary)")
        panel.orderOut(nil)
    }

    private func actEnded(_ act: Act?) {
        clickAction = nil
        if act == .vibe || director.act != .vibe { beatTap.stop() }
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

        updateAway(now)
        updateWorkingStrip(now)

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

        if let ps = pendingSystem {
            if now > ps.deadline {
                pendingSystem = nil
            } else if canShowSystem {
                pendingSystem = nil
                present(ps.act)
                clickAction = ps.click
                return
            }
        }

        if let pm = pendingMoment {
            if now > pm.deadline || !momentWanted(pm.moment) {
                pendingMoment = nil
            } else if canShowMoment {
                if pm.moment == .music {
                    // Wait until music is actually coming out of Spotify.
                    let prefixes = pm.source.map(AudioProcesses.prefixes(for:)) ?? ["com.spotify.client"]
                    let playing = AudioProcesses.playing(prefixes: prefixes)
                    if !playing.isEmpty {
                        playMoment(.music, audio: playing)
                        return
                    }
                } else {
                    playMoment(pm.moment, audio: [])
                    return
                }
            }
        }

        let ambientBlocked = (director.act != nil && director.act?.isWorking != true) || director.isRetracting
            || !activity.screenAvailable
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

    // MARK: - App moments

    private var canShowMoment: Bool {
        switch director.act {
        case nil, .idle?, .peek?, .working?: return true
        default: return false
        }
    }

    private var canShowSystem: Bool {
        switch director.act {
        case nil, .idle?, .peek?, .working?, .system?: return true
        default: return false
        }
    }

    // MARK: - Mac events

    private func systemEvent(_ e: SystemEvent, wait: TimeInterval, reaction: Settings.Reaction,
                             click: (() -> Void)? = nil) {
        guard settings.reactionEnabled(reaction), !settings.isPaused, activity.screenAvailable else { return }
        pendingSystem = (.system(e), Date().addingTimeInterval(wait), click)
        tick()
    }

    /// The "Claude is working" strip: Little Bro's resting state while any session works.
    private func updateWorkingStrip(_ now: Date) {
        let sessions = claude.tracker.workingSessions(now: now)
        let want = settings.claudeEnabled && settings.reactionEnabled(.working) && !settings.isPaused
            && !sessions.isEmpty && !ClaudeBridge.claudeIsFrontmost && activity.screenAvailable
        if want {
            let n = sessions.count
            workingSession = sessions.first
            director.restingAct = .working(count: n)
            if case .working(let current)? = director.act {
                if current != n { director.updateWorking(count: n) }
            } else if director.isHidden {
                present(.working(count: n))
            }
        } else if !previewingStrip {
            workingSession = nil
            director.restingAct = nil
            if director.act?.isWorking == true { director.retract() }
        }
    }

    /// Back after 10+ minutes away (or the screen was locked/asleep): one summary card.
    private func updateAway(_ now: Date) {
        let idle = activity.inputIdle
        if !activity.screenAvailable || idle >= 600 {
            if awaySince == nil { awaySince = activity.screenAvailable ? now.addingTimeInterval(-idle) : now }
            return
        }
        guard let since = awaySince, idle < 3 else { return }
        awaySince = nil
        guard settings.claudeEnabled, settings.reactionEnabled(.welcome), !settings.isPaused else { return }
        let fresh = claude.tracker.pending.filter { $0.since >= since }
        let waiting = fresh.filter { $0.kind.isNeedsInput }.count
        let finished = fresh.count - waiting
        guard finished + waiting > 0 else { return }
        // The summary stands in for the one-by-one reminders right now.
        for item in claude.tracker.pending { claude.tracker.markShown(item.sessionId, at: now) }
        let top = claude.tracker.pending.first
        Log.info("welcome back: \(finished) finished, \(waiting) waiting")
        pendingSystem = (.system(.welcome(finished: finished, waiting: waiting)), now.addingTimeInterval(10), { [weak self] in
            if let top { self?.claude.open(top) }
            self?.onStateChange?()
        })
    }

    private var previewingStrip = false

    func momentWanted(_ m: Moment) -> Bool {
        settings.momentEnabled(m) && !settings.isPaused && settings.momentGate.allows(m, now: Date())
    }

    private func momentTriggered(_ m: Moment, _ source: MomentWatcher.Source) {
        guard momentWanted(m), activity.screenAvailable else { return }
        // Music waits (up to a minute) for playback to start; the others for a card to finish.
        pendingMoment = (m, source, Date().addingTimeInterval(m == .music ? 60 : 15))
        tick()
    }

    private func playMoment(_ m: Moment, audio: [AudioObjectID]) {
        pendingMoment = nil
        var gate = settings.momentGate
        gate.record(m, at: Date())
        settings.momentGate = gate
        switch m {
        case .music:
            present(.vibe)
            if !audio.isEmpty { beatTap.start(processes: audio) }
        case .hacker:
            // The two Hackermen take turns.
            let style: HackerStyle = settings.lastHackerStyle == .shades ? .rain : .shades
            settings.lastHackerStyle = style
            present(.hacker(style))
        case .gaming:
            rallyCounts = true
            let s = settings.paddleScore
            present(.game(left: s.left, right: s.right))
        }
        onStateChange?()
    }

    private func rallyPoint(_ winner: Int) {
        guard rallyCounts else { return }
        var s = settings.paddleScore
        if winner < 0 { s.left += 1 } else { s.right += 1 }
        settings.paddleScore = s
        Log.info("paddle point to \(winner < 0 ? "left" : "right") → \(s.left):\(s.right)")
    }

    /// Plays an animation from the menu or `littlebro://play/<key>` (never counts towards the score).
    func preview(_ key: String) {
        switch key {
        case "vibe":
            present(.vibe)
            let playing = AudioProcesses.playing(prefixes: ["com.spotify.client"])
            if !playing.isEmpty { beatTap.start(processes: playing) }
        case "game":
            rallyCounts = false
            let s = settings.paddleScore
            present(.game(left: s.left, right: s.right))
        case "working":
            previewingStrip = true
            director.restingAct = .working(count: 2)
            present(.working(count: 2))
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self else { return }
                self.previewingStrip = false
                self.tick()
            }
        default:
            if let act = Previews.act(key) { present(act) }
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
        if let action = clickAction {
            clickAction = nil
            action()
            director.acknowledge()
            return
        }
        if act.isWorking {
            if let sid = workingSession { claude.openSession(cliId: sid) }
            return
        }
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
