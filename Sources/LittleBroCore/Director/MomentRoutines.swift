import CoreGraphics
import Foundation

/// Choreography for app moments: music, Hackerman, gaming.
extension Director {
    public static let vibeDuration = 9.5

    func buildVibe() {
        let t = timeline
        t.at(0) { d in
            d.enter(CGSize(width: 116, height: Metrics.compact.height))
            d.setBase(.blissful)
            d.eyesOpenInGroove = false
            d.look(0, 0.1)
            d.glow(.white, 0.7)
            d.life = false
            d.overlays.append(HeadphonesOverlay())
            d.rhythmAmount.target = 1
        }
        t.at(0.2) { d in d.character.open.target = 1 }
        t.at(Director.vibeDuration) { d in d.retract() }
    }

    func buildHacker(_ style: HackerStyle) {
        let t = timeline
        switch style {
        case .shades:
            var overlay: ShadesTerminalOverlay?
            t.at(0) { d in
                d.enter(Metrics.compact)
                d.setBase(.neutral)
                d.look(0, 0.1)
                d.glow(.white, 0.75)
                d.life = false
                let o = ShadesTerminalOverlay(rng: &d.rng)
                overlay = o
                d.overlays.append(o)
            }
            t.at(0.2) { d in d.character.open.target = 1 }
            t.at(0.5) { d in d.look(-0.85, 0.1) }
            t.at(0.8) { d in d.look(0.85, 0.1) }
            t.at(1.05) { d in
                d.look(0, 0.1)
                overlay?.drop.target = 1
            }
            t.at(1.3) { d in
                // Shades on: eyes narrow behind them; the body widens for the terminal.
                d.setBase(.focused)
                d.character.open.target = 0.3
                d.glow(RGBA(0.24, 1, 0.48), 0.6)
                d.character.baseSize.width = 296
                d.character.faceX.target = -(296 / 2 - 42)
            }
            t.at(6.75) { d in
                overlay?.showTerminal = false
                d.character.baseSize.width = Metrics.compact.width
                d.character.faceX.target = 0
            }
            t.at(7.1) { d in
                overlay?.drop.target = 0
                d.character.open.target = 1
                d.setBase(.content)
                d.glow(.white, 0.75)
            }
            t.at(7.7) { d in d.retract() }

        case .rain:
            t.at(0) { d in
                d.enter(CGSize(width: 176, height: Metrics.compact.height))
                d.setBase(.neutral)
                d.look(0, 0.1)
                d.glow(.white, 0.75)
                d.life = false
                d.overlays.append(CodeRainOverlay(rng: &d.rng))
            }
            t.at(0.2) { d in d.character.open.target = 1 }
            t.at(0.75) { d in
                d.setBase(.focused)
                d.character.setEyeColor(RGBA(0.85, 1, 0.9))
                d.glow(RGBA(0.24, 1, 0.48), 1)
            }
            // Speed-reading: the gaze steps along a line, then flicks back to the next one.
            var step = 0
            var at = 1.0
            while at < 6.2 {
                let i = step
                t.at(at) { d in
                    let col = i % 6, line = (i / 6) % 3
                    d.look(lerp(-0.9, 0.9, Double(col) / 5), -0.25 + Double(line) * 0.3)
                }
                step += 1
                at += step % 6 == 0 ? 0.32 : 0.13
            }
            t.at(6.4) { d in
                d.look(0, 0.1)
                d.character.setEyeColor(.white)
                d.setBase(.content)
                d.glow(.white, 0.75)
            }
            t.at(7.0) { d in d.retract() }
        }
    }

    func buildGame(left: Int, right: Int) {
        let t = timeline
        t.at(0) { d in
            d.enter(CGSize(width: 200, height: Metrics.compact.height))
            d.setBase(.neutral)
            d.look(0, 0.1)
            d.glow(.white, 0.75)
            d.life = false
            let seed = UInt64(d.rng.range(0, 1_000_000_000))
            d.overlays.append(CourtOverlay(score: (left, right), seed: seed,
                                           topInset: d.character.profile.topInset))
        }
        t.at(0.2) { d in d.character.open.target = 1 }
        t.at(0.6) { d in d.character.paddleMix.target = 1 }
        // Safety net: the rally always ends well before this, but never hang around.
        t.at(16) { d in d.retract() }
    }
}
