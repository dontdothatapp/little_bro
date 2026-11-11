import Foundation
import LittleBroCore

enum AppPaths {
    static let appSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LittleBro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let inbox = appSupport.appendingPathComponent("inbox", isDirectory: true)
    static let hookScript = appSupport.appendingPathComponent("bin/littlebro-hook")
    static let claudeSettings = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")
    static let desktopSessions = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    static let log = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/LittleBro.log")
}

enum Log {
    private static let queue = DispatchQueue(label: "littlebro.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func info(_ message: @autoclosure () -> String) {
        let line = "\(formatter.string(from: Date())) \(message())\n"
        queue.async {
            let url = AppPaths.log
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(line.data(using: .utf8)!)
                try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
            // Keep the log small.
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 2_000_000 {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

/// User preferences.
final class Settings {
    private let d = UserDefaults.standard

    init() {
        d.register(defaults: [
            "claudeEnabled": true,
            "idleEnabled": true,
            "peeksEnabled": true,
        ])
    }

    var claudeEnabled: Bool {
        get { d.bool(forKey: "claudeEnabled") }
        set { d.set(newValue, forKey: "claudeEnabled") }
    }

    var idleEnabled: Bool {
        get { d.bool(forKey: "idleEnabled") }
        set { d.set(newValue, forKey: "idleEnabled") }
    }

    var peeksEnabled: Bool {
        get { d.bool(forKey: "peeksEnabled") }
        set { d.set(newValue, forKey: "peeksEnabled") }
    }

    var pausedUntil: Date? {
        get { d.object(forKey: "pausedUntil") as? Date }
        set { d.set(newValue, forKey: "pausedUntil") }
    }

    var isPaused: Bool { (pausedUntil ?? .distantPast) > Date() }

    var setupCardDismissed: Bool {
        get { d.bool(forKey: "setupCardDismissed") }
        set { d.set(newValue, forKey: "setupCardDismissed") }
    }

    // MARK: App moments

    var momentFrequency: MomentFrequency {
        get { d.string(forKey: "momentFrequency").flatMap(MomentFrequency.init(rawValue:)) ?? .everyThreeHours }
        set { d.set(newValue.rawValue, forKey: "momentFrequency") }
    }

    func momentEnabled(_ m: Moment) -> Bool {
        d.object(forKey: "moment.\(m.rawValue)") as? Bool ?? true
    }

    func setMoment(_ m: Moment, enabled: Bool) {
        d.set(enabled, forKey: "moment.\(m.rawValue)")
    }

    var momentGate: MomentGate {
        get {
            var g = d.data(forKey: "momentGate").flatMap { try? JSONDecoder().decode(MomentGate.self, from: $0) }
                ?? MomentGate()
            g.frequency = momentFrequency
            return g
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "momentGate") }
    }

    /// The all-time paddle ball score: left player, right player.
    var paddleScore: (left: Int, right: Int) {
        get {
            let a = d.array(forKey: "paddleScore") as? [Int] ?? [0, 0]
            return (a.first ?? 0, a.count > 1 ? a[1] : 0)
        }
        set { d.set([newValue.left, newValue.right], forKey: "paddleScore") }
    }

    // MARK: Mac reactions

    enum Reaction: String, CaseIterable {
        case working, welcome, power, downloads, sound, devices

        var title: String {
            switch self {
            case .working: "Claude working strip"
            case .welcome: "Welcome back summary"
            case .power: "Charger & low battery"
            case .downloads: "Downloads"
            case .sound: "Mute / unmute"
            case .devices: "Bluetooth devices"
            }
        }
    }

    func reactionEnabled(_ r: Reaction) -> Bool {
        d.object(forKey: "reaction.\(r.rawValue)") as? Bool ?? true
    }

    func setReaction(_ r: Reaction, enabled: Bool) {
        d.set(enabled, forKey: "reaction.\(r.rawValue)")
    }

    var lastHackerStyle: HackerStyle? {
        get { d.string(forKey: "lastHackerStyle").flatMap(HackerStyle.init(rawValue:)) }
        set { d.set(newValue?.rawValue, forKey: "lastHackerStyle") }
    }
}
