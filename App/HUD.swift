import AppKit
import SwiftUI

/// A small floating pill near the bottom of the screen that shows recording
/// and transcription state. It never takes focus, so the target app keeps
/// its cursor.
@MainActor
final class HUDController {
    enum Content: Equatable {
        case recording(locked: Bool)
        case transcribing
        case message(String, isError: Bool)
    }

    private var panel: NSPanel?
    private let model = HUDModel()
    private var hideWorkItem: DispatchWorkItem?

    func show(_ content: Content, state: AppState) {
        hideWorkItem?.cancel()
        model.content = content
        let panel = panel ?? makePanel(state: state)
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide(after delay: TimeInterval = 0) {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func makePanel(state: AppState) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 56),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: HUDView(model: model).environmentObject(state))
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = host
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 72))
    }
}

@MainActor
final class HUDModel: ObservableObject {
    @Published var content: HUDController.Content = .recording(locked: false)
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            switch model.content {
            case .recording(let locked):
                Circle().fill(.red).frame(width: 9, height: 9)
                LevelMeter(level: state.audioLevel)
                if locked {
                    Text("Listening · \(state.dictateShortcutText) to finish, esc to cancel")
                } else {
                    Text("Listening")
                }
            case .transcribing:
                ProgressView().controlSize(.small)
                Text("Transcribing")
            case .message(let text, let isError):
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(isError ? .yellow : .white)
                Text(text).lineLimit(2)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LevelMeter: View {
    let level: Float
    private let bars = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(index < litBars ? 0.95 : 0.3))
                    .frame(width: 3, height: CGFloat(6 + index * 3))
            }
        }
        .animation(.easeOut(duration: 0.08), value: litBars)
    }

    /// Maps RMS (roughly 0.001 quiet … 0.3 loud) onto a log scale.
    private var litBars: Int {
        let db = 20 * log10(max(level, 0.0001))
        let normalized = (db + 55) / 45
        return Int((max(0, min(1, normalized)) * Float(bars)).rounded(.up))
    }
}
