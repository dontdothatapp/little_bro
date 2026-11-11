import CoreGraphics
import Foundation

let electricYellow = RGBA(1.0, 0.84, 0.04)
let gamerGreen = RGBA(0.24, 0.86, 0.31)
let alertRed = RGBA(1.0, 0.27, 0.23)

// MARK: - Working strip: session count

final class StripOverlay: Overlay {
    var count: Int
    init(count: Int) {
        self.count = count
        super.init()
    }

    override func decorate(_ s: inout Scene, _ d: Director) {
        let p = clamp(presence.value, 0, 1)
        guard s.isVisible, p > 0.01, count > 1, s.blobHeight > 6 else { return }
        let text = String(count)
        let size = TextRasterizer.shared.measure(text, style: .micro, maxWidth: 20)
        s.texts.append(TextDraw(key: "strip-count", text: text, style: .micro, color: RGBA(1, 1, 1, 0.55),
                                origin: CGPoint(x: s.blobWidth / 2 - 8 - Double(size.width), y: (s.blobHeight - Double(size.height)) / 2),
                                maxWidth: 20, maxLines: 1, opacity: p * clamp((s.blobHeight - 6) / 5, 0, 1), blur: 0))
    }
}

// MARK: - Charger: a lightning bolt

final class BoltOverlay: Overlay {
    override func update(_ dt: Double, _ d: Director) {
        super.update(dt, d)
        if time > 0.45 { presence.target = 0 }
    }

    override func decorate(_ s: inout Scene, _ d: Director) {
        guard s.isVisible else { return }
        let flash = clamp(1 - time / 0.34, 0, 1)
        guard flash > 0.01 else { return }
        let x = Double(s.faceCenter.x), bottom = min(s.blobHeight - 4, Double(s.faceCenter.y) + 13)
        let bolt = CGMutablePath()
        bolt.move(to: CGPoint(x: x + 3, y: -2))
        bolt.addLine(to: CGPoint(x: x - 4.5, y: bottom * 0.5))
        bolt.addLine(to: CGPoint(x: x + 0.5, y: bottom * 0.5))
        bolt.addLine(to: CGPoint(x: x - 3, y: bottom))
        bolt.addLine(to: CGPoint(x: x + 6, y: bottom * 0.38))
        bolt.addLine(to: CGPoint(x: x + 1, y: bottom * 0.38))
        bolt.addLine(to: CGPoint(x: x + 6.5, y: -2))
        bolt.closeSubpath()
        s.shapes.append(ShapeDraw(key: "bolt", path: bolt, fill: electricYellow, glow: electricYellow, glowRadius: 12,
                                  opacity: flash))
    }
}

// MARK: - Low battery

final class BatteryOverlay: Overlay {
    override func decorate(_ s: inout Scene, _ d: Director) {
        let p = clamp(presence.value, 0, 1)
        guard s.isVisible, p > 0.01 else { return }
        let x = Double(s.faceCenter.x) + 31, y = Double(s.faceCenter.y) - 4
        let outline = CGMutablePath()
        outline.addRoundedRect(in: CGRect(x: x, y: y, width: 15, height: 8), cornerWidth: 2, cornerHeight: 2)
        s.shapes.append(ShapeDraw(key: "battery", path: outline, stroke: RGBA(1, 1, 1, 0.8), lineWidth: 1.3,
                                  opacity: p))
        s.shapes.append(ShapeDraw(key: "battery-tip", path: CGPath(rect: CGRect(x: x + 15.6, y: y + 2.5, width: 1.6, height: 3), transform: nil),
                                  fill: RGBA(1, 1, 1, 0.8), opacity: p))
        let on = Int(time * 2.2) % 2 == 0
        s.shapes.append(ShapeDraw(key: "battery-level", path: CGPath(rect: CGRect(x: x + 2, y: y + 2, width: 2.6, height: 4), transform: nil),
                                  fill: alertRed, glow: alertRed, glowRadius: 6, opacity: p * (on ? 1 : 0.15)))
    }
}

// MARK: - Download: a file floating up into the body

final class FileOverlay: Overlay {
    let start = 0.15, duration = 0.95
    var position = CGPoint(x: 0, y: 160)

    override func update(_ dt: Double, _ d: Director) {
        super.update(dt, d)
        let u = clamp((time - start) / duration, 0, 1)
        let e = u * u * (3 - 2 * u)
        position = CGPoint(x: 0, y: lerp(150, 22, e))
        if u < 1 { d.gaze = .point(Double(position.x), Double(position.y)) }
        if time > start + duration + 0.1 { presence.target = 0 }
    }

    override func decorate(_ s: inout Scene, _ d: Director) {
        guard s.isVisible, time > start else { return }
        // Fades as it disappears into the body.
        let a = clamp((Double(position.y) - s.blobHeight + 4) / 16, 0, 1) * clamp(presence.value, 0, 1)
        guard a > 0.01 else { return }
        let x = Double(position.x), y = Double(position.y)
        let page = CGMutablePath()
        page.move(to: CGPoint(x: x - 5.5, y: y - 7.5))
        page.addLine(to: CGPoint(x: x + 2, y: y - 7.5))
        page.addLine(to: CGPoint(x: x + 5.5, y: y - 4))
        page.addLine(to: CGPoint(x: x + 5.5, y: y + 7.5))
        page.addLine(to: CGPoint(x: x - 5.5, y: y + 7.5))
        page.closeSubpath()
        let fold = CGMutablePath()
        fold.move(to: CGPoint(x: x + 2, y: y - 7.5))
        fold.addLine(to: CGPoint(x: x + 2, y: y - 4))
        fold.addLine(to: CGPoint(x: x + 5.5, y: y - 4))
        fold.closeSubpath()
        s.shapes.append(ShapeDraw(key: "file", path: page, fill: .white, glow: RGBA(1, 1, 1, 0.6), glowRadius: 6,
                                  opacity: a, plane: .overlay))
        s.shapes.append(ShapeDraw(key: "file-fold", path: fold, fill: RGBA(0.62, 0.62, 0.62), opacity: a, plane: .overlay))
    }
}

// MARK: - Mute / unmute: a speaker

final class SpeakerOverlay: Overlay {
    let muted: Bool
    init(muted: Bool) {
        self.muted = muted
        super.init()
    }

    override func decorate(_ s: inout Scene, _ d: Director) {
        let p = clamp(presence.value, 0, 1)
        guard s.isVisible, p > 0.01 else { return }
        let x = Double(s.faceCenter.x) + 30, y = Double(s.faceCenter.y)
        let body = CGMutablePath()
        body.move(to: CGPoint(x: x, y: y - 2.6))
        body.addLine(to: CGPoint(x: x + 3, y: y - 2.6))
        body.addLine(to: CGPoint(x: x + 7.5, y: y - 6.5))
        body.addLine(to: CGPoint(x: x + 7.5, y: y + 6.5))
        body.addLine(to: CGPoint(x: x + 3, y: y + 2.6))
        body.addLine(to: CGPoint(x: x, y: y + 2.6))
        body.closeSubpath()
        s.shapes.append(ShapeDraw(key: "spk", path: body, fill: .white, glow: RGBA(1, 1, 1, 0.4), glowRadius: 4, opacity: p))
        if muted {
            let draw = clamp((time - 0.15) / 0.25, 0, 1)
            let slash = CGMutablePath()
            slash.move(to: CGPoint(x: x - 2.5, y: y - 7.5))
            slash.addLine(to: CGPoint(x: x - 2.5 + 15 * draw, y: y - 7.5 + 15 * draw))
            s.shapes.append(ShapeDraw(key: "spk-slash", path: slash, stroke: RGBA.claude, lineWidth: 1.7,
                                      glow: RGBA.claude, glowRadius: 5, opacity: p * (draw > 0 ? 1 : 0)))
        } else {
            for (i, r) in [4.2, 7.8].enumerated() {
                let a = clamp((time - 0.2 - Double(i) * 0.15) / 0.2, 0, 1)
                let wave = CGMutablePath()
                wave.addArc(center: CGPoint(x: x + 8, y: y), radius: r, startAngle: -0.8, endAngle: 0.8, clockwise: false)
                s.shapes.append(ShapeDraw(key: "spk-wave\(i)", path: wave, stroke: .white, lineWidth: 1.5,
                                          glow: RGBA(1, 1, 1, 0.4), glowRadius: 4, opacity: p * a))
            }
        }
    }
}

// MARK: - AirPods: two buds at the sides

final class AirPodsOverlay: Overlay {
    var pop = Spring(0, SpringParams(response: 0.42, damping: 0.62))

    override func update(_ dt: Double, _ d: Director) {
        super.update(dt, d)
        if time > 0.35 { pop.target = presence.target }
        pop.step(dt)
    }

    override func decorate(_ s: inout Scene, _ d: Director) {
        let p = clamp(pop.value, -0.2, 1.2)
        guard s.isVisible, presence.value > 0.01, p > 0.01 else { return }
        for side in [-1.0, 1.0] {
            let x = side * (s.blobWidth / 2 + 7), y = lerp(52, 15, p)
            let bud = CGMutablePath()
            bud.addEllipse(in: CGRect(x: x - 4.6, y: y - 5, width: 9.2, height: 10))
            bud.addRoundedRect(in: CGRect(x: x + side * 0.5 - 1.6, y: y + 2, width: 3.2, height: 12.5), cornerWidth: 1.6,
                               cornerHeight: 1.6)
            s.shapes.append(ShapeDraw(key: "airpod\(side)", path: bud, fill: .white, glow: RGBA(1, 1, 1, 0.5),
                                      glowRadius: 5, opacity: clamp(p * 1.4, 0, 1) * clamp(presence.value, 0, 1),
                                      plane: .overlay))
        }
    }
}

// MARK: - Over-ear headphones: big cups, noise fading out

final class OverEarOverlay: Overlay {
    var drop = Spring(0, SpringParams(response: 0.4, damping: 0.62))

    override func update(_ dt: Double, _ d: Director) {
        super.update(dt, d)
        if time > 0.15 { drop.target = presence.target }
        drop.step(dt)
    }

    override func decorate(_ s: inout Scene, _ d: Director) {
        let p = clamp(drop.value, -0.2, 1.2)
        guard s.isVisible, presence.value > 0.01 else { return }
        let w = s.blobWidth, h = s.blobHeight
        let o = clamp(presence.value, 0, 1)
        // Sound around it, shrinking and fading: the noise goes away.
        let quiet = clamp((time - 0.75) / 1.0, 0, 1)
        for side in [-1.0, 1.0] {
            let xc = side * (w / 2 + 2), yc = lerp(-16, h * 0.55, p)
            for i in 0..<3 {
                let r = 8 + Double(i) * 6 - quiet * 6
                let a = (1 - quiet) * (0.55 - Double(i) * 0.15) * (p > 0.6 ? 1 : 0)
                guard a > 0.01, r > 2 else { continue }
                let arc = CGMutablePath()
                let mid = side > 0 ? 0.0 : Double.pi
                arc.addArc(center: CGPoint(x: xc + side * 8, y: yc), radius: r, startAngle: mid - 0.9, endAngle: mid + 0.9,
                           clockwise: false)
                s.shapes.append(ShapeDraw(key: "noise\(side)\(i)", path: arc, stroke: RGBA(1, 1, 1, a), lineWidth: 1.4,
                                          opacity: o, plane: .overlay))
            }
            let band = CGMutablePath()
            band.move(to: CGPoint(x: xc, y: yc - 13))
            band.addCurve(to: CGPoint(x: xc - side * 16, y: -6), control1: CGPoint(x: xc, y: yc - 26),
                          control2: CGPoint(x: xc - side * 6, y: -4))
            s.shapes.append(ShapeDraw(key: "oe-band\(side)", path: band, stroke: .white, lineWidth: 2.6,
                                      glow: RGBA(1, 1, 1, 0.45), glowRadius: 4, opacity: o, plane: .overlay))
            let cup = CGPath(roundedRect: CGRect(x: xc - 8, y: yc - 14, width: 16, height: 28), cornerWidth: 8,
                             cornerHeight: 8, transform: nil)
            s.shapes.append(ShapeDraw(key: "oe-cup\(side)", path: cup, fill: RGBA(0.07, 0.07, 0.07), stroke: .white,
                                      lineWidth: 2, glow: RGBA(1, 1, 1, 0.45), glowRadius: 4, opacity: o, plane: .overlay))
        }
    }
}

// MARK: - Game controller

final class ControllerOverlay: Overlay {
    var slide = Spring(0, SpringParams(response: 0.45, damping: 0.7))
    var lit = false

    override func update(_ dt: Double, _ d: Director) {
        super.update(dt, d)
        if time > 0.15 { slide.target = presence.target }
        slide.step(dt)
    }

    override func decorate(_ s: inout Scene, _ d: Director) {
        let o = clamp(presence.value, 0, 1)
        guard s.isVisible, o > 0.01 else { return }
        let x = lerp(s.blobWidth / 2 + 30, 40, clamp(slide.value, -0.2, 1.2)), y = Double(s.faceCenter.y) + 1
        let pad = CGMutablePath()
        pad.move(to: CGPoint(x: x - 11, y: y - 5))
        pad.addQuadCurve(to: CGPoint(x: x + 11, y: y - 5), control: CGPoint(x: x, y: y - 7.5))
        pad.addQuadCurve(to: CGPoint(x: x + 14, y: y + 8), control: CGPoint(x: x + 17, y: y + 3))
        pad.addQuadCurve(to: CGPoint(x: x + 6, y: y + 4), control: CGPoint(x: x + 10, y: y + 10))
        pad.addLine(to: CGPoint(x: x - 6, y: y + 4))
        pad.addQuadCurve(to: CGPoint(x: x - 14, y: y + 8), control: CGPoint(x: x - 10, y: y + 10))
        pad.addQuadCurve(to: CGPoint(x: x - 11, y: y - 5), control: CGPoint(x: x - 17, y: y + 3))
        s.shapes.append(ShapeDraw(key: "pad", path: pad, stroke: .white, lineWidth: 1.5, opacity: o))
        let dpad = CGMutablePath()
        dpad.addRect(CGRect(x: x - 9, y: y - 1.4, width: 4.5, height: 1.4))
        dpad.addRect(CGRect(x: x - 7.5, y: y - 2.9, width: 1.4, height: 4.5))
        s.shapes.append(ShapeDraw(key: "pad-dpad", path: dpad, fill: .white, opacity: o))
        let buttons: [(Double, Double, RGBA)] = [(7, -2.4, RGBA(1, 0.82, 0.25)), (9.4, 0, RGBA(1, 0.3, 0.37)),
                                                  (4.6, 0, RGBA(0.3, 0.64, 1)), (7, 2.4, gamerGreen)]
        for (i, b) in buttons.enumerated() {
            let dot = CGPath(ellipseIn: CGRect(x: x + b.0 - 1.25, y: y + b.1 - 1.25, width: 2.5, height: 2.5), transform: nil)
            let c = lit ? b.2 : RGBA(1, 1, 1, 0.6)
            s.shapes.append(ShapeDraw(key: "pad-b\(i)", path: dot, fill: c, glow: lit ? c : nil, glowRadius: lit ? 5 : 0,
                                      opacity: o))
        }
    }
}

// MARK: - Mouse: a tiny cursor the eyes chase

final class CursorOverlay: Overlay {
    var position = CGPoint.zero
    let clickAt = 2.1

    override func update(_ dt: Double, _ d: Director) {
        super.update(dt, d)
        let u = clamp((time - 0.2) / 3.6, 0, 1)
        position = CGPoint(x: 50 * sin(u * 2 * .pi * 1.3 + 0.6), y: 20 + 8 * sin(u * 2 * .pi * 2.1))
        if presence.target > 0 { d.gaze = .point(Double(position.x), Double(position.y)) }
        if time >= clickAt && time - dt < clickAt { d.character.blink() }
    }

    override func decorate(_ s: inout Scene, _ d: Director) {
        let o = clamp(presence.value, 0, 1) * clamp((time - 0.2) / 0.3, 0, 1)
        guard s.isVisible, o > 0.01 else { return }
        let x = Double(position.x), y = Double(position.y), k = 0.62
        let arrow = CGMutablePath()
        let pts: [(Double, Double)] = [(0, 0), (0, 16), (4.2, 12.2), (7, 18), (9.4, 17), (6.7, 11.3), (11.5, 11.3)]
        arrow.move(to: CGPoint(x: x, y: y))
        for (px, py) in pts.dropFirst() { arrow.addLine(to: CGPoint(x: x + px * k, y: y + py * k)) }
        arrow.closeSubpath()
        s.shapes.append(ShapeDraw(key: "cursor", path: arrow, fill: .white, glow: RGBA(1, 1, 1, 0.6), glowRadius: 5,
                                  opacity: o))
        let ct = time - clickAt
        if ct > 0 && ct < 0.4 {
            let ring = CGPath(ellipseIn: CGRect(x: x - 3 - ct * 18, y: y - 3 - ct * 18, width: 6 + ct * 36,
                                                height: 6 + ct * 36), transform: nil)
            s.shapes.append(ShapeDraw(key: "cursor-click", path: ring, stroke: .white, lineWidth: 1.2,
                                      opacity: o * clamp(0.8 - ct * 2, 0, 1)))
        }
    }
}

// MARK: - Keyboard: a row of keycaps typing

final class KeycapsOverlay: Overlay {
    var rise = Spring(0, SpringParams(response: 0.4, damping: 0.7))
    static let sequence = [2, 4, 1, 5, 3, 6, 0, 2, 5, 1, 4, 3, 6, 2]

    override func update(_ dt: Double, _ d: Director) {
        super.update(dt, d)
        if time > 0.2 { rise.target = presence.target }
        rise.step(dt)
        if typing { d.look(0.4 * sin(time * 5), 1) }
    }

    var typing: Bool { time > 0.7 && time < 3.2 }

    override func decorate(_ s: inout Scene, _ d: Director) {
        let o = clamp(presence.value, 0, 1)
        guard s.isVisible, o > 0.01 else { return }
        let n = 7, kw = 9.0, gap = 3.0
        let x0 = -(Double(n) * kw + Double(n - 1) * gap) / 2
        let y = lerp(s.blobHeight + 6, s.blobHeight - 13, clamp(rise.value, -0.2, 1.2))
        let beat = Int((time - 0.7) * 7)
        for i in 0..<n {
            let pressed = typing && Self.sequence[max(0, beat) % Self.sequence.count] == i
            let key = CGPath(roundedRect: CGRect(x: x0 + Double(i) * (kw + gap), y: y + (pressed ? 1.2 : 0),
                                                 width: kw, height: 7.5), cornerWidth: 2, cornerHeight: 2, transform: nil)
            s.shapes.append(ShapeDraw(key: "key\(i)", path: key, fill: pressed ? .white : RGBA(1, 1, 1, 0.08),
                                      stroke: .white, lineWidth: 1.2, glow: pressed ? RGBA(1, 1, 1, 0.7) : nil,
                                      glowRadius: pressed ? 6 : 0, opacity: o))
        }
    }
}
