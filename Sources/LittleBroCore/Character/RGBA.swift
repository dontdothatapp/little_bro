import CoreGraphics

public struct RGBA: Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let white = RGBA(1, 1, 1)
    public static let black = RGBA(0, 0, 0)
    /// Warm, Claude-ish orange. The only colour Little Bro uses for now, and only for "needs you".
    public static let claude = RGBA(0.96, 0.58, 0.40)

    public func with(alpha: Double) -> RGBA { RGBA(r, g, b, alpha) }

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}
