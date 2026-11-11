import CoreGraphics
import Foundation

/// The choreography of every act. Times are seconds from the start of the act.
extension Director {
    /// How long a card stays out (before hover pauses).
    public static let cardDuration = 9.7

    func buildCard(_ card: Card, intro: Bool) {
        let t = timeline
        switch (card.kind, intro) {
        case (.done, true):
            // Drops in, wakes up, a happy hop, then slides the title out.
            t.at(0) { d in
                d.enter(Metrics.compact)
                d.setBase(.neutral)
                d.look(0, 0.1)
                d.glow(.white, 0.85)
                d.life = false
            }
            t.at(0.17) { d in d.character.open.target = 1 }
            t.at(0.6) { d in
                d.setBase(.happy)
                d.hop(150)
            }
            t.at(1.3) { d in
                d.setBase(.content)
                d.showCard(card)
            }
            t.at(1.55) { d in
                d.gaze = .cursor
                d.life = true
                d.nextBlink = d.clock + 1.4
            }
            t.at(5.2) { d in d.setBase(.happy) }
            t.at(5.75) { d in d.setBase(.content) }
            t.at(Director.cardDuration) { d in d.retract() }

        case (.done, false):
            t.at(0) { d in
                d.enter(Metrics.compact)
                d.setBase(.happy)
                d.look(0, 0.15)
                d.glow(.white, 0.85)
                d.life = false
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            t.at(0.5) { d in d.hop(90) }
            t.at(0.85) { d in
                d.setBase(.content)
                d.showCard(card)
            }
            t.at(1.0) { d in
                d.gaze = .cursor
                d.life = true
                d.nextBlink = d.clock + 1.0
            }
            t.at(5.4) { d in d.setBase(.happy) }
            t.at(5.95) { d in d.setBase(.content) }
            t.at(Director.cardDuration) { d in d.retract() }

        case (.needsInput, true):
            // Wide-eyed, looks around for you, then a pleading look with an orange glow.
            t.at(0) { d in
                d.enter(Metrics.compact)
                d.setBase(.wide)
                d.look(0, 0.05)
                d.glow(.claude, 1.0)
                d.life = false
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            t.at(0.50) { d in d.look(-0.85, 0.15) }
            t.at(0.85) { d in d.look(0.85, 0.15) }
            t.at(1.2) { d in d.plead() }
            t.at(1.3) { d in d.showCard(card) }
            t.at(1.5) { d in
                d.life = true
                d.nextBlink = d.clock + 1.6
            }
            for nt in [2.9, 5.8, 8.4] {
                t.at(nt) { d in d.nudge() }
            }
            t.at(Director.cardDuration) { d in d.retract() }

        case (.needsInput, false):
            t.at(0) { d in
                d.enter(Metrics.compact)
                d.setBase(.pleading)
                d.look(0, 0.0)
                d.glow(.claude, 1.0, pulse: 1)
                d.life = false
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            t.at(0.45) { d in
                d.plead()
                d.showCard(card)
            }
            t.at(0.65) { d in
                d.nudge()
                d.life = true
                d.nextBlink = d.clock + 1.4
            }
            for nt in [3.6, 6.6] {
                t.at(nt) { d in d.nudge() }
            }
            t.at(Director.cardDuration) { d in d.retract() }
        }
    }

    func buildIdle(_ variant: IdleVariant) {
        let t = timeline
        switch variant {
        case .lookAround:
            t.at(0) { d in
                d.enter(Metrics.idle)
                d.setBase(.neutral)
                d.look(0, 0.25)
                d.glow(.white, 0.7)
                d.life = false
            }
            t.at(0.35) { d in d.character.open.target = 1 }
            t.at(1.0) { d in d.look(-0.85, 0.35) }
            t.at(1.9) { d in d.look(0.85, 0.35) }
            t.at(2.5) { d in d.character.blink() }
            t.at(2.8) { d in
                d.gaze = .cursor
                d.life = true
                d.nextBlink = d.clock + 2
            }
            t.at(3.4) { d in d.setBase(.glad) }
            t.at(5.4) { d in d.setBase(.neutral) }
            t.at(6.4) { d in d.retract() }

        case .sleepy:
            t.at(0) { d in
                d.enter(Metrics.idle)
                d.setBase(.sleepy)
                d.look(0, 0.45)
                d.glow(.white, 0.5)
                d.life = false
            }
            t.at(0.45) { d in d.character.open.target = 1 }
            t.at(1.5) { d in d.character.blink(slow: true) }
            t.at(2.6) { d in
                d.setBase(.drowsy)
                d.character.baseSize.height = Metrics.idle.height + 4
                d.character.breathe.target = 1.5
                d.look(0, 0.7)
            }
            t.at(3.4) { d in d.character.open.target = 0.1 }
            t.at(4.7) { d in
                d.character.open.target = 1
                d.character.baseSize.height = Metrics.idle.height
                d.character.breathe.target = 0
                d.setBase(.wide)
                d.hop(140)
                d.look(0, 0.1)
            }
            t.at(5.3) { d in
                d.setBase(.sleepy)
                d.gaze = .cursor
            }
            t.at(6.1) { d in d.character.blink(slow: true) }
            t.at(7.0) { d in d.retract() }

        case .hello:
            t.at(0) { d in
                d.enter(Metrics.idle)
                d.setBase(.neutral)
                d.look(0, 0.3)
                d.glow(.white, 0.8)
                d.life = false
            }
            t.at(0.25) { d in d.character.open.target = 1 }
            t.at(0.55) { d in
                d.setBase(.happy)
                d.hop(160)
            }
            t.at(1.05) { d in
                d.gaze = .cursor
                d.setBase(.wink)
                d.shimmy(95)
            }
            t.at(1.75) { d in
                d.setBase(.content)
                d.life = true
                d.nextBlink = d.clock + 1.2
            }
            t.at(2.6) { d in d.hop(100) }
            t.at(4.8) { d in d.retract() }

        case .curious:
            t.at(0) { d in
                d.enter(Metrics.idle)
                d.setBase(.neutral)
                d.gaze = .cursor
                d.glow(.white, 0.75)
                d.life = false
            }
            t.at(0.3) { d in d.character.open.target = 1 }
            t.at(1.0) { d in d.setBase(.curiousLeft) }
            t.at(2.3) { d in d.setBase(.curiousRight) }
            t.at(3.5) { d in
                d.setBase(.neutral)
                d.life = true
                d.nextBlink = d.clock + 0.5
            }
            t.at(5.2) { d in d.retract() }

        case .shy:
            t.at(0) { d in
                let fromHidden = d.character.isFullyHidden
                d.enter(Metrics.idle)
                if fromHidden { d.character.faceX.snap(to: 52) }
                d.character.faceX.target = 52
                d.setBase(.sly)
                d.look(-0.6, 0.2)
                d.glow(.white, 0.7)
                d.life = false
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            t.at(0.3) { d in d.character.faceX.target = 20 }
            t.at(1.5) { d in d.gaze = .cursor }
            t.at(2.3) { d in
                d.character.faceX.target = 0
                d.setBase(.content)
                d.character.blush.target = 1
                d.life = true
                d.nextBlink = d.clock + 1
            }
            t.at(3.4) { d in d.character.blush.target = 0 }
            t.at(3.9) { d in
                d.character.faceX.target = 84
                d.setBase(.sly)
                d.look(-0.7, 0.2)
                d.life = false
            }
            t.at(4.1) { d in d.retract(fast: true) }
        }
    }

    /// The "needs you" face: pleading, a touch bigger, looking up towards you, gently swaying.
    func plead() {
        gaze = .cursor
        gazeGainY = 0.35
        gazeBiasY = -0.32
        setBase(.pleading)
        character.faceScale.target = 1.08
        restingFaceScale = 1.08
        character.sway.target = 1.0
        glow(.claude, 1.0, pulse: 1)
    }

    func buildPeek() {
        let t = timeline
        t.at(0) { d in
            d.enter(Metrics.peek, anchor: 1, faceScale: 0.6)
            d.setBase(.peek)
            d.look(0, 1)
            d.glow(.white, 0.6)
            d.life = false
        }
        t.at(0.3) { d in d.character.open.target = 1 }
        t.at(1.0) { d in d.look(-0.45, 1) }
        t.at(1.9) { d in d.look(0.35, 1) }
        t.at(2.4) { d in d.character.blink() }
        t.at(2.8) { d in
            d.gaze = .cursor
            d.setBase(.content)
        }
        t.at(3.4) { d in
            d.look(0, 1)
            d.setBase(.peek)
        }
        t.at(4.0) { d in d.retract() }
    }
}
