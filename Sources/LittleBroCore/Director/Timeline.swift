import Foundation

/// A list of timed cues. Routines are written as "at t seconds, do this".
final class Timeline {
    private struct Cue {
        let at: Double
        let order: Int
        let run: (Director) -> Void
    }

    private(set) var time: Double = 0
    private var cues: [Cue] = []
    private var index = 0
    private var started = false

    var isFinished: Bool { started && index >= cues.count }

    func at(_ t: Double, _ run: @escaping (Director) -> Void) {
        cues.append(Cue(at: t, order: cues.count, run: run))
    }

    func start() {
        cues.sort { $0.at == $1.at ? $0.order < $1.order : $0.at < $1.at }
        index = 0
        time = 0
        started = true
    }

    func advance(_ dt: Double, _ director: Director) {
        guard started else { return }
        time += dt
        while index < cues.count, cues[index].at <= time {
            let cue = cues[index]
            index += 1
            cue.run(director)
            // A cue may have replaced the director's timeline (e.g. by retracting).
            if director.timeline !== self { return }
        }
    }
}
