import AppKit
import MLXAudioCore
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
