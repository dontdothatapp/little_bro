import CoreGraphics
import Testing
@testable import LittleBroCore

@Suite struct SpringTests {
    @Test(arguments: [0.3, 0.7, 1.0, 1.6])
    func convergesToTarget(damping: Double) {
        var s = Spring(0, SpringParams(response: 0.4, damping: damping))
        s.target = 100
        for _ in 0..<600 { s.step(1 / 120) }
        #expect(abs(s.value - 100) < 0.01)
        #expect(abs(s.velocity) < 0.1)
    }

    @Test(arguments: [0.25, 0.68, 1.0, 1.4])
    func exactRegardlessOfFrameSplitting(damping: Double) {
        let p = SpringParams(response: 0.5, damping: damping)
        var a = Spring(0, p)
        var b = Spring(0, p)
        a.target = 50
        b.target = 50
        a.velocity = 30
        b.velocity = 30
        a.step(0.2)
        for _ in 0..<40 { b.step(0.005) }
        #expect(abs(a.value - b.value) < 1e-6)
        #expect(abs(a.velocity - b.velocity) < 1e-5)
    }

    @Test func hugeFrameTimeStaysFinite() {
        var s = Spring(0, SpringParams(response: 0.2, damping: 0.4))
        s.target = 10
        s.step(5)
        #expect(s.value.isFinite)
        #expect(abs(s.value - 10) < 1)
    }

    @Test func underdampedOvershoots() {
        var s = Spring(0, SpringParams(response: 0.5, damping: 0.5))
        s.target = 1
        var peak = 0.0
        for _ in 0..<240 {
            s.step(1 / 120)
            peak = max(peak, s.value)
        }
        #expect(peak > 1.05)
    }
}

@Suite struct PathTests {
    @Test func blobIsEmptyWhenRetracted() {
        #expect(Paths.blob(width: 100, height: 0, cornerRadius: 22, earRadius: 9).isEmpty)
    }

    @Test func blobBoundsMatchSize() {
        let p = Paths.blob(width: 120, height: 50, cornerRadius: 22, earRadius: 9)
        let b = p.boundingBoxOfPath
        #expect(abs(b.maxY - 50) < 0.01)
        // Ears flare past the body by the ear radius.
        #expect(abs(b.minX - (-60 - 9)) < 0.01)
        #expect(abs(b.maxX - (60 + 9)) < 0.01)
        #expect(p.contains(CGPoint(x: 0, y: 25)))
        #expect(!p.contains(CGPoint(x: 0, y: 51)))
    }

    @Test(arguments: [
        EyeShape(), Expression.happy.left, Expression.worried.left, Expression.sleepy.left,
        Expression.drowsy.left, Expression.peek.left, Expression.glad.left,
    ])
    func eyesAreNonEmptyAndCentred(shape: EyeShape) {
        for side in [-1.0, 1.0] {
            let p = Paths.eye(center: CGPoint(x: 10, y: 20), width: 13 * shape.width, height: 19 * shape.height,
                              roundness: shape.roundness, lidTop: shape.lidTop, lidAngle: shape.lidAngle,
                              side: side, happy: shape.happy, rotation: 0)
            let b = p.boundingBoxOfPath
            #expect(!p.isEmpty)
            #expect(b.width > 5)
            #expect(abs(b.midX - 10) < 3)
        }
    }

    @Test func worriedLidsMirror() {
        let s = Expression.worried.left
        let l = Paths.eye(center: .zero, width: 13, height: 19, roundness: s.roundness, lidTop: s.lidTop,
                          lidAngle: s.lidAngle, side: -1, happy: 0, rotation: 0).boundingBoxOfPath
        let r = Paths.eye(center: .zero, width: 13, height: 19, roundness: s.roundness, lidTop: s.lidTop,
                          lidAngle: s.lidAngle, side: 1, happy: 0, rotation: 0).boundingBoxOfPath
        #expect(abs(l.minX + r.maxX) < 0.01)
        #expect(abs(l.minY - r.minY) < 0.01)
    }
}
