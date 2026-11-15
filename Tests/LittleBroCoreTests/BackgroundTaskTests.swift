import Foundation
import Testing
@testable import LittleBroCore

@Suite struct BackgroundTaskLedgerTests {
    func json(_ o: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
    }
    func toolResult(_ content: Any) -> String {
        json(["type": "user", "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1",
                                                                         "content": content]]]])
    }
    func enqueue(_ id: String, status: String = "completed") -> String {
        json(["type": "queue-operation", "operation": "enqueue",
              "content": "<task-notification>\n<task-id>\(id)</task-id>\n<tool-use-id>t</tool-use-id>\n<status>\(status)</status>\n</task-notification>"])
    }

    @Test func tracksLaunchesAndCompletions() {
        var l = BackgroundTaskLedger()
        l.ingest(toolResult("Command did not complete within its 300s timeout and was moved to the background (ID: bgjc1). Output is being written to: /tmp/x"))
        l.ingest(toolResult([["type": "text", "text": "Async agent launched successfully. (internal)\nagentId: a2771c (internal ID)"]]))
        l.ingest(toolResult("Command running in background with ID: b77. Output is being written to /tmp/y"))
        #expect(l.running == ["bgjc1", "a2771c", "b77"])
        l.ingest(enqueue("a2771c"))
        l.ingest(toolResult("Successfully stopped task: bgjc1 (./scripts/build.sh)"))
        l.ingest(enqueue("b77", status: "failed"))
        #expect(l.running.isEmpty)
    }

    @Test func otherCompletionAndStopForms() {
        var l = BackgroundTaskLedger()
        l.ingest(toolResult("Command running in background with ID: bo9. Output is being written to: /tmp/o"))
        l.ingest(toolResult("Command running in background with ID: bg2. Output is being written to: /tmp/p"))
        // Completion recorded only as a delivered queued command.
        l.ingest(json(["type": "attachment", "attachment": ["type": "queued_command", "commandMode": "task-notification",
                                                            "prompt": "<task-notification>\n<task-id>bo9</task-id>\n<status>completed</status>"]]))
        // The stop tool answers in JSON.
        l.ingest(toolResult(#"{"message":"Successfully stopped task: bg2 (sleep 100)","task_id":"bg2"}"#))
        #expect(l.running.isEmpty)
    }

    @Test func quotesAndOtherLinesAreIgnored() {
        var l = BackgroundTaskLedger()
        // A grep of a log that merely contains the phrases.
        l.ingest(toolResult("== moved\n   4 moved to the background (ID: zzz)\nAsync agent launched successfully agentId: q"))
        // The assistant talking about it, and raw request blobs.
        l.ingest(json(["type": "assistant", "message": ["content": [["type": "text", "text": "Command running in background with ID: nope"]]]]))
        l.ingest(json(["type": "api-request-blob", "body": "Command running in background with ID: nope2"]))
        l.ingest(json(["type": "queue-operation", "operation": "remove", "content": "<task-notification><task-id>x</task-id>"]))
        #expect(l.running.isEmpty)
        l.ingest("not json at all, with background in it")
        #expect(l.running.isEmpty)
    }

    /// Runs the ledger over real transcripts when LB_TRANSCRIPTS points at a folder of them,
    /// printing what each would consider still running (a sanity check, not a pass/fail).
    @Test func realTranscripts() throws {
        guard let dir = ProcessInfo.processInfo.environment["LB_TRANSCRIPTS"] else { return }
        let fm = FileManager.default
        let files = (try fm.contentsOfDirectory(atPath: dir)).filter { $0.hasSuffix(".jsonl") }
        for f in files {
            let text = try String(contentsOfFile: dir + "/" + f, encoding: .utf8)
            var l = BackgroundTaskLedger()
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) { l.ingest(String(line)) }
            print("TRANSCRIPT \(f.prefix(8)) running=\(l.running.sorted())")
        }
    }
}

@Suite struct HoldFinishTests {
    let t0 = Date(timeIntervalSince1970: 4_000_000)
    func ev(_ name: String, _ dt: Double, tool: String? = nil) -> HookEvent {
        HookEvent(sessionId: "s", name: name, toolName: tool, receivedAt: t0.addingTimeInterval(dt))
    }

    @Test func busyStopIsHeldUntilWorkIsDoneAndQuiet() {
        let a = AttentionTracker()
        a.handle(ev("UserPromptSubmit", 0))
        a.handle(ev("Stop", 10), busy: true)
        #expect(a.items.isEmpty)
        #expect(a.heldSessions == ["s"])
        // Still busy: nothing.
        #expect(a.releaseHeld(now: t0.addingTimeInterval(60), isBusy: { _ in true }).isEmpty)
        // Work done: wait for the session to stay quiet…
        #expect(a.releaseHeld(now: t0.addingTimeInterval(70), isBusy: { _ in false }).isEmpty)
        #expect(a.releaseHeld(now: t0.addingTimeInterval(90), isBusy: { _ in false }).isEmpty)
        // …then it's finished.
        let c = a.releaseHeld(now: t0.addingTimeInterval(101), isBusy: { _ in false })
        #expect(c.count == 1)
        #expect(a.items["s"]?.kind == .done)
        #expect(a.heldSessions.isEmpty)
    }

    /// The usual path: the task finishes, the session wakes to handle it and finishes for real.
    @Test func wakingUpDropsTheHoldAndTheRealStopNotifies() {
        let a = AttentionTracker()
        a.handle(ev("Stop", 10), busy: true)
        a.handle(ev("PreToolUse", 200, tool: "Read"))
        #expect(a.heldSessions.isEmpty)
        #expect(a.items.isEmpty)
        #expect(a.handle(ev("Stop", 230), busy: false) != .none)
        #expect(a.items["s"]?.kind == .done)
    }

    @Test func neverHeldForever() {
        let a = AttentionTracker()
        a.handle(ev("Stop", 0), busy: true)
        let c = a.releaseHeld(now: t0.addingTimeInterval(3700), isBusy: { _ in true })
        #expect(c.count == 1)
    }

    @Test func needsInputIsNeverHeld() {
        let a = AttentionTracker()
        a.handle(ev("Stop", 0), busy: true)
        a.handle(ev("PermissionRequest", 5, tool: "Bash"))
        #expect(a.items["s"]?.kind == .needsInput(.permission))
    }
}
