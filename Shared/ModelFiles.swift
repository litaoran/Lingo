import Foundation
import HuggingFace
import MLXAudioCore

/// Where models live on disk, and how they are downloaded, measured and deleted.
///
/// Models are stored under `~/Library/Application Support/Lingo/Models`. The only
/// network traffic Lingo ever makes is downloading model files from huggingface.co.
enum ModelFiles {
    static let completionMarker = ".lingo-complete"

    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Lingo/Models", isDirectory: true)
    }

    static var cache: HubCache {
        HubCache(cacheDirectory: rootDirectory)
    }

    /// Directory that holds the model's weights, tokenizer and config.
    static func directory(for model: ASRModel) -> URL {
        rootDirectory
            .appendingPathComponent("mlx-audio", isDirectory: true)
            .appendingPathComponent(model.repo.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
    }

    /// Directories the Hugging Face client may leave behind for this model.
    private static func auxiliaryDirectories(for model: ASRModel) -> [URL] {
        var dirs: [URL] = []
        if let repo = Repo.ID(rawValue: model.repo) {
            dirs.append(cache.repoDirectory(repo: repo, kind: .model))
        }
        return dirs
    }

    static func isInstalled(_ model: ASRModel) -> Bool {
        FileManager.default.fileExists(
            atPath: directory(for: model).appendingPathComponent(completionMarker).path)
    }

    /// Bytes the model occupies on disk, or nil if it is not installed.
    static func installedBytes(_ model: ASRModel) -> Int64? {
        guard isInstalled(model) else { return nil }
        return directorySize(directory(for: model))
    }

    /// Downloads the model if needed and returns its directory.
    /// `progress` receives a fraction between 0 and 1 on the main actor.
    @discardableResult
    static func download(
        _ model: ASRModel,
        progress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let dir = directory(for: model)
        if isInstalled(model) { return dir }

        guard let repoID = Repo.ID(rawValue: model.repo) else {
            throw LingoError.invalidRepository(model.repo)
        }

        // A directory without the marker is a partial download; start over.
        removeFiles(for: model)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let client = HubClient(cache: cache)
        let resolved = try await ModelUtils.resolveOrDownloadModel(
            client: client,
            cache: cache,
            repoID: repoID,
            requiredExtension: "safetensors",
            additionalMatchingPatterns: model.downloadPatterns,
            progressHandler: { p in
                progress?(p.fractionCompleted)
            }
        )
        try Task.checkCancellation()

        // The Hugging Face client also keeps a copy in its own cache layout.
        // Lingo loads from `resolved`, so drop the duplicate.
        for aux in auxiliaryDirectories(for: model) {
            try? FileManager.default.removeItem(at: aux)
        }

        try Data().write(to: resolved.appendingPathComponent(completionMarker))
        return resolved
    }

    /// Deletes the model's files. Safe to call when nothing is installed.
    static func removeFiles(for model: ASRModel) {
        let fm = FileManager.default
        try? fm.removeItem(at: directory(for: model))
        for aux in auxiliaryDirectories(for: model) {
            try? fm.removeItem(at: aux)
        }
    }

    static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: keys, options: [], errorHandler: nil)
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}

enum LingoError: LocalizedError {
    case invalidRepository(String)
    case modelNotInstalled(String)
    case noModelLoaded
    case microphoneUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepository(let repo): return "Invalid model repository: \(repo)"
        case .modelNotInstalled(let name): return "\(name) is not downloaded yet."
        case .noModelLoaded: return "No speech model is loaded."
        case .microphoneUnavailable(let reason): return "Microphone unavailable: \(reason)"
        }
    }
}
