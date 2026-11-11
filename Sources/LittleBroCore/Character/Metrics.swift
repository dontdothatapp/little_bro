import CoreGraphics

/// All sizes in points. The scene's origin is the top-centre of the screen, y grows down.
public enum Metrics {
    // Eyes
    public static let eyeWidth: Double = 15
    public static let eyeHeight: Double = 21.5
    public static let eyeGap: Double = 13
    public static let minEyeLine: Double = 1.3
    public static let maxLookX: Double = 10
    public static let maxLookY: Double = 5.5
    public static let peekBottomPad: Double = 5

    // Body
    public static let earRadius: Double = 9
    public static let maxCorner: Double = 22
    public static let shadowOpacity: Double = 0.18
    public static let shadowOffset: Double = 2
    public static let blushColor = RGBA(1.0, 0.47, 0.52)

    // Poses
    public static let compact = CGSize(width: 120, height: 40)
    public static let idle = CGSize(width: 102, height: 40)
    public static let peek = CGSize(width: 80, height: 25)
    public static let hoverGrow = CGSize(width: 10, height: 4)

    // Card layout
    public static let faceBoxWidth: Double = 78
    public static let textLeadingInset: Double = 4
    public static let textRightPadding: Double = 22
    public static let maxTextWidth: Double = 220
    public static let badgePadX: Double = 5
    public static let badgeGap: Double = 7
    public static let recapMaxWidth: Double = 250
    public static let recapLines = 2
    public static let recapGap: Double = 6
    public static let recapBottomPad: Double = 11

    /// Size of the transparent window the scene is drawn into.
    public static let canvas = CGSize(width: 560, height: 200)
}

public struct ScreenProfile: Equatable, Sendable {
    /// Height of the hardware notch (0 on screens without one).
    public var topInset: Double
    /// Width of the hardware notch (0 on screens without one).
    public var minWidth: Double

    public init(topInset: Double = 0, minWidth: Double = 0) {
        self.topInset = topInset
        self.minWidth = minWidth
    }
}
