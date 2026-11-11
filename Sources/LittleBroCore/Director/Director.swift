import CoreGraphics
import Foundation

public enum IdleVariant: String, CaseIterable, Sendable {
    case lookAround, sleepy, hello, curious, shy
}

/// What a Claude notification says.
public struct Card: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case done, needsInput }

    public var kind: Kind
    public var status: String
    public var title: String
    public var badge: String?
    public var recap: String?
    /// Shown right after the title, in the accent colour (e.g. "1 needs you").
    public var accent: String?

    public init(kind: Kind, status: String, title: String, badge: String? = nil, recap: String? = nil,
                accent: String? = nil) {
        self.kind = kind
        self.status = status
        self.title = title
        self.badge = badge
        self.recap = recap
        self.accent = accent
    }
}

public enum HackerStyle: String, CaseIterable, Sendable {
    /// Pixel shades + a terminal that "hacks the mainframe".
    case shades
    /// Code rain inside the body, focused green eyes.
    case rain
}

/// Something Little Bro can perform.
public enum Act: Equatable, Sendable {
    /// A Claude session card. `intro` is the full first-time choreography; reminders are shorter.
    case card(Card, intro: Bool)
    case idle(IdleVariant)
    case peek
    /// Headphones on, bobbing to the beat.
    case vibe
    case hacker(HackerStyle)
    /// One real point of paddle ball; the running score is shown.
    case game(left: Int, right: Int)
    /// The tiny strip shown while Claude sessions are working. Stays out until replaced.
    case working(count: Int)
    /// Something happened on the Mac (charger, download, mute, a device…).
    case system(SystemEvent)

    public var priority: Int {
        switch self {
        case .card(let c, _): return c.kind == .needsInput ? 3 : 2
        case .system: return 2
        case .peek, .vibe, .hacker, .game: return 1
        case .idle: return 0
        case .working: return -1
        }
    }

    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    public var isCard: Bool {
        if case .card = self { return true }
        return false
    }
}

/// Per-frame input from the outside world, in scene coordinates.
public struct FrameInput: Sendable {
    public var mouse: CGPoint?
    public var mouseMoved: Bool
    public var hovering: Bool

    public init(mouse: CGPoint? = nil, mouseMoved: Bool = false, hovering: Bool = false) {
        self.mouse = mouse
        self.mouseMoved = mouseMoved
        self.hovering = hovering
    }
}

enum Gaze: Equatable {
    case fixed(Double, Double)
    case cursor
    case wander
    case watch
    /// Slow left-right scanning (busy).
    case scan
    /// Look at a point in scene coordinates.
    case point(Double, Double)
}

/// Runs the choreography: decides targets over time, plus the "alive" layer of
/// blinks and saccades, and steps the character once per frame.
public final class Director {
    public let character = Character()
    public private(set) var act: Act?
    public private(set) var isRetracting = false
    /// Called once Little Bro has fully tucked away, with the act that just ended.
    public var onHidden: ((Act?) -> Void)?
    /// A paddle-ball point was decided: -1 the left player won, +1 the right one.
    public var onRallyPoint: ((Int) -> Void)?
    /// Called whenever an act ends — by tucking away or by settling back into `restingAct`.
    public var onActEnded: ((Act) -> Void)?
    /// When set, finished acts settle back into this one (the "Claude is working" strip)
    /// instead of tucking away.
    public var restingAct: Act?

    /// Keeps the beat while vibing; feed it measurements with `syncBeat`.
    public private(set) var beatClock = BeatClock()
    var rhythmAmount = Spring(0, SpringParams(response: 0.5, damping: 1))
    var eyesOpenInGroove = false
    var overlays: [Overlay] = []

    var timeline = Timeline()
    var gaze: Gaze = .fixed(0, 0.15)
    var life = false
    var blinkScale = 1.0
    var rng: SeededRandom
    var clock = 0.0
    var nextBlink = 0.0
    var pendingDoubleBlink: Double?
    var nextSaccade = 0.0
    var saccade = (x: 0.0, y: 0.0)
    var wanderTarget = (x: 0.0, y: 0.2)
    var nextWander = 0.0
    var baseExpression = Expression.neutral
    var hovering = false
    var startled = false
    /// Cursor-gaze shaping: vertical gain and bias (a pleading look stays up, towards you).
    var gazeGainY = 1.0
    var gazeBiasY = 0.0
    var endedAct: Act?
    var restingFaceScale = 1.0

    public init(seed: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)) {
        rng = SeededRandom(seed: seed)
    }

    public var isHidden: Bool { act == nil && !isRetracting && character.isFullyHidden }
    public var timelineTime: Double { timeline.time }

    // MARK: - Public commands

    public func play(_ newAct: Act) {
        isRetracting = false
        endedAct = nil
        act = newAct
        startled = false
        timeline = Timeline()
        for o in overlays { o.presence.target = 0 }
        rhythmAmount.target = 0
        character.paddleMix.target = 0
        character.setEyeColor(.white)
        switch newAct {
        case .card(let card, let intro): buildCard(card, intro: intro)
        case .idle(let variant): buildIdle(variant)
        case .peek: buildPeek()
        case .vibe: buildVibe()
        case .hacker(let style): buildHacker(style)
        case .game(let l, let r): buildGame(left: l, right: r)
        case .working(let n): buildWorking(count: n)
        case .system(let e): buildSystem(e)
        }
        timeline.start()
        timeline.advance(0, self)
    }

    /// Change how many sessions the working strip shows, without restarting it.
    public func updateWorking(count: Int) {
        guard case .working = act else { return }
        act = .working(count: count)
        if restingAct?.isWorking == true { restingAct = .working(count: count) }
        for o in overlays { (o as? StripOverlay)?.count = count }
        character.baseSize.width = count > 1 ? Metrics.strip.width + 12 : Metrics.strip.width
    }

    /// Update the text of the card on screen without restarting the choreography.
    public func updateCard(_ card: Card) {
        guard case .card(_, let intro) = act else { return }
        act = .card(card, intro: intro)
        if character.textOn { showCard(card) }
    }

    /// Tuck away. Finishes with `onHidden`.
    public func retract(fast: Bool = false) {
        guard !isRetracting else { return }
        if let rest = restingAct, let current = act, !current.isWorking {
            // Settle back into the strip instead of hiding.
            onActEnded?(current)
            play(rest)
            return
        }
        if character.isFullyHidden {
            let ended = act
            act = nil
            if ended != nil { onHidden?(ended) }
            return
        }
        isRetracting = true
        endedAct = act
        act = nil
        life = false
        let hadText = character.textOn
        let s = fast ? 0.5 : 1.0
        let textOut = hadText ? 0.12 : 0
        timeline = Timeline()
        // Keeps whatever expression it has: it closes its eyes from there.
        for o in overlays { o.presence.target = 0 }
        rhythmAmount.target = 0
        character.paddleMix.target = 0
        timeline.at(0) { d in
            d.character.setEyeColor(.white)
            d.character.textFading = true
            d.character.recapOn = false
            d.character.hovering = false
            d.hovering = false
            d.character.pulseAmount.target = 0
            d.character.sway.target = 0
            d.character.breathe.target = 0
            d.character.blush.target = 0
        }
        timeline.at(textOut * s) { d in
            // Text has faded: now the layout may collapse.
            d.character.textOn = false
            d.character.textFading = false
        }
        timeline.at((textOut + (hadText ? 0.12 : 0.06)) * s) { d in
            d.character.open.target = 0
            d.character.baseSize.width = min(d.character.baseSize.width, Metrics.compact.width * 0.9)
        }
        let rise = (hadText ? 0.46 : 0.26) * s
        timeline.at(rise - 0.09 * s) { d in
            // Anticipation: sink 3 pt before pulling up into the edge.
            d.character.blobH.params = SpringParams(response: 0.16, damping: 1)
            d.character.baseSize.height = d.character.rowHeight - d.character.profile.topInset + 3
        }
        timeline.at(rise) { d in
            d.character.blobH.params = .blobRetract
            d.character.baseSize = CGSize(width: d.character.baseSize.width * 0.5, height: 0)
            d.character.glowAmount.target = 0
        }
        timeline.start()
        timeline.advance(0, self)
    }

    /// The user pressed on Little Bro.
    public func pressDown() {
        character.squash.velocity += 70
    }

    /// The user clicked: a happy acknowledgement, then away.
    public func acknowledge() {
        guard act != nil, !isRetracting else { return }
        timeline = Timeline()
        timeline.at(0) { d in
            d.setBase(.happy)
            d.character.hop.velocity -= 110
            d.life = false
        }
        timeline.at(0.38) { d in d.retract(fast: true) }
        timeline.start()
        timeline.advance(0, self)
    }

    // MARK: - Frame

    public func update(dt: Double, input: FrameInput) -> Scene {
        clock += dt

        let hoverNow = input.hovering && act != nil && !isRetracting
        if hoverNow != hovering {
            hovering = hoverNow
            character.hovering = hoverNow
            character.recapOn = hoverNow && (act?.isCard ?? false)
            applyExpression()
            if hoverNow {
                restingFaceScale = character.faceScale.target
                character.faceScale.target = restingFaceScale * 1.06
                character.blink()
            } else {
                character.faceScale.target = restingFaceScale
            }
        }

        if case .idle = act, !startled, !hovering, timeline.time > 0.9, input.mouseMoved {
            startle()
        }

        if !hovering { timeline.advance(dt, self) }

        updateGaze(input)
        if life && !isRetracting { updateLife() }
        updateRhythm(dt)
        for o in overlays {
            o.presence.step(dt)
            o.update(dt, self)
        }
        overlays.removeAll { $0.isGone }

        character.step(dt)

        if isRetracting {
            // Critically damped retraction: done once the body is (almost) gone.
            if character.blobH.value < 0.35 && character.baseSize.height <= 0 {
                finishHidden()
            }
        }
        var scene = character.scene()
        for o in overlays { o.decorate(&scene, self) }
        return scene
    }

    /// Feed a tempo measurement (BPM and the current phase 0…1 of the music).
    public func syncBeat(bpm: Double, phase: Double) {
        beatClock.sync(bpm: bpm, phase: phase)
    }

    private func updateRhythm(_ dt: Double) {
        rhythmAmount.step(dt)
        let amount = clamp(rhythmAmount.value, 0, 1)
        guard amount > 0.0005 || act == .vibe else {
            character.rhythm = Character.Rhythm()
            return
        }
        beatClock.advance(dt)
        let pos = beatClock.position
        let phase = pos - floor(pos)
        // A beat: quick (but continuous) attack, then a falling decay.
        let attack = 0.09
        let hit = phase < attack ? sin(phase / attack * .pi / 2) : pow(1 - (phase - attack) / (1 - attack), 2)
        var r = Character.Rhythm()
        r.bob = 3.2 * hit * amount
        r.squash = 2.0 * hit * amount
        r.lean = 3.6 * sin(.pi * pos) * amount
        r.tilt = 0.11 * sin(.pi * pos) * amount
        character.rhythm = r
        // Eyes closed in bliss; every eight beats they open for two to look at you.
        if act == .vibe {
            let open = pos.truncatingRemainder(dividingBy: 8) >= 6
            if open != eyesOpenInGroove {
                eyesOpenInGroove = open
                setBase(open ? .content : .blissful)
                if open { character.blink() }
            }
        }
    }

    /// Called by the court when a point is decided.
    func rallyEnded(winner: Int) {
        onRallyPoint?(winner)
        // Hold the court so the new score is seen, then turn back into happy eyes.
        timeline.after(1.25) { d in d.character.paddleMix.target = 0 }
        timeline.after(1.5) { d in d.setBase(.happy) }
        timeline.after(1.9) { d in d.hop(110) }
        timeline.after(3.0) { d in d.retract() }
    }

    private func finishHidden() {
        overlays.removeAll()
        rhythmAmount.snap(to: 0)
        isRetracting = false
        let ended = endedAct
        if let ended { onActEnded?(ended) }
        endedAct = nil
        character.resetHidden(width: 60)
        timeline = Timeline()
        onHidden?(ended)
    }

    // MARK: - Helpers used by routines

    func enter(_ size: CGSize, anchor: Double = 0, faceScale: Double = 1) {
        if character.isFullyHidden {
            // Starts as a narrow drop and spreads as it falls.
            character.resetHidden(width: 26)
            character.entering = true
            nextBlink = clock + 2.5
        }
        character.blobH.params = .blobHeight
        character.blobW.params = .blobWidth
        character.open.params = .open
        character.textFading = false
        character.sway.target = 0
        character.breathe.target = 0
        character.blush.target = 0
        gazeGainY = 1
        gazeBiasY = 0
        restingFaceScale = faceScale
        character.baseSize = size
        character.rowHeight = size.height + character.profile.topInset
        character.anchor.target = anchor
        character.faceScale.target = faceScale
        character.faceX.target = 0
        character.textOn = false
        character.recapOn = false
        blinkScale = 1
    }

    func setBase(_ e: Expression) {
        baseExpression = e
        applyExpression()
    }

    private func applyExpression() {
        if hovering {
            character.setExpression(baseExpression.mixed(with: .delighted, 0.75))
        } else {
            character.setExpression(baseExpression)
        }
    }

    func showCard(_ card: Card) {
        let statusColor = card.kind == .needsInput ? RGBA.claude : RGBA(1, 1, 1, 0.5)
        character.status.set(card.status, color: statusColor)
        character.title.set(card.title, color: RGBA(1, 1, 1, 0.96))
        character.badge.set(card.badge, color: RGBA(1, 1, 1, 0.4))
        character.recap.set(card.recap, color: RGBA(1, 1, 1, 0.62))
        character.accent.set(card.accent, color: .claude)
        character.textOn = true
    }

    func glow(_ c: RGBA, _ amount: Double, pulse: Double = 0) {
        character.setGlow(c, amount: amount, pulse: pulse)
    }

    func look(_ x: Double, _ y: Double) { gaze = .fixed(x, y) }

    func hop(_ strength: Double) {
        character.hop.velocity -= strength
        // The body pushes off: a little squash that rebounds.
        character.squash.velocity += strength * 0.4
    }

    /// Side-to-side wobble of the body.
    func shimmy(_ strength: Double) { character.jiggle.velocity += strength }

    func squash(_ strength: Double) { character.squash.velocity += strength }

    func wiggle(_ strength: Double) { character.wiggle.velocity += strength }

    func nudge() {
        wiggle(200)
        shimmy(60)
        hop(70)
        character.blink()
    }

    private func startle() {
        startled = true
        timeline = Timeline()
        timeline.at(0) { d in
            d.setBase(.wide)
            d.gaze = .cursor
            d.life = false
            d.hop(130)
        }
        timeline.at(0.5) { d in d.setBase(.suspicious) }
        timeline.at(0.8) { d in d.retract(fast: true) }
        timeline.start()
        timeline.advance(0, self)
    }

    // MARK: - Gaze & life

    private func updateGaze(_ input: FrameInput) {
        var tx = 0.0
        var ty = 0.0
        switch gaze {
        case .fixed(let x, let y):
            tx = x
            ty = y
        case .cursor:
            if let m = input.mouse {
                let fc = character.lastFaceCenter
                let dx = Double(m.x - fc.x)
                let dy = Double(m.y - fc.y)
                tx = dx / (dx * dx + 240 * 240).squareRoot()
                ty = gazeBiasY + gazeGainY * (0.12 + 0.8 * dy / (dy * dy + 260 * 260).squareRoot())
            } else {
                tx = 0
                ty = 0.3
            }
        case .wander:
            if clock >= nextWander {
                wanderTarget = (rng.range(-0.85, 0.85), rng.range(-0.1, 0.6))
                nextWander = clock + rng.range(0.7, 1.9)
            }
            tx = wanderTarget.x
            ty = wanderTarget.y
        case .watch:
            tx = 0.4 * sin(clock * 0.75)
            ty = 1.0
        case .scan:
            tx = 0.95 * sin(clock * 2.3)
            ty = 0
        case .point(let x, let y):
            let fc = character.lastFaceCenter
            let dx = x - Double(fc.x), dy = y - Double(fc.y)
            tx = dx / (dx * dx + 50 * 50).squareRoot()
            ty = dy / (dy * dy + 22 * 22).squareRoot()
        }
        if hovering, let m = input.mouse {
            // Close up: look right at the cursor, whatever the routine was doing.
            let fc = character.lastFaceCenter
            tx = clamp(Double(m.x - fc.x) / 22, -1, 1)
            ty = clamp(Double(m.y - fc.y) / 16, -1, 1) * 0.85
        }
        if life {
            tx += saccade.x
            ty += saccade.y
        }
        character.lookX.target = tx
        character.lookY.target = ty
    }

    private func updateLife() {
        if clock >= nextBlink {
            if character.open.value > 0.6 && !character.isBlinking {
                character.blink(slow: blinkScale > 1.3)
                if rng.chance(0.16) { pendingDoubleBlink = clock + 0.3 }
            }
            nextBlink = clock + rng.range(2.4, 5.6) * blinkScale
        }
        if let p = pendingDoubleBlink, clock >= p {
            character.blink()
            pendingDoubleBlink = nil
        }
        if clock >= nextSaccade {
            saccade = (rng.range(-0.07, 0.07), rng.range(-0.05, 0.05))
            nextSaccade = clock + rng.range(0.35, 1.4)
        }
    }
}
