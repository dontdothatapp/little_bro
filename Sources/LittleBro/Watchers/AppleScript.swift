import Foundation

enum AppleScript {
    enum Result {
        case success(String)
        case denied
        case failed
    }

    /// Runs AppleScript in a child `osascript` (off the main thread; never blocks a frame).
    static func run(_ source: String) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return .failed }
        let deadline = Date().addingTimeInterval(4)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning {
            p.terminate()
            return .failed
        }
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus == 0 { return .success(o) }
        if e.contains("-1743") || e.lowercased().contains("not authorized") { return .denied }
        return .failed
    }
}
