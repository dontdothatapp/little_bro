import AppKit
import LittleBroCore
import QuartzCore

/// Hosts the layers and runs the frame loop on the display's vsync while visible.
/// When Little Bro is tucked away the display link is paused: zero work per frame.
final class CharacterView: NSView {
    let director: Director
    private(set) var renderer: LayerRenderer!
    private var link: CADisplayLink?
    private var lastTarget: CFTimeInterval?
    private var lastMouse: CGPoint?
    private(set) var hovering = false
    private var pressed = false
    var screenFrame: NSRect = .zero

    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onHidden: (() -> Void)?

    private(set) var stats = FrameStats()

    init(director: Director) {
        self.director = director
        super.init(frame: NSRect(origin: .zero, size: Metrics.canvas))
        let root = CALayer()
        layer = root
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layerContentsRedrawPolicy = .never
        renderer = LayerRenderer(root: root, size: Metrics.canvas)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderer.scale = window?.backingScaleFactor ?? 2
    }

    var isRunning: Bool { link.map { !$0.isPaused } ?? false }

    func start() {
        if link == nil {
            let l = displayLink(target: self, selector: #selector(frame(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            l.add(to: .main, forMode: .common)
            link = l
        }
        lastTarget = nil
        stats = FrameStats()
        link?.isPaused = false
    }

    func stop() {
        link?.isPaused = true
        setHovering(false)
    }

    /// Converts the global mouse position into scene coordinates (origin top-centre, y down).
    func sceneMouse() -> CGPoint {
        let m = NSEvent.mouseLocation
        return CGPoint(x: m.x - screenFrame.midX, y: screenFrame.maxY - m.y)
    }

    @objc private func frame(_ link: CADisplayLink) {
        let started = CACurrentMediaTime()
        let target = link.targetTimestamp
        var dt = lastTarget.map { target - $0 } ?? (link.targetTimestamp - link.timestamp)
        lastTarget = target
        dt = min(max(dt, 1.0 / 240), 1.0 / 20)

        let mouse = sceneMouse()
        let moved = lastMouse.map { hypot($0.x - mouse.x, $0.y - mouse.y) > 0.5 } ?? false
        lastMouse = mouse

        let scene = director.update(dt: dt, input: FrameInput(mouse: mouse, mouseMoved: moved, hovering: hovering))
        renderer.apply(scene)

        // Hit-test for the next frame: only the body itself takes the mouse.
        let inside = scene.isVisible && !director.isRetracting && mouse.y >= -1
            && (scene.blobPath?.contains(mouse) ?? false)
        setHovering(inside)
        if hovering { NSCursor.pointingHand.set() }

        stats.record(frameDuration: link.duration, interval: dt, work: CACurrentMediaTime() - started)

        if director.isHidden {
            stop()
            onHidden?()
        }
    }

    private func setHovering(_ v: Bool) {
        guard v != hovering else { return }
        hovering = v
        window?.ignoresMouseEvents = !v
        if !v {
            NSCursor.arrow.set()
            pressed = false
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard hovering else { return }
        pressed = true
        director.pressDown()
    }

    override func mouseUp(with event: NSEvent) {
        guard pressed, hovering else { return }
        pressed = false
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard hovering else { return }
        onRightClick?(event)
    }
}

/// Frame pacing numbers, logged after every appearance.
struct FrameStats {
    var frames = 0
    var late = 0
    var worstInterval = 0.0
    var totalWork = 0.0
    var worstWork = 0.0

    mutating func record(frameDuration: Double, interval: Double, work: Double) {
        frames += 1
        if frames > 2 && frameDuration > 0 && interval > frameDuration * 1.5 { late += 1 }
        if frames > 2 { worstInterval = max(worstInterval, interval) }
        totalWork += work
        worstWork = max(worstWork, work)
    }

    var summary: String {
        guard frames > 0 else { return "no frames" }
        return String(format: "%d frames, %d late, worst interval %.1f ms, work avg %.2f ms / worst %.2f ms",
                      frames, late, worstInterval * 1000, totalWork / Double(frames) * 1000, worstWork * 1000)
    }
}
