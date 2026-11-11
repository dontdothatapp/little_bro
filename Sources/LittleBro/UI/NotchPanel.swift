import AppKit
import LittleBroCore

/// A borderless, transparent, non-activating panel pinned to the top-centre of a
/// screen, above the menu bar and over full-screen apps. It ignores the mouse except
/// while the cursor is over Little Bro's body.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Metrics.canvas),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Allow sitting over the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func place(on screen: NSScreen) {
        let size = Metrics.canvas
        let frame = NSRect(x: (screen.frame.midX - size.width / 2).rounded(), y: screen.frame.maxY - size.height,
                           width: size.width, height: size.height)
        if self.frame != frame { setFrame(frame, display: false) }
    }
}

extension NSScreen {
    /// Notch size, if this screen has one.
    var notchProfile: ScreenProfile {
        let top = safeAreaInsets.top
        guard top > 0, let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea else { return ScreenProfile() }
        return ScreenProfile(topInset: Double(top), minWidth: Double(frame.width - l.width - r.width))
    }

    static var withMouse: NSScreen? {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main
    }
}
