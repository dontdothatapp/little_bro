import Foundation

/// Shape of one eye, as multipliers/fractions of the base eye.
public struct EyeShape: Equatable, Sendable {
    /// Width multiplier.
    public var width: Double = 1
    /// Height multiplier.
    public var height: Double = 1
    /// Fraction of the eye height covered by a flat top lid (0 open … 1 shut).
    public var lidTop: Double = 0
    /// Tilt of the top lid in radians. Positive lowers the inner corner (cross),
    /// negative raises it (worried / pleading).
    public var lidAngle: Double = 0
    /// 0…1: a dome cut from below turns the eye into a happy "∩" arch.
    public var happy: Double = 0
    /// Corner radius as a fraction of the shorter side.
    public var roundness: Double = 0.42

    public init(width: Double = 1, height: Double = 1, lidTop: Double = 0, lidAngle: Double = 0,
                happy: Double = 0, roundness: Double = 0.42) {
        self.width = width
        self.height = height
        self.lidTop = lidTop
        self.lidAngle = lidAngle
        self.happy = happy
        self.roundness = roundness
    }

    public func mixed(with o: EyeShape, _ t: Double) -> EyeShape {
        EyeShape(width: lerp(width, o.width, t), height: lerp(height, o.height, t),
                 lidTop: lerp(lidTop, o.lidTop, t), lidAngle: lerp(lidAngle, o.lidAngle, t),
                 happy: lerp(happy, o.happy, t), roundness: lerp(roundness, o.roundness, t))
    }
}

/// A facial expression: both eyes plus how the pair sits.
public struct Expression: Equatable, Sendable {
    public var left: EyeShape
    public var right: EyeShape
    /// Head tilt in radians (rotates the eye pair).
    public var tilt: Double
    /// Distance between the eyes, multiplier.
    public var spacing: Double

    public init(_ both: EyeShape = EyeShape(), tilt: Double = 0, spacing: Double = 1) {
        left = both
        right = both
        self.tilt = tilt
        self.spacing = spacing
    }

    public init(left: EyeShape, right: EyeShape, tilt: Double = 0, spacing: Double = 1) {
        self.left = left
        self.right = right
        self.tilt = tilt
        self.spacing = spacing
    }

    public func mixed(with o: Expression, _ t: Double) -> Expression {
        Expression(left: left.mixed(with: o.left, t), right: right.mixed(with: o.right, t),
                   tilt: lerp(tilt, o.tilt, t), spacing: lerp(spacing, o.spacing, t))
    }

    public static let neutral = Expression()
    public static let happy = Expression(EyeShape(width: 1.08, height: 0.94, happy: 0.8, roundness: 0.5),
                                         spacing: 1.02)
    public static let glad = Expression(EyeShape(width: 1.03, height: 0.96, happy: 0.2, roundness: 0.46))
    public static let wide = Expression(EyeShape(width: 1.1, height: 1.2, roundness: 0.46), spacing: 1.04)
    public static let worried = Expression(EyeShape(width: 1.0, height: 1.06, lidTop: 0.2, lidAngle: -0.42),
                                           spacing: 0.96)
    public static let sleepy = Expression(EyeShape(width: 1.04, height: 0.94, lidTop: 0.46, lidAngle: 0.04))
    public static let drowsy = Expression(EyeShape(width: 1.06, height: 0.9, lidTop: 0.72, lidAngle: 0.04))
    public static let suspicious = Expression(EyeShape(width: 1.04, height: 0.92, lidTop: 0.4, lidAngle: 0.12))
    /// Peeking at a video: round, open, interested.
    public static let peek = Expression(EyeShape(width: 1.04, height: 1.02, roundness: 0.48))
    /// Half-lidded, used when slipping in or out shyly.
    public static let sly = Expression(EyeShape(width: 1.0, height: 0.96, lidTop: 0.2))
    /// The resting face on a "done" card: a clearly content smile.
    public static let content = Expression(EyeShape(width: 1.05, height: 0.94, happy: 0.44, roundness: 0.5))
    /// A hover: delighted squint.
    public static let delighted = Expression(EyeShape(width: 1.06, height: 0.88, happy: 0.5, roundness: 0.5))
    /// Pleading: inner corners raised, a touch bigger.
    public static let pleading = Expression(EyeShape(width: 1.04, height: 1.1, lidTop: 0.16, lidAngle: -0.4),
                                            spacing: 0.96)
    public static let wink = Expression(left: EyeShape(width: 1.12, height: 0.62, happy: 0.92, roundness: 0.5),
                                        right: EyeShape(width: 1.04, height: 1.06),
                                        tilt: 0.14)
    public static let curiousLeft = Expression(left: EyeShape(width: 1.12, height: 1.1),
                                               right: EyeShape(width: 1.08, height: 0.9),
                                               tilt: 0.17)
    public static let curiousRight = Expression(left: EyeShape(width: 1.08, height: 0.9),
                                                right: EyeShape(width: 1.12, height: 1.1),
                                                tilt: -0.17)
}
