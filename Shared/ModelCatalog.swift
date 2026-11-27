import Foundation

/// The model architectures Lingo knows how to load.
enum ModelFamily: String, Codable, Sendable {
    case qwen3ASR
    case whisper
}

/// A speech recognition model that Lingo can download and run on device.
struct ASRModel: Identifiable, Hashable, Sendable {
    /// Stable identifier stored in user defaults. Never change an existing one.
    let id: String
    let displayName: String
    /// Hugging Face repository the weights are downloaded from.
    let repo: String
    let family: ModelFamily
    /// Total size of the files Lingo downloads, in bytes (from the Hugging Face file listing).
    let downloadBytes: Int64
    /// One-line description shown in the model list.
    let summary: String

    var formattedSize: String { ByteFormatter.string(downloadBytes) }

    /// File patterns fetched from the repository.
    var downloadPatterns: [String] {
        switch family {
        case .qwen3ASR: return []
        case .whisper: return ["*.json", "*.txt", "*.model", "merges.txt", "vocab.json"]
        }
    }
}

enum ModelCatalog {
    static let all: [ASRModel] = [
        ASRModel(
            id: "qwen3-asr-1.7b-8bit",
            displayName: "Qwen3-ASR 1.7B (8-bit)",
            repo: "mlx-community/Qwen3-ASR-1.7B-8bit",
            family: .qwen3ASR,
            downloadBytes: 2_467_856_503,
            summary: "Default. Best for mixed Chinese and English."
        ),
        ASRModel(
            id: "qwen3-asr-1.7b-bf16",
            displayName: "Qwen3-ASR 1.7B (bf16)",
            repo: "mlx-community/Qwen3-ASR-1.7B-bf16",
            family: .qwen3ASR,
            downloadBytes: 4_080_707_826,
            summary: "Full precision. Largest download and memory use."
        ),
        ASRModel(
            id: "qwen3-asr-1.7b-4bit",
            displayName: "Qwen3-ASR 1.7B (4-bit)",
            repo: "mlx-community/Qwen3-ASR-1.7B-4bit",
            family: .qwen3ASR,
            downloadBytes: 1_607_630_579,
            summary: "Smaller and faster, slightly less accurate."
        ),
        ASRModel(
            id: "qwen3-asr-0.6b-8bit",
            displayName: "Qwen3-ASR 0.6B (8-bit)",
            repo: "mlx-community/Qwen3-ASR-0.6B-8bit",
            family: .qwen3ASR,
            downloadBytes: 1_010_771_234,
            summary: "Smallest and fastest Qwen3-ASR."
        ),
        ASRModel(
            id: "whisper-large-v3-turbo",
            displayName: "Whisper large-v3-turbo",
            repo: "openai/whisper-large-v3-turbo",
            family: .whisper,
            downloadBytes: 1_622_443_339,
            summary: "OpenAI Whisper. Strong for English and many other languages."
        ),
    ]

    static let defaultModelID = "qwen3-asr-1.7b-8bit"

    static var defaultModel: ASRModel { model(id: defaultModelID)! }

    static func model(id: String) -> ASRModel? {
        all.first { $0.id == id }
    }
}

/// Language hint passed to the model.
enum TranscriptionLanguage: String, CaseIterable, Identifiable, Sendable {
    /// Chinese, including mixed Chinese and English speech. English stays English.
    case chinese = "zh"
    case english = "en"
    /// Let the model detect the language. Qwen3-ASR may translate the Chinese
    /// parts of mixed speech into English in this mode.
    case auto = "auto"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: return "中文 (Chinese, keeps English)"
        case .english: return "English"
        case .auto: return "Auto-detect"
        }
    }

    /// Value passed to the model; nil lets the model detect the language.
    var modelCode: String? {
        self == .auto ? nil : rawValue
    }
}

enum ByteFormatter {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }
}
