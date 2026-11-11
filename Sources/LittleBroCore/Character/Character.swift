import CoreGraphics
import Foundation

extension SpringParams {
    static let blobWidth = SpringParams(response: 0.56, damping: 0.68)
    static let blobHeight = SpringParams(response: 0.46, damping: 0.62)
    static let blobRetract = SpringParams(response: 0.30, damping: 1.0)
    static let hover = SpringParams(response: 0.32, damping: 0.72)
    static let squash = SpringParams(response: 0.30, damping: 0.42)
    static let wiggle = SpringParams(response: 0.15, damping: 0.20)
    static let reveal = SpringParams(response: 0.50, damping: 0.88)
    static let face = SpringParams(response: 0.50, damping: 0.80)
    static let eyesFollow = SpringParams(response: 0.24, damping: 0.56)
    static let hop = SpringParams(response: 0.34, damping: 0.42)
    static let scale = SpringParams(response: 0.30, damping: 0.72)
    static let open = SpringParams(response: 0.20, damping: 0.78)
    static let gaze = SpringParams(response: 0.17, damping: 0.86)
    static let eyeShape = SpringParams(response: 0.26, damping: 0.72)
    static let fade = SpringParams(response: 0.30, damping: 1.0)
    static let glow = SpringParams(response: 0.45, damping: 1.0)
    static let deform = SpringParams(response: 0.12, damping: 1.0)
    static let eyesExit = SpringParams(response: 0.10, damping: 1.0)
    static let lean = SpringParams(response: 0.14, damping: 0.9)
    static let jiggle = SpringParams(response: 0.20, damping: 0.30)
    static let ambient = SpringParams(response: 0.6, damping: 1.0)
}

struct EyeSprings {
    var width = Spring(1, .eyeShape)
    var height = Spring(1, .eyeShape)
    var lidTop = Spring(0, .eyeShape)
    var lidAngle = Spring(0, .eyeShape)
    var happy = Spring(0, .eyeShape)
    var roundness = Spring(0.42, .eyeShape)

    mutating func setTarget(_ s: EyeShape) {
        width.target = s.width
        height.target = s.height
        lidTop.target = s.lidTop
        lidAngle.target = s.lidAngle
        happy.target = s.happy
        roundness.target = s.roundness
    }

    mutating func snap(_ s: EyeShape) {
        width.snap(to: s.width)
        height.snap(to: s.height)
        lidTop.snap(to: s.lidTop)
        lidAngle.snap(to: s.lidAngle)
        happy.snap(to: s.happy)
        roundness.snap(to: s.roundness)
    }

    mutating func step(_ dt: Double) {
        width.step(dt)
        height.step(dt)
        lidTop.step(dt)
        lidAngle.step(dt)
        happy.step(dt)
        roundness.step(dt)
    }

    var value: EyeShape {
        EyeShape(width: width.value, height: height.value, lidTop: max(0, lidTop.value),
                 lidAngle: lidAngle.value, happy: max(0, happy.value), roundness: roundness.value)
    }
}

/// One line of text that cross-fades when its content changes.
struct TextSlot {
    var desired: String?
    var desiredColor = RGBA.white
    var shown: String?
    var color = RGBA.white
    var opacity = Spring(0, .fade)

    mutating func set(_ text: String?, color: RGBA) {
        if let t = text, !t.isEmpty { desired = t } else { desired = nil }
        desiredColor = color
    }

    mutating func reset() {
        desired = nil
        shown = nil
        opacity.snap(to: 0)
    }

    mutating func step(_ dt: Double, visible: Bool) {
        let wanted = visible ? desired : nil
        if wanted != shown || (wanted != nil && desiredColor != color) {
            if shown == nil || opacity.value < 0.03 {
                shown = wanted
                color = desiredColor
            } else {
                opacity.target = 0
            }
        }
        if wanted == shown && (shown == nil || desiredColor == color) {
            opacity.target = shown == nil ? 0 : 1
        }
        opacity.step(dt)
    }
}

/// The physical state of Little Bro: every moving quantity is a spring.
/// Routines only ever change *targets* (or kick velocities), never values, which
/// is what keeps every transition continuous.
public final class Character {
    public var profile = ScreenProfile()
    public private(set) var time: Double = 0

    // Layout intent set by the director.
    public var baseSize = CGSize(width: 60, height: 0)
    public var rowHeight: Double = Metrics.compact.height
    public var textOn = false
    /// Text is fading out but the layout holds (so the eyes don't slide over the ghost text).
    public var textFading = false
    public var recapOn = false
    public var hovering = false
    /// Set when appearing from nothing: the first height overshoot triggers a landing squash.
    var entering = false

    // Body.
    var blobW = Spring(60, .blobWidth)
    var blobH = Spring(0, .blobHeight)
    var hoverGrow = Spring(0, .hover)
    var squash = Spring(0, .squash)
    var wiggle = Spring(0, .wiggle)
    var textReveal = Spring(0, .reveal)
    var recapReveal = Spring(0, .reveal)
    /// Velocity-driven deformation, smoothed so a sudden change in speed never kinks the outline.
    var stretch = Spring(0, .deform)
    var bulge = Spring(0, .deform)
    /// The bottom of the body follows the gaze and head tilt a beat late…
    var lean = Spring(0, .lean)
    /// …and wobbles side to side when kicked.
    var jiggle = Spring(0, .jiggle)
    /// Slow ambient motion amplitudes: side-to-side sway (pt) and breathing (pt).
    var sway = Spring(0, .ambient)
    var breathe = Spring(0, .ambient)
    /// 0…1: how much the exit-only shaping applies (blended, so re-entering mid-exit is smooth).
    var exitMix = Spring(0, .deform)
    /// Width multiplier while tucking away (smoothed, so reversing mid-exit never jerks).
    var narrow = Spring(1, .deform)

    // Face.
    var faceX = Spring(0, .face)
    var anchor = Spring(0, .face)
    var eyesY = Spring(0, .eyesFollow)
    var hop = Spring(0, .hop)
    var faceScale = Spring(1, .scale)
    var open = Spring(0, .open)
    var lookX = Spring(0, .gaze)
    var lookY = Spring(0, .gaze)
    var left = EyeSprings()
    var right = EyeSprings()
    var tilt = Spring(0, .eyeShape)
    var spacing = Spring(1, .eyeShape)

    // Glow and blush.
    var glowR = Spring(1, .glow)
    var glowG = Spring(1, .glow)
    var glowB = Spring(1, .glow)
    var glowAmount = Spring(0, .glow)
    var pulseAmount = Spring(0, .glow)
    var blush = Spring(0, .glow)
    /// Eye colour (white, or tinted for some acts).
    var eyeR = Spring(1, .glow)
    var eyeG = Spring(1, .glow)
    var eyeB = Spring(1, .glow)

    /// Paddle mode: the eyes become two paddles at ±`paddleHalfSpan`, at heights `paddleY`.
    var paddleMix = Spring(0, SpringParams(response: 0.38, damping: 0.82))
    public var paddleY: (left: Double, right: Double) = (20, 20)
    public var paddleHalfSpan: Double = 70
    /// Paddle height as a fraction of an eye (matches the rally's collision size).
    public var paddleHeightFactor: Double = 0.726

    /// Beat-driven offsets, recomputed by the director every frame while vibing.
    public struct Rhythm: Sendable {
        public var bob = 0.0
        public var squash = 0.0
        public var lean = 0.0
        public var tilt = 0.0
        public init() {}
    }
    public var rhythm = Rhythm()

    // Blink: an explicit timed curve (springs are too soft for a blink).
    private var blinkElapsed: Double?
    private var blinkTiming: (close: Double, hold: Double, open: Double) = (0.075, 0.035, 0.16)

    // Text.
    var status = TextSlot()
    var title = TextSlot()
    var badge = TextSlot()
    var recap = TextSlot()
    var accent = TextSlot()

    /// Face centre from the last built scene (used for gaze-at-cursor).
    public private(set) var lastFaceCenter = CGPoint(x: 0, y: 25)

    public init() {}

    // MARK: - State queries

    public var isFullyHidden: Bool {
        baseSize.height <= 0 && blobH.value < 0.35 && abs(blobH.velocity) < 3
    }

    public var isBlinking: Bool { blinkElapsed != nil }

    var isExiting: Bool { baseSize.height <= 0 }

    // MARK: - Commands

    func resetHidden(width: Double) {
        blobW.snap(to: width)
        blobH.snap(to: 0)
        blobH.params = .blobHeight
        eyesY.params = .eyesFollow
        for sp in [\Character.hoverGrow, \.squash, \.wiggle, \.textReveal, \.recapReveal, \.faceX, \.eyesY, \.hop,
                   \.open, \.tilt, \.lookX, \.glowAmount, \.pulseAmount, \.stretch, \.bulge, \.lean, \.jiggle,
                   \.sway, \.breathe, \.blush, \.exitMix] as [ReferenceWritableKeyPath<Character, Spring>] {
            self[keyPath: sp].snap(to: 0)
        }
        faceScale.snap(to: 1)
        narrow.snap(to: 1)
        eyeR.snap(to: 1)
        eyeG.snap(to: 1)
        eyeB.snap(to: 1)
        paddleMix.snap(to: 0)
        rhythm = Rhythm()
        spacing.snap(to: 1)
        lookY.snap(to: 0.15)
        left.snap(EyeShape())
        right.snap(EyeShape())
        status.reset()
        title.reset()
        badge.reset()
        recap.reset()
        accent.reset()
        textOn = false
        textFading = false
        recapOn = false
        blinkElapsed = nil
        entering = false
    }

    func setExpression(_ e: Expression) {
        left.setTarget(e.left)
        right.setTarget(e.right)
        tilt.target = e.tilt
        spacing.target = e.spacing
    }

    func blink(slow: Bool = false) {
        guard blinkElapsed == nil else { return }
        blinkElapsed = 0
        blinkTiming = slow ? (0.15, 0.08, 0.32) : (0.075, 0.035, 0.16)
    }

    func setEyeColor(_ c: RGBA) {
        eyeR.target = c.r
        eyeG.target = c.g
        eyeB.target = c.b
    }

    func setGlow(_ c: RGBA, amount: Double, pulse: Double) {
        glowR.target = c.r
        glowG.target = c.g
        glowB.target = c.b
        glowAmount.target = amount
        pulseAmount.target = pulse
    }

    // MARK: - Simulation

    private var blinkClosure: Double {
        guard let t = blinkElapsed else { return 0 }
        let (c, h, o) = blinkTiming
        if t < c { let u = t / c; return u * u }
        if t < c + h { return 1 }
        let u = min((t - c - h) / o, 1)
        let inv = 1 - u
        return inv * inv * inv
    }

    private func badgeWidth(_ text: String) -> Double {
        Double(TextRasterizer.shared.measure(text, style: .badge, maxWidth: 60).width) + Metrics.badgePadX * 2
    }

    private func textBlockWidth() -> Double {
        let r = TextRasterizer.shared
        var w = 0.0
        if let s = status.desired {
            w = max(w, Double(r.measure(s, style: .status, maxWidth: Metrics.maxTextWidth).width))
        }
        var titleW = 0.0
        var badgeW = 0.0
        if let b = badge.desired {
            badgeW = badgeWidth(b) + Metrics.badgeGap
        }
        if let t = title.desired {
            titleW = Double(r.measure(t, style: .title, maxWidth: Metrics.maxTextWidth - badgeW).width)
        }
        if let a = accent.desired {
            titleW += Double(r.measure(a, style: .title, maxWidth: Metrics.maxTextWidth).width)
                + (title.desired != nil ? Metrics.accentGap : 0)
        }
        w = max(w, titleW + badgeW)
        return min(w, Metrics.maxTextWidth)
    }

    private func recapSize() -> CGSize {
        guard let text = recap.desired else { return .zero }
        return TextRasterizer.shared.measure(text, style: .recap, maxWidth: Metrics.recapMaxWidth,
                                              maxLines: Metrics.recapLines)
    }

    public func step(_ dt: Double) {
        time += dt

        // Layout targets.
        hoverGrow.target = hovering ? 1 : 0
        let showRecap = textOn && recapOn && recap.desired != nil
        var wantW = baseSize.width
        var wantH = baseSize.height
        if textOn {
            wantW = max(wantW, Metrics.faceBoxWidth + Metrics.textLeadingInset + textBlockWidth()
                        + Metrics.textRightPadding)
        }
        if showRecap {
            let rs = recapSize()
            wantW = max(wantW, Metrics.faceBoxWidth + Metrics.textLeadingInset + Double(rs.width)
                        + Metrics.textRightPadding)
            let raster = TextRasterizer.shared
            let blockH = raster.lineHeight(.status) + raster.lineHeight(.title)
            let rowCenter = (rowHeight - profile.topInset) / 2
            wantH = max(wantH, rowCenter + blockH / 2 + Metrics.recapGap + Double(rs.height)
                        + Metrics.recapBottomPad)
        }
        if profile.minWidth > 0 { wantW = max(wantW, profile.minWidth + 16) }
        blobW.target = wantW + hoverGrow.value * Double(Metrics.hoverGrow.width)
        if baseSize.height > 0 {
            blobH.target = wantH + profile.topInset + hoverGrow.value * Double(Metrics.hoverGrow.height)
        } else {
            blobH.target = 0
        }
        textReveal.target = textOn ? 1 : 0
        recapReveal.target = showRecap ? 1 : 0

        // Physics.
        let wasFalling = blobH.velocity > 0
        blobW.step(dt)
        blobH.step(dt)
        if entering && wasFalling && blobH.velocity <= 0 {
            // It just hit the bottom of its overshoot: squash on landing.
            squash.velocity += 75
            entering = false
        }
        hoverGrow.step(dt)
        squash.step(dt)
        wiggle.step(dt)
        textReveal.step(dt)
        recapReveal.step(dt)
        faceX.step(dt)
        anchor.step(dt)
        hop.step(dt)
        faceScale.step(dt)
        open.step(dt)
        lookX.step(dt)
        lookY.step(dt)
        left.step(dt)
        right.step(dt)
        tilt.step(dt)
        spacing.step(dt)
        glowR.step(dt)
        glowG.step(dt)
        glowB.step(dt)
        glowAmount.step(dt)
        pulseAmount.step(dt)
        blush.step(dt)
        eyeR.step(dt)
        eyeG.step(dt)
        eyeB.step(dt)
        paddleMix.step(dt)
        sway.step(dt)
        breathe.step(dt)
        stretch.target = min(abs(blobH.velocity) * 0.028, 9)
        bulge.target = clamp(blobH.velocity * 0.011, 0, min(5, max(0, blobH.value) * 0.2))
        stretch.step(dt)
        bulge.step(dt)
        // The bottom follows the gaze (≈ a quarter of the eye offset) and the head tilt.
        lean.target = isExiting ? 0 : lookX.value * Metrics.maxLookX * 0.28 + tilt.value * 14
        lean.step(dt)
        jiggle.step(dt)
        exitMix.target = isExiting ? 1 : 0
        exitMix.step(dt)
        if isExiting {
            let u = clamp(max(0, blobH.value) / max(rowHeight * 0.65, 1), 0, 1)
            narrow.target = 0.3 + 0.7 * u * u * (3 - 2 * u)
        } else {
            narrow.target = 1
        }
        narrow.step(dt)

        // Eyes ride on the body with a little lag, which gives a jiggle when it lands.
        // On the way out they must keep up, or the rising edge would slice them.
        eyesY.params = isExiting ? .eyesExit : .eyesFollow
        eyesY.target = eyeAnchorY(height: max(0, blobH.value))
        eyesY.step(dt)

        if let b = blinkElapsed {
            let total = blinkTiming.close + blinkTiming.hold + blinkTiming.open
            blinkElapsed = b + dt >= total ? nil : b + dt
        }

        // Text waits until the body has widened enough to hold it.
        let roomForText = textOn && !textFading && textReveal.value > 0.55
        status.step(dt, visible: roomForText)
        title.step(dt, visible: roomForText)
        badge.step(dt, visible: roomForText)
        accent.step(dt, visible: roomForText)
        recap.step(dt, visible: showRecap && !textFading && recapReveal.value > 0.5)
    }

    private func eyeAnchorY(height h: Double) -> Double {
        let top = profile.topInset
        let row = min(h, rowHeight)
        let center = top + max(row - top, 0) / 2
        let eh = Metrics.eyeHeight * faceScale.value
        let bottom = row - Metrics.peekBottomPad - eh / 2
        return lerp(center, bottom, clamp(anchor.value, 0, 1))
    }

    // MARK: - Scene

    public func scene() -> Scene {
        var s = Scene()
        var w = max(0, blobW.value + wiggle.value + (squash.value + rhythm.squash) * 1.4 - stretch.value)
        let h = max(0, blobH.value - squash.value - rhythm.squash + breathe.value * sin(time * 2 * .pi * 0.4))
        let exiting = clamp(exitMix.value, 0, 1)
        if narrow.value < 0.999 {
            // Narrow with the height on the way out, so it ends as a small drop, not a thin bar.
            w = max(min(w, 22), w * narrow.value)
        }
        guard h > 0.25, w > 1 else { return s }
        s.isVisible = true
        let bodyLean = lean.value + jiggle.value + sway.value * sin(time * 2 * .pi * 0.5) + rhythm.lean
        s.blobPath = Paths.blob(width: w, height: h, cornerRadius: Metrics.maxCorner,
                                earRadius: Metrics.earRadius, bulge: bulge.value, lean: bodyLean)
        s.blobWidth = w
        s.blobHeight = h
        s.bodyLean = bodyLean
        s.shadowOpacity = Metrics.shadowOpacity * clamp(h / 28, 0, 1)

        // Face placement (rides half of the lean, being halfway down the body).
        let reveal = clamp(textReveal.value, 0, 1.1)
        let faceLeftX = -w / 2 + Metrics.faceBoxWidth / 2
        var faceCY = eyesY.value + hop.value + rhythm.bob
        if exiting > 0.001 { faceCY = lerp(faceCY, min(faceCY, h / 2 - 1), exiting) }
        let faceCX = lerp(faceX.value, faceLeftX, reveal) + bodyLean * clamp(faceCY / max(h, 1), 0, 1)
        s.faceCenter = CGPoint(x: faceCX, y: faceCY)
        lastFaceCenter = s.faceCenter

        // Eyes fade with the body: never a stray line in a sliver.
        let fadeStart = rowHeight * 0.42
        s.eyeOpacity = clamp((h - fadeStart) / max(rowHeight * 0.28, 1), 0, 1)
        let scale = faceScale.value
        let closure = blinkClosure
        let openness = clamp(open.value, 0, 1.25) * (1 - closure)
        let lx = clamp(lookX.value, -1.3, 1.3)
        let ly = clamp(lookY.value, -1.3, 1.3)
        let halfSpan = (Metrics.eyeGap / 2 + Metrics.eyeWidth / 2) * scale * spacing.value * (1 - 0.07 * abs(lx))
        let offX = lx * Metrics.maxLookX * scale
        // Vertical look range shrinks in a short body so the eyes never touch the edge.
        let room = (rowHeight - profile.topInset - Metrics.eyeHeight * scale) / 2
        let offY = ly * clamp(room - 3.5, 1.5, Metrics.maxLookY) * scale
        let pm = clamp(paddleMix.value, 0, 1.05)
        let rot = (tilt.value + rhythm.tilt) * (1 - min(pm, 1))
        let inner = w / 2 - 1.5
        for (side, eye) in [(-1.0, left.value), (1.0, right.value)] {
            // Perspective (the eye on the near side grows) — but not with slanted lids,
            // where it makes one eye look raised and skeptical.
            let slant = clamp(abs(eye.lidAngle) / 0.2, 0, 1)
            let perspective = 1 + 0.07 * lx * side * (1 - slant)
            let squint = 1 + 0.12 * (1 - min(openness, 1))
            let ew = Metrics.eyeWidth * scale * eye.width * perspective * squint * lerp(1, 0.42, pm)
            let eh = max(Metrics.minEyeLine,
                         Metrics.eyeHeight * scale * eye.height * perspective * openness * lerp(1, paddleHeightFactor, pm))
            let local = side * halfSpan
            var cx = faceCX + offX * (1 - pm) + local * cos(rot)
            var cy = faceCY + offY * (1 - pm) + local * sin(rot)
            if pm > 0.0001 {
                cx = lerp(cx, faceCX + side * paddleHalfSpan, pm)
                cy = lerp(cy, side < 0 ? paddleY.left : paddleY.right, pm)
            }
            s.eyes.append(Paths.eye(center: CGPoint(x: cx, y: cy), width: ew, height: eh,
                                    roundness: eye.roundness, lidTop: eye.lidTop, lidAngle: eye.lidAngle,
                                    side: side, happy: eye.happy, rotation: rot))
            // An eye mostly beyond the body's edge fades instead of leaving a clipped dot.
            let visible = max(0, min(cx + ew / 2, inner) - max(cx - ew / 2, -inner)) / max(ew, 0.1)
            let u = clamp((visible - 0.45) / 0.4, 0, 1)
            s.eyeAlphas.append(u * u * (3 - 2 * u))
            if blush.value > 0.01 {
                let by = cy + eh / 2 + 3.5
                s.blush.append(CGPath(ellipseIn: CGRect(x: cx - ew * 0.45 + side * 2, y: by - 2.2, width: ew * 0.9,
                                                        height: 4.4), transform: nil))
            }
        }
        s.blushOpacity = clamp(blush.value, 0, 1) * s.eyeOpacity
        s.eyeColor = RGBA(clamp(eyeR.value, 0, 1), clamp(eyeG.value, 0, 1), clamp(eyeB.value, 0, 1))
        s.blushColor = Metrics.blushColor

        // Glow: soft and white normally; tighter, brighter and pulsing when it needs you.
        let pa = clamp(pulseAmount.value, 0, 1)
        let wave = 0.5 + 0.5 * sin(time * 2 * .pi / 1.6)
        s.glowColor = RGBA(clamp(glowR.value, 0, 1), clamp(glowG.value, 0, 1), clamp(glowB.value, 0, 1))
        s.glowOpacity = clamp(glowAmount.value * (0.5 + pa * (0.22 + 0.28 * wave)), 0, 1)
        s.glowRadius = lerp(6, 3, pa) + 2 * pa * wave

        // Text block, vertically centred on the main row.
        let raster = TextRasterizer.shared
        let rowCenter = profile.topInset + (rowHeight - profile.topInset) / 2
        let statusH = raster.lineHeight(.status)
        let titleH = raster.lineHeight(.title)
        let blockTop = rowCenter - (statusH + titleH) / 2 + hop.value * 0.25
        let textX = -w / 2 + Metrics.faceBoxWidth + Metrics.textLeadingInset
        func fade(_ o: Double) -> (dx: Double, blur: Double) { ((1 - o) * -7, (1 - o) * 5) }

        var badgeW = 0.0
        if let b = badge.shown { badgeW = badgeWidth(b) }
        if let text = status.shown, status.opacity.value > 0.005 {
            let o = clamp(status.opacity.value, 0, 1)
            let f = fade(o)
            s.texts.append(TextDraw(key: "status", text: text, style: .status, color: status.color,
                                    origin: CGPoint(x: textX + f.dx, y: blockTop), maxWidth: Metrics.maxTextWidth,
                                    maxLines: 1, opacity: o, blur: f.blur))
        }
        var titleW = 0.0
        if let text = title.shown {
            let maxW = Metrics.maxTextWidth - (badgeW > 0 ? badgeW + Metrics.badgeGap : 0)
            titleW = Double(raster.measure(text, style: .title, maxWidth: maxW).width)
            if title.opacity.value > 0.005 {
                let o = clamp(title.opacity.value, 0, 1)
                let f = fade(o)
                s.texts.append(TextDraw(key: "title", text: text, style: .title, color: title.color,
                                        origin: CGPoint(x: textX + f.dx, y: blockTop + statusH), maxWidth: maxW,
                                        maxLines: 1, opacity: o, blur: f.blur))
            }
        }
        if let text = accent.shown, accent.opacity.value > 0.005 {
            let o = clamp(accent.opacity.value, 0, 1)
            let f = fade(o)
            let x = textX + titleW + (titleW > 0 ? Metrics.accentGap : 0) + f.dx
            s.texts.append(TextDraw(key: "accent", text: text, style: .title, color: accent.color,
                                    origin: CGPoint(x: x, y: blockTop + statusH), maxWidth: Metrics.maxTextWidth,
                                    maxLines: 1, opacity: o, blur: f.blur))
            titleW += Double(TextRasterizer.shared.measure(text, style: .title, maxWidth: Metrics.maxTextWidth).width)
                + (titleW > 0 ? Metrics.accentGap : 0)
        }
        if let text = badge.shown, badge.opacity.value > 0.005 {
            let o = clamp(badge.opacity.value, 0, 1)
            let f = fade(o)
            let badgeH = raster.lineHeight(.badge)
            let pillH = badgeH + 1
            let pill = CGRect(x: textX + titleW + Metrics.badgeGap + f.dx,
                              y: blockTop + statusH + (titleH - pillH) / 2 + 0.5, width: badgeW, height: pillH)
            s.badgePill = pill
            s.badgePillOpacity = o
            s.texts.append(TextDraw(key: "badge", text: text, style: .badge, color: badge.color,
                                    origin: CGPoint(x: pill.minX + Metrics.badgePadX - 1, y: pill.minY),
                                    maxWidth: 60, maxLines: 1, opacity: o, blur: f.blur))
        }
        if let text = recap.shown {
            let o = clamp(recap.opacity.value * clamp(recapReveal.value, 0, 1), 0, 1)
            if o > 0.005 {
                s.texts.append(TextDraw(key: "recap", text: text, style: .recap, color: recap.color,
                                        origin: CGPoint(x: textX, y: blockTop + statusH + titleH + Metrics.recapGap
                                                        + (1 - o) * -4),
                                        maxWidth: Metrics.recapMaxWidth, maxLines: Metrics.recapLines,
                                        opacity: o, blur: (1 - o) * 4))
            }
        }
        return s
    }
}
