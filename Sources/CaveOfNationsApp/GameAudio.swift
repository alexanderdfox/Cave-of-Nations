//
//  GameAudio.swift
//  CaveOfNationsApp
//
//  Routes UI feedback sounds through volume sliders until dedicated music/FX assets ship.
//

import AppKit

@MainActor
final class GameAudio {
    static let shared = GameAudio()

    enum Effect {
        case select
        case move
        case dig
        case invalid
        case hover
    }

    private var musicVolume: Double = 0.7
    private var effectsVolume: Double = 0.8

    private init() {}

    func configure(musicVolume: Double, effectsVolume: Double) {
        self.musicVolume = min(max(musicVolume, 0), 1)
        self.effectsVolume = min(max(effectsVolume, 0), 1)
    }

    var effectiveMusicVolume: Double { musicVolume }

    func play(_ effect: Effect) {
        guard effectsVolume > 0.01 else { return }
        let soundName: String
        switch effect {
        case .select: soundName = "Pop"
        case .move: soundName = "Tock"
        case .dig: soundName = "Blow"
        case .invalid: soundName = "Basso"
        case .hover: soundName = "Morse"
        }
        guard let sound = NSSound(named: soundName) else {
            NSSound.beep()
            return
        }
        sound.volume = Float(effectsVolume)
        sound.play()
    }
}
