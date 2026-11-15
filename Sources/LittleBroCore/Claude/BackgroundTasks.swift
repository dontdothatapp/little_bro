import Foundation

/// Keeps track of a session's background tasks by reading its transcript (JSONL):
/// background commands and agents announce themselves in their tool result, and say they
/// are done through a queued `<task-notification>`.
public struct BackgroundTaskLedger: Sendable {
    public private(set) var running = Set<String>()

    public init() {}

    private static let markers: [[UInt8]] = ["Command running in background", "moved to the background",
                                             "Async agent launched", "<task-notification>",
                                             "Successfully stopped task"].map { Array($0.utf8) }
    private static let skipTypes: [[UInt8]] = ["\"type\":\"api-request", "\"type\":\"assistant\""].map { Array($0.utf8) }

    /// Feed one transcript line.
    public mutating func ingest(_ line: String) {
        ingest(Data(line.utf8))
    }

    /// Feed one transcript line as raw bytes. Fast path: a byte search rules out almost every
    /// line (and the multi-megabyte request records) without building strings or parsing JSON.
    public mutating func ingest(_ line: Data) {
        let interesting: Bool = line.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return false }
            let headLen = min(raw.count, 80)
            for t in Self.skipTypes where Self.find(t, in: base, count: headLen) { return false }
            return Self.markers.contains { Self.find($0, in: base, count: raw.count) }
        }
        guard interesting,
              let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = o["type"] as? String else { return }
        switch type {
        case "user":
            guard let message = o["message"] as? [String: Any], let content = message["content"] as? [Any] else { return }
            for item in content {
                guard let d = item as? [String: Any], d["type"] as? String == "tool_result" else { continue }
                for text in Self.texts(d["content"]) { toolResult(text) }
            }
        case "queue-operation":
            guard o["operation"] as? String == "enqueue", let text = o["content"] as? String else { return }
            notification(text)
        case "attachment":
            // Completion notices are sometimes recorded only as a delivered queued command.
            guard let a = o["attachment"] as? [String: Any], a["type"] as? String == "queued_command",
                  let text = a["prompt"] as? String else { return }
            notification(text)
        default:
            return // assistant text, request blobs: never trusted
        }
    }

    private static func find(_ needle: [UInt8], in base: UnsafeRawPointer, count: Int) -> Bool {
        needle.withUnsafeBytes { n in memmem(base, count, n.baseAddress, n.count) != nil }
    }

    private static func texts(_ content: Any?) -> [String] {
        if let s = content as? String { return [s] }
        if let list = content as? [Any] {
            return list.compactMap { ($0 as? [String: Any])?["text"] as? String }
        }
        return []
    }

    /// Only the tool's own launch/stop message counts — it always *starts* with these words,
    /// so output that merely quotes them (a grep of a log, say) is ignored.
    private mutating func toolResult(_ text: String) {
        let head = String(text.prefix(400))
        if head.hasPrefix("Command running in background"), let id = Self.match(head, #"with ID:\s*([A-Za-z0-9_-]+)"#) {
            running.insert(id)
        } else if head.hasPrefix("Command did not complete within"), head.contains("moved to the background"),
                  let id = Self.match(head, #"\(ID:\s*([A-Za-z0-9_-]+)\)"#) {
            running.insert(id)
        } else if head.hasPrefix("Async agent launched successfully") || head.hasPrefix("Async agent launched"),
                  let id = Self.match(text, #"agentId:\s*([A-Za-z0-9_-]+)"#) {
            running.insert(id)
        } else if let id = Self.match(head, #"Successfully stopped task:\s*([A-Za-z0-9_-]+)"#) {
            // Stopping can match anywhere (the tool answers in JSON); a false stop only ever
            // lets a notification through sooner.
            running.remove(id)
        }
    }

    private mutating func notification(_ text: String) {
        guard text.hasPrefix("<task-notification>"), let id = Self.match(text, #"<task-id>([^<]+)</task-id>"#) else { return }
        let status = Self.match(text, #"<status>([^<]+)</status>"#)?.lowercased() ?? "completed"
        if status != "running" && status != "started" { running.remove(id) }
    }

    static func match(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}
