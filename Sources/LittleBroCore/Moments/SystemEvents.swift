import Foundation

/// Kinds of Bluetooth gadgets Little Bro reacts to differently.
public enum DeviceKind: String, CaseIterable, Sendable {
    case airpods
    /// Over-ear / on-ear headphones and headsets (Sony WH-1000XM5, Xbox headset…).
    case overEar
    case controller
    case mouse
    case keyboard
    /// Anything else (speakers, conference phones…): a simple "Connected" card.
    case other
}

/// Things that happen on the Mac that Little Bro reacts to.
public enum SystemEvent: Equatable, Sendable {
    case charging
    case lowBattery
    case download(name: String, count: Int)
    case sound(muted: Bool)
    case device(DeviceKind, name: String)
    case welcome(finished: Int, waiting: Int)
}

/// Works out what kind of device just connected, from what macOS tells us without
/// any special permission: audio devices' names, and HID usage for input devices.
public enum DeviceClassifier {
    /// A Bluetooth *audio* device, by name.
    public static func audioKind(name: String) -> DeviceKind {
        let n = name.lowercased()
        if n.contains("airpods") || n.contains("beats") || n.contains("powerbeats") { return .airpods }
        let overEar = ["wh-", "headphone", "headset", "xbox wireless headset", "bose", "qc", "quietcomfort",
                       "sennheiser", "momentum", "jbl tune", "jabra", "steelseries", "arctis", "hyperx", "razer",
                       "skullcandy", "audio-technica", "ath-", "beyerdynamic", "marshall", "sony"]
        if overEar.contains(where: { n.contains($0) }) { return .overEar }
        return .other
    }

    /// An input device, by HID usage page/usage (Generic Desktop page 1: 2 mouse, 6 keyboard,
    /// 4/5 joystick/gamepad; digitizer page 0x0D: trackpads) and product name.
    public static func hidKind(usagePage: Int, usage: Int, product: String) -> DeviceKind? {
        let p = product.lowercased()
        if p.contains("controller") || p.contains("gamepad") || p.contains("dualsense") || p.contains("dualshock") {
            return .controller
        }
        if usagePage == 1 {
            switch usage {
            case 4, 5: return .controller
            case 2: return .mouse
            case 6, 7: return .keyboard
            default: break
            }
        }
        if usagePage == 0x0D || p.contains("trackpad") || p.contains("mouse") { return .mouse }
        if p.contains("keyboard") { return .keyboard }
        return nil
    }

    /// A friendlier display name ("Alex’s AirPods Pro" stays as is; "WH-1000XM5" too).
    public static func displayName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The text for the "while you were away" card.
public enum WelcomeSummary {
    public static func title(finished: Int, waiting: Int) -> (main: String, accent: String?) {
        func plural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "\(n) \(one)" : "\(n) \(many)" }
        switch (finished, waiting) {
        case (0, let w): return ("", plural(w, "needs you", "need you"))
        case (let f, 0): return (plural(f, "session finished", "sessions finished"), nil)
        case (let f, let w): return ("\(f) finished ·", plural(w, "needs you", "need you"))
        }
    }
}
