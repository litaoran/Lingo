import Foundation
import MLX
import MLXAudioCore
import MLXAudioSTT

/// Owns the loaded speech model and runs transcription off the main thread.
///
/// MLX models are not thread-safe, so every call goes through this actor and
/// only one transcription runs at a time.
actor TranscriptionEngine {
    static let sampleRate = 16_000

    private var model: (any STTGenerationModel)?
    private(set) var loadedModelID: String?

    init() {
        // Keep MLX from holding on to large buffers between dictations.
        MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)
    }

    /// Loads an installed model, replacing whatever was loaded before.
    func load(_ descriptor: ASRModel) async throws {
        if loadedModelID == descriptor.id, model != nil { return }
        guard ModelFiles.isInstalled(descriptor) else {
            throw LingoError.modelNotInstalled(descriptor.displayName)
        }
        unload()

        let dir = ModelFiles.directory(for: descriptor)
        let loaded: any STTGenerationModel
        switch descriptor.family {
        case .qwen3ASR:
            loaded = try await Qwen3ASRModel.fromModelDirectory(dir)
        case .whisper:
            loaded = try await WhisperModel.fromDirectory(dir, cache: ModelFiles.cache)
        }
        model = loaded
        loadedModelID = descriptor.id

        // Run once on silence so the first real dictation doesn't pay for
        // Metal kernel compilation.
        _ = run(samples: [Float](repeating: 0, count: Self.sampleRate / 2), language: "en")
    }

    func unload() {
        model = nil
        loadedModelID = nil
        MLX.GPU.clearCache()
    }

    /// Transcribes 16 kHz mono samples. `language` is an ISO code such as
    /// "zh" or "en", or nil to let the model detect it.
    func transcribe(samples: [Float], language: String?) throws -> String {
        guard model != nil else { throw LingoError.noModelLoaded }
        return run(samples: samples, language: language)
    }

    private func run(samples: [Float], language: String?) -> String {
        guard let model else { return "" }
        let audio = MLXArray(samples)
        let parameters = STTGenerateParameters(
            maxTokens: 2048,
            temperature: 0.0,
            topP: 0.95,
            topK: 0,
            verbose: false,
            language: language
        )
        let output = model.generate(audio: audio, generationParameters: parameters)
        MLX.GPU.clearCache()
        return TextCleanup.clean(output.text)
    }
}

enum TextCleanup {
    /// Trims whitespace and drops artifacts models emit on silence.
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Qwen3-ASR prefixes "language X<asr_text>" when it detects the language itself.
        if let range = text.range(of: "<asr_text>") {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Near-silent recordings often come back as a lone filler such as "嗯。".
        // Pasting that is never useful, so treat it as no speech.
        if isOnlyFiller(text) { return "" }
        return text
    }

    private static let fillers: Set<String> = [
        "嗯", "嗯嗯", "呃", "啊", "哦", "噢", "唔", "呣", "额",
        "hmm", "hm", "mm", "mhm", "um", "uh", "er", "ah", "oh",
    ]

    static func isOnlyFiller(_ text: String) -> Bool {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters
                .union(.whitespacesAndNewlines).union(.symbols))
            .filter { !$0.isEmpty }
        return !words.isEmpty && words.allSatisfy { fillers.contains($0) }
    }
}
