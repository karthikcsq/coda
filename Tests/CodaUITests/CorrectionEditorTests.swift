import AppKit
import SwiftUI
import Testing
import CodaCore
@testable import Coda

@MainActor private func controllerWithHistory() -> (DictationController, inserted: DictationRecord) {
    let controller = DictationController(preview: true)
    let inserted = DictationRecord(created: .now.addingTimeInterval(-30), text: "Ask Cartick to review the supper base migration.",
                                   target: "Slack", outcome: .inserted, detail: "Inserted into Slack.",
                                   rawText: "ask cartick to review the supper base migration", cleanupMode: .light)
    controller.records = [
        DictationRecord(created: .now, text: "Saved but never inserted", target: "Notes", outcome: .copyRequired, detail: ""),
        inserted,
        DictationRecord(created: .now.addingTimeInterval(-600), text: "Older insert", target: "Mail", outcome: .inserted, detail: "")
    ]
    return (controller, inserted)
}

@Test @MainActor func shortcutOpensEditorForLatestInsertedDictationPrefilled() throws {
    let (controller, inserted) = controllerWithHistory()
    controller.correctLastDictation()
    let editor = controller.correctionEditor
    #expect(editor.isPresented)
    #expect(editor.draft?.recordID == inserted.id && editor.draft?.inserted == inserted.text && editor.draft?.target == "Slack")
    #expect(editor.text == inserted.text && editor.canSave)
    // Pressing the shortcut again keeps a draft in progress.
    editor.text = "Ask Karthik"
    controller.correctLastDictation()
    #expect(editor.text == "Ask Karthik")
}

@Test @MainActor func savingStoresCorrectionPreservesOriginalAndSuggestsWords() throws {
    let (controller, inserted) = controllerWithHistory()
    controller.correctLastDictation()
    let editor = controller.correctionEditor
    editor.text = "Ask Karthik to review the Supabase migration.\n"
    editor.save()
    #expect(!editor.isPresented && editor.draft == nil && editor.error == nil)
    let saved = try #require(controller.records.first { $0.id == inserted.id })
    #expect(saved.correctedText == "Ask Karthik to review the Supabase migration.")
    #expect(saved.text == inserted.text && saved.rawText == inserted.rawText && saved.outcome == .inserted)
    #expect(saved.correctedAt != nil)
    // Existing correction learning receives the explicit correction.
    let suggested = Set(controller.dictionary.possible.map(\.word))
    #expect(suggested.contains("Karthik") && suggested.contains("Supabase"))
    // Reopening shows the earlier correction as the starting text, and the inserted text above it.
    controller.correctLastDictation()
    #expect(editor.draft?.previouslyCorrected == true && editor.draft?.inserted == inserted.text)
    #expect(editor.text == saved.correctedText)
    editor.cancel()
}

@Test @MainActor func cancelAndBlankInputNeverChangeTheRecord() throws {
    let (controller, inserted) = controllerWithHistory()
    let editor = controller.correctionEditor
    controller.correctLastDictation()
    editor.text = "Something else entirely"
    editor.cancel()
    #expect(!editor.isPresented && editor.text.isEmpty)
    #expect(controller.records.first { $0.id == inserted.id } == inserted)

    controller.correctLastDictation()
    #expect(editor.text == inserted.text) // A cancelled draft is not restored.
    editor.text = "   \n"
    #expect(!editor.canSave)
    editor.save()
    #expect(editor.isPresented && editor.error != nil)
    #expect(controller.saveCorrection(id: inserted.id, text: "") != nil)
    #expect(controller.records.first { $0.id == inserted.id } == inserted)
    editor.text = inserted.text
    editor.save() // Unchanged text closes without writing a correction.
    #expect(!editor.isPresented)
    #expect(controller.records.first { $0.id == inserted.id }?.correctedText == nil)
    #expect(controller.saveCorrection(id: UUID(), text: "Missing") != nil)
}

@Test @MainActor func noRecentInsertionShowsEmptyStateAndBusySessionsDoNotOpen() throws {
    let controller = DictationController(preview: true)
    controller.records = [DictationRecord(text: "Saved only", target: "Notes", outcome: .saved, detail: "")]
    controller.correctLastDictation()
    let editor = controller.correctionEditor
    #expect(editor.isPresented && editor.draft == nil && !editor.canSave)
    editor.save() // The empty state's only action closes it.
    #expect(!editor.isPresented)

    let (busy, _) = controllerWithHistory()
    #expect(busy.lifecycle.begin(meetingBusy: false, modelReady: true) != nil)
    busy.correctLastDictation()
    #expect(!busy.correctionEditor.isPresented)
    #expect(busy.message.contains("Finish the current dictation"))
}

@Test @MainActor func historyCardShowsTheCorrectionAndKeepsTheInsertedText() throws {
    let (controller, inserted) = controllerWithHistory()
    #expect(controller.saveCorrection(id: inserted.id, text: "Ask Karthik to review the Supabase migration.") == nil)
    let saved = try #require(controller.records.first { $0.id == inserted.id })
    let host = NSHostingView(rootView: RecordCard(record: saved, controller: controller, expanded: true).frame(width: 720))
    host.frame = CGRect(x: 0, y: 0, width: 720, height: 320); host.layoutSubtreeIfNeeded()
    #expect(host.fittingSize.height > 0)
    #expect(saved.finalText == "Ask Karthik to review the Supabase migration.")
}

/// Native render evidence, opt-in like the workspace renders:
///   CODA_RENDER_DOCS=1 ./scripts/test.sh --filter CorrectionEditorRenderSuite
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CODA_RENDER_DOCS"] == "1", "Opt-in docs render; set CODA_RENDER_DOCS=1."))
struct CorrectionEditorRenderSuite {
    @MainActor private func render<V: View>(_ view: V, size: CGSize, name: String) throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: size); host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: .now.addingTimeInterval(0.1))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/images", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent(name))
    }
    @Test @MainActor func renderCorrectionEditorStates() throws {
        let (controller, inserted) = controllerWithHistory()
        let editor = controller.correctionEditor
        controller.correctLastDictation()
        editor.text = "Ask Karthik to review the Supabase migration."
        try render(CorrectionEditorView(editor: editor), size: CGSize(width: 520, height: 420), name: "correction-editor.png")
        editor.text = " "; editor.save()
        try render(CorrectionEditorView(editor: editor), size: CGSize(width: 520, height: 420), name: "correction-editor-empty-input.png")
        editor.cancel()
        let empty = DictationController(preview: true)
        empty.correctLastDictation()
        try render(CorrectionEditorView(editor: empty.correctionEditor), size: CGSize(width: 520, height: 200), name: "correction-editor-no-dictation.png")
        _ = controller.saveCorrection(id: inserted.id, text: "Ask Karthik to review the Supabase migration.")
        let saved = try #require(controller.records.first { $0.id == inserted.id })
        try render(RecordCard(record: saved, controller: controller, expanded: true).frame(width: 720).background(CodaStyle.canvas),
                   size: CGSize(width: 720, height: 300), name: "correction-history-card.png")
        let model = AppModel(preview: true)
        controller.attach(model)
        try render(SettingsPanel(model: model, controller: controller).background(CodaStyle.canvas),
                   size: CGSize(width: 980, height: 1500), name: "correction-settings-shortcut.png")
    }
}
