import AppKit
import Observation
import SwiftUI
import KeyboardShortcuts
import CodaCore

private typealias EditorState<Value> = SwiftUI.State<Value>

extension KeyboardShortcuts.Name {
    /// Global: marks the most recently inserted dictation wrong and opens the editor.
    static let codaCorrectLastDictation = Self("codaCorrectLastDictation", default: .init(.c, modifiers: BuildIdentity.isDevelopment ? [.control, .option, .shift] : [.control, .option]))
}

/// Editing state for one marked-wrong dictation. Closing without saving keeps
/// the record exactly as it was.
@MainActor @Observable final class CorrectionEditor {
    struct Draft: Equatable {
        let recordID: UUID
        let inserted: String
        let target: String
        let created: Date
        let previouslyCorrected: Bool
    }
    private(set) var draft: Draft?
    private(set) var isPresented = false
    var text = ""
    var error: String?
    /// Returns nil when saved, or a message that keeps the editor open.
    @ObservationIgnored var onSave: ((UUID, String) -> String?)?
    @ObservationIgnored private var window: CorrectionWindow?
    @ObservationIgnored private var previousApp: NSRunningApplication?
    private let preview: Bool
    init(preview: Bool = false) { self.preview = preview }

    var canSave: Bool { draft != nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// `nil` shows the empty state, so the shortcut always gives feedback.
    func present(_ record: DictationRecord?) {
        // Pressing the shortcut again for the same dictation keeps the typed draft.
        if !(isPresented && record != nil && draft?.recordID == record?.id) {
            draft = record.map { Draft(recordID: $0.id, inserted: $0.text, target: $0.target, created: $0.created, previouslyCorrected: $0.correctedText != nil) }
            text = record?.finalText ?? ""
            error = nil
        }
        if !isPresented {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == getpid() ? nil : front
        }
        isPresented = true
        guard !preview else { return }
        if window == nil { window = CorrectionWindow(editor: self) }
        window?.show()
    }
    func save() {
        guard let draft else { close(); return }
        guard canSave else { error = "Enter the text you meant, or press Cancel."; return }
        if let failure = onSave?(draft.recordID, text) { error = failure; return }
        close()
    }
    func cancel() { close() }
    /// Also called when the window's close button is used.
    func close() {
        guard isPresented else { return }
        isPresented = false; draft = nil; text = ""; error = nil
        window?.hide()
        // Return to the app the user was correcting from.
        previousApp?.activate(); previousApp = nil
    }
}

@MainActor final class CorrectionWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    private weak var editor: CorrectionEditor?
    init(editor: CorrectionEditor) {
        self.editor = editor
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 420), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "Correct dictation" + (BuildIdentity.isDevelopment ? " — Coda Dev" : "")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(CodaStyle.canvas)
        window.contentViewController = NSHostingController(rootView: CorrectionEditorView(editor: editor))
        window.delegate = self
    }
    func show() {
        if !window.isVisible {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                let size = window.frame.size
                window.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.1))
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func hide() { if window.isVisible { window.orderOut(nil) } }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        editor?.cancel(); return false
    }
}

struct CorrectionEditorView: View {
    @Bindable var editor: CorrectionEditor
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let draft = editor.draft { form(draft) } else { empty }
        }
        .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 20)
        .frame(width: 520)
        .frame(minHeight: editor.draft == nil ? 200 : 420, alignment: .top)
        .background(CodaStyle.canvas)
        .preferredColorScheme(.dark).environment(\.colorScheme, .dark).foregroundStyle(CodaStyle.ink)
        .onAppear { focused = true }
        .onChange(of: editor.draft?.recordID) { focused = true }
    }
    private var empty: some View {
        VStack(alignment: .leading, spacing: 16) {
            CodaEmptyState(icon: "text.badge.xmark", title: "No inserted dictation to correct",
                           message: "Dictate into another app first. Then press this shortcut to fix what Coda typed.")
            HStack { Spacer(); Button("Close") { editor.cancel() }.buttonStyle(CodaPrimaryButtonStyle()).keyboardShortcut(.cancelAction) }
        }
    }
    private func form(_ draft: CorrectionEditor.Draft) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Correct last dictation").font(CodaStyle.pageTitleFont).tracking(CodaStyle.pageTitleTracking)
                Text("\(draft.target) · \(draft.created.formatted(date: .abbreviated, time: .shortened))")
                    .font(CodaStyle.secondaryFont).foregroundStyle(CodaStyle.muted)
            }
            VStack(alignment: .leading, spacing: 6) {
                CodaEyebrow(text: "Coda inserted")
                ScrollView {
                    Text(draft.inserted).font(CodaStyle.bodyFont).foregroundStyle(CodaStyle.ink.opacity(0.8))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 76).fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(CodaStyle.sunken, in: RoundedRectangle(cornerRadius: CodaStyle.radiusSmall))
                .accessibilityElement(children: .combine).accessibilityLabel("Coda inserted: " + draft.inserted)
            }
            VStack(alignment: .leading, spacing: 6) {
                CodaEyebrow(text: "What you meant")
                TextEditor(text: $editor.text)
                    .font(.system(size: 14)).scrollContentBackground(.hidden)
                    .focused($focused)
                    .padding(6).frame(minHeight: 110, maxHeight: .infinity)
                    .background(CodaStyle.raised, in: RoundedRectangle(cornerRadius: CodaStyle.radiusSmall))
                    .overlay(RoundedRectangle(cornerRadius: CodaStyle.radiusSmall).strokeBorder(focused ? CodaStyle.strongEdge : CodaStyle.hairline))
                    .accessibilityLabel("What you meant")
                    .onChange(of: editor.text) { if editor.error != nil && editor.canSave { editor.error = nil } }
            }
            if let error = editor.error { CodaNotice(kind: .caution, text: error) }
            HStack(spacing: 10) {
                Text(draft.previouslyCorrected ? "Replaces your earlier correction. The inserted text stays in History." : "The inserted text stays in History.")
                    .font(CodaStyle.captionFont).foregroundStyle(CodaStyle.faint).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Cancel") { editor.cancel() }.buttonStyle(CodaSecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save correction") { editor.save() }.buttonStyle(CodaPrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command).disabled(!editor.canSave)
                    .help("Save correction (⌘↩)")
            }
        }
    }
}
