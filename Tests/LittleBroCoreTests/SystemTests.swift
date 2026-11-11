import CoreGraphics
import Foundation
import Testing
@testable import LittleBroCore

@Suite struct DeviceClassifierTests {
    @Test func audioDevicesByName() {
        #expect(DeviceClassifier.audioKind(name: "Alex’s AirPods Pro") == .airpods)
        #expect(DeviceClassifier.audioKind(name: "AirPods (Sam) - Find My") == .airpods)
        #expect(DeviceClassifier.audioKind(name: "WH-1000XM5") == .overEar)
        #expect(DeviceClassifier.audioKind(name: "Xbox Wireless Headset") == .overEar)
        #expect(DeviceClassifier.audioKind(name: "Bose QC45") == .overEar)
        #expect(DeviceClassifier.audioKind(name: "Yealink-CP960") == .other)
    }

    @Test func inputDevicesByUsage() {
        #expect(DeviceClassifier.hidKind(usagePage: 1, usage: 2, product: "M720 Triathlon") == .mouse)
        #expect(DeviceClassifier.hidKind(usagePage: 1, usage: 6, product: "Rainy 75") == .keyboard)
        #expect(DeviceClassifier.hidKind(usagePage: 1, usage: 5, product: "Xbox Wireless Controller") == .controller)
        #expect(DeviceClassifier.hidKind(usagePage: 0x0D, usage: 5, product: "Magic Trackpad") == .mouse)
        #expect(DeviceClassifier.hidKind(usagePage: 12, usage: 1, product: "Xbox Wireless Controller") == .controller)
        #expect(DeviceClassifier.hidKind(usagePage: 12, usage: 1, product: "Consumer Control") == nil)
    }

    @Test func welcomeTitles() {
        #expect(WelcomeSummary.title(finished: 2, waiting: 1) == ("2 finished ·", "1 needs you"))
        #expect(WelcomeSummary.title(finished: 1, waiting: 0) == ("1 session finished", nil))
        #expect(WelcomeSummary.title(finished: 3, waiting: 0) == ("3 sessions finished", nil))
        #expect(WelcomeSummary.title(finished: 0, waiting: 2) == ("", "2 need you"))
    }
}

@Suite struct WorkingTests {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    func ev(_ name: String, _ dt: Double, tool: String? = nil, sid: String = "s") -> HookEvent {
        HookEvent(sessionId: sid, name: name, toolName: tool, receivedAt: t0.addingTimeInterval(dt))
    }

    @Test func promptToStop() {
        let a = AttentionTracker()
        a.handle(ev("UserPromptSubmit", 0))
        #expect(a.workingSessions(now: t0.addingTimeInterval(1)) == ["s"])
        a.handle(ev("PreToolUse", 5, tool: "Bash"))
        a.handle(ev("Stop", 20))
        #expect(a.workingSessions(now: t0.addingTimeInterval(21)).isEmpty)
    }

    @Test func waitingOnYouIsNotWorking() {
        let a = AttentionTracker()
        a.handle(ev("UserPromptSubmit", 0))
        a.handle(ev("PermissionRequest", 3, tool: "Bash"))
        #expect(a.workingSessions(now: t0.addingTimeInterval(4)).isEmpty)
        a.handle(ev("PostToolUse", 9, tool: "Bash"))
        #expect(a.workingSessions(now: t0.addingTimeInterval(10)) == ["s"])
    }

    @Test func goesStale() {
        let a = AttentionTracker()
        a.handle(ev("UserPromptSubmit", 0))
        #expect(a.workingSessions(now: t0.addingTimeInterval(700), staleAfter: 600).isEmpty)
    }
}

@Suite struct RestingStripTests {
    @Test func cardsSettleBackIntoTheStripAndItCanTuckAway() {
        let d = Director(seed: 3)
        var hidden = false
        var ended: [Act] = []
        d.onHidden = { _ in hidden = true }
        d.onActEnded = { ended.append($0) }
        d.restingAct = .working(count: 1)
        d.play(.working(count: 1))
        var samples: [(Bool, Double, Double)] = []
        let card = Card(kind: .done, status: "Finished", title: "Something")
        for f in 0..<(60 * 20) {
            let t = Double(f) / 60
            if f == 120 { d.play(.card(card, intro: true)) }
            if f == 60 * 14 {
                d.restingAct = nil
                d.retract()
            }
            let s = d.update(dt: 1.0 / 60, input: FrameInput(mouse: CGPoint(x: 100, y: 150)))
            samples.append((s.isVisible, s.blobWidth, s.blobHeight))
            if f == 60 * 13 {
                // The card ended (≈ 2 + 9.7 s) and the strip is back.
                #expect(d.act == .working(count: 1))
                #expect(s.isVisible)
                #expect(abs(s.blobHeight - Metrics.strip.height) < 1.5, "height \(s.blobHeight)")
            }
            _ = t
        }
        #expect(hidden)
        #expect(ended.contains { $0.isCard })
        // Continuous all the way.
        for i in 2..<samples.count where samples[i].0 && samples[i - 1].0 && samples[i - 2].0 {
            let j = abs((samples[i].1 - samples[i - 1].1) - (samples[i - 1].1 - samples[i - 2].1))
            #expect(j < 12, "width jerk \(j) at frame \(i)")
        }
    }

    @Test func updatingTheCountDoesNotRestart() {
        let d = Director(seed: 1)
        d.play(.working(count: 1))
        for _ in 0..<60 { _ = d.update(dt: 1.0 / 60, input: FrameInput()) }
        d.updateWorking(count: 3)
        #expect(d.act == .working(count: 3))
        var last = d.update(dt: 1.0 / 60, input: FrameInput())
        for _ in 0..<90 { last = d.update(dt: 1.0 / 60, input: FrameInput()) }
        #expect(last.texts.contains { $0.key == "strip-count" && $0.text == "3" })
    }
}
