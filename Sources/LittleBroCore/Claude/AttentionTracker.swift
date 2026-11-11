import Foundation

public enum NeedReason: String, Equatable, Sendable {
    case permission, question, plan, input

    public var status: String {
        switch self {
        case .permission: "Needs your OK"
        case .question: "Has a question"
        case .plan: "Plan ready for review"
        case .input: "Needs your input"
        }
    }
}

public enum AttentionKind: Equatable, Sendable {
    case done
    case failed
    case needsInput(NeedReason)

    public var isNeedsInput: Bool {
        if case .needsInput = self { return true }
        return false
    }

    public var status: String {
        switch self {
        case .done: "Finished"
        case .failed: "Stopped with an error"
        case .needsInput(let r): r.status
        }
    }

    /// Higher shows first.
    public var priority: Int {
        switch self {
        case .needsInput: 3
        case .failed: 2
        case .done: 1
        }
    }
}

/// A Claude session that wants the user.
public struct AttentionItem: Equatable, Sendable {
    public var sessionId: String
    public var kind: AttentionKind
    public var since: Date
    public var cwd: String?
    /// The tool the session is waiting on (for permission prompts and questions).
    public var toolName: String?
    public var lastShownAt: Date?
    public var showCount: Int = 0

    public init(sessionId: String, kind: AttentionKind, since: Date, cwd: String?, toolName: String? = nil) {
        self.sessionId = sessionId
        self.kind = kind
        self.since = since
        self.cwd = cwd
        self.toolName = toolName
    }
}

/// Turns the stream of hook events into "which sessions are waiting for me, and why".
public final class AttentionTracker {
    public private(set) var items: [String: AttentionItem] = [:]
    /// Sessions currently working (last activity time), for the "Claude is working" strip.
    public private(set) var working: [String: Date] = [:]

    public init() {}

    public enum Change: Equatable {
        case none
        case raised(AttentionItem)
        case cleared(String)
    }

    @discardableResult
    public func handle(_ e: HookEvent) -> Change {
        trackWork(e)
        return handleAttention(e)
    }

    private func trackWork(_ e: HookEvent) {
        let sid = e.sessionId
        switch e.name {
        case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure", "SubagentStart", "PreCompact",
             "ElicitationResult":
            working[sid] = e.receivedAt
        case "PreToolUse":
            if e.toolName == "AskUserQuestion" || e.toolName == "ExitPlanMode" {
                working.removeValue(forKey: sid)
            } else {
                working[sid] = e.receivedAt
            }
        case "Stop", "StopFailure", "SessionEnd", "PermissionRequest", "Elicitation":
            working.removeValue(forKey: sid)
        case "Notification":
            if e.notificationType == "permission_prompt" || e.notificationType == "elicitation_dialog" {
                working.removeValue(forKey: sid)
            }
        default:
            break
        }
    }

    /// Sessions that are working right now. A session that has gone quiet for `staleAfter`
    /// (e.g. Claude crashed mid-turn) stops counting.
    public func workingSessions(now: Date, staleAfter: TimeInterval = 600) -> [String] {
        working.filter { now.timeIntervalSince($0.value) < staleAfter }.sorted { $0.value > $1.value }.map(\.key)
    }

    public func stopWorking(_ sid: String) {
        working.removeValue(forKey: sid)
    }

    private func handleAttention(_ e: HookEvent) -> Change {
        let sid = e.sessionId
        switch e.name {
        case "Stop":
            return raise(sid, .done, e)
        case "StopFailure":
            return raise(sid, .failed, e)
        case "PermissionRequest":
            return raise(sid, .needsInput(.permission), e)
        case "Notification":
            switch e.notificationType {
            case "permission_prompt": return raise(sid, .needsInput(.permission), e)
            case "elicitation_dialog": return raise(sid, .needsInput(.input), e)
            default: return .none
            }
        case "Elicitation":
            return raise(sid, .needsInput(.input), e)
        case "PreToolUse":
            switch e.toolName {
            case "AskUserQuestion": return raise(sid, .needsInput(.question), e)
            case "ExitPlanMode": return raise(sid, .needsInput(.plan), e)
            default:
                // A new tool call starting means the wait is over. Calls in the same parallel
                // batch arrive within milliseconds of the prompt, so ignore those.
                guard let item = items[sid], item.kind.isNeedsInput,
                      e.receivedAt.timeIntervalSince(item.since) > 1.5 else { return .none }
                return clear(sid)
            }
        case "PostToolUse", "PostToolUseFailure":
            guard let item = items[sid], item.kind.isNeedsInput else { return .none }
            if item.toolName == nil || item.toolName == e.toolName { return clear(sid) }
            return .none
        case "ElicitationResult", "PermissionDenied":
            return clearIfWaiting(sid)
        case "UserPromptSubmit", "SessionEnd":
            return clear(sid)
        default:
            return .none
        }
    }

    private func raise(_ sid: String, _ kind: AttentionKind, _ e: HookEvent) -> Change {
        if var existing = items[sid], existing.kind == kind {
            // Same state again (e.g. Notification after PermissionRequest): keep the original timing.
            existing.cwd = e.cwd ?? existing.cwd
            existing.toolName = existing.toolName ?? e.toolName
            items[sid] = existing
            return .none
        }
        let item = AttentionItem(sessionId: sid, kind: kind, since: e.receivedAt, cwd: e.cwd ?? items[sid]?.cwd,
                                 toolName: kind.isNeedsInput ? (e.toolName ?? items[sid]?.toolName) : nil)
        items[sid] = item
        return .raised(item)
    }

    private func clearIfWaiting(_ sid: String) -> Change {
        guard let item = items[sid], item.kind.isNeedsInput else { return .none }
        return clear(sid)
    }

    @discardableResult
    public func clear(_ sid: String) -> Change {
        guard items.removeValue(forKey: sid) != nil else { return .none }
        return .cleared(sid)
    }

    public func markShown(_ sid: String, at date: Date) {
        guard var item = items[sid] else { return }
        item.lastShownAt = date
        item.showCount += 1
        items[sid] = item
    }

    /// Pending items, most important first (needs-you before done, then newest first).
    public var pending: [AttentionItem] {
        items.values.sorted {
            if $0.kind.priority != $1.kind.priority { return $0.kind.priority > $1.kind.priority }
            return $0.since > $1.since
        }
    }

    /// The item that should be shown now, if any.
    /// - settle: an item must be this old before its first appearance (debounces auto-approved prompts).
    /// - interval: minimum time between appearances of the same item.
    public func due(now: Date, settle: TimeInterval, interval: TimeInterval) -> AttentionItem? {
        pending.first { item in
            guard now.timeIntervalSince(item.since) >= settle else { return false }
            guard let last = item.lastShownAt else { return true }
            return now.timeIntervalSince(last) >= interval
        }
    }
}
