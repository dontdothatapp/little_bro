import AppKit
import CoreGraphics

/// Is anyone there, and is the cursor moving? Uses only public, permission-free APIs.
final class ActivityMonitor {
    private(set) var screensAsleep = false
    private(set) var screensaverRunning = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false
        })
        let dc = DistributedNotificationCenter.default()
        observers.append(dc.addObserver(forName: .init("com.apple.screensaver.didstart"), object: nil, queue: .main) { [weak self] _ in
            self?.screensaverRunning = true
        })
        observers.append(dc.addObserver(forName: .init("com.apple.screensaver.didstop"), object: nil, queue: .main) { [weak self] _ in
            self?.screensaverRunning = false
        })
    }

    /// Seconds since the cursor last moved (or dragged).
    var mouseIdle: Double {
        let s = CGEventSourceStateID.combinedSessionState
        return min(CGEventSource.secondsSinceLastEventType(s, eventType: .mouseMoved),
                   CGEventSource.secondsSinceLastEventType(s, eventType: .leftMouseDragged),
                   CGEventSource.secondsSinceLastEventType(s, eventType: .rightMouseDragged))
    }

    /// Seconds since any input at all.
    var inputIdle: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    var isLocked: Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["CGSSessionScreenIsLocked"] as? Bool) ?? ((d["CGSSessionScreenIsLocked"] as? Int) == 1)
    }

    /// The screen is on and unlocked.
    var screenAvailable: Bool { !screensAsleep && !screensaverRunning && !isLocked }

    /// Someone is (probably) looking at the screen.
    var userPresent: Bool { screenAvailable && inputIdle < 5 * 60 }
}
