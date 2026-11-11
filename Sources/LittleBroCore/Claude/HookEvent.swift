import Foundation

/// One Claude Code hook invocation, as delivered on the hook's stdin.
public struct HookEvent: Equatable, Sendable {
    public var sessionId: String
    public var name: String
    public var cwd: String?
    public var toolName: String?
    public var notificationType: String?
    public var message: String?
    public var receivedAt: Date

    public init(sessionId: String, name: String, cwd: String? = nil, toolName: String? = nil,
                notificationType: String? = nil, message: String? = nil, receivedAt: Date = Date()) {
        self.sessionId = sessionId
        self.name = name
        self.cwd = cwd
        self.toolName = toolName
        self.notificationType = notificationType
        self.message = message
        self.receivedAt = receivedAt
    }

    public static func parse(_ data: Data, receivedAt: Date) -> HookEvent? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sid = obj["session_id"] as? String, !sid.isEmpty,
              let name = obj["hook_event_name"] as? String, !name.isEmpty else { return nil }
        return HookEvent(sessionId: sid, name: name, cwd: obj["cwd"] as? String,
                         toolName: obj["tool_name"] as? String,
                         notificationType: obj["notification_type"] as? String,
                         message: obj["message"] as? String, receivedAt: receivedAt)
    }
}
