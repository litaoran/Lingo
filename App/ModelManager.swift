import AppKit
import Foundation

/// Tracks which models are on disk and runs downloads with progress.
@MainActor
final class ModelManager: ObservableObject {
    /// Installed model id → bytes on disk.
    @Published private(set) var installed: [String: Int64] = [:]
    /// Model id → download progress (0...1) for downloads in flight.
    @Published private(set) var downloads: [String: Double] = [:]
    /// Model id → last download error.
    @Published private(set) var errors: [String: String] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]
    private var completions: [String: [(Bool) -> Void]] = [:]

    init() {
        refresh()
    }

    func refresh() {
        var result: [String: Int64] = [:]
        for model in ModelCatalog.all {
            if let bytes = ModelFiles.installedBytes(model) { result[model.id] = bytes }
        }
        installed = result
    }

    func isInstalled(_ model: ASRModel) -> Bool { installed[model.id] != nil }

    func isDownloading(_ model: ASRModel) -> Bool { downloads[model.id] != nil }

    var totalInstalledBytes: Int64 { installed.values.reduce(0, +) }

    /// Size to show: bytes on disk if installed, download size otherwise.
    func sizeText(_ model: ASRModel) -> String {
        ByteFormatter.string(installed[model.id] ?? model.downloadBytes)
    }

    /// Starts downloading `model`. `completion` runs on the main actor with
    /// true when the model is ready on disk.
    func download(_ model: ASRModel, completion: ((Bool) -> Void)? = nil) {
        if isInstalled(model) {
            completion?(true)
            return
        }
        if let completion { completions[model.id, default: []].append(completion) }
        guard tasks[model.id] == nil else { return }

        errors[model.id] = nil
        downloads[model.id] = 0
        tasks[model.id] = Task { [weak self] in
            var succeeded = false
            do {
                try await ModelFiles.download(model) { fraction in
                    self?.downloads[model.id] = fraction
                }
                succeeded = true
            } catch is CancellationError {
                ModelFiles.removeFiles(for: model)
            } catch {
                if Task.isCancelled {
                    ModelFiles.removeFiles(for: model)
                } else {
                    self?.errors[model.id] = error.localizedDescription
                }
            }
            guard let self else { return }
            self.tasks[model.id] = nil
            self.downloads[model.id] = nil
            self.refresh()
            let waiting = self.completions.removeValue(forKey: model.id) ?? []
            waiting.forEach { $0(succeeded) }
        }
    }

    func cancelDownload(_ model: ASRModel) {
        tasks[model.id]?.cancel()
    }

    /// Deletes a model after asking the user. Returns true if it was deleted.
    @discardableResult
    func confirmAndDelete(_ model: ASRModel) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete \(model.displayName)?"
        alert.informativeText = "This frees \(sizeText(model)). You can download it again later."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        ModelFiles.removeFiles(for: model)
        refresh()
        return true
    }
}
