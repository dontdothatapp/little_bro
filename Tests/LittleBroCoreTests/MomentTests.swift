import Foundation
import Testing
@testable import LittleBroCore

@Suite struct BeatTests {
    /// A little synthetic track: kick on every beat, hat on the off-beats, a bass note, noise.
    func track(bpm: Double, seconds: Double, offset: Double, sampleRate: Double = 44100) -> [Float] {
        var rng = SeededRandom(seed: 99)
        let n = Int(seconds * sampleRate)
        var out = [Float](repeating: 0, count: n)
        let period = 60 / bpm
        var beatT = offset
        while beatT < seconds {
            for (t0, isKick) in [(beatT, true), (beatT + period / 2, false)] {
                let start = Int(t0 * sampleRate)
                let len = Int((isKick ? 0.12 : 0.04) * sampleRate)
                for i in 0..<len where start + i < n && start + i >= 0 {
                    let t = Double(i) / sampleRate
                    let env = exp(-t * (isKick ? 30 : 90))
                    let v = isKick ? sin(2 * .pi * (55 + 80 * exp(-t * 40)) * t) : rng.range(-1, 1)
                    out[start + i] += Float(env * v * (isKick ? 0.9 : 0.3))
                }
            }
            beatT += period
        }
        for i in 0..<n {
            out[i] += Float(0.12 * sin(2 * .pi * 110 * Double(i) / sampleRate) + rng.range(-0.02, 0.02))
        }
        return out
    }

    @Test(arguments: [(96.0, 0.13), (112.0, 0.31), (128.0, 0.05), (140.0, 0.22)])
    func detectsTempoAndPhase(bpm: Double, offset: Double) throws {
        let seconds = 7.0
        let d = BeatDetector(sampleRate: 44100)
        d.process(track(bpm: bpm, seconds: seconds, offset: offset))
        let e = try #require(d.estimate())
        #expect(abs(e.bpm - bpm) < 2.5, "bpm \(e.bpm) vs \(bpm)")
        let period = 60 / bpm
        let analysedEnd = d.secondsAnalysed + 1024.0 / 44100 // last frame's window end
        let expected = ((analysedEnd - offset) / period).truncatingRemainder(dividingBy: 1)
        var diff = abs(e.phase - expected)
        diff = min(diff, 1 - diff)
        #expect(diff < 0.15, "phase \(e.phase) vs \(expected)")
        #expect(e.confidence > 0.1)
    }

    @Test func silenceGivesNothing() {
        let d = BeatDetector(sampleRate: 44100)
        d.process([Float](repeating: 0, count: 44100 * 5))
        #expect(d.estimate() == nil)
    }

    @Test func clockLocksOnWithoutJumping() {
        var c = BeatClock(bpm: 112)
        let truth = 124.0
        var truthPos = 0.37
        var maxStep = 0.0
        var last = c.position
        for i in 0..<(60 * 8) {
            let dt = 1.0 / 60
            truthPos += truth / 60 * dt
            if i % 15 == 0 { c.sync(bpm: truth, phase: truthPos - floor(truthPos)) }
            c.advance(dt)
            maxStep = max(maxStep, c.position - last)
            last = c.position
        }
        var err = abs(c.phase - (truthPos - floor(truthPos)))
        err = min(err, 1 - err)
        #expect(abs(c.bpm - truth) < 0.5)
        #expect(err < 0.05)
        // Never more than 30 % faster than the tempo in one frame (no visible skip).
        #expect(maxStep < truth / 60 / 60 * 1.35)
    }

    @Test func clockKeepsItsOctave() {
        var c = BeatClock(bpm: 120)
        c.sync(bpm: 61, phase: 0)
        for _ in 0..<600 { c.advance(1.0 / 60) }
        #expect(abs(c.bpm - 122) < 1)
    }
}

@Suite struct RallyTests {
    @Test func everyRallyEndsAndEitherSideCanWin() {
        var leftWins = 0, rightWins = 0, totalHits = 0
        for seed in 0..<300 {
            var r = PaddleRally(seed: UInt64(seed))
            r.serve()
            var t = 0.0
            while !r.isFinished && t < 20 {
                r.step(1.0 / 60)
                t += 1.0 / 60
            }
            #expect(r.isFinished, "seed \(seed) never ended")
            #expect(t < 9, "seed \(seed) took \(t)s")
            if r.winner == -1 { leftWins += 1 } else if r.winner == 1 { rightWins += 1 }
            totalHits += r.hits
        }
        #expect(leftWins > 90 && rightWins > 90, "left \(leftWins) right \(rightWins)")
        let avg = Double(totalHits) / 300
        #expect(avg > 2 && avg < 8, "average hits \(avg)")
    }

    @Test func ballStaysInsideTheCourtVertically() {
        var r = PaddleRally(seed: 4)
        r.serve()
        for _ in 0..<600 {
            r.step(1.0 / 60)
            #expect(Double(r.ball.y) >= r.config.top - 0.01 && Double(r.ball.y) <= r.config.bottom + 0.01)
        }
    }

    @Test func sameSeedSameRally() {
        var a = PaddleRally(seed: 77), b = PaddleRally(seed: 77)
        a.serve(); b.serve()
        for _ in 0..<300 { a.step(1.0 / 60); b.step(1.0 / 60) }
        #expect(a.ball == b.ball && a.hits == b.hits)
    }
}

@Suite struct MomentCatalogTests {
    @Test func appsMap() {
        #expect(MomentCatalog.moment(bundleId: "com.spotify.client") == .music)
        #expect(MomentCatalog.moment(bundleId: "com.googlecode.iterm2") == .hacker)
        #expect(MomentCatalog.moment(bundleId: "com.todesktop.230313mzl4w4u92") == .hacker) // Cursor
        #expect(MomentCatalog.moment(bundleId: "com.jetbrains.intellij") == .hacker)
        #expect(MomentCatalog.moment(bundleId: "com.valvesoftware.steam") == .gaming)
        #expect(MomentCatalog.moment(bundleId: "com.example.game", category: "public.app-category.action-games") == .gaming)
        #expect(MomentCatalog.moment(bundleId: nil, bundlePath: "/x/steamapps/common/Brotato/Brotato.app") == .gaming)
        #expect(MomentCatalog.moment(bundleId: "com.anthropic.claudefordesktop") == nil)
        #expect(MomentCatalog.moment(bundleId: "com.apple.Safari") == nil)
    }

    @Test func sitesMap() {
        #expect(MomentCatalog.moment(url: "https://open.spotify.com/playlist/37i9") == .music)
        #expect(MomentCatalog.moment(url: "https://steamdb.info/app/570/") == .gaming)
        #expect(MomentCatalog.moment(url: "https://www.gog.com/en/game/x") == .gaming)
        #expect(MomentCatalog.moment(url: "https://bitbucket.itch.io/game") == .gaming)
        #expect(MomentCatalog.moment(url: "https://www.xbox.com/play") == .gaming)
        #expect(MomentCatalog.moment(url: "https://www.xbox.com/en-US/games") == nil)
        #expect(MomentCatalog.moment(url: "https://github.com/x") == nil)
        #expect(MomentCatalog.moment(url: "not a url") == nil)
        #expect(MomentCatalog.moment(url: "https://logue.is/") == .love)
        #expect(MomentCatalog.moment(url: "https://www.logue.is/some/page?x=1") == .love)
        #expect(MomentCatalog.moment(url: "https://app.logue.is/") == .love)
        #expect(MomentCatalog.moment(url: "https://catalogue.is/") == nil)
        #expect(MomentCatalog.webMoments.contains(.love))
    }

    @Test func gate() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var g = MomentGate(frequency: .everyThreeHours)
        #expect(g.allows(.music, now: t0))
        g.record(.music, at: t0)
        #expect(!g.allows(.music, now: t0.addingTimeInterval(2 * 3600)))
        #expect(g.allows(.hacker, now: t0.addingTimeInterval(60)))
        #expect(g.allows(.music, now: t0.addingTimeInterval(3 * 3600 + 1)))
        g.frequency = .everyTime
        #expect(g.allows(.music, now: t0.addingTimeInterval(1)))
    }

    @Test func gateRoundTrips() throws {
        var g = MomentGate()
        g.record(.gaming, at: Date(timeIntervalSince1970: 5))
        let back = try JSONDecoder().decode(MomentGate.self, from: JSONEncoder().encode(g))
        #expect(back.lastPlayed[.gaming] == Date(timeIntervalSince1970: 5))
    }
}
