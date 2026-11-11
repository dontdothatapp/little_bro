import Foundation
import Testing
@testable import LittleBroCore

@Suite struct AttentionTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func ev(_ name: String, _ dt: Double, tool: String? = nil, type: String? = nil, sid: String = "s1") -> HookEvent {
        HookEvent(sessionId: sid, name: name, cwd: "/tmp/proj", toolName: tool, notificationType: type,
                  receivedAt: t0.addingTimeInterval(dt))
    }

    @Test func stopRaisesDoneAndPromptClears() {
        let a = AttentionTracker()
        #expect(a.handle(ev("Stop", 0)) != .none)
        #expect(a.items["s1"]?.kind == .done)
        #expect(a.handle(ev("UserPromptSubmit", 5)) == .cleared("s1"))
        #expect(a.items.isEmpty)
    }

    @Test func permissionClearsWhenThatToolRuns() {
        let a = AttentionTracker()
        a.handle(ev("PermissionRequest", 0, tool: "Bash"))
        #expect(a.items["s1"]?.kind == .needsInput(.permission))
        // A parallel tool finishing doesn't clear it…
        a.handle(ev("PostToolUse", 0.5, tool: "Read"))
        #expect(a.items["s1"] != nil)
        // …a tool in the same batch starting doesn't either…
        a.handle(ev("PreToolUse", 0.01, tool: "Grep"))
        #expect(a.items["s1"] != nil)
        // …but the approved tool running does.
        a.handle(ev("PostToolUse", 4, tool: "Bash"))
        #expect(a.items["s1"] == nil)
    }

    @Test func laterToolCallClearsAfterDenial() {
        let a = AttentionTracker()
        a.handle(ev("PermissionRequest", 0, tool: "Bash"))
        a.handle(ev("PreToolUse", 6, tool: "Read"))
        #expect(a.items["s1"] == nil)
    }

    @Test func questionsAndPlans() {
        let a = AttentionTracker()
        a.handle(ev("PreToolUse", 0, tool: "AskUserQuestion"))
        #expect(a.items["s1"]?.kind == .needsInput(.question))
        a.handle(ev("PostToolUse", 3, tool: "AskUserQuestion"))
        #expect(a.items["s1"] == nil)
        a.handle(ev("PreToolUse", 4, tool: "ExitPlanMode"))
        #expect(a.items["s1"]?.kind == .needsInput(.plan))
    }

    @Test func duplicateNotificationKeepsOriginalTime() {
        let a = AttentionTracker()
        a.handle(ev("PermissionRequest", 0, tool: "Edit"))
        a.handle(ev("Notification", 0.2, type: "permission_prompt"))
        #expect(a.items["s1"]?.since == t0)
        a.handle(ev("Notification", 1, type: "idle_prompt"))
        #expect(a.items["s1"]?.kind == .needsInput(.permission))
    }

    @Test func dueRespectsSettleIntervalAndPriority() {
        let a = AttentionTracker()
        a.handle(ev("Stop", 0, sid: "done"))
        a.handle(ev("PermissionRequest", 1, tool: "Bash", sid: "ask"))
        #expect(a.due(now: t0.addingTimeInterval(1.5), settle: 1.2, interval: 60)?.sessionId == "done")
        #expect(a.due(now: t0.addingTimeInterval(2.5), settle: 1.2, interval: 60)?.sessionId == "ask")
        a.markShown("ask", at: t0.addingTimeInterval(2.5))
        a.markShown("done", at: t0.addingTimeInterval(2.5))
        #expect(a.due(now: t0.addingTimeInterval(30), settle: 1.2, interval: 60) == nil)
        #expect(a.due(now: t0.addingTimeInterval(63), settle: 1.2, interval: 60)?.sessionId == "ask")
        #expect(a.pending.map(\.sessionId) == ["ask", "done"])
    }

    @Test func parsesHookJSON() {
        let json = #"{"session_id":"abc","hook_event_name":"PermissionRequest","cwd":"/x","tool_name":"Bash"}"#
        let e = HookEvent.parse(Data(json.utf8), receivedAt: t0)
        #expect(e?.sessionId == "abc")
        #expect(e?.toolName == "Bash")
        #expect(HookEvent.parse(Data("{}".utf8), receivedAt: t0) == nil)
        #expect(HookEvent.parse(Data("nope".utf8), receivedAt: t0) == nil)
    }
}

@Suite struct HookInstallerTests {
    let existing: [String: Any] = [
        "model": "opus",
        "hooks": [
            "Stop": [["hooks": [["type": "command", "command": "/other/tool"]]]],
            "PreCompact": [["hooks": [["type": "command", "command": "/x"]]]],
        ],
    ]

    @Test func installKeepsOtherHooksAndIsIdempotent() {
        let once = HookInstaller.install(into: existing, command: "'/a b/littlebro-hook'")
        let twice = HookInstaller.install(into: once, command: "'/a b/littlebro-hook'")
        #expect(HookInstaller.isInstalled(in: twice))
        let hooks = twice["hooks"] as! [String: Any]
        let stop = hooks["Stop"] as! [[String: Any]]
        #expect(stop.count == 2)
        #expect(((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as! String) == "/other/tool")
        #expect(hooks["PreCompact"] != nil)
        #expect(twice["model"] as? String == "opus")
        for (event, _) in HookInstaller.events {
            let groups = hooks[event] as! [[String: Any]]
            let ours = groups.filter { ($0["hooks"] as! [Any]).contains(where: HookInstaller.isOurs) }
            #expect(ours.count == 1, "\(event)")
        }
    }

    @Test func uninstallRemovesOnlyOurs() {
        let installed = HookInstaller.install(into: existing, command: "/p/littlebro-hook")
        let removed = HookInstaller.uninstall(from: installed)
        #expect(!HookInstaller.isInstalled(in: removed))
        let hooks = removed["hooks"] as! [String: Any]
        #expect(Set(hooks.keys) == ["Stop", "PreCompact"])
        #expect((hooks["Stop"] as! [[String: Any]]).count == 1)
    }

    @Test func scriptQuotesThePath() {
        let s = HookInstaller.script(inbox: "/Users/me/Library/Application Support/LittleBro/inbox")
        #expect(s.contains("dir='/Users/me/Library/Application Support/LittleBro/inbox'"))
        #expect(s.hasPrefix("#!/bin/sh"))
    }
}

@Suite struct PlannerTests {
    @Test func idleVisitHappensWithinFiveMinutesOfStillness() {
        var p = IdleVisitPlanner()
        var rng = SeededRandom(seed: 3)
        var firedAt: Double?
        for i in 0..<400 {
            let t = Double(i)
            if p.update(now: t, mouseIdle: t, inputIdle: t, blocked: false, rng: &rng) { firedAt = t; break }
        }
        #expect(firedAt != nil)
        #expect(firedAt! <= p.stillThreshold + p.maxDelay + 1)
        #expect(firedAt! >= p.stillThreshold + p.minDelay)
    }

    @Test func movingCancelsThePlan() {
        var p = IdleVisitPlanner()
        var rng = SeededRandom(seed: 3)
        for i in 0..<2000 {
            let t = Double(i)
            let mouseIdle = Double(i % 20) // moves every 20 s
            #expect(!p.update(now: t, mouseIdle: mouseIdle, inputIdle: mouseIdle, blocked: false, rng: &rng))
        }
    }

    @Test func noVisitsWhenAway() {
        var p = IdleVisitPlanner()
        var rng = SeededRandom(seed: 3)
        for i in 0..<400 {
            let t = Double(i) + 2000
            #expect(!p.update(now: t, mouseIdle: t, inputIdle: t, blocked: false, rng: &rng))
        }
    }

    @Test func blockedPostpones() {
        var p = IdleVisitPlanner()
        var rng = SeededRandom(seed: 9)
        var fired = 0
        for i in 0..<400 where p.update(now: Double(i), mouseIdle: Double(i), inputIdle: 1, blocked: true, rng: &rng) {
            fired += 1
        }
        #expect(fired == 0)
        #expect(p.plannedAt != nil)
    }

    @Test func peeksWhileWatching() {
        var p = PeekPlanner()
        var rng = SeededRandom(seed: 5)
        var fires: [Double] = []
        for i in 0..<1800 where p.update(now: Double(i), watching: true, blocked: false, rng: &rng) {
            fires.append(Double(i))
        }
        #expect(fires.count >= 3)
        #expect(fires[0] >= 90 && fires[0] <= 301)
        #expect(!p.update(now: 1801, watching: false, blocked: false, rng: &rng))
        #expect(p.nextAt == nil)
    }

    @Test func variantsDontRepeat() {
        var v = VariantPicker()
        var rng = SeededRandom(seed: 1)
        var last: IdleVariant?
        for _ in 0..<200 {
            let n = v.next(&rng)
            #expect(n != last)
            last = n
        }
    }
}

@Suite struct DesktopSessionTests {
    @Test func parsesTheFieldsWeUse() {
        let json = """
        {"sessionId":"local_abc","cliSessionId":"c1","lastAssistantCliSessionId":"c2","title":"Fix it",
         "cwd":"/w","lastFocusedAt":1000,"lastTurnEdgeAt":2000,"isArchived":false,
         "turnWrapUp":{"description":"It is fixed."}}
        """
        let s = DesktopSession.parse(Data(json.utf8))
        #expect(s?.localId == "local_abc")
        #expect(s?.cliIds == ["c1", "c2"])
        #expect(s?.recap == "It is fixed.")
        #expect(s?.openURL?.absoluteString == "claude://code/continue?session=local_abc")
        #expect(DesktopSession.parse(Data(#"{"sessionId":"nope"}"#.utf8)) == nil)
    }
}
