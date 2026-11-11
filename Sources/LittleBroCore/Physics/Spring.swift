import Foundation

/// Spring tuning in the same terms SwiftUI uses: `response` is the period (seconds)
/// of the undamped oscillation, `damping` the damping fraction (1 = critical).
public struct SpringParams: Equatable, Sendable {
    public var response: Double
    public var damping: Double

    public init(response: Double, damping: Double) {
        self.response = response
        self.damping = damping
    }
}

/// A damped harmonic oscillator advanced with its closed-form solution.
/// Exact for any `dt`, so a dropped frame never makes the motion jump or explode,
/// and the target can be changed at any moment without losing velocity.
public struct Spring: Sendable {
    public var value: Double
    public var velocity: Double
    public var target: Double
    public var params: SpringParams

    public init(_ value: Double, _ params: SpringParams) {
        self.value = value
        self.velocity = 0
        self.target = value
        self.params = params
    }

    public mutating func step(_ dt: Double) {
        guard dt > 0 else { return }
        let omega = 2 * Double.pi / max(params.response, 1e-4)
        let zeta = max(params.damping, 0)
        let x0 = value - target
        let v0 = velocity
        if abs(x0) < 1e-9 && abs(v0) < 1e-9 {
            value = target
            velocity = 0
            return
        }
        let x: Double
        let v: Double
        if zeta < 0.9999 {
            let wd = omega * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega * dt)
            let c = cos(wd * dt)
            let s = sin(wd * dt)
            let a = x0
            let b = (v0 + zeta * omega * x0) / wd
            x = decay * (a * c + b * s)
            v = decay * ((b * wd - zeta * omega * a) * c - (a * wd + zeta * omega * b) * s)
        } else if zeta <= 1.0001 {
            let decay = exp(-omega * dt)
            let a = x0
            let b = v0 + omega * x0
            x = (a + b * dt) * decay
            v = (b - omega * (a + b * dt)) * decay
        } else {
            let root = (zeta * zeta - 1).squareRoot()
            let r1 = -omega * (zeta - root)
            let r2 = -omega * (zeta + root)
            let c2 = (v0 - r1 * x0) / (r2 - r1)
            let c1 = x0 - c2
            let e1 = exp(r1 * dt)
            let e2 = exp(r2 * dt)
            x = c1 * e1 + c2 * e2
            v = r1 * c1 * e1 + r2 * c2 * e2
        }
        value = target + x
        velocity = v
    }

    public func isSettled(_ epsilon: Double = 0.01) -> Bool {
        abs(value - target) < epsilon && abs(velocity) < epsilon * 10
    }

    public mutating func snap(to v: Double) {
        value = v
        target = v
        velocity = 0
    }
}

@inline(__always) public func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
    min(max(x, lo), hi)
}

@inline(__always) public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}
