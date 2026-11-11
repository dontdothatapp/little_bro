import Foundation

/// What Little Bro reads from the Claude desktop app's own per-session file
/// (`~/Library/Application Support/Claude/claude-code-sessions/**/local_*.json`).
/// These files are internal to the app, so everything here is best-effort.
public struct DesktopSession: Equatable, Sendable {
    /// Desktop id, e.g. `local_…` — used in `claude://code/continue?session=…`.
    public var localId: String
    /// Claude Code session ids (what hooks report) that belong to this desktop session.
    public var cliIds: Set<String>
    public var title: String?
    public var cwd: String?
    /// Milliseconds since 1970.
    public var lastFocusedAt: Double
    public var lastTurnEdgeAt: Double
    public var isArchived: Bool
    /// Claude's one-line recap of the last turn, when present.
    public var recap: String?

    public init(localId: String, cliIds: Set<String>, title: String?, cwd: String?, lastFocusedAt: Double,
                lastTurnEdgeAt: Double, isArchived: Bool, recap: String?) {
        self.localId = localId
        self.cliIds = cliIds
        self.title = title
        self.cwd = cwd
        self.lastFocusedAt = lastFocusedAt
        self.lastTurnEdgeAt = lastTurnEdgeAt
        self.isArchived = isArchived
        self.recap = recap
    }

    public static func parse(_ data: Data) -> DesktopSession? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = o["sessionId"] as? String, id.hasPrefix("local_") else { return nil }
        var ids = Set<String>()
        for key in ["cliSessionId", "lastAssistantCliSessionId", "unarchivedCliSessionId", "preClearCliSessionId"] {
            if let v = o[key] as? String, !v.isEmpty { ids.insert(v) }
        }
        let wrap = o["turnWrapUp"] as? [String: Any]
        let recap = (wrap?["description"] as? String) ?? (wrap?["recap"] as? String)
        return DesktopSession(localId: id, cliIds: ids, title: o["title"] as? String,
                              cwd: (o["originCwd"] as? String) ?? (o["cwd"] as? String),
                              lastFocusedAt: (o["lastFocusedAt"] as? NSNumber)?.doubleValue ?? 0,
                              lastTurnEdgeAt: (o["lastTurnEdgeAt"] as? NSNumber)?.doubleValue ?? 0,
                              isArchived: (o["isArchived"] as? Bool) ?? false,
                              recap: recap?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Deep link that opens this exact session in the desktop app.
    public var openURL: URL? {
        var c = URLComponents()
        c.scheme = "claude"
        c.host = "code"
        c.path = "/continue"
        c.queryItems = [URLQueryItem(name: "session", value: localId)]
        return c.url
    }
}
