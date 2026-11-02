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
    private var listening: Bool { controller.lifecycle.phase == .listening }
    var body: some View {
        HStack(spacing: 12) {
            if listening {
                HStack(spacing: 3) { ForEach(0..<7) { index in
                    Capsule().fill(Color.white.opacity(0.88)).frame(width: 3, height: 5 + controller.level * (index.isMultiple(of: 3) ? 22 : 14))
                } }.frame(width: 39, height: 28).animation(.easeOut(duration: 0.1), value: controller.level)
            } else if controller.lifecycle.busy {
                ProgressView().controlSize(.small).frame(width: 28)
            } else { Image(systemName: "waveform").font(.system(size: 19, weight: .light)).frame(width: 28) }
            VStack(alignment: .leading, spacing: 3) {
                Text(listening ? "Listening" : controller.lifecycle.busy ? "Transcribing" : controller.pendingInsertion != nil ? "Choose a text field" : controller.text.isEmpty ? "Ready to dictate" : "Text saved")
                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(listening ? "Esc to cancel" : controller.lifecycle.busy ? "On your Mac" : controller.text.isEmpty ? controller.shortcutLabel : controller.message)
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).help(controller.message)
            if !controller.lifecycle.busy && !controller.text.isEmpty {
                Button { controller.copyResult() } label: { Image(systemName: "doc.on.doc").font(.system(size: 13)) }.buttonStyle(.plain).help("Copy saved text")
            }
            if !controller.lifecycle.busy || listening {
                Button { controller.button() } label: {
                    Image(systemName: listening ? "stop.fill" : controller.pendingInsertion != nil ? "arrow.up.doc" : "mic.fill").font(.system(size: 12)).frame(width: 30, height: 30).background(Color.white.opacity(0.12), in: Circle())
                }.buttonStyle(.plain).help(listening ? "Stop dictation" : controller.pendingInsertion != nil ? "Insert text here" : "Start dictation")
            }
            Button { controller.dismissOverlay() } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 20, height: 30) }.buttonStyle(.plain).help(controller.lifecycle.busy ? "Cancel dictation" : "Dismiss; text stays in History")
        }.padding(.horizontal, 17).frame(width: 320, height: 64)
        .background(Color(white: 0.075), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
        .preferredColorScheme(.dark).environment(\.colorScheme, .dark).foregroundStyle(Color(white: 0.9))
        .accessibilityElement(children: .contain).accessibilityLabel("Coda dictation")
    }
}
