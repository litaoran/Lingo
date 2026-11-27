import AppKit

/// The cue sounds played when recording starts and stops.
enum SoundStyle: String, CaseIterable, Identifiable {
    case soft
    case bubble
    case chime
    case system
    case off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .soft: return "Soft"
        case .bubble: return "Bubble"
        case .chime: return "Chime"
        case .system: return "Classic (system)"
        case .off: return "Off"
        }
    }
}

/// Plays Lingo's start and stop cues. Sounds are loaded once and reused.
@MainActor
final class SoundPlayer {
    private var cache: [String: NSSound] = [:]

    func playStart(_ style: SoundStyle) {
        play(style, cue: "start", systemName: "Tink")
    }

    func playStop(_ style: SoundStyle) {
        play(style, cue: "stop", systemName: "Pop")
    }

    /// Plays the start cue, then the stop cue, so a style can be auditioned.
    func preview(_ style: SoundStyle) {
        playStart(style)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.playStop(style)
        }
    }

    private func play(_ style: SoundStyle, cue: String, systemName: String) {
        let sound: NSSound?
        switch style {
        case .off:
            return
        case .system:
            sound = NSSound(named: systemName)
        default:
            sound = bundled("\(cue)-\(style.rawValue)")
        }
        guard let sound else { return }
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
