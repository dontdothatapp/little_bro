import CoreGraphics
import Foundation

/// One point of paddle ball, played out for real: a random serve, two imperfect
/// computer players, a ball that speeds up with every hit. Nobody knows who wins.
/// Coordinates are scene points relative to the court centre line (x) and the screen top (y).
public struct PaddleRally: Sendable {
    public struct Config: Sendable {
        /// Distance from the centre line to each paddle.
        public var halfWidth: Double = 74
        public var top: Double = 7
        public var bottom: Double = 33
        public var paddleHalf: Double = 6.6
        public var paddleHalfWidth: Double = 3.2
        public var ballRadius: Double = 2.4
        public var serveSpeed: Double = 140
        public var speedUp: Double = 1.09
        public var maxSpeed: Double = 330
        public var paddleSpeed: Double = 78
        /// After this long, the players get sloppy so the point always ends.
        public var fatigueAfter: Double = 5.0

        public init() {}
    }

    public let config: Config
    public private(set) var ball: CGPoint
    public private(set) var velocity: CGVector = .zero
    public private(set) var left: Double
    public private(set) var right: Double
    public private(set) var hits = 0
    /// -1: the left player won the point, +1: the right one.
    public private(set) var winner: Int?
    public private(set) var time: Double = 0
    public private(set) var served = false
    private var aim: (left: Double, right: Double)
    private var rng: SeededRandom
    private var missedAt: Double?

    public init(config: Config = Config(), seed: UInt64) {
        self.config = config
        rng = SeededRandom(seed: seed)
        let mid = (config.top + config.bottom) / 2
        ball = CGPoint(x: 0, y: mid)
        left = mid
        right = mid
        aim = (mid, mid)
    }

    /// The point is over and the ball has left the court.
    public var isFinished: Bool {
        guard let m = missedAt else { return false }
        return time - m > 0.35
    }

    public mutating func serve() {
        guard !served else { return }
        served = true
        let dir: Double = rng.chance(0.5) ? 1 : -1
        let angle = rng.range(-0.55, 0.55)
        velocity = CGVector(dx: dir * config.serveSpeed * cos(angle), dy: config.serveSpeed * sin(angle))
        planAim()
    }

    public mutating func step(_ dt: Double) {
        guard dt > 0 else { return }
        var remaining = dt
        while remaining > 0 {
            let h = min(remaining, 1.0 / 240)
            tick(h)
            remaining -= h
        }
    }

    private mutating func tick(_ dt: Double) {
        time += dt
        movePaddles(dt)
        guard served else { return }
        var p = ball
        p.x += velocity.dx * dt
        p.y += velocity.dy * dt
        let r = config.ballRadius
        // Walls.
        if p.y < config.top + r {
            p.y = config.top + r + (config.top + r - p.y)
            velocity.dy = abs(velocity.dy)
        } else if p.y > config.bottom - r {
            p.y = config.bottom - r - (p.y - (config.bottom - r))
            velocity.dy = -abs(velocity.dy)
        }
        // Paddles: test when the ball crosses a paddle's face while moving towards it.
        let face = config.halfWidth - config.paddleHalfWidth - r
        if winner == nil {
            if velocity.dx > 0 && ball.x <= face && p.x > face {
                if abs(p.y - right) <= config.paddleHalf + r { bounce(&p, side: 1) } else { miss(side: 1) }
            } else if velocity.dx < 0 && ball.x >= -face && p.x < -face {
                if abs(p.y - left) <= config.paddleHalf + r { bounce(&p, side: -1) } else { miss(side: -1) }
            }
        }
        ball = p
    }

    private mutating func bounce(_ p: inout CGPoint, side: Double) {
        let paddleY = side > 0 ? right : left
        let face = config.halfWidth - config.paddleHalfWidth - config.ballRadius
        p.x = side * face - (p.x - side * face)
        hits += 1
        let speed = min(config.maxSpeed, hypot(velocity.dx, velocity.dy) * config.speedUp)
        // Where it hits the paddle steers it ("english"), plus a little randomness.
        let offset = clamp((p.y - paddleY) / config.paddleHalf, -1.2, 1.2)
        let angle = clamp(offset * 0.75 + rng.range(-0.12, 0.12), -1.0, 1.0)
        velocity = CGVector(dx: -side * speed * cos(angle), dy: speed * sin(angle))
        planAim()
    }

    private mutating func miss(side: Double) {
        winner = side > 0 ? -1 : 1
        missedAt = time
    }

    /// Each approach, the receiving player commits to a guess. Usually a good one; but the
    /// longer the rally, the likelier they misjudge it — so points stay short and anyone can win.
    private mutating func planAim() {
        let movingRight = velocity.dx > 0
        let predicted = predictArrival()
        let (lo, hi) = paddleRange
        let missChance = min(0.95, 0.1 + Double(hits) * 0.085 + (time > config.fatigueAfter ? 0.7 : 0))
        var target = predicted + gaussian() * 1.6
        if rng.chance(missChance) {
            let gap = config.paddleHalf + config.ballRadius + rng.range(2.5, 7)
            let up = predicted - gap, down = predicted + gap
            let upOK = up >= lo, downOK = down <= hi
            if upOK && downOK { target = rng.chance(0.5) ? up : down } else if upOK { target = up } else if downOK {
                target = down
            }
        }
        let mid = (config.top + config.bottom) / 2
        if movingRight {
            aim.right = target
            aim.left = mid
        } else {
            aim.left = target
            aim.right = mid
        }
    }

    /// Paddles may slide partly past the court edges (under the body's edge).
    private var paddleRange: (Double, Double) {
        (config.top - config.paddleHalf * 0.4, config.bottom + config.paddleHalf * 0.4)
    }

    private func predictArrival() -> Double {
        let face = config.halfWidth - config.paddleHalfWidth - config.ballRadius
        guard abs(velocity.dx) > 1 else { return Double(ball.y) }
        let targetX = velocity.dx > 0 ? face : -face
        let t = (targetX - Double(ball.x)) / Double(velocity.dx)
        var y = Double(ball.y) + Double(velocity.dy) * t
        let lo = config.top + config.ballRadius, hi = config.bottom - config.ballRadius
        let span = hi - lo
        // Unfold wall reflections.
        var u = (y - lo).truncatingRemainder(dividingBy: 2 * span)
        if u < 0 { u += 2 * span }
        y = u <= span ? lo + u : hi - (u - span)
        return y
    }

    private mutating func movePaddles(_ dt: Double) {
        let (lo, hi) = paddleRange
        func approach(_ v: Double, _ target: Double, _ speed: Double) -> Double {
            let d = clamp(target, lo, hi) - v
            let stepMax = speed * dt
            // Ease in the last few points so paddles settle instead of snapping.
            let s = abs(d) < 4 ? d * min(1, dt * 14) : (d > 0 ? stepMax : -stepMax)
            return v + (abs(s) > abs(d) ? d : s)
        }
        left = approach(left, aim.left, velocity.dx < 0 ? config.paddleSpeed : config.paddleSpeed * 0.45)
        right = approach(right, aim.right, velocity.dx > 0 ? config.paddleSpeed : config.paddleSpeed * 0.45)
    }

    private mutating func gaussian() -> Double {
        let u1 = max(rng.range(0, 1), 1e-9), u2 = rng.range(0, 1)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
