import Foundation

/// Adds/removes Little Bro's entries in Claude Code's `settings.json` hooks,
/// leaving every other hook untouched.
public enum HookInstaller {
    /// (event, matcher)
    public static let events: [(String, String?)] = [
        ("UserPromptSubmit", nil),
        ("Stop", nil),
        ("StopFailure", nil),
        ("SessionEnd", nil),
        ("PermissionRequest", nil),
        ("Notification", nil),
        ("PreToolUse", nil),
        ("PostToolUse", nil),
        ("PostToolUseFailure", nil),
        ("Elicitation", nil),
        ("ElicitationResult", nil),
    ]

    public static let marker = "littlebro-hook"

    public static func isOurs(_ hook: Any) -> Bool {
        guard let h = hook as? [String: Any], let cmd = h["command"] as? String else { return false }
        return cmd.contains(marker)
    }

    public static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event, _ in
            guard let groups = hooks[event] as? [[String: Any]] else { return false }
            return groups.contains { ($0["hooks"] as? [Any])?.contains(where: isOurs) ?? false }
        }
    }

    public static func install(into settings: [String: Any], command: String) -> [String: Any] {
        var out = uninstall(from: settings)
        var hooks = out["hooks"] as? [String: Any] ?? [:]
        for (event, matcher) in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5] as [String: Any]]]
            if let m = matcher { group["matcher"] = m }
            groups.append(group)
            hooks[event] = groups
        }
        out["hooks"] = hooks
        return out
    }

    public static func uninstall(from settings: [String: Any]) -> [String: Any] {
        var out = settings
        guard var hooks = out["hooks"] as? [String: Any] else { return out }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for var g in groups {
                if let list = g["hooks"] as? [Any] {
                    let filtered = list.filter { !isOurs($0) }
                    if filtered.isEmpty && !list.isEmpty { continue }
                    g["hooks"] = filtered
                }
                kept.append(g)
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { out.removeValue(forKey: "hooks") } else { out["hooks"] = hooks }
        return out
    }

    /// The tiny script the hooks run: drop stdin into the inbox, atomically, and never fail.
    public static func script(inbox: String) -> String {
        """
        #!/bin/sh
        # Little Bro — forwards Claude Code hook events to the Little Bro app.
        # It only writes the event JSON into a folder; it never blocks or changes Claude.
        dir='\(inbox)'
        [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || exit 0
        base="$(date +%s)-$$"
        tmp="$dir/.$base.tmp"
        cat > "$tmp" 2>/dev/null && mv -f "$tmp" "$dir/$base.json" 2>/dev/null
        exit 0

        """
    }
}
