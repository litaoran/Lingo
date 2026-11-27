import AppKit
import MLXAudioCore
import CoreAudio
import SwiftUI

@main
struct LingoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
                .environmentObject(state.models)
        } label: {
            Image(systemName: state.menuBarSymbol)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--self-test") {
            SelfTest.run(arguments: Array(CommandLine.arguments[(index + 1)...]))
            return
        }
        MainActor.assumeIsolated {
            AppState.shared.start()
        }
    }
}

/// Developer check that runs the app bundle's transcription stack without UI:
///   Lingo.app/Contents/MacOS/Lingo --self-test <audio-file> [model-id ...]
/// Loads each model in turn (the same switch the menu performs), prints the
/// transcript, and exits.
enum SelfTest {
    static func run(arguments: [String]) {
        if arguments.first == "record" {
            recordTest(arguments: Array(arguments.dropFirst()))
            return
        }
        guard let path = arguments.first else {
            print("usage: Lingo --self-test <audio-file> [model-id ...]")
            exit(2)
        }
        let ids = arguments.count > 1 ? Array(arguments.dropFirst()) : [ModelCatalog.defaultModelID]
        Task.detached {
            let engine = TranscriptionEngine()
            var failed = false
            do {
                let (_, audio) = try loadAudioArray(
                    from: URL(fileURLWithPath: path), sampleRate: TranscriptionEngine.sampleRate)
                let samples = audio.asArray(Float.self)
                for id in ids {
                    guard let model = ModelCatalog.model(id: id) else {
                        print("unknown model \(id)")
                        failed = true
                        continue
                    }
                    let start = Date()
                    try await engine.load(model)
                    let loaded = Date()
                    let text = try await engine.transcribe(samples: samples, language: "zh")
                    print(String(format: "[%@] load %.1fs, transcribe %.2fs: %@", id,
                                 loaded.timeIntervalSince(start), Date().timeIntervalSince(loaded), text))
                }
            } catch {
                print("self-test failed: \(error.localizedDescription)")
                failed = true
            }
            exit(failed ? 1 : 0)
        }
    }

    /// Records the microphone for a few seconds, transcribes it with the default
    /// model and writes one JSON line to `out-file`. Used to check echo cancellation:
    ///   open -n -W Lingo.app --args --self-test record <seconds> <on|off> <out-file> [prewarm]
    /// (launch through `open` so macOS applies Lingo's own microphone permission).
    static func recordTest(arguments: [String]) {
        guard arguments.count >= 3, let seconds = Double(arguments[0]) else {
            print("usage: Lingo --self-test record <seconds> <on|off> <out-file> [prewarm]")
            exit(2)
        }
        let echoCancellation = arguments[1] == "on"
        let outURL = URL(fileURLWithPath: arguments[2])
        let prewarm = arguments.count > 3 && arguments[3] == "prewarm"
        Task.detached {
            var result: [String: Any] = ["echo_cancellation_requested": echoCancellation]
            do {
                let engine = TranscriptionEngine()
                try await engine.load(ModelCatalog.defaultModel)
                let recorder = AudioRecorder()
                if prewarm {
                    recorder.prewarm(echoCancellation: echoCancellation)
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    result["mic_running_while_prewarmed"] = AudioDeviceProbe.defaultInputIsRunning()
                }
                try recorder.start(echoCancellation: echoCancellation)
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                let samples = recorder.stop()
                let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1))).squareRoot()
                result["echo_cancellation_active"] = recorder.echoCancellationActive
                result["startup_ms"] = Int((recorder.startupLatency ?? -1) * 1000)
                result["voice_processing_setup_ms"] = Int(recorder.voiceProcessingSetup * 1000)
                result["engine_start_ms"] = Int(recorder.engineStartDuration * 1000)
                result["prewarmed"] = recorder.usedPrewarmedEngine
                result["seconds"] = Double(samples.count) / Double(TranscriptionEngine.sampleRate)
                result["rms"] = rms
                result["text"] = try await engine.transcribe(samples: samples, language: "zh")
            } catch {
                result["error"] = error.localizedDescription
            }
            var data = (try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])) ?? Data()
            data.append(0x0A)
            if let handle = try? FileHandle(forWritingTo: outURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: outURL)
            }
            exit(result["error"] == nil ? 0 : 1)
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var models: ModelManager

    var body: some View {
        Text(state.statusLine)

        Button(state.phase == .recording ? "Stop and Transcribe" : "Start Recording") {
            state.toggleFromMenu()
        }
        .disabled(state.phase == .transcribing || (state.phase == .idle && state.modelStatus != .ready))

        if state.phase == .recording {
            Button("Cancel Recording") { state.cancelRecording() }
        }

        Divider()

        Menu("Model: \(state.selectedModel.displayName)") {
            modelMenu
        }

        Picker("Language", selection: $state.language) {
            ForEach(TranscriptionLanguage.allCases) { language in
                Text(language.displayName).tag(language)
            }
        }

        Divider()

        if state.lastTranscript != nil {
            Button("Copy Last Transcript") { state.copyLastTranscript() }
        }
        Button("Settings…") { SettingsWindowController.shared.show() }
            .keyboardShortcut(",")

        Divider()

        Button("Quit Lingo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder private var modelMenu: some View {
        let installed = ModelCatalog.all.filter { models.isInstalled($0) }
        let available = ModelCatalog.all.filter { !models.isInstalled($0) }

        if installed.isEmpty {
            Text("No models downloaded")
        } else {
            Picker("Use", selection: Binding(
                get: { state.selectedModelID },
                set: { state.selectModel($0) }
            )) {
                ForEach(installed) { model in
                    Text("\(model.displayName) — \(models.sizeText(model))").tag(model.id)
                }
            }
            .pickerStyle(.inline)
        }

        if !available.isEmpty {
            Divider()
            Menu("Download") {
                ForEach(available) { model in
                    if let progress = models.downloads[model.id] {
                        Button("Cancel \(model.displayName) (\(Int(progress * 100))%)") {
                            models.cancelDownload(model)
                        }
                    } else {
                        Button("\(model.displayName) — \(model.formattedSize)") {
                            state.selectModel(model.id)
                        }
                    }
                }
            }
        }

        if !installed.isEmpty {
            Menu("Delete") {
                ForEach(installed) { model in
                    Button("\(model.displayName) — \(models.sizeText(model))") {
                        state.delete(model)
                    }
                }
            }
        }

        Divider()
        Button("Manage Models…") { SettingsWindowController.shared.show(tab: .models) }
    }
}

/// Self-test helper: whether any process is capturing from the default input device
/// (the condition that turns on the orange microphone indicator).
enum AudioDeviceProbe {
    static func defaultInputIsRunning() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        return running != 0
    }
}
