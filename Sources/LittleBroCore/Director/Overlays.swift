import CoreGraphics
import Foundation

/// Extra things an act draws on top of the character (headphones, shades, a court…).
/// Each overlay fades with `presence`, so acts can hand over to each other smoothly.
public class Overlay {
    var presence = Spring(0, SpringParams(response: 0.32, damping: 0.85))
    var time = 0.0

    init() { presence.target = 1 }

    func update(_ dt: Double, _ d: Director) { time += dt }
    func decorate(_ s: inout Scene, _ d: Director) {}

    var isGone: Bool { presence.target == 0 && presence.value < 0.01 }
}

let terminalGreen = RGBA(0.24, 1.0, 0.48)

// MARK: - Headphones

final class HeadphonesOverlay: Overlay {
    override func decorate(_ s: inout Scene, _ d: Director) {
        let p = clamp(presence.value, 0, 1.2)
        guard s.isVisible, p > 0.01 else { return }
        let w = s.blobWidth, h = s.blobHeight
        let cupW = 10.5, cupH = min(20.0, h * 0.52)
        // They drop onto the head as they appear.
        let yc = h * 0.54 - (1 - min(p, 1)) * 18
        for side in [-1.0, 1.0] {
            let xc = side * (w / 2 + 0.5) + s.bodyLean * clamp(yc / max(h, 1), 0, 1)
            let cup = CGPath(roundedRect: CGRect(x: xc - cupW / 2, y: yc - cupH / 2, width: cupW, height: cupH),
                             cornerWidth: cupW / 2, cornerHeight: cupW / 2, transform: nil)
            let band = CGMutablePath()
            band.move(to: CGPoint(x: xc, y: yc - cupH / 2))
            band.addCurve(to: CGPoint(x: xc - side * 12, y: -3), control1: CGPoint(x: xc, y: yc - cupH / 2 - 9),
                          control2: CGPoint(x: xc - side * 3, y: 0))
            let o = clamp(p * 1.4, 0, 1)
            s.shapes.append(ShapeDraw(key: "hp-band\(side)", path: band, stroke: .white, lineWidth: 2.1,
                                      glow: RGBA(1, 1, 1, 0.45), glowRadius: 3, opacity: o, plane: .overlay))
            s.shapes.append(ShapeDraw(key: "hp-cup\(side)", path: cup, fill: RGBA(0.08, 0.08, 0.08), stroke: .white,
                                      lineWidth: 1.9, glow: RGBA(1, 1, 1, 0.45), glowRadius: 3, opacity: o,
                                      plane: .overlay))
        }
    }
}

// MARK: - Hackerman A: pixel shades + terminal

final class ShadesTerminalOverlay: Overlay {
    var drop = Spring(0, SpringParams(response: 0.34, damping: 0.62))
    let command: String
    let finale: String
    var showTerminal = true

    static let commands = ["> sudo hack --mainframe", "> ssh root@mainframe", "> ./bypass_firewall.sh",
                           "> nmap -sS 10.0.0.0/8", "> git push --force", "> make coffee --strong"]
    static let finales = ["ACCESS GRANTED", "I'M IN.", "HACK COMPLETE", "MAINFRAME OWNED"]

    init(rng: inout SeededRandom) {
        command = Self.commands[Int(rng.range(0, Double(Self.commands.count) - 0.001))]
        finale = Self.finales[Int(rng.range(0, Double(Self.finales.count) - 0.001))]
        super.init()
    }

    // Pixel-art shades, inverted to suit a black body: white frames, black glints.
    static let rows = [
        "1111111111111111111111111111",
        "1111111111111111111111111111",
        "0111111111100001111111111110",
        "0111111111100001111111111110",
        "0011111111000000111111111100",
        "0001111110000000011111111000",
    ]
    static let glints = [(3, 2), (4, 3), (17, 2), (18, 3)]

    override func update(_ dt: Double, _ d: Director) {
        super.update(dt, d)
        drop.step(dt)
    }

    override func decorate(_ s: inout Scene, _ d: Director) {
        let p = clamp(presence.value, 0, 1)
        guard s.isVisible, p > 0.01 else { return }
        let px = 2.0
        let gw = Double(Self.rows[0].count) * px, gh = Double(Self.rows.count) * px
        let cx = Double(s.faceCenter.x), cy = lerp(-gh - 4, Double(s.faceCenter.y), drop.value)
        let frames = CGMutablePath(), glints = CGMutablePath()
        for (r, row) in Self.rows.enumerated() {
            for (i, c) in row.enumerated() where c == "1" {
                frames.addRect(CGRect(x: cx - gw / 2 + Double(i) * px, y: cy - gh / 2 + Double(r) * px, width: px, height: px))
            }
        }
        for (i, r) in Self.glints {
            glints.addRect(CGRect(x: cx - gw / 2 + Double(i) * px, y: cy - gh / 2 + Double(r) * px, width: px, height: px))
        }
        if drop.value > 0.01 {
            s.shapes.append(ShapeDraw(key: "shades", path: frames, fill: .white, glow: terminalGreen.with(alpha: 0.75),
                                      glowRadius: 4, opacity: p))
            s.shapes.append(ShapeDraw(key: "shades-glint", path: glints, fill: .black, opacity: p))
        }

        // The terminal, to the right of the face.
        guard showTerminal else { return }
        let x = cx + 40
        let t = time
        let line1Y = Double(s.faceCenter.y) - 14, line2Y = Double(s.faceCenter.y) + 1
        let caret = Int(t * 3) % 2 == 0 ? "█" : " "
        func add(_ key: String, _ text: String, _ style: TextStyle, y: Double, opacity: Double) {
            guard opacity > 0.01 else { return }
            s.texts.append(TextDraw(key: key, text: text, style: style, color: terminalGreen, origin: CGPoint(x: x, y: y),
                                    maxWidth: 200, maxLines: 1, opacity: opacity * p, blur: 0,
                                    glow: terminalGreen.with(alpha: 0.6)))
        }
        if t > 1.75 {
            let n = Int(clamp((t - 1.75) / 1.0, 0, 1) * Double(command.count))
            let typed = String(command.prefix(n))
            add("term-1", typed + (n < command.count || t < 3.0 ? caret : ""), .mono, y: line1Y, opacity: 1)
        }
        if t > 3.0 && t < 4.65 {
            let prog = clamp((t - 3.0) / 1.5, 0, 1), cells = 12, on = Int((prog * Double(cells)).rounded())
            let bar = "[" + String(repeating: "█", count: on) + String(repeating: "░", count: cells - on) + "] "
                + String(Int(prog * 100)) + "%"
            add("term-2", bar, .mono, y: line2Y, opacity: 1)
        }
        if t >= 4.65 {
            let on = Int((t - 4.65) * 4) % 2 == 0 || t > 6.2
            add("term-3", finale, .monoBold, y: line2Y - 1, opacity: on ? 1 : 0.15)
        }
    }
}

// MARK: - Hackerman B: code rain

public final class CodeRainOverlay: Overlay {
    struct Column { var speed: Double; var offset: Double; var seed: Int }
    var columns: [Column] = []
    static let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄ01<>{}/=+*#$;").map(String.init)
    public static let headColor = RGBA(0.8, 1, 0.86)

    /// Renders every glyph once up front so the first frames don't stall.
    public static func warmUp(scale: Double) {
        for g in glyphs {
            for c in [headColor, terminalGreen] {
                _ = TextRasterizer.shared.render(g, style: .rain, color: c, maxWidth: 20, scale: scale)
            }
        }
    }

    init(rng: inout SeededRandom) {
        for c in 0..<13 {
            columns.append(Column(speed: rng.range(26, 46), offset: rng.range(0, 60), seed: c * 7 + Int(rng.range(0, 50))))
        }
        super.init()
    }

    override func decorate(_ s: inout Scene, _ d: Director) {
        let p = clamp(presence.value, 0, 1)
        guard s.isVisible, p > 0.01 else { return }
        let w = s.blobWidth, h = s.blobHeight
        let colW = w / Double(columns.count)
        let tick = Int(time * 9)
        for (c, col) in columns.enumerated() {
            let head = (time * col.speed + col.offset).truncatingRemainder(dividingBy: h + 34) - 8
            for k in 0..<5 {
                let y = head - Double(k) * 9.5
                guard y > -6, y < h else { continue }
                let g = Self.glyphs[(col.seed + k * 5 + tick / (k + 1)) % Self.glyphs.count]
                let alpha = k == 0 ? 0.85 : 0.5 - Double(k) * 0.09
                // Two colours only (fading via opacity), so every glyph image is rendered once and reused.
                let color = k == 0 ? CodeRainOverlay.headColor : terminalGreen
                s.texts.append(TextDraw(key: "rain-\(c)-\(k)", text: g, style: .rain, color: color,
                                        origin: CGPoint(x: -w / 2 + colW * (Double(c) + 0.5) - 3, y: y),
                                        maxWidth: 20, maxLines: 1, opacity: alpha * p, blur: 0, plane: .behindEyes))
            }
        }
        // A dark pocket behind the eyes keeps them readable over the rain.
        let fc = s.faceCenter
        let pocket = CGPath(roundedRect: CGRect(x: Double(fc.x) - 34, y: Double(fc.y) - 13, width: 68, height: 26),
                            cornerWidth: 13, cornerHeight: 13, transform: nil)
        s.shapes.append(ShapeDraw(key: "rain-pocket", path: pocket, fill: RGBA(0, 0, 0, 0.72), glow: .black,
                                  glowRadius: 6, opacity: p, plane: .behindEyes))
    }
}

// MARK: - Paddle court

final class CourtOverlay: Overlay {
    var rally: PaddleRally
    var score: (left: Int, right: Int)
    let serveAt: Double
    var reported = false
    var pop: (side: Int, at: Double)?

    init(score: (Int, Int), seed: UInt64, topInset: Double) {
        var config = PaddleRally.Config()
        config.top += topInset
        config.bottom += topInset
        rally = PaddleRally(config: config, seed: seed)
        self.score = score
        serveAt = 1.05
        super.init()
    }

    override func update(_ dt: Double, _ d: Director) {
        super.update(dt, d)
        if time >= serveAt { rally.serve() }
        rally.step(dt)
        d.character.paddleY = (rally.left, rally.right)
        d.character.paddleHalfSpan = rally.config.halfWidth
        d.character.paddleHeightFactor = rally.config.paddleHalf * 2 / Metrics.eyeHeight
        if rally.isFinished && !reported, let w = rally.winner {
            reported = true
            if w < 0 { score.left += 1 } else { score.right += 1 }
            pop = (w, time)
            d.rallyEnded(winner: w)
        }
    }

    override func decorate(_ s: inout Scene, _ d: Director) {
        let p = clamp(presence.value, 0, 1)
        guard s.isVisible, p > 0.01 else { return }
        let paddles = clamp(d.character.paddleMix.value, 0, 1)
        let cfg = rally.config
        // Centre line.
        let dashes = CGMutablePath()
        var y = cfg.top - 2
        while y < cfg.bottom + 1 {
            dashes.addRect(CGRect(x: -0.75, y: y, width: 1.5, height: 3.5))
            y += 6.5
        }
        s.shapes.append(ShapeDraw(key: "court-line", path: dashes, fill: RGBA(1, 1, 1, 0.16), opacity: p * paddles,
                                  plane: .behindEyes))
        // Ball.
        if rally.served && !rally.isFinished {
            let r = cfg.ballRadius
            let ball = CGPath(roundedRect: CGRect(x: rally.ball.x - r, y: rally.ball.y - r, width: 2 * r, height: 2 * r),
                              cornerWidth: 1, cornerHeight: 1, transform: nil)
            s.shapes.append(ShapeDraw(key: "court-ball", path: ball, fill: .white, glow: RGBA(1, 1, 1, 0.7),
                                      glowRadius: 4, opacity: p))
        }
        // Score: dim digits either side of the centre line; the winner's pops.
        let raster = TextRasterizer.shared
        for (side, value) in [(-1, score.left), (1, score.right)] {
            let text = String(value)
            let size = raster.measure(text, style: .score, maxWidth: 40)
            var alpha = 0.5
            var lift = 0.0
            if let pop, pop.side == side {
                let age = time - pop.at
                alpha = 0.5 + 0.5 * clamp(1 - (age - 1.0) / 0.5, 0, 1)
                lift = age < 0.45 ? -3 * sin(age / 0.45 * .pi) : 0
            }
            let x = side < 0 ? -9 - Double(size.width) : 9
            s.texts.append(TextDraw(key: "score\(side)", text: text, style: .score, color: RGBA(1, 1, 1, alpha),
                                    origin: CGPoint(x: x, y: cfg.top - 5 + lift), maxWidth: 40, maxLines: 1,
                                    opacity: p * paddles, blur: 0, plane: .behindEyes))
        }
    }
}
