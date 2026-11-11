import AppKit
import CoreText

public enum TextStyle: Hashable, Sendable {
    case status
    case title
    case badge
    case recap
    /// Terminal text (SF Mono).
    case mono
    case monoBold
    /// Tiny glyphs for the code rain.
    case rain
    /// Scoreboard digits.
    case score
    /// Tiny numbers on the working strip.
    case micro

    var pointSize: CGFloat {
        switch self {
        case .status: 11
        case .title: 13
        case .badge: 11
        case .recap: 11.5
        case .mono: 10.5
        case .monoBold: 11.5
        case .rain: 8.5
        case .score: 10
        case .micro: 8.5
        }
    }

    var weight: NSFont.Weight {
        switch self {
        case .status: .medium
        case .title: .semibold
        case .badge: .semibold
        case .recap: .regular
        case .mono: .semibold
        case .monoBold: .heavy
        case .rain: .medium
        case .score: .bold
        case .micro: .semibold
        }
    }

    var isMonospaced: Bool {
        switch self {
        case .mono, .monoBold, .rain, .score: true
        default: false
        }
    }
}

/// Measures and rasterises the little bits of text Little Bro shows, in SF Pro Rounded.
/// Results are cached, so per-frame calls are dictionary lookups.
public final class TextRasterizer {
    public static let shared = TextRasterizer()

    public struct Output {
        public let image: CGImage
        /// Size in points.
        public let size: CGSize
    }

    private struct RenderKey: Hashable {
        let text: String
        let style: TextStyle
        let color: RGBA
        let maxWidth: Int
        let maxLines: Int
        let scale: Int
    }

    private struct MeasureKey: Hashable {
        let text: String
        let style: TextStyle
        let maxWidth: Int
        let maxLines: Int
    }

    private var renders: [RenderKey: Output] = [:]
    private var measures: [MeasureKey: CGSize] = [:]
    private var fonts: [TextStyle: CTFont] = [:]
    private let lock = NSLock()

    public init() {}

    func font(_ style: TextStyle) -> CTFont {
        if let f = fonts[style] { return f }
        if style.isMonospaced {
            let mono = NSFont.monospacedSystemFont(ofSize: style.pointSize, weight: style.weight) as CTFont
            fonts[style] = mono
            return mono
        }
        let base = NSFont.systemFont(ofSize: style.pointSize, weight: style.weight)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let font = (NSFont(descriptor: descriptor, size: style.pointSize) ?? base) as CTFont
        fonts[style] = font
        return font
    }

    public func lineHeight(_ style: TextStyle) -> Double {
        lock.lock(); defer { lock.unlock() }
        let f = font(style)
        return Double(ceil(CTFontGetAscent(f) + CTFontGetDescent(f) + 1))
    }

    public func measure(_ text: String, style: TextStyle, maxWidth: Double, maxLines: Int = 1) -> CGSize {
        lock.lock(); defer { lock.unlock() }
        let key = MeasureKey(text: text, style: style, maxWidth: Int(maxWidth.rounded()), maxLines: maxLines)
        if let s = measures[key] { return s }
        let lines = layout(text, style: style, color: .white, maxWidth: maxWidth, maxLines: maxLines)
        let size = blockSize(lines, style: style)
        measures[key] = size
        return size
    }

    public func render(_ text: String, style: TextStyle, color: RGBA, maxWidth: Double,
                       maxLines: Int = 1, scale: Double) -> Output? {
        lock.lock(); defer { lock.unlock() }
        let key = RenderKey(text: text, style: style, color: color, maxWidth: Int(maxWidth.rounded()),
                            maxLines: maxLines, scale: Int((scale * 100).rounded()))
        if let o = renders[key] { return o }
        let lines = layout(text, style: style, color: color, maxWidth: maxWidth, maxLines: maxLines)
        let size = blockSize(lines, style: style)
        guard size.width > 0, size.height > 0 else { return nil }
        let pad = 1.0
        let pxW = Int(ceil((size.width + pad * 2) * scale))
        let pxH = Int(ceil((size.height + pad * 2) * scale))
        guard let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setAllowsFontSmoothing(false)
        ctx.setShouldSmoothFonts(false)
        ctx.setShouldAntialias(true)
        let f = font(style)
        let ascent = CTFontGetAscent(f)
        let lh = CGFloat(lineHeightUnlocked(style))
        let totalH = CGFloat(size.height + pad * 2)
        for (i, line) in lines.enumerated() {
            // Bitmap contexts are y-up: first line at the top.
            let baseline = totalH - CGFloat(pad) - ascent - CGFloat(i) * lh
            ctx.textPosition = CGPoint(x: pad, y: baseline)
            CTLineDraw(line, ctx)
        }
        guard let image = ctx.makeImage() else { return nil }
        let out = Output(image: image, size: CGSize(width: size.width + pad * 2, height: size.height + pad * 2))
        if renders.count > 800 { renders.removeAll() }
        renders[key] = out
        return out
    }

    // MARK: - Internals (call with the lock held)

    private func lineHeightUnlocked(_ style: TextStyle) -> Double {
        let f = font(style)
        return Double(ceil(CTFontGetAscent(f) + CTFontGetDescent(f) + 1))
    }

    private func blockSize(_ lines: [CTLine], style: TextStyle) -> CGSize {
        guard !lines.isEmpty else { return .zero }
        var width = 0.0
        for line in lines {
            width = max(width, Double(CTLineGetTypographicBounds(line, nil, nil, nil)))
        }
        let lh = lineHeightUnlocked(style)
        return CGSize(width: ceil(width), height: lh * Double(lines.count))
    }

    private func layout(_ text: String, style: TextStyle, color: RGBA, maxWidth: Double, maxLines: Int) -> [CTLine] {
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return [] }
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(style),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        let attributed = NSAttributedString(string: clean, attributes: attrs)
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attrs))
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let length = attributed.length
        var lines: [CTLine] = []
        var start = 0
        while start < length && lines.count < max(maxLines, 1) {
            let isLast = lines.count == max(maxLines, 1) - 1
            if isLast {
                let rest = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: length - start))
                let width = CTLineGetTypographicBounds(rest, nil, nil, nil)
                if width > maxWidth {
                    lines.append(CTLineCreateTruncatedLine(rest, maxWidth, .end, ellipsis) ?? rest)
                } else {
                    lines.append(rest)
                }
                break
            }
            let count = CTTypesetterSuggestLineBreak(typesetter, start, maxWidth)
            guard count > 0 else { break }
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        return lines
    }
}
