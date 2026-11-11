import CoreGraphics
import CoreImage
import Foundation

/// Draws a `Scene` into a bitmap — used by the offline preview renderer and tests.
/// It mirrors what `LayerRenderer` does on screen: same paths, same text images,
/// same glow and shadow parameters.
public struct BitmapRenderer {
    public enum Backdrop: String, CaseIterable, Sendable {
        case none
        /// A dark wallpaper with a translucent dark menu bar.
        case dark
        /// A light wallpaper with a translucent light menu bar.
        case light
        /// A video frame (for the YouTube peek).
        case video
    }

    public var size: CGSize
    public var scale: Double
    public var backdrop: Backdrop

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    public init(size: CGSize = Metrics.canvas, scale: Double = 2, backdrop: Backdrop = .dark) {
        self.size = size
        self.scale = scale
        self.backdrop = backdrop
    }

    public func render(_ scene: Scene, cursor: CGPoint? = nil) -> CGImage? {
        let pxW = Int(size.width * scale)
        let pxH = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        // Flip to y-down, origin top-left.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        drawBackdrop(ctx)
        ctx.translateBy(x: size.width / 2, y: 0)

        if scene.isVisible, let blob = scene.blobPath {
            // Shadow (CG shadow offsets live in device space, y up: negative = down on screen).
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -Metrics.shadowOffset * scale), blur: 14 * scale,
                          color: RGBA(0, 0, 0, scene.shadowOpacity).cgColor)
            ctx.addPath(blob)
            ctx.setFillColor(RGBA.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            ctx.saveGState()
            ctx.addPath(blob)
            ctx.clip()
            drawTexts(ctx, scene.texts.filter { $0.plane == .behindEyes })
            drawShapes(ctx, scene.shapes.filter { $0.plane == .behindEyes })
            if scene.blushOpacity > 0.005 {
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 7 * scale, color: scene.blushColor.with(alpha: 0.9).cgColor)
                ctx.setFillColor(scene.blushColor.with(alpha: 0.55 * scene.blushOpacity).cgColor)
                for b in scene.blush {
                    ctx.addPath(b)
                    ctx.fillPath()
                }
                ctx.restoreGState()
            }
            if scene.eyeOpacity > 0.001 {
                for (i, eye) in scene.eyes.enumerated() {
                    let alpha = scene.eyeOpacity * (i < scene.eyeAlphas.count ? scene.eyeAlphas[i] : 1)
                    guard alpha > 0.001 else { continue }
                    ctx.saveGState()
                    ctx.setShadow(offset: .zero, blur: scene.glowRadius * scale,
                                  color: scene.glowColor.with(alpha: scene.glowOpacity).cgColor)
                    ctx.setAlpha(alpha)
                    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                    ctx.setFillColor(scene.eyeColor.cgColor)
                    ctx.setStrokeColor(scene.eyeColor.cgColor)
                    ctx.setLineWidth(scene.eyeSoftening)
                    ctx.setLineJoin(.round)
                    ctx.addPath(eye)
                    ctx.drawPath(using: .fillStroke)
                    ctx.endTransparencyLayer()
                    ctx.restoreGState()
                }
            }
            if let pill = scene.badgePill, scene.badgePillOpacity > 0.005 {
                ctx.setFillColor(RGBA(1, 1, 1, 0.14 * scene.badgePillOpacity).cgColor)
                ctx.addPath(CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2,
                                   transform: nil))
                ctx.fillPath()
            }
            drawShapes(ctx, scene.shapes.filter { $0.plane == .aboveEyes })
            drawTexts(ctx, scene.texts.filter { $0.plane == .aboveEyes })
            ctx.restoreGState()
            drawShapes(ctx, scene.shapes.filter { $0.plane == .overlay })
            drawTexts(ctx, scene.texts.filter { $0.plane == .overlay })
        }

        if let c = cursor { drawCursor(ctx, at: c) }
        return ctx.makeImage()
    }

    private func drawShapes(_ ctx: CGContext, _ shapes: [ShapeDraw]) {
        for sh in shapes where sh.opacity > 0.001 {
            ctx.saveGState()
            if let g = sh.glow, sh.glowRadius > 0 {
                ctx.setShadow(offset: .zero, blur: sh.glowRadius * scale, color: g.cgColor)
            }
            ctx.setAlpha(sh.opacity)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            if let f = sh.fill {
                ctx.addPath(sh.path)
                ctx.setFillColor(f.cgColor)
                ctx.fillPath()
            }
            if let st = sh.stroke, sh.lineWidth > 0 {
                ctx.addPath(sh.path)
                ctx.setStrokeColor(st.cgColor)
                ctx.setLineWidth(sh.lineWidth)
                ctx.strokePath()
            }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    private func drawTexts(_ ctx: CGContext, _ texts: [TextDraw]) {
        for t in texts {
            guard let out = TextRasterizer.shared.render(t.text, style: t.style, color: t.color,
                                                         maxWidth: t.maxWidth, maxLines: t.maxLines,
                                                         scale: scale) else { continue }
            var image = out.image
            var drawRect = CGRect(origin: t.origin, size: out.size)
            if t.blur > 0.25, let blurred = blur(image, radius: t.blur * scale) {
                image = blurred.image
                drawRect = drawRect.insetBy(dx: -blurred.padPx / scale, dy: -blurred.padPx / scale)
            }
            ctx.saveGState()
            ctx.setAlpha(t.opacity)
            if let g = t.glow { ctx.setShadow(offset: .zero, blur: 5 * scale, color: g.cgColor) }
            ctx.translateBy(x: drawRect.minX, y: drawRect.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(origin: .zero, size: drawRect.size))
            ctx.restoreGState()
        }
    }

    /// Blurs an image; `radius` and the returned padding are in pixels.
    private func blur(_ image: CGImage, radius: Double) -> (image: CGImage, padPx: Double)? {
        let pad = ceil(radius * 3)
        guard let f = CIFilter(name: "CIGaussianBlur") else { return nil }
        f.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        f.setValue(radius, forKey: kCIInputRadiusKey)
        guard let out = f.outputImage else { return nil }
        let extent = CGRect(x: -pad, y: -pad, width: Double(image.width) + pad * 2,
                            height: Double(image.height) + pad * 2)
        guard let cg = Self.ciContext.createCGImage(out, from: extent) else { return nil }
        return (cg, pad)
    }

    private func drawBackdrop(_ ctx: CGContext) {
        let full = CGRect(origin: .zero, size: size)
        switch backdrop {
        case .none:
            return
        case .dark, .light, .video:
            let colors: [CGColor]
            switch backdrop {
            case .light:
                colors = [RGBA(0.86, 0.88, 0.93).cgColor, RGBA(0.74, 0.79, 0.88).cgColor]
            case .video:
                colors = [RGBA(0.16, 0.21, 0.26).cgColor, RGBA(0.36, 0.30, 0.24).cgColor]
            default:
                colors = [RGBA(0.13, 0.15, 0.25).cgColor, RGBA(0.29, 0.22, 0.36).cgColor]
            }
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray,
                                      locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width * 0.4, y: size.height),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            if backdrop == .video { return }
            // Menu bar.
            let barH = 24.0
            let bar = CGRect(x: 0, y: 0, width: full.width, height: barH)
            ctx.setFillColor(backdrop == .light ? RGBA(1, 1, 1, 0.62).cgColor : RGBA(0, 0, 0, 0.32).cgColor)
            ctx.fill(bar)
            let ink = backdrop == .light ? RGBA(0, 0, 0, 0.55) : RGBA(1, 1, 1, 0.7)
            ctx.setFillColor(ink.cgColor)
            var x = 14.0
            for w in [12.0, 34, 28, 30, 44] {
                ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 8, width: w, height: 8), cornerWidth: 3,
                                   cornerHeight: 3, transform: nil))
                x += w + 14
            }
            x = full.width - 14
            for w in [52.0, 16, 16, 18] {
                x -= w
                ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: 8, width: w, height: 8), cornerWidth: 3,
                                   cornerHeight: 3, transform: nil))
                x -= 12
            }
            ctx.fillPath()
        }
    }

    private func drawCursor(_ ctx: CGContext, at p: CGPoint) {
        let path = CGMutablePath()
        path.move(to: p)
        path.addLine(to: CGPoint(x: p.x, y: p.y + 16))
        path.addLine(to: CGPoint(x: p.x + 4.2, y: p.y + 12.2))
        path.addLine(to: CGPoint(x: p.x + 7, y: p.y + 18))
        path.addLine(to: CGPoint(x: p.x + 9.4, y: p.y + 17))
        path.addLine(to: CGPoint(x: p.x + 6.7, y: p.y + 11.3))
        path.addLine(to: CGPoint(x: p.x + 11.5, y: p.y + 11.3))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(RGBA.black.cgColor)
        ctx.setStrokeColor(RGBA.white.cgColor)
        ctx.setLineWidth(1.2)
        ctx.drawPath(using: .fillStroke)
    }
}
