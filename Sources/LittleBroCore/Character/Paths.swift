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
    // MARK: - Eye ↔ heart morph

    /// Points around a rounded rectangle, evenly spaced by arc length, starting at the top
    /// centre and going clockwise on screen (y down).
    static func roundedRectOutline(width w: Double, height h: Double, radius rIn: Double, count n: Int) -> [CGPoint] {
        let r = max(0, min(rIn, min(w, h) / 2))
        let hw = w / 2, hh = h / 2
        let straightX = w - 2 * r, straightY = h - 2 * r
        let arc = Double.pi / 2 * r
        let perimeter = 2 * straightX + 2 * straightY + 4 * arc
        guard perimeter > 0 else { return Array(repeating: .zero, count: n) }
        func point(at sIn: Double) -> CGPoint {
            var s = sIn.truncatingRemainder(dividingBy: perimeter)
            // Top edge, right half.
            if s < straightX / 2 { return CGPoint(x: s, y: -hh) }
            s -= straightX / 2
            // Top-right corner.
            if s < arc { let a = -Double.pi / 2 + s / max(r, 1e-9); return CGPoint(x: hw - r + r * cos(a), y: -hh + r + r * sin(a)) }
            s -= arc
            if s < straightY { return CGPoint(x: hw, y: -hh + r + s) }
            s -= straightY
            if s < arc { let a = s / max(r, 1e-9); return CGPoint(x: hw - r + r * cos(a), y: hh - r + r * sin(a)) }
            s -= arc
            if s < straightX { return CGPoint(x: hw - r - s, y: hh) }
            s -= straightX
            if s < arc { let a = Double.pi / 2 + s / max(r, 1e-9); return CGPoint(x: -hw + r + r * cos(a), y: hh - r + r * sin(a)) }
            s -= arc
            if s < straightY { return CGPoint(x: -hw, y: hh - r - s) }
            s -= straightY
            if s < arc { let a = Double.pi + s / max(r, 1e-9); return CGPoint(x: -hw + r + r * cos(a), y: -hh + r + r * sin(a)) }
            s -= arc
            return CGPoint(x: -hw + r + s, y: -hh)
        }
        return (0..<n).map { point(at: Double($0) / Double(n) * perimeter) }
    }

    /// Points around a heart of the given width, evenly spaced by arc length, starting at the
    /// dip between the lobes and going clockwise on screen (y down). Centred on its bounds.
    static func heartOutline(width: Double, count n: Int) -> [CGPoint] {
        let unit = unitHeart(count: n)
        return unit.map { CGPoint(x: $0.x * width, y: $0.y * width) }
    }

    private static let heartCacheLock = NSLock()
    nonisolated(unsafe) private static var heartCache: [Int: [CGPoint]] = [:]

    /// The heart outline for width 1, computed once per point count.
    static func unitHeart(count n: Int) -> [CGPoint] {
        heartCacheLock.lock(); defer { heartCacheLock.unlock() }
        if let c = heartCache[n] { return c }
        let c = computeHeartOutline(width: 1, count: n)
        heartCache[n] = c
        return c
    }

    private static func computeHeartOutline(width: Double, count n: Int) -> [CGPoint] {
        // The classic parametric heart, flipped for y-down; t = 0 is the dip.
        let dense = 720
        var pts: [CGPoint] = []
        pts.reserveCapacity(dense)
        for i in 0..<dense {
            let t = Double(i) / Double(dense) * 2 * .pi
            let x = 16 * pow(sin(t), 3)
            let y = -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))
            pts.append(CGPoint(x: x, y: y))
        }
        let minY = pts.map(\.y).min() ?? 0, maxY = pts.map(\.y).max() ?? 0
        let scale = width / 32
        let midY = (minY + maxY) / 2
        pts = pts.map { CGPoint(x: $0.x * scale, y: ($0.y - midY) * scale) }
        // Resample by arc length so it lines up with the rectangle's points.
        var cumulative = [0.0]
        for i in 1...pts.count {
            let a = pts[i - 1], b = pts[i % pts.count]
            cumulative.append(cumulative[i - 1] + Double(hypot(b.x - a.x, b.y - a.y)))
        }
        let total = cumulative.last ?? 1
        var out: [CGPoint] = []
        var j = 0
        for k in 0..<n {
            let target = Double(k) / Double(n) * total
            while j < pts.count - 1 && cumulative[j + 1] < target { j += 1 }
            let span = cumulative[j + 1] - cumulative[j]
            let u = span > 0 ? (target - cumulative[j]) / span : 0
            let a = pts[j], b = pts[(j + 1) % pts.count]
            out.append(CGPoint(x: Double(a.x) + (Double(b.x) - Double(a.x)) * u, y: Double(a.y) + (Double(b.y) - Double(a.y)) * u))
        }
        return out
    }

    /// An eye part-way to being a heart (`mix` 0 = eye, 1 = heart).
    public static func eyeHeart(center: CGPoint, width ew: Double, height eh: Double, roundness: Double,
                                heartWidth: Double, mix: Double, rotation: Double) -> CGPath {
        let n = 96
        let rect = roundedRectOutline(width: max(ew, 0.5), height: max(eh, 0.5),
                                      radius: min(ew, eh) * clamp(roundness, 0, 0.5), count: n)
        let heart = heartOutline(width: heartWidth, count: n)
        let m = clamp(mix, 0, 1.2)
        let path = CGMutablePath()
        for i in 0..<n {
            let p = CGPoint(x: Double(rect[i].x) + (Double(heart[i].x) - Double(rect[i].x)) * m,
                            y: Double(rect[i].y) + (Double(heart[i].y) - Double(rect[i].y)) * m)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        var t = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: rotation)
        return path.copy(using: &t) ?? path
    }

    /// A small heart (for floating decorations).
    public static func heart(center: CGPoint, width: Double) -> CGPath {
        let pts = heartOutline(width: width, count: 48)
        let path = CGMutablePath()
        for (i, p) in pts.enumerated() {
            let q = CGPoint(x: p.x + center.x, y: p.y + center.y)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        return path
    }
}
