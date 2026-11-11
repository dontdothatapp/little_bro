import CoreGraphics
import Foundation

extension Expression {
    /// Running on empty.
    static let tired = Expression(EyeShape(width: 1.02, height: 0.9, lidTop: 0.44, lidAngle: -0.28))
    /// Game on.
    static let gameFace = Expression(EyeShape(width: 1.06, height: 1.0, lidTop: 0.34, lidAngle: 0.18))
}

/// Choreography for the working strip and for things that happen on the Mac.
extension Director {
    func buildWorking(count: Int) {
        let t = timeline
        t.at(0) { d in
            let size = CGSize(width: count > 1 ? Metrics.strip.width + 12 : Metrics.strip.width,
                              height: Metrics.strip.height)
            d.enter(size, faceScale: 0.3)
            d.setBase(.neutral)
            d.gaze = .scan
            d.glow(.white, 0.5)
            d.life = true
            d.nextBlink = d.clock + 1.5
            d.overlays.append(StripOverlay(count: count))
        }
        t.at(0.12) { d in d.character.open.target = 1 }
    }

    func buildSystem(_ event: SystemEvent) {
        let t = timeline
        switch event {
        case .charging:
            t.at(0) { d in
                d.enter(Metrics.idle)
                d.setBase(.neutral)
                d.look(0, 0.1)
                d.glow(.white, 0.7)
                d.life = false
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            t.at(0.55) { d in
                d.overlays.append(BoltOverlay())
                d.setBase(.wide)
                d.character.setEyeColor(RGBA(1, 0.98, 0.86))
                d.glow(electricYellow, 1)
                d.hop(90)
            }
            t.at(1.25) { d in
                d.setBase(.happy)
                d.character.setEyeColor(.white)
            }
            t.at(1.9) { d in d.glow(.white, 0.7) }
            t.at(2.8) { d in d.retract() }

        case .lowBattery:
            t.at(0) { d in
                d.enter(CGSize(width: 104, height: Metrics.compact.height))
                d.setBase(.tired)
                d.look(0, 0.7)
                d.glow(.white, 0.45)
                d.life = true
                d.blinkScale = 1.7
                d.character.faceX.target = -8
                d.overlays.append(BatteryOverlay())
            }
            t.at(0.2) { d in d.character.open.target = 1 }
            t.at(0.6) { d in
                // Sag: a little taller and narrower, slowly.
                d.character.blobW.params = SpringParams(response: 1.6, damping: 1)
                d.character.blobH.params = SpringParams(response: 1.6, damping: 1)
                d.character.baseSize = CGSize(width: 94, height: Metrics.compact.height + 6)
                d.character.rowHeight = Metrics.compact.height + 6
            }
            t.at(4.3) { d in
                d.character.blobW.params = SpringParams(response: 0.56, damping: 0.68)
                d.retract()
            }

        case .download(let name, let count):
            t.at(0) { d in
                d.enter(Metrics.compact)
                d.setBase(.neutral)
                d.look(0, 0.6)
                d.glow(.white, 0.75)
                d.life = false
                d.overlays.append(FileOverlay())
            }
            t.at(0.12) { d in d.character.open.target = 1 }
            t.at(1.12) { d in
                // Gulp.
                d.squash(95)
                d.setBase(.happy)
            }
            t.at(1.7) { d in
                d.setBase(.content)
                d.gaze = .cursor
                d.life = true
                d.showCard(Card(kind: .done, status: "Downloaded", title: count > 1 ? "\(count) files" : name))
            }
            t.at(5.8) { d in d.retract() }

        case .sound(let muted):
            t.at(0) { d in
                let fromHidden = d.character.isFullyHidden
                d.enter(CGSize(width: 112, height: Metrics.compact.height))
                d.character.faceX.target = -10
                d.setBase(.neutral)
                d.look(0, 0.05)
                d.glow(.white, 0.75)
                d.life = false
                d.overlays.append(SpeakerOverlay(muted: muted))
                if !muted {
                    // Unmute: the eyes start as tiny dots…
                    if fromHidden { d.character.faceScale.snap(to: 0.15) }
                    d.character.faceScale.target = 0.15
                    d.restingFaceScale = 0.15
                }
            }
            t.at(0.12) { d in d.character.open.target = 1 }
            if muted {
                // …mute: full-size eyes shrink down to tiny dots.
                t.at(0.5) { d in
                    d.character.faceScale.target = 0.15
                    d.restingFaceScale = 0.15
                }
            } else {
                t.at(0.4) { d in
                    d.character.faceScale.target = 1
                    d.restingFaceScale = 1
                    d.setBase(.wide)
                }
                t.at(1.2) { d in d.setBase(.neutral) }
            }
            t.at(2.2) { d in d.retract() }

        case .welcome(let finished, let waiting):
            let (main, accent) = WelcomeSummary.title(finished: finished, waiting: waiting)
            t.at(0) { d in
                d.enter(Metrics.compact)
                d.setBase(.neutral)
                d.look(0, 0.1)
                d.glow(.white, 0.8)
                d.life = false
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            t.at(0.45) { d in
                d.setBase(.happy)
                d.hop(140)
            }
            t.at(1.0) { d in
                d.setBase(.content)
                d.showCard(Card(kind: .done, status: "While you were away", title: main, accent: accent))
            }
            t.at(1.3) { d in
                d.gaze = .cursor
                d.life = true
            }
            t.at(7.5) { d in d.retract() }

        case .device(let kind, let name):
            buildDevice(kind, name: name)
        }
    }

    private func buildDevice(_ kind: DeviceKind, name: String) {
        let t = timeline
        let card = Card(kind: .done, status: "Connected", title: name)
        switch kind {
        case .airpods:
            t.at(0) { d in
                d.enter(CGSize(width: 112, height: Metrics.compact.height))
                d.setBase(.neutral)
                d.look(0, 0.1)
                d.glow(.white, 0.75)
                d.life = false
                d.overlays.append(AirPodsOverlay())
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            t.at(0.95) { d in d.look(-0.9, 0.1) }
            t.at(1.35) { d in d.look(0.9, 0.1) }
            t.at(1.75) { d in
                d.look(0, 0.1)
                d.setBase(.content)
                d.showCard(card)
            }
            t.at(2.1) { d in
                d.gaze = .cursor
                d.life = true
            }
            t.at(5.4) { d in d.retract() }

        case .overEar:
            t.at(0) { d in
                d.enter(CGSize(width: 116, height: Metrics.compact.height))
                d.setBase(.neutral)
                d.look(0, 0.1)
                d.glow(.white, 0.75)
                d.life = false
                d.overlays.append(OverEarOverlay())
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            // The noise fades away… and it closes its eyes in relief.
            t.at(1.2) { d in
                d.character.open.params = SpringParams(response: 0.7, damping: 1)
                d.character.open.target = 0.08
            }
            t.at(2.4) { d in
                d.character.open.params = SpringParams(response: 0.2, damping: 0.78)
                d.character.open.target = 1
                d.setBase(.content)
            }
            t.at(2.7) { d in
                d.showCard(card)
                d.gaze = .cursor
                d.life = true
            }
            t.at(6.0) { d in d.retract() }

        case .controller:
            var overlay: ControllerOverlay?
            t.at(0) { d in
                d.enter(CGSize(width: 150, height: Metrics.compact.height))
                d.character.faceX.target = -18
                d.setBase(.neutral)
                d.look(0, 0.1)
                d.glow(.white, 0.75)
                d.life = false
                let o = ControllerOverlay()
                overlay = o
                d.overlays.append(o)
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            t.at(0.8) { d in d.look(0.9, 0.1) }
            t.at(1.4) { d in
                d.look(0, 0.1)
                d.setBase(.gameFace)
                d.glow(gamerGreen, 1)
                overlay?.lit = true
            }
            t.at(1.9) { d in d.hop(110) }
            t.at(2.25) { d in d.hop(110) }
            t.at(4.6) { d in
                d.setBase(.content)
                d.glow(.white, 0.75)
            }
            t.at(5.0) { d in d.retract() }

        case .mouse:
            t.at(0) { d in
                d.enter(CGSize(width: 160, height: Metrics.compact.height))
                d.setBase(.neutral)
                d.glow(.white, 0.75)
                d.life = false
                d.overlays.append(CursorOverlay())
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            t.at(2.6) { d in d.setBase(.content) }
            t.at(3.9) { d in
                for o in d.overlays where o is CursorOverlay { o.presence.target = 0 }
                d.look(0, 0.1)
            }
            t.at(4.4) { d in d.retract() }

        case .keyboard:
            t.at(0) { d in
                d.enter(CGSize(width: 160, height: Metrics.compact.height + 4), faceScale: 0.8)
                d.character.rowHeight = 30
                d.setBase(.neutral)
                d.look(0, 0.5)
                d.glow(.white, 0.75)
                d.life = false
                d.overlays.append(KeycapsOverlay())
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            t.at(3.3) { d in
                d.look(0, 0)
                d.setBase(.happy)
            }
            t.at(3.8) { d in d.setBase(.content) }
            t.at(4.9) { d in d.retract() }

        case .other:
            t.at(0) { d in
                d.enter(Metrics.compact)
                d.setBase(.neutral)
                d.look(0, 0.1)
                d.glow(.white, 0.75)
                d.life = false
            }
            t.at(0.15) { d in d.character.open.target = 1 }
            t.at(0.5) { d in
                d.setBase(.content)
                d.character.blink()
            }
            t.at(0.8) { d in
                d.showCard(card)
                d.gaze = .cursor
                d.life = true
            }
            t.at(4.6) { d in d.retract() }
        }
    }
}
