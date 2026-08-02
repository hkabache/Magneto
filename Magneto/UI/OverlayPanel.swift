import AppKit
import SwiftUI

@MainActor
final class OverlayController {
    private weak var app: AppState?
    private var panel: NSPanel?
    private let size = NSSize(width: 240, height: 44)

    init(app: AppState) {
        self.app = app
    }

    func show() {
        guard AppSettings.shared.overlayPosition != .none else { return }
        guard let panel = ensurePanel() else { return }
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel? {
        if let panel {
            return panel
        }
        guard let app else { return nil }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: OverlayView(app: app, recorder: app.recorder))
        self.panel = panel
        return panel
    }

    /// The pill shows up on the screen currently containing the mouse cursor,
    /// horizontally centered, top or bottom according to settings.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let area = screen.visibleFrame
        let x = area.midX - size.width / 2
        let y: CGFloat
        switch AppSettings.shared.overlayPosition {
        case .top:
            y = area.maxY - size.height - 24
        case .bottom, .none:
            y = area.minY + 24
        }
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

struct OverlayView: View {
    @ObservedObject var app: AppState
    @ObservedObject var recorder: Recorder

    /// System-driven: when "Reduce transparency" is on, backgrounds must be opaque
    /// rather than a glass material.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var pillBackground: AnyShapeStyle {
        reduceTransparency
            ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
            : AnyShapeStyle(.regularMaterial)
    }

    var body: some View {
        HStack(spacing: 10) {
            if app.phase == .recording {
                LevelBars(level: recorder.level)
                Text("Enregistrement")
            } else {
                ProgressView()
                    .controlSize(.small)
                Text(app.busyLabel)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(pillBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LevelBars: View {
    let level: Float

    private static let factors: [CGFloat] = [0.35, 0.65, 1.0, 0.8, 1.0, 0.65, 0.35]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Self.factors.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.red)
                    .frame(width: 3, height: 4 + CGFloat(level) * 16 * Self.factors[index])
            }
        }
        .animation(.linear(duration: 0.08), value: level)
        .frame(height: 22)
    }
}
