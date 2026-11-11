import AppKit
import ImageIO
import LittleBroCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings()
    var presenter: Presenter!
    var statusMenu: StatusMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One Little Bro at a time.
        let me = ProcessInfo.processInfo.processIdentifier
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != me }) {
            Log.info("another instance is running; exiting")
            NSApp.terminate(nil)
            return
        }

        presenter = Presenter(settings: settings)
        statusMenu = StatusMenu(presenter: presenter, settings: settings)
        presenter.onStateChange = { [weak self] in self?.statusMenu.refreshIcon() }

        presenter.start()
        Log.info("launched \(Bundle.main.bundlePath)")

        // Say hi. If Claude Code isn't connected yet, offer it with a card: Little Bro never
        // edits ~/.claude/settings.json on its own — only when you click to connect.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            if self.settings.claudeEnabled && !ClaudeHooks.isInstalled() && !self.settings.setupCardDismissed {
                self.presenter.offerSetup()
            } else {
                self.presenter.present(.idle(.hello))
            }
        }
    }

    /// `littlebro://play/<act>` plays an animation (handy for testing);
    /// `littlebro://debug/snapshot` writes the current frame to disk.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "littlebro" {
            let parts = url.pathComponents.filter { $0 != "/" }
            switch url.host {
            case "play":
                if let key = parts.first, let act = Previews.act(key) { presenter.present(act) }
            case "debug":
                if parts.first == "snapshot" { DebugSnapshot.write(presenter) }
                if parts.first == "present" { presenter.forcePresentUntil = Date().addingTimeInterval(120) }
            default:
                break
            }
        }
    }
}

enum DebugSnapshot {
    /// Renders the live layer tree to a PNG next to the log, for checking orientation and layout.
    static func write(_ presenter: Presenter) {
        guard let layer = presenter.view.layer else { return }
        let scale: CGFloat = 2
        let size = layer.bounds.size
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        layer.presentation()?.render(in: ctx) ?? layer.render(in: ctx)
        guard let image = ctx.makeImage() else { return }
        let url = AppPaths.appSupport.appendingPathComponent("snapshot-\(Int(Date().timeIntervalSince1970)).png")
        if let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            Log.info("snapshot \(url.path) window \(presenter.panel.windowNumber) frame \(presenter.panel.frame)")
        }
    }
}
