import AppKit

/// Plays Lingo's start and stop cues. Sounds are loaded once and reused.
@MainActor
final class SoundPlayer {
    /// The bundled cue set: `start-<name>.wav` and `stop-<name>.wav`.
    private static let cueSet = "soft"
    private var cache: [String: NSSound] = [:]

    func playStart() { play("start") }

    func playStop() { play("stop") }

    /// Plays the start cue, then the stop cue.
    func preview() {
        playStart()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.playStop()
        }
    }

    private func play(_ cue: String) {
        guard let sound = bundled("\(cue)-\(Self.cueSet)") else { return }
        sound.stop()
        sound.play()
    }

    private func bundled(_ name: String) -> NSSound? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return nil }
        cache[name] = sound
        return sound
    }
}
