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

    public init(kind: Kind, status: String, title: String, badge: String? = nil, recap: String? = nil) {
        self.kind = kind
        self.status = status
        self.title = title
        self.badge = badge
        self.recap = recap
    }
}

/// Something Little Bro can perform.
public enum Act: Equatable, Sendable {
    /// A Claude session card. `intro` is the full first-time choreography; reminders are shorter.
    case card(Card, intro: Bool)
    case idle(IdleVariant)
    case peek

    public var priority: Int {
        switch self {
        case .card(let c, _): return c.kind == .needsInput ? 3 : 2
        case .peek: return 1
        case .idle: return 0
        }
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
}

/// Runs the choreography: decides targets over time, plus the "alive" layer of
/// blinks and saccades, and steps the character once per frame.
public final class Director {
    public let character = Character()
    public private(set) var act: Act?
    public private(set) var isRetracting = false
    /// Called once Little Bro has fully tucked away, with the act that just ended.
    public var onHidden: ((Act?) -> Void)?

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
        switch newAct {
        case .card(let card, let intro): buildCard(card, intro: intro)
        case .idle(let variant): buildIdle(variant)
        case .peek: buildPeek()
        }
        timeline.start()
        timeline.advance(0, self)
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
        timeline.at(0) { d in
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

        character.step(dt)

        if isRetracting {
            // Critically damped retraction: done once the body is (almost) gone.
            if character.blobH.value < 0.35 && character.baseSize.height <= 0 {
                finishHidden()
            }
        } else if act == nil && character.isFullyHidden {
            // Nothing to do.
        }
        return character.scene()
    }

    private func finishHidden() {
        isRetracting = false
        let ended = endedAct
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
