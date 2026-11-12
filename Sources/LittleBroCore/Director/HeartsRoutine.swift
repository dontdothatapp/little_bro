import CoreGraphics
import Foundation

let heartPink = RGBA(1.0, 0.36, 0.5)

/// Tiny hearts drifting up beside the eyes.
final class FloatingHeartsOverlay: Overlay {
    /// (start time, side, size)
    private let hearts: [(Double, Double, Double)] = [(1.7, 1, 5.5), (2.3, -1, 4.5), (2.9, 1, 4), (3.5, -1, 5),
                                                      (4.1, 1, 4.5), (4.6, -1, 4)]
    private let rise = 1.5

    override func decorate(_ s: inout Scene, _ d: Director) {
        let p = clamp(presence.value, 0, 1)
        guard s.isVisible, p > 0.01 else { return }
        let fc = s.faceCenter
        for (i, h) in hearts.enumerated() {
            let age = time - h.0
            guard age > 0, age < rise else { continue }
            let u = age / rise
            let x = Double(fc.x) + h.1 * (33 + 4 * sin(age * 5)) + h.1 * u * 4
            let y = s.blobHeight - 6 - u * (s.blobHeight - 4)
            let a = p * clamp(age * 6, 0, 1) * clamp((1 - u) * 2.2, 0, 1)
            s.shapes.append(ShapeDraw(key: "float-heart\(i)", path: Paths.heart(center: CGPoint(x: x, y: y), width: h.2),
                                      fill: heartPink, glow: heartPink, glowRadius: 5, opacity: a))
        }
    }
}

extension Director {
    /// Visiting a friend's site: eyes → two hearts → one shared, beating heart → eyes.
    func buildHearts() {
        let t = timeline
        t.at(0) { d in
            // A touch taller than a card, so the beating heart has room.
            d.enter(CGSize(width: 124, height: Metrics.compact.height + 4))
            d.setBase(.neutral)
            d.look(0, 0.1)
            d.glow(.white, 0.75)
            d.life = false
            d.overlays.append(FloatingHeartsOverlay())
        }
        t.at(0.15) { d in d.character.open.target = 1 }
        t.at(0.5) { d in
            // Eyes → two hearts, with a little pop.
            d.character.heartMix.target = 1
            d.character.setEyeColor(heartPink)
            d.glow(heartPink, 1)
            d.character.faceScale.velocity += 1.6
            d.hop(70)
        }
        t.at(1.35) { d in
            // The two hearts slide together into one.
            d.character.heartMerge.target = 1
        }
        t.at(1.75) { d in d.squash(45) }
        // Lub-dub, three times: the heart pumps and the body gives with it.
        for beat in [2.25, 3.1, 3.95] {
            t.at(beat) { d in
                d.character.faceScale.velocity += 1.9
                d.squash(30)
            }
            t.at(beat + 0.2) { d in
                d.character.faceScale.velocity += 1.2
                d.squash(18)
            }
        }
        t.at(4.85) { d in d.character.heartMerge.target = 0 }
        t.at(5.15) { d in
            d.character.heartMix.target = 0
            d.character.setEyeColor(.white)
            d.setBase(.happy)
            d.glow(.white, 0.75)
        }
        t.at(5.7) { d in d.setBase(.content) }
        t.at(6.3) { d in d.retract() }
    }
}
