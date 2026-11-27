import AppKit
import Combine
import KeyboardShortcuts
import OSLog
import SwiftUI

/// Logs state changes and timings, never transcript text or audio.
let log = Logger(subsystem: "io.github.litaoran.Lingo", category: "app")

extension KeyboardShortcuts.Name {
    /// Hold to record, release to transcribe and paste.
    static let holdToTalk = Self("holdToTalk", initial: .init(.space, modifiers: [.option]))
    /// Press once to start recording, press again to transcribe and paste.
    static let toggleRecording = Self("toggleRecording", initial: .init(.space, modifiers: [.option, .shift]))
}

/// Central state: model loading, the record → transcribe → paste pipeline,
/// and user settings.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
    }

    enum ModelStatus: Equatable {
        case notInstalled
        case downloading
        case loading
        case ready
        case failed(String)
    }

    private enum RecordingMode {
        case hold
        case toggle
    }

    // MARK: Published state

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var modelStatus: ModelStatus = .notInstalled
    @Published private(set) var lastTranscript: String?
    @Published private(set) var lastError: String?
    @Published private(set) var audioLevel: Float = 0

    // MARK: Settings

    @Published var selectedModelID: String {
        didSet { defaults.set(selectedModelID, forKey: Keys.model) }
    }
    @Published var language: TranscriptionLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }
    @Published var restoreClipboard: Bool {
        didSet { defaults.set(restoreClipboard, forKey: Keys.restoreClipboard) }
    }
    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.playSounds) }
    }
    @Published var showIndicator: Bool {
        didSet { defaults.set(showIndicator, forKey: Keys.showIndicator) }
    }

    let models = ModelManager()

    private let engine = TranscriptionEngine()
    private let recorder = AudioRecorder()
    private let hud = HUDController()
    private let defaults = UserDefaults.standard
    private var mode: RecordingMode = .hold
    private var recordingStartedAt: Date?
    private var maxDurationTimer: Timer?
    private var loadTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    /// Recordings shorter than this are treated as accidental taps.
    private let minimumDuration: TimeInterval = 0.3
    /// Safety limit so a forgotten toggle recording doesn't run forever.
    private let maximumDuration: TimeInterval = 10 * 60

    private enum Keys {
        static let model = "selectedModelID"
        static let language = "language"
        static let restoreClipboard = "restoreClipboard"
        static let playSounds = "playSounds"
        static let showIndicator = "showIndicator"
    }

    private init() {
        defaults.register(defaults: [
            Keys.model: ModelCatalog.defaultModelID,
            Keys.language: TranscriptionLanguage.chinese.rawValue,
            Keys.restoreClipboard: true,
            Keys.playSounds: true,
            Keys.showIndicator: true,
        ])
        let storedModel = defaults.string(forKey: Keys.model) ?? ModelCatalog.defaultModelID
        selectedModelID = ModelCatalog.model(id: storedModel) != nil ? storedModel : ModelCatalog.defaultModelID
        language = TranscriptionLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .chinese
        restoreClipboard = defaults.bool(forKey: Keys.restoreClipboard)
        playSounds = defaults.bool(forKey: Keys.playSounds)
        showIndicator = defaults.bool(forKey: Keys.showIndicator)

        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.audioLevel = level }
        }
        // Re-publish model changes so views observing AppState refresh too.
        models.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    func start() {
        KeyboardShortcuts.onKeyDown(for: .holdToTalk) { [weak self] in self?.holdKeyDown() }
        KeyboardShortcuts.onKeyUp(for: .holdToTalk) { [weak self] in self?.holdKeyUp() }
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [weak self] in self?.toggleKeyPressed() }

        if models.isInstalled(selectedModel) {
            loadSelectedModel()
        } else {
            modelStatus = .notInstalled
        }
        if needsSetup {
            SettingsWindowController.shared.show(tab: .general)
        }
    }

    var selectedModel: ASRModel {
        ModelCatalog.model(id: selectedModelID) ?? ModelCatalog.defaultModel
    }

    var needsSetup: Bool {
        !models.isInstalled(selectedModel) || !Permissions.isMicrophoneGranted
            || !Permissions.isAccessibilityTrusted
    }

    // MARK: Models

    /// Switches to `id`, downloading it first if needed.
    func selectModel(_ id: String) {
        guard let model = ModelCatalog.model(id: id) else { return }
        selectedModelID = id
        if models.isInstalled(model) {
            loadSelectedModel()
        } else {
            modelStatus = .downloading
            models.download(model) { [weak self] ok in
                guard let self, self.selectedModelID == id else { return }
                if ok {
                    self.loadSelectedModel()
                } else {
                    self.modelStatus = self.models.errors[id].map { .failed($0) } ?? .notInstalled
                }
            }
        }
    }

    func downloadSelectedModel() {
        selectModel(selectedModelID)
    }

    func delete(_ model: ASRModel) {
        guard models.confirmAndDelete(model) else { return }
        log.info("Deleted model \(model.id, privacy: .public)")
        if model.id == selectedModelID {
            loadTask?.cancel()
            Task { await engine.unload() }
            modelStatus = .notInstalled
        }
    }

    private func loadSelectedModel() {
        let model = selectedModel
        loadTask?.cancel()
        modelStatus = .loading
        log.info("Loading model \(model.id, privacy: .public)")
        loadTask = Task { [weak self] in
            guard let self else { return }
            let start = Date()
            do {
                try await self.engine.load(model)
                guard !Task.isCancelled, self.selectedModelID == model.id else { return }
                self.modelStatus = .ready
                log.info("Model \(model.id, privacy: .public) ready in \(Date().timeIntervalSince(start), format: .fixed(precision: 1))s")
            } catch {
                log.error("Model \(model.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                guard self.selectedModelID == model.id else { return }
                self.modelStatus = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Hotkeys

    private func holdKeyDown() {
        guard phase == .idle else { return }
        mode = .hold
        startRecording()
    }

    private func holdKeyUp() {
        guard phase == .recording, mode == .hold else { return }
        stopRecordingAndTranscribe()
    }

    private func toggleKeyPressed() {
        switch phase {
        case .idle:
            mode = .toggle
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing:
            break
        }
    }

    /// Menu bar "Start/Stop Recording" item.
    func toggleFromMenu() {
        toggleKeyPressed()
    }

    // MARK: Pipeline

    private func startRecording() {
        lastError = nil

        switch modelStatus {
        case .ready:
            break
        case .loading:
            flash("Model is still loading…")
            return
        case .downloading:
            flash("Model is still downloading…")
            return
        case .notInstalled, .failed:
            flash("Download a model first")
            SettingsWindowController.shared.show(tab: .models)
            return
        }

        switch Permissions.microphoneStatus {
        case .authorized:
            break
        case .notDetermined:
            Task {
                if await Permissions.requestMicrophone() {
                    self.flash("Microphone ready. Press the shortcut again.")
                }
            }
            return
        default:
            flash("Lingo needs microphone access")
            SettingsWindowController.shared.show(tab: .permissions)
            return
        }

        do {
            try recorder.start()
        } catch {
            fail(error.localizedDescription)
            return
        }
        phase = .recording
        recordingStartedAt = Date()
        log.info("Recording started (\(self.mode == .hold ? "hold" : "toggle", privacy: .public))")
        if playSounds { NSSound(named: "Tink")?.play() }
        if showIndicator { hud.show(.recording, state: self) }

        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maximumDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.stopRecordingAndTranscribe()
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        let samples = recorder.stop()
        audioLevel = 0
        let duration = Double(samples.count) / Double(TranscriptionEngine.sampleRate)

        guard duration >= minimumDuration, samples.contains(where: { abs($0) > 0.0005 }) else {
            phase = .idle
            hud.hide()
            return
        }

        phase = .transcribing
        if playSounds { NSSound(named: "Pop")?.play() }
        if showIndicator { hud.show(.transcribing, state: self) }

        let languageCode = language.modelCode
        log.info("Transcribing \(duration, format: .fixed(precision: 1))s of audio")
        Task {
            let start = Date()
            do {
                let text = try await engine.transcribe(samples: samples, language: languageCode)
                log.info("Transcribed in \(Date().timeIntervalSince(start), format: .fixed(precision: 2))s, \(text.count) characters")
                self.finish(with: text)
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }

    private func finish(with text: String) {
        phase = .idle
        hud.hide()
        guard !text.isEmpty else { return }
        lastTranscript = text
        switch Paster.paste(text, restoreClipboard: restoreClipboard) {
        case .pasted:
            log.info("Pasted into frontmost app")
        case .copiedOnly:
            log.notice("Accessibility not granted; copied to clipboard only")
            flash("Copied. Allow Accessibility to paste automatically.")
        }
    }

    private func fail(_ message: String) {
        log.error("\(message, privacy: .public)")
        phase = .idle
        lastError = message
        flash(message, isError: true)
    }

    private func flash(_ message: String, isError: Bool = false) {
        hud.show(.message(message, isError: isError), state: self)
        hud.hide(after: 2.5)
        if isError { NSSound.beep() }
    }

    func copyLastTranscript() {
        guard let lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }

    // MARK: Display

    var menuBarSymbol: String {
        switch phase {
        case .recording: return "mic.fill"
        case .transcribing: return "ellipsis.bubble"
        case .idle:
            switch modelStatus {
            case .ready: return "mic"
            case .failed: return "mic.slash"
            default: return "arrow.down.circle"
            }
        }
    }

    var statusLine: String {
        switch phase {
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .idle: break
        }
        switch modelStatus {
        case .ready:
            if let shortcut = KeyboardShortcuts.getShortcut(for: .holdToTalk) {
                return "Ready — hold \(shortcut) to dictate"
            }
            return "Ready"
        case .loading:
            return "Loading \(selectedModel.displayName)…"
        case .downloading:
            let percent = Int((models.downloads[selectedModelID] ?? 0) * 100)
            return "Downloading \(selectedModel.displayName)… \(percent)%"
        case .notInstalled:
            return "No model downloaded"
        case .failed(let message):
            return "Model error: \(message)"
        }
    }
}
