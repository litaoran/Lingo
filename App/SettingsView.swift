import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Hosts the settings window. Managed with AppKit so any part of the app can
/// open it, including at first launch.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    enum Tab: String, Hashable {
        case general, models, permissions, about
    }

    final class Selection: ObservableObject {
        @Published var tab: Tab = .general
    }

    private var window: NSWindow?
    private let selection = Selection()

    func show(tab: Tab? = nil) {
        if let tab { selection.tab = tab }
        if window == nil {
            let view = SettingsView()
                .environmentObject(AppState.shared)
                .environmentObject(AppState.shared.models)
                .environmentObject(selection)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Lingo Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        // Show a Dock icon while settings are open so the window can be
        // reached with ⌘-Tab like any other app window.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var selection: SettingsWindowController.Selection

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsWindowController.Tab.general)
            ModelSettings()
                .tabItem { Label("Models", systemImage: "square.stack.3d.down.right") }
                .tag(SettingsWindowController.Tab.models)
            PermissionSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
                .tag(SettingsWindowController.Tab.permissions)
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsWindowController.Tab.about)
        }
        .frame(width: 580, height: 520)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            if state.needsSetup {
                Section("Get started") {
                    SetupChecklist()
                }
            }

            Section("Shortcuts") {
                LabeledContent("Hold to talk") {
                    KeyboardShortcuts.Recorder(for: .holdToTalk)
                }
                LabeledContent("Press to start, press again to stop") {
                    KeyboardShortcuts.Recorder(for: .toggleRecording)
                }
            }

            Section {
                Picker("Language", selection: $state.language) {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                LabeledContent("Model") {
                    Text(state.selectedModel.displayName)
                }
            } header: {
                Text("Transcription")
            } footer: {
                Text("Use 中文 for Chinese and mixed Chinese–English speech with Qwen3-ASR; English words stay in English. Auto-detect can turn Chinese parts of mixed speech into English. With Whisper, choose Auto-detect: forcing 中文 makes Whisper translate English into Chinese.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Restore the clipboard after pasting", isOn: $state.restoreClipboard)
                Toggle("Play sounds when recording starts and stops", isOn: $state.playSounds)
                Toggle("Show recording indicator", isOn: $state.showIndicator)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SetupChecklist: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var models: ModelManager
    @State private var micGranted = Permissions.isMicrophoneGranted
    @State private var axTrusted = Permissions.isAccessibilityTrusted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChecklistRow(done: models.isInstalled(state.selectedModel),
                         title: "Download \(state.selectedModel.displayName)",
                         detail: state.selectedModel.formattedSize) {
                if let progress = models.downloads[state.selectedModelID] {
                    ProgressView(value: progress).frame(width: 120)
                } else {
                    Button("Download") { state.downloadSelectedModel() }
                }
            }
            ChecklistRow(done: micGranted, title: "Allow microphone access",
                         detail: "To hear you while you hold the shortcut") {
                Button("Allow") {
                    Task {
                        if Permissions.microphoneStatus == .notDetermined {
                            micGranted = await Permissions.requestMicrophone()
                        } else {
                            Permissions.openMicrophoneSettings()
                        }
                    }
                }
            }
            ChecklistRow(done: axTrusted, title: "Allow Accessibility access",
                         detail: "To paste the text into the app you're typing in") {
                Button("Open Settings") {
                    Permissions.promptForAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }
        }
        .onReceive(timer) { _ in
            micGranted = Permissions.isMicrophoneGranted
            axTrusted = Permissions.isAccessibilityTrusted
        }
    }
}

private struct ChecklistRow<Action: View>: View {
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !done { action() }
        }
    }
}

// MARK: - Models

private struct ModelSettings: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var models: ModelManager

    var body: some View {
        Form {
            Section {
                ForEach(ModelCatalog.all) { model in
                    ModelRow(model: model)
                }
            } header: {
                Text("Speech models")
            } footer: {
                Text("Models run entirely on this Mac. Downloads come from huggingface.co.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Used by downloaded models") {
                    Text(ByteFormatter.string(models.totalInstalledBytes))
                }
                LabeledContent("Location") {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(
                            at: ModelFiles.rootDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([ModelFiles.rootDirectory])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { models.refresh() }
    }
}

private struct ModelRow: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var models: ModelManager
    let model: ASRModel

    private var isSelected: Bool { state.selectedModelID == model.id }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName).fontWeight(.medium)
                    if isSelected {
                        Text(selectedBadge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    }
                }
                Text("\(model.summary) · \(models.sizeText(model))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = models.errors[model.id] {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            actions
        }
        .padding(.vertical, 2)
    }

    private var selectedBadge: String {
        switch state.modelStatus {
        case .loading where isSelected: return "LOADING"
        case .ready: return "IN USE"
        default: return "SELECTED"
        }
    }

    @ViewBuilder private var actions: some View {
        if let progress = models.downloads[model.id] {
            ProgressView(value: progress).frame(width: 90)
            Text("\(Int(progress * 100))%").monospacedDigit().font(.caption).frame(width: 34)
            Button("Cancel") { models.cancelDownload(model) }
        } else if models.isInstalled(model) {
            if !isSelected {
                Button("Use") { state.selectModel(model.id) }
            }
            Button(role: .destructive) {
                state.delete(model)
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete this model")
        } else {
            Button("Download") {
                if isSelected { state.selectModel(model.id) } else { models.download(model) }
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionSettings: View {
    @State private var micStatus = Permissions.microphoneStatus
    @State private var axTrusted = Permissions.isAccessibilityTrusted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    granted: micStatus == .authorized,
                    title: "Microphone",
                    detail: "Records only while you hold or toggle the shortcut. Audio stays on this Mac and is discarded after transcription."
                ) {
                    Button(micStatus == .notDetermined ? "Allow" : "Open Settings") {
                        Task {
                            if micStatus == .notDetermined {
                                _ = await Permissions.requestMicrophone()
                                micStatus = Permissions.microphoneStatus
                            } else {
                                Permissions.openMicrophoneSettings()
                            }
                        }
                    }
                }
                PermissionRow(
                    granted: axTrusted,
                    title: "Accessibility",
                    detail: "Lets Lingo press ⌘V to paste the transcript into the current app. Without it, the text is copied to the clipboard and you paste it yourself."
                ) {
                    Button("Open Settings") {
                        Permissions.promptForAccessibility()
                        Permissions.openAccessibilitySettings()
                    }
                }
            } footer: {
                Text("After installing a new version of Lingo, macOS may keep an outdated Accessibility entry. If pasting stops working, remove Lingo from the list with − and add it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("Lingo transcribes on this Mac. It never uploads audio or text and collects no analytics. The only network requests it makes are model downloads from huggingface.co.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in
            micStatus = Permissions.microphoneStatus
            axTrusted = Permissions.isAccessibilityTrusted
        }
    }
}

private struct PermissionRow<Action: View>: View {
    let granted: Bool
    let title: String
    let detail: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Text("Allowed").foregroundStyle(.secondary)
            } else {
                action()
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - About

private struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Lingo").font(.title.bold())
            Text(version).foregroundStyle(.secondary)
            Text("Private, on-device dictation for mixed Chinese and English.")
                .multilineTextAlignment(.center)
            Text("Open source under the MIT License. Built with MLX, mlx-audio-swift and KeyboardShortcuts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("github.com/litaoran/Lingo", destination: URL(string: "https://github.com/litaoran/Lingo")!)
                .font(.callout)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
