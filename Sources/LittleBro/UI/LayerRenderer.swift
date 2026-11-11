import AppKit
import CoreImage
import LittleBroCore
import QuartzCore

/// Pushes a `Scene` into Core Animation layers. Paths are rebuilt every frame on the
/// CPU (cheap at this size); compositing, the glow and the shadow happen on the GPU.
final class LayerRenderer {
    let root: CALayer
    private let body = CAShapeLayer()
    private let face = CALayer()
    private let faceMask = CAShapeLayer()
    private let eyes = [CAShapeLayer(), CAShapeLayer()]
    private let blushes = [CAShapeLayer(), CAShapeLayer()]
    private let pill = CAShapeLayer()
    private var texts: [String: CALayer] = [:]
    private var textContent: [String: String] = [:]
    private var textBlur: [String: Double] = [:]
    private let originX: CGFloat
    private let height: CGFloat
    var scale: CGFloat = 2 {
        didSet { if scale != oldValue { applyScale() } }
    }

    init(root: CALayer, size: CGSize) {
        self.root = root
        originX = size.width / 2
        height = size.height
        root.frame = CGRect(origin: .zero, size: size)
        // Standard (y-up) layer geometry; scene coordinates (y-down) are flipped in `apply`.
        root.isGeometryFlipped = false
        root.masksToBounds = false

        body.frame = root.bounds
        body.fillColor = NSColor.black.cgColor
        body.shadowColor = NSColor.black.cgColor
        body.shadowOffset = CGSize(width: 0, height: -Metrics.shadowOffset)
        body.shadowRadius = 7
        body.shadowOpacity = 0
        root.addSublayer(body)

        face.frame = root.bounds
        faceMask.frame = face.bounds
        faceMask.fillColor = NSColor.black.cgColor
        face.mask = faceMask
        root.addSublayer(face)

        for b in blushes {
            b.frame = face.bounds
            b.fillColor = Metrics.blushColor.with(alpha: 0.55).cgColor
            b.shadowColor = Metrics.blushColor.cgColor
            b.shadowOpacity = 0.9
            b.shadowRadius = 3.5
            b.shadowOffset = .zero
            face.addSublayer(b)
        }
        pill.frame = face.bounds
        pill.fillColor = NSColor(white: 1, alpha: 0.14).cgColor
        face.addSublayer(pill)
        for eye in eyes {
            eye.frame = face.bounds
            eye.fillColor = NSColor.white.cgColor
            eye.strokeColor = NSColor.white.cgColor
            eye.lineJoin = .round
            eye.shadowOffset = .zero
            face.addSublayer(eye)
        }
        applyScale()
        disableActions(on: [root, body, face, faceMask, pill] + eyes + blushes)
    }

    private func applyScale() {
        for l in [root, body, face, faceMask, pill] + eyes + blushes { l.contentsScale = scale }
        for l in texts.values { l.contentsScale = scale }
        textContent.removeAll()
    }

    private func disableActions(on layers: [CALayer]) {
        let none: [String: CAAction] = [
            "path": NSNull(), "shadowPath": NSNull(), "opacity": NSNull(), "position": NSNull(), "bounds": NSNull(),
            "contents": NSNull(), "shadowOpacity": NSNull(), "shadowColor": NSNull(), "shadowRadius": NSNull(),
            "hidden": NSNull(), "filters": NSNull(), "frame": NSNull(), "lineWidth": NSNull(),
        ]
        for l in layers { l.actions = none }
    }

    func apply(_ scene: Scene) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard scene.isVisible, let blobPath = scene.blobPath else {
            body.path = nil
            body.shadowPath = nil
            faceMask.path = nil
            body.shadowOpacity = 0
            face.isHidden = true
            return
        }
        // Scene → layer: origin top-centre, y down → origin bottom-left, y up.
        var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: originX, ty: height)
        let path = blobPath.copy(using: &t)
        body.path = path
        body.shadowPath = path
        body.shadowOpacity = Float(scene.shadowOpacity)
        faceMask.path = path
        face.isHidden = false

        let glow = scene.glowColor.with(alpha: 1).cgColor
        for (i, eye) in eyes.enumerated() {
            guard i < scene.eyes.count else {
                eye.path = nil
                continue
            }
            let p = scene.eyes[i].copy(using: &t)
            eye.path = p
            eye.shadowPath = p
            eye.lineWidth = scene.eyeSoftening
            let alpha = scene.eyeOpacity * (i < scene.eyeAlphas.count ? scene.eyeAlphas[i] : 1)
            eye.opacity = Float(alpha)
            eye.shadowColor = glow
            eye.shadowOpacity = Float(scene.glowOpacity)
            // CG "blur" is roughly twice CA's shadow radius.
            eye.shadowRadius = scene.glowRadius / 2
        }

        for (i, b) in blushes.enumerated() {
            if scene.blushOpacity > 0.005, i < scene.blush.count {
                let p = scene.blush[i].copy(using: &t)
                b.path = p
                b.shadowPath = p
                b.opacity = Float(scene.blushOpacity)
            } else {
                b.path = nil
                b.opacity = 0
            }
        }
        if let r = scene.badgePill, scene.badgePillOpacity > 0.005 {
            pill.path = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: &t)
            pill.opacity = Float(scene.badgePillOpacity)
        } else {
            pill.path = nil
        }

        var seen = Set<String>()
        for d in scene.texts {
            seen.insert(d.key)
            let layer = textLayer(d.key)
            let identity = "\(d.text)|\(d.color)|\(d.maxWidth)|\(d.maxLines)"
            var size = layer.bounds.size
            if textContent[d.key] != identity,
               let out = TextRasterizer.shared.render(d.text, style: d.style, color: d.color, maxWidth: d.maxWidth,
                                                      maxLines: d.maxLines, scale: scale) {
                layer.contents = out.image
                size = out.size
                textContent[d.key] = identity
            }
            layer.frame = CGRect(x: d.origin.x + originX, y: height - d.origin.y - size.height,
                                 width: size.width, height: size.height)
            layer.opacity = Float(d.opacity)
            layer.isHidden = false
            setBlur(layer, key: d.key, radius: d.blur)
        }
        for (key, layer) in texts where !seen.contains(key) {
            layer.isHidden = true
        }
    }

    private func textLayer(_ key: String) -> CALayer {
        if let l = texts[key] { return l }
        let l = CALayer()
        l.contentsScale = scale
        l.contentsGravity = .resize
        l.masksToBounds = false
        disableActions(on: [l])
        face.addSublayer(l)
        texts[key] = l
        return l
    }

    private func setBlur(_ layer: CALayer, key: String, radius: Double) {
        let r = (radius * 4).rounded() / 4 // quantise: fewer filter updates
        if r < 0.25 {
            if textBlur[key] != nil {
                layer.filters = nil
                textBlur[key] = nil
            }
            return
        }
        if textBlur[key] == nil {
            let f = CIFilter(name: "CIGaussianBlur")!
            f.name = "blur"
            f.setValue(r, forKey: kCIInputRadiusKey)
            layer.filters = [f]
            textBlur[key] = r
        } else if textBlur[key] != r {
            layer.setValue(r, forKeyPath: "filters.blur.inputRadius")
            textBlur[key] = r
        }
    }
}
