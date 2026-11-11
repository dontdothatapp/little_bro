import CoreGraphics
import Testing
@testable import LittleBroCore

/// Guards the "never snaps" property: whatever happens, every visible quantity
/// moves continuously from frame to frame.
@Suite struct SmoothnessTests {
    struct Sample {
        var visible: Bool
        var w: Double
        var h: Double
        var face: CGPoint
        var eyes: [CGRect]
        var eyeOpacity: Double
    }

    static let card = Card(kind: .done, status: "Finished", title: "A fairly long session title here", badge: "+2",
                           recap: "Did the thing, and then the other thing, and it all works now.")
    static let needs = Card(kind: .needsInput, status: "Needs your OK", title: "Build the notch thing")

    static let allActs: [Act] = [
        .card(card, intro: true), .card(card, intro: false), .card(needs, intro: true), .card(needs, intro: false),
        .peek,
    ] + IdleVariant.allCases.map { Act.idle($0) }

    /// Runs `script` (time → action) and records one sample per frame.
    func run(fps: Double, seconds: Double, seed: UInt64 = 1, hover: ClosedRange<Double>? = nil,
             mouse: (Double) -> CGPoint = { _ in CGPoint(x: 150, y: 170) },
             script: [(Double, (Director) -> Void)]) -> [Sample] {
        let d = Director(seed: seed)
        var pending = script.sorted { $0.0 < $1.0 }
        var out: [Sample] = []
        let dt = 1 / fps
        var t = 0.0
        var last = mouse(0)
        while t < seconds {
            while let first = pending.first, first.0 <= t {
                first.1(d)
                pending.removeFirst()
            }
            let m = mouse(t)
            let moved = hypot(m.x - last.x, m.y - last.y) > 0.5
            last = m
            let hovering = hover?.contains(t) ?? false
            let s = d.update(dt: dt, input: FrameInput(mouse: m, mouseMoved: moved, hovering: hovering))
            out.append(Sample(visible: s.isVisible, w: s.blobWidth, h: s.blobHeight, face: s.faceCenter,
                              eyes: s.eyes.map { $0.boundingBoxOfPath }, eyeOpacity: s.eyeOpacity))
            t += dt
        }
        return out
    }

    /// Largest change in per-frame velocity (a teleport shows up as a spike), normalised to 60 fps.
    func maxJerk(_ samples: [Sample], fps: Double, _ f: (Sample) -> Double) -> Double {
        var worst = 0.0
        let k = fps / 60
        for i in 2..<samples.count where samples[i].visible && samples[i - 1].visible && samples[i - 2].visible {
            let v1 = f(samples[i - 1]) - f(samples[i - 2])
            let v2 = f(samples[i]) - f(samples[i - 1])
            worst = max(worst, abs(v2 - v1) * k * k)
        }
        return worst
    }

    func maxStep(_ samples: [Sample], fps: Double, _ f: (Sample) -> Double) -> Double {
        var worst = 0.0
        for i in 1..<samples.count where samples[i].visible && samples[i - 1].visible {
            worst = max(worst, abs(f(samples[i]) - f(samples[i - 1])) * fps / 60)
        }
        return worst
    }

    func checkContinuity(_ s: [Sample], fps: Double, label: String) {
        #expect(s.allSatisfy { $0.w.isFinite && $0.h.isFinite && $0.face.x.isFinite && $0.face.y.isFinite },
                "\(label): non-finite values")
        let wJerk = maxJerk(s, fps: fps) { $0.w }
        let hJerk = maxJerk(s, fps: fps) { $0.h }
        // Eyes and face only matter while the eyes can be seen.
        let seen = s.map { var c = $0; c.visible = c.visible && c.eyeOpacity > 0.05; return c }
        let fxStep = maxStep(seen, fps: fps) { Double($0.face.x) }
        let fyStep = maxStep(seen, fps: fps) { Double($0.face.y) }
        #expect(wJerk < 12, "\(label): body width jerk \(wJerk)")
        #expect(hJerk < 8, "\(label): body height jerk \(hJerk)")
        // Sliding the face back from a card layout is fast but must stay continuous.
        let fxJerk = maxJerk(seen, fps: fps) { Double($0.face.x) }
        #expect(fxStep < 24, "\(label): face x step \(fxStep)")
        #expect(fxJerk < 8, "\(label): face x jerk \(fxJerk)")
        #expect(fyStep < 8, "\(label): face y step \(fyStep)")
        let eyeX = maxStep(seen.filter { $0.eyes.count == 2 }, fps: fps) { Double($0.eyes[0].midX) }
        #expect(eyeX < 24, "\(label): eye x step \(eyeX)")
    }

    @Test(arguments: [30.0, 60.0, 120.0])
    func everyActIsContinuousAndEndsHidden(fps: Double) {
        for act in Self.allActs {
            var hidden = false
            let s = run(fps: fps, seconds: 13, script: [(0, { d in
                d.onHidden = { _ in hidden = true }
                d.play(act)
            })])
            checkContinuity(s, fps: fps, label: "\(act) @\(fps)")
            #expect(hidden, "\(act) never finished")
            #expect(s.last?.visible == false, "\(act) still visible at the end")
            #expect(s.contains { $0.visible }, "\(act) never appeared")
        }
    }

    @Test func randomInterruptionsStayContinuous() {
        var rng = SeededRandom(seed: 42)
        for round in 0..<40 {
            var script: [(Double, (Director) -> Void)] = []
            var t = 0.0
            for _ in 0..<5 {
                let act = Self.allActs[Int(rng.range(0, Double(Self.allActs.count) - 0.001))]
                script.append((t, { $0.play(act) }))
                t += rng.range(0.05, 3.5)
                if rng.chance(0.3) {
                    script.append((t, { $0.retract(fast: Bool.random()) }))
                    t += rng.range(0.05, 0.8)
                }
            }
            let s = run(fps: 60, seconds: t + 3, seed: UInt64(round), script: script)
            checkContinuity(s, fps: 60, label: "round \(round)")
        }
    }

    @Test func hoverAndAcknowledgeAreContinuous() {
        let s = run(fps: 60, seconds: 6, hover: 2.0...3.5,
                    script: [(0, { $0.play(.card(Self.card, intro: true)) }), (3.6, { $0.pressDown() }),
                             (3.7, { $0.acknowledge() })])
        checkContinuity(s, fps: 60, label: "hover+ack")
        #expect(s.last?.visible == false)
    }

    @Test func hoverPausesTheTimeline() {
        // Hovering from 1 s to 15 s keeps the card out well past its normal 9.7 s.
        let s = run(fps: 60, seconds: 14, hover: 1.0...15.0, script: [(0, { $0.play(.card(Self.card, intro: true)) })])
        #expect(s.last?.visible == true)
    }

    @Test func cursorMovementStartlesAnIdleVisit() {
        var ended = false
        let s = run(fps: 60, seconds: 4, mouse: { t in t < 2 ? CGPoint(x: 150, y: 170) : CGPoint(x: 150 + (t - 2) * 300, y: 170) },
                    script: [(0, { d in d.onHidden = { _ in ended = true }; d.play(.idle(.lookAround)) })])
        checkContinuity(s, fps: 60, label: "startle")
        #expect(ended, "should have hidden well before the 6.4 s routine end")
    }
}
