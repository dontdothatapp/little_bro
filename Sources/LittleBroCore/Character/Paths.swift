import CoreGraphics
import Foundation

/// Geometry builders. Scene coordinates: origin at the top-centre of the screen, y down.
public enum Paths {
    /// Cubic Bézier handle length for a quarter circle.
    static let kappa = 0.5522847498

    /// The black body hanging from the top edge.
    ///
    /// Concave "ears" flare it into the top edge like a drop of liquid under surface
    /// tension. While it moves, the bottom edge bulges like a drop (`bulge` ≥ 0), and the
    /// whole body can lean (`lean`: horizontal shift of the bottom edge, top stays put).
    /// The bottom corners meet the bulge tangent-continuously, so there is never a crease.
    public static func blob(width w: Double, height h: Double, cornerRadius: Double,
                            earRadius: Double, bulge rawBulge: Double = 0, lean: Double = 0) -> CGPath {
        let path = CGMutablePath()
        guard w > 0.5, h > 0.2 else { return path }
        let re = max(0, min(earRadius, h * 0.4, w * 0.14))
        let rb = max(0, min(cornerRadius, h - re, w / 2 - 0.25))
        let k = kappa
        let left = -w / 2
        let right = w / 2
        let above = -48.0 // extend above the screen edge so there is never a seam
        let flat = right - rb - (left + rb)
        let bulge = flat > 0.5 ? max(0, rawBulge) : 0
        // Tangent angle where the bottom quad leaves the corners.
        let theta = bulge > 0 ? atan(4 * bulge / flat) : 0
        let ct = cos(theta), st = sin(theta)

        path.move(to: CGPoint(x: left - re, y: above))
        path.addLine(to: CGPoint(x: left - re, y: 0))
        // Left ear: concave quarter circle centred at (left - re, re).
        path.addCurve(to: CGPoint(x: left, y: re),
                      control1: CGPoint(x: left - re + k * re, y: 0),
                      control2: CGPoint(x: left, y: re - k * re))
        path.addLine(to: CGPoint(x: left, y: h - rb))
        // Bottom-left corner, ending on the bulge's tangent.
        path.addCurve(to: CGPoint(x: left + rb, y: h),
                      control1: CGPoint(x: left, y: h - rb + k * rb),
                      control2: CGPoint(x: left + rb - k * rb * ct, y: h - k * rb * st))
        if bulge > 0 {
            path.addQuadCurve(to: CGPoint(x: right - rb, y: h), control: CGPoint(x: 0, y: h + bulge * 2))
        } else {
            path.addLine(to: CGPoint(x: right - rb, y: h))
        }
        // Bottom-right corner, starting on the bulge's tangent.
        path.addCurve(to: CGPoint(x: right, y: h - rb),
                      control1: CGPoint(x: right - rb + k * rb * ct, y: h - k * rb * st),
                      control2: CGPoint(x: right, y: h - rb + k * rb))
        path.addLine(to: CGPoint(x: right, y: re))
        // Right ear.
        path.addCurve(to: CGPoint(x: right + re, y: 0),
                      control1: CGPoint(x: right, y: re - k * re),
                      control2: CGPoint(x: right + re - k * re, y: 0))
        path.addLine(to: CGPoint(x: right + re, y: above))
        path.closeSubpath()
        guard abs(lean) > 0.01 else { return path }
        // Shear: x' = x + lean * y / h — the top edge stays, the bottom shifts by `lean`.
        var shear = CGAffineTransform(a: 1, b: 0, c: lean / h, d: 1, tx: 0, ty: 0)
        return path.copy(using: &shear) ?? path
    }

    /// One eye. `side` is -1 for the left eye and +1 for the right one, so lid
    /// angles mirror and both eyes stay symmetric.
    public static func eye(center: CGPoint, width ew: Double, height eh: Double, roundness: Double,
                           lidTop: Double, lidAngle: Double, side: Double, happy: Double,
                           rotation: Double) -> CGPath {
        let w = max(ew, 0.5)
        let h = max(eh, 0.5)
        let r = min(min(w, h) * clamp(roundness, 0, 0.5), min(w, h) / 2 - 0.001)
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        var shape: CGPath = CGPath(roundedRect: rect, cornerWidth: max(r, 0), cornerHeight: max(r, 0),
                                   transform: nil)

        if lidTop > 0.002 || abs(lidAngle) > 0.002 {
            // Visible region is everything below the lid line.
            let y0 = -h / 2 + clamp(lidTop, 0, 1) * h
            let slope = tan(clamp(lidAngle, -1.2, 1.2))
            let reach = w * 2 + 4
            func lidY(_ x: Double) -> Double { y0 - side * slope * x }
            let region = CGMutablePath()
            region.move(to: CGPoint(x: -reach, y: lidY(-reach)))
            region.addLine(to: CGPoint(x: reach, y: lidY(reach)))
            region.addLine(to: CGPoint(x: reach, y: h + reach * 3))
            region.addLine(to: CGPoint(x: -reach, y: h + reach * 3))
            region.closeSubpath()
            shape = shape.intersection(region)
        }

        if happy > 0.002 {
            // A dome rising from below carves the eye into an arch.
            let top = h / 2 - clamp(happy, 0, 1) * h * 0.64
            let dome = CGPath(ellipseIn: CGRect(x: -w * 0.92, y: top, width: w * 1.84, height: h * 1.5),
                              transform: nil)
            shape = shape.subtracting(dome)
        }

        var t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation)
        return shape.copy(using: &t) ?? shape
    }
}
