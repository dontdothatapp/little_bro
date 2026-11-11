import CoreGraphics
import Foundation
import ImageIO
import LittleBroCore
import UniformTypeIdentifiers

// Offline renderer: plays an act frame by frame and writes PNG frames, a contact
// sheet and (with ffmpeg) an MP4, so the animation can be inspected exactly.
//
//   swift run littlebro-render <act> [--out DIR] [--fps 60] [--seconds S] [--backdrop dark|light|video]
//                              [--hover T0-T1] [--move T] [--then ACT@T] [--every N] [--mp4] [--trace]
//
// Acts: done, done-reminder, needs, needs-reminder, peek, idle-<variant>, all

struct Options {
    var act = "done"
    var out = "previews"
    var fps = 60.0
    var seconds: Double?
    var backdrop = BitmapRenderer.Backdrop.dark
    var hover: ClosedRange<Double>?
    var moveAt: Double?
    var then: (String, Double)?
    var every = 6
    var mp4 = false
    var trace = false
    var scale = 2.0
    var frames = true
    var seed: UInt64 = 7
}

func parse() -> Options {
    var o = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    if let first = args.first, !first.hasPrefix("--") {
        o.act = first
        args.removeFirst()
    }
    var i = 0
    func value() -> String { i += 1; return i < args.count ? args[i] : "" }
    while i < args.count {
        switch args[i] {
        case "--out": o.out = value()
        case "--fps": o.fps = Double(value()) ?? 60
        case "--seconds": o.seconds = Double(value())
        case "--backdrop": o.backdrop = BitmapRenderer.Backdrop(rawValue: value()) ?? .dark
        case "--hover":
            let parts = value().split(separator: "-").compactMap { Double($0) }
            if parts.count == 2 { o.hover = parts[0]...parts[1] }
        case "--move": o.moveAt = Double(value())
        case "--then":
            let parts = value().split(separator: "@")
            if parts.count == 2, let t = Double(parts[1]) { o.then = (String(parts[0]), t) }
        case "--every": o.every = Int(value()) ?? 6
        case "--mp4": o.mp4 = true
        case "--trace": o.trace = true
        case "--scale": o.scale = Double(value()) ?? 2
        case "--no-frames": o.frames = false
        case "--seed": o.seed = UInt64(value()) ?? 7
        default: break
        }
        i += 1
    }
    return o
}

let sampleDone = Card(kind: .done, status: "Finished", title: "Mac notch companion app", badge: "+1",
                      recap: "The first build runs: Little Bro drops from the top edge, tracks the cursor and opens the session on click.")
let sampleNeeds = Card(kind: .needsInput, status: "Needs your OK", title: "Game polish: map, HUD, elevation")

func act(named name: String) -> Act? {
    switch name {
    case "done": return .card(sampleDone, intro: true)
    case "done-reminder": return .card(sampleDone, intro: false)
    case "needs": return .card(sampleNeeds, intro: true)
    case "needs-reminder": return .card(sampleNeeds, intro: false)
    case "peek": return .peek
    case "vibe": return .vibe
    case "hacker-shades": return .hacker(.shades)
    case "hacker-rain": return .hacker(.rain)
    case "game": return .game(left: 8, right: 11)
    case "working": return .working(count: 1)
    case "working-2": return .working(count: 2)
    case "charging": return .system(.charging)
    case "low-battery": return .system(.lowBattery)
    case "download": return .system(.download(name: "little-bro-0.2.dmg", count: 1))
    case "mute": return .system(.sound(muted: true))
    case "unmute": return .system(.sound(muted: false))
    case "welcome": return .system(.welcome(finished: 2, waiting: 1))
    case "airpods": return .system(.device(.airpods, name: "AirPods Pro"))
    case "overear": return .system(.device(.overEar, name: "WH-1000XM5"))
    case "controller": return .system(.device(.controller, name: "Xbox Wireless Controller"))
    case "mouse": return .system(.device(.mouse, name: "M720 Triathlon"))
    case "keyboard": return .system(.device(.keyboard, name: "Rainy 75"))
    case "device": return .system(.device(.other, name: "Yealink-CP960"))
    default:
        if name.hasPrefix("idle-"), let v = IdleVariant(rawValue: String(name.dropFirst(5))) { return .idle(v) }
        return nil
    }
}

func defaultSeconds(_ a: Act) -> Double {
    switch a {
    case .card: return Director.cardDuration + 1.4
    case .peek: return 5.2
    case .vibe: return Director.vibeDuration + 1.3
    case .hacker(let s): return s == .shades ? 9.2 : 8.4
    case .game: return 12
    case .working: return 4
    case .system(let e):
        switch e {
        case .welcome: return 9
        case .download: return 7.2
        case .lowBattery: return 5.6
        case .device(let k, _): return k == .overEar ? 7.2 : 6.5
        default: return 4
        }
    case .idle(let v):
        switch v {
        case .sleepy: return 8.2
        case .lookAround: return 7.6
        case .shy: return 6.2
        case .hello: return 6.0
        case .curious: return 6.4
        }
    }
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func cursorPosition(at t: Double, _ o: Options, base: CGPoint, faceTarget: CGPoint) -> CGPoint {
    var p = base
    if let h = o.hover {
        // Glide in over 0.35 s, stay, glide out.
        let inU = clamp((t - h.lowerBound) / 0.35, 0, 1)
        let outU = clamp((t - h.upperBound) / 0.35, 0, 1)
        let u = inU - outU
        let e = u * u * (3 - 2 * u)
        p = CGPoint(x: base.x + (faceTarget.x - base.x) * e, y: base.y + (faceTarget.y - base.y) * e)
    }
    if let m = o.moveAt, t >= m {
        let u = clamp((t - m) / 0.6, 0, 1)
        p = CGPoint(x: base.x - 120 * u, y: base.y + 30 * sin(u * .pi))
    }
    return p
}

func run(_ o: Options, actName: String) {
    guard let first = act(named: actName) else {
        FileHandle.standardError.write("unknown act \(actName)\n".data(using: .utf8)!)
        exit(2)
    }
    let outDir = URL(fileURLWithPath: o.out).appendingPathComponent(actName + (o.backdrop == .dark ? "" : "-\(o.backdrop.rawValue)"))
    let framesDir = outDir.appendingPathComponent("frames")
    try? FileManager.default.removeItem(at: outDir)
    try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

    let director = Director(seed: o.seed)
    var hiddenAt: Double?
    director.onHidden = { _ in hiddenAt = hiddenAt ?? -1 }
    director.play(first)

    let backdrop: BitmapRenderer.Backdrop = (first == .peek && o.backdrop == .dark) ? .video : o.backdrop
    let renderer = BitmapRenderer(size: Metrics.canvas, scale: o.scale, backdrop: backdrop)
    let seconds = o.seconds ?? defaultSeconds(first) + (o.then != nil ? 6 : 0)
    let dt = 1 / o.fps
    let frameCount = Int(seconds * o.fps)
    let baseCursor = CGPoint(x: 150, y: 168)
    var lastCursor = baseCursor
    var thenFired = false
    var sheetFrames: [(Double, CGImage)] = []
    var trace = "t,w,h,faceX,faceY,visible\n"

    for f in 0..<frameCount {
        let t = Double(f) * dt
        if let (name, at) = o.then, !thenFired, t >= at, let next = act(named: name) {
            director.play(next)
            thenFired = true
        }
        let faceTarget = director.character.lastFaceCenter
        let cursor = cursorPosition(at: t, o, base: baseCursor, faceTarget: CGPoint(x: faceTarget.x + 6, y: faceTarget.y + 4))
        let moved = hypot(cursor.x - lastCursor.x, cursor.y - lastCursor.y) > 0.5
        lastCursor = cursor
        var hovering = false
        if let h = o.hover, t >= h.lowerBound + 0.25, t <= h.upperBound { hovering = true }
        let scene = director.update(dt: dt, input: FrameInput(mouse: cursor, mouseMoved: moved, hovering: hovering))
        if o.trace {
            trace += String(format: "%.4f,%.3f,%.3f,%.3f,%.3f,%d\n", t, scene.blobWidth, scene.blobHeight,
                            scene.faceCenter.x, scene.faceCenter.y, scene.isVisible ? 1 : 0)
        }
        let needImage = o.frames || f % o.every == 0
        guard needImage, let image = renderer.render(scene, cursor: cursor) else { continue }
        if o.frames {
            writePNG(image, to: framesDir.appendingPathComponent(String(format: "%05d.png", f)))
        }
        if f % o.every == 0 { sheetFrames.append((t, image)) }
    }

    // Contact sheet: crop to the interesting top-centre band and tile.
    let crop = CGRect(x: (Metrics.canvas.width - 380) / 2 * o.scale, y: 0, width: 380 * o.scale, height: 110 * o.scale)
    let cols = 4
    let rows = Int(ceil(Double(sheetFrames.count) / Double(cols)))
    let cellW = Int(crop.width), cellH = Int(crop.height) + Int(16 * o.scale)
    if rows > 0, let ctx = CGContext(data: nil, width: cellW * cols, height: cellH * rows, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: cellW * cols, height: cellH * rows))
        for (i, (t, img)) in sheetFrames.enumerated() {
            guard let cropped = img.cropping(to: crop) else { continue }
            let col = i % cols, row = i / cols
            let y = cellH * (rows - 1 - row)
            ctx.draw(cropped, in: CGRect(x: col * cellW, y: y + Int(16 * o.scale), width: cellW, height: Int(crop.height)))
            // Time label as a tiny bar: width proportional to t within the act.
            ctx.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: Double(col * cellW) + 4, y: Double(y) + 5, width: max(2, t / seconds * Double(cellW - 8)), height: 6))
        }
        if let sheet = ctx.makeImage() { writePNG(sheet, to: outDir.appendingPathComponent("sheet.png")) }
    }
    if o.trace {
        try? trace.write(to: outDir.appendingPathComponent("trace.csv"), atomically: true, encoding: .utf8)
    }
    if o.mp4 && o.frames {
        let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.fileExists(atPath: $0) }
        if let ffmpeg {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ffmpeg)
            p.arguments = ["-y", "-loglevel", "error", "-framerate", String(Int(o.fps)), "-i",
                           framesDir.appendingPathComponent("%05d.png").path, "-c:v", "libx264", "-pix_fmt", "yuv420p",
                           "-crf", "14", outDir.appendingPathComponent("\(actName).mp4").path]
            try? p.run()
            p.waitUntilExit()
        }
    }
    print("\(actName): \(frameCount) frames → \(outDir.path)")
}

/// Draws the app icon at `px` pixels: a black squircle with Little Bro's eyes.
func iconImage(px: Int) -> CGImage? {
    let s = Double(px)
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: s / 1024, y: -s / 1024) // work in a 1024 canvas, y down
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s / 1024), blur: 28 * s / 1024,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    // A faint top highlight so it reads on dark docks.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 520), options: [])
    // Eyes.
    let eyeW = 132.0, eyeH = 196.0, gap = 112.0
    ctx.setShadow(offset: .zero, blur: 46 * s / 1024, color: CGColor(gray: 1, alpha: 0.55))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    for side in [-1.0, 1.0] {
        let e = EyeShape()
        let p = Paths.eye(center: CGPoint(x: 512 + side * (gap / 2 + eyeW / 2), y: 540), width: eyeW * e.width,
                          height: eyeH * e.height, roundness: e.roundness, lidTop: 0, lidAngle: 0, side: side,
                          happy: e.happy, rotation: 0)
        ctx.addPath(p)
        ctx.fillPath()
    }
    ctx.restoreGState()
    return ctx.makeImage()
}

func writeIconset(to dir: String) {
    let url = URL(fileURLWithPath: dir)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                       ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
        if let img = iconImage(px: px) { writePNG(img, to: url.appendingPathComponent("icon_\(name).png")) }
    }
    print("iconset → \(dir)")
}

if CommandLine.arguments.count > 2 && CommandLine.arguments[1] == "--icon" {
    writeIconset(to: CommandLine.arguments[2])
    exit(0)
}

let options = parse()
if options.act == "all" {
    for name in ["done", "done-reminder", "needs", "needs-reminder", "peek", "vibe", "hacker-shades", "hacker-rain", "game",
                 "working", "charging", "low-battery", "download", "mute", "unmute", "welcome", "airpods", "overear",
                 "controller", "mouse", "keyboard", "device"]
        + IdleVariant.allCases.map({ "idle-\($0.rawValue)" }) {
        run(options, actName: name)
    }
} else {
    run(options, actName: options.act)
}
