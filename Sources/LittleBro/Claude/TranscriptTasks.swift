import Foundation
import LittleBroCore

/// Follows each session's transcript (only reading what was appended since last time) to know
/// how many background tasks it still has running. Reading happens on a background queue: the
/// first, larger read starts as soon as a session shows up, so later checks are tiny deltas.
final class TranscriptTasks {
    private struct Tail {
        var path: String
        var offset: UInt64
        var started = false
        var partial = Data()
        var ledger = BackgroundTaskLedger()
    }

    private var tails: [String: Tail] = [:]
    private let queue = DispatchQueue(label: "littlebro.transcripts", qos: .utility)
    /// On first sight of a long transcript, only its end is read.
    private let initialWindow: UInt64 = 8 * 1024 * 1024

    /// Call from the main thread with each hook event's transcript path.
    func note(session: String, transcript: String?) {
        guard let path = transcript, !path.isEmpty else { return }
        queue.async { [self] in
            guard tails[session]?.path != path else { return }
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
            var tail = Tail(path: path, offset: size > initialWindow ? size - initialWindow : 0)
            catchUp(&tail)
            tails[session] = tail
        }
    }

    /// Background tasks still running for this session (reads any new transcript lines first).
    func running(_ session: String) -> Set<String> {
        queue.sync {
            guard var tail = tails[session] else { return [] }
            catchUp(&tail)
            tails[session] = tail
            return tail.ledger.running
        }
    }

    private func catchUp(_ tail: inout Tail) {
        guard let h = FileHandle(forReadingAtPath: tail.path) else { return }
        defer { try? h.close() }
        guard let end = try? h.seekToEnd(), end > tail.offset else { return }
        let midFile = !tail.started && tail.offset > 0
        tail.started = true
        try? h.seek(toOffset: tail.offset)
        guard var chunk = try? h.read(upToCount: Int(end - tail.offset)) else { return }
        tail.offset = end
        if midFile, let nl = chunk.firstIndex(of: 0x0A) {
            // Started mid-file: drop the cut-off first line.
            chunk = chunk.subdata(in: chunk.index(after: nl)..<chunk.endIndex)
        }
        let data = tail.partial + chunk
        var start = data.startIndex
        while let nl = data[start...].firstIndex(of: 0x0A) {
            tail.ledger.ingest(data.subdata(in: start..<nl))
            start = data.index(after: nl)
        }
        tail.partial = data.subdata(in: start..<data.endIndex)
    }
}
