import Foundation

/// Decides when Little Bro pops by while the cursor is still.
///
/// Once the cursor has been still for `stillThreshold` seconds, a visit is planned at a
/// random moment within the next `maxDelay` seconds. Moving the cursor cancels the
/// plan; it is re-planned the next time the cursor rests. After a visit, if the cursor
/// stays still, another one is planned the same way.
public struct IdleVisitPlanner: Sendable {
    public var stillThreshold: Double = 6
    public var minDelay: Double = 25
    public var maxDelay: Double = 300
    /// No visits once there has been no input at all for this long (nobody is there).
    public var awayAfter: Double = 15 * 60
    public private(set) var plannedAt: Double?

    public init() {}

    /// - Parameters:
    ///   - now: monotonic seconds.
    ///   - mouseIdle: seconds since the cursor last moved.
    ///   - inputIdle: seconds since any input.
    ///   - blocked: something else is on screen, or visits are suppressed (video, locked…).
    /// - Returns: true when a visit should start now.
    public mutating func update(now: Double, mouseIdle: Double, inputIdle: Double, blocked: Bool,
                                rng: inout SeededRandom) -> Bool {
        if mouseIdle < stillThreshold || inputIdle > awayAfter {
            plannedAt = nil
            return false
        }
        guard let at = plannedAt else {
            plannedAt = now + rng.range(minDelay, maxDelay)
            return false
        }
        guard now >= at else { return false }
        if blocked {
            plannedAt = now + rng.range(15, 40)
            return false
        }
        plannedAt = now + rng.range(max(minDelay, 90), maxDelay)
        return true
    }
}

/// Decides when the eyes peek at a video the user is watching.
public struct PeekPlanner: Sendable {
    public var firstDelay: ClosedRange<Double> = 90...300
    public var repeatDelay: ClosedRange<Double> = 240...540
    public private(set) var nextAt: Double?

    public init() {}

    public mutating func update(now: Double, watching: Bool, blocked: Bool, rng: inout SeededRandom) -> Bool {
        guard watching else {
            nextAt = nil
            return false
        }
        guard let at = nextAt else {
            nextAt = now + rng.range(firstDelay.lowerBound, firstDelay.upperBound)
            return false
        }
        guard now >= at else { return false }
        if blocked {
            nextAt = now + rng.range(20, 45)
            return false
        }
        nextAt = now + rng.range(repeatDelay.lowerBound, repeatDelay.upperBound)
        return true
    }
}

/// Picks idle variants at random without repeating the last one.
public struct VariantPicker: Sendable {
    private var last: IdleVariant?

    public init() {}

    public mutating func next(_ rng: inout SeededRandom) -> IdleVariant {
        let weights: [(IdleVariant, Double)] = [(.lookAround, 3), (.hello, 2), (.curious, 2), (.sleepy, 1.5), (.shy, 1.5)]
        let options = weights.filter { $0.0 != last }
        let total = options.reduce(0) { $0 + $1.1 }
        var pick = rng.range(0, total)
        for (v, w) in options {
            if pick < w {
                last = v
                return v
            }
            pick -= w
        }
        last = options.last!.0
        return options.last!.0
    }
}
