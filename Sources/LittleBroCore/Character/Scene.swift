import CoreGraphics

/// A piece of text to draw this frame.
public struct TextDraw {
    public var key: String
    public var text: String
    public var style: TextStyle
    public var color: RGBA
    /// Top-left corner in scene coordinates.
    public var origin: CGPoint
    public var maxWidth: Double
    public var maxLines: Int
    public var opacity: Double
    /// Gaussian blur radius in points (used while fading in/out).
    public var blur: Double
}

/// Everything needed to draw one frame. Produced by `Character.scene()`, consumed
/// by both the on-screen layer renderer and the offline bitmap renderer, so what
/// the previews show is what the screen shows.
public struct Scene {
    public var isVisible = false
    public var blobPath: CGPath?
    public var blobWidth = 0.0
    public var blobHeight = 0.0
    public var shadowOpacity = 0.0
    public var eyes: [CGPath] = []
    public var eyeColor = RGBA.white
    /// Eyes fade in with the body so a sliver never shows stray lines.
    public var eyeOpacity = 1.0
    /// Per-eye opacity (eyes slipping past the body's edge fade out).
    public var eyeAlphas: [Double] = []
    /// Width of a same-colour round-join stroke that softens corners left by lid cuts.
    public var eyeSoftening = 1.3
    /// Soft blush under the eyes (shy moments).
    public var blush: [CGPath] = []
    public var blushColor = RGBA.white
    public var blushOpacity = 0.0
    /// Pill behind the "+N" badge.
    public var badgePill: CGRect?
    public var badgePillOpacity = 0.0
    public var glowColor = RGBA.white
    public var glowOpacity = 0.0
    public var glowRadius = 6.0
    public var texts: [TextDraw] = []
    public var faceCenter = CGPoint.zero

    public init() {}
}
