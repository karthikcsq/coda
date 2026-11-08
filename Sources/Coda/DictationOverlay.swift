import AppKit
import SwiftUI
import CodaCore

private final class FloatingDictationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor final class DictationOverlay: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private var positions: [String: CGRect] = [:]
    private var displayID: String?
    private var updating = false
    override init() { fatalError("Use init(controller:)") }
    init(controller: DictationController) {
        panel = FloatingDictationPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.delegate = self
        panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: DictationHUD(controller: controller))
        NotificationCenter.default.addObserver(self, selector: #selector(displaysChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    private func id(_ screen: NSScreen) -> String { String(describing: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "main") }
    func show(preferredFrame: CGRect?) {
        // Once visible, never follow the pointer or steal focus. A new session uses its target display.
        if !panel.isVisible {
            let screen = NSScreen.screens.first(where: { $0.visibleFrame == preferredFrame })
                ?? NSScreen.screens.first(where: { id($0) == displayID }) ?? NSScreen.main
            if let screen { place(on: screen) }
        }
        panel.orderFrontRegardless()
    }
    private func place(on screen: NSScreen) {
        let key = id(screen)
        updating = true; displayID = key
        panel.setFrame(DictationPlacement.frame(current: positions[key], visible: screen.visibleFrame, size: CGSize(width: 320, height: 64)), display: true)
        positions[key] = panel.frame; updating = false
    }
    func windowDidMove(_ notification: Notification) {
        guard !updating, let screen = panel.screen else { return }
        displayID = id(screen); positions[id(screen)] = panel.frame
    }
    @objc private func displaysChanged() {
        guard let screen = NSScreen.screens.first(where: { id($0) == displayID }) ?? NSScreen.main else { return }
        place(on: screen)
    }
    var isVisible: Bool { panel.isVisible }
    func hide() { panel.orderOut(nil) }
}
struct DictationHUD: View {
    @Bindable var controller: DictationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var listening: Bool { controller.lifecycle.phase == .listening }
    var statusTitle: String {
        switch controller.lifecycle.phase {
        case .arming: "Starting microphone"
        case .listening: "Listening"
        case .processing: "Transcribing"
        case .cancelling: "Cancelling"
        case .failed: controller.failureTitle
        default: controller.pendingInsertion != nil ? "Choose a text field"
            : !controller.text.isEmpty ? "Text saved"
            : controller.message.hasPrefix("Ready") ? "Ready to dictate" : "Dictation"
        }
    }
    var statusDetail: String {
        if listening { return controller.practiceSession ? "Practice in Coda" : controller.targetName + " / " + controller.activeStyleLabel }
        return controller.message.hasPrefix("Ready") ? controller.shortcutLabel : controller.message
    }
    /// Only failures and pending insertions earn a second line; everything else is one word.
    private var showsDetail: Bool { controller.lifecycle.phase == .failed || controller.pendingInsertion != nil }
    private var failed: Bool { controller.lifecycle.phase == .failed }
    var body: some View {
        HStack(spacing: 10) {
            indicator.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if showsDetail {
                    Text(statusDetail).font(.system(size: 10.5)).foregroundStyle(CodaStyle.muted).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).help(controller.message)
            if !controller.lifecycle.busy && !controller.text.isEmpty {
                Button { controller.copyResult() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(CodaIconButtonStyle(size: 26)).help("Copy saved text").accessibilityLabel("Copy saved text")
            }
            if listening || (!controller.lifecycle.busy && controller.pendingInsertion != nil) {
                Button { controller.button() } label: {
                    Image(systemName: listening ? "stop.fill" : "arrow.up.doc")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Color(white: 0.07))
                        .frame(width: 26, height: 26).background(Color(white: 0.95), in: Circle())
                }
                .buttonStyle(.plain)
                .help(listening ? "Stop dictation" : "Insert text here")
                .accessibilityLabel(listening ? "Stop dictation" : "Insert text here")
            } else if !controller.lifecycle.busy && controller.text.isEmpty {
                Button { controller.button() } label: {
                    Image(systemName: "mic.fill").font(.system(size: 11))
                        .frame(width: 26, height: 26).background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain).help("Start dictation").accessibilityLabel("Start dictation")
            }
            Button { controller.dismissOverlay() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(CodaIconButtonStyle(size: 26))
                .help(controller.lifecycle.busy ? "Cancel dictation" : "Dismiss; text stays in History")
                .accessibilityLabel(controller.lifecycle.busy ? "Cancel dictation" : "Dismiss dictation; text stays in History")
        }
        .padding(.leading, 10).padding(.trailing, 8).frame(width: 280, height: showsDetail ? 54 : 46)
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1)))
        .frame(width: 320, height: 64)
        .preferredColorScheme(.dark).environment(\.colorScheme, .dark).foregroundStyle(CodaStyle.ink)
        .accessibilityElement(children: .contain).accessibilityLabel("Coda dictation")
    }
    @ViewBuilder private var indicator: some View {
        if listening {
            // Reduce Motion keeps the level meter readable without the continuous animation.
            HStack(spacing: 2.5) { ForEach(0..<5) { index in
                Capsule().fill(CodaStyle.recording)
                    .frame(width: 2.5, height: 4 + controller.level * [8, 16, 20, 14, 9][index])
            } }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: controller.level)
            .accessibilityHidden(true)
        } else if controller.lifecycle.busy {
            ProgressView().controlSize(.small)
        } else if failed {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)).foregroundStyle(CodaStyle.caution)
        } else if !controller.text.isEmpty {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(white: 0.07))
                .frame(width: 22, height: 22).background(CodaStyle.mint, in: Circle())
        } else {
            Image(systemName: "waveform").font(.system(size: 14)).foregroundStyle(CodaStyle.muted)
        }
    }
}
