import AppKit
import SwiftUI
import Testing
import CodaCore
@testable import Coda

@Test @MainActor func newWordNoticeQueuesOnceAndClosingKeepsWordsForReview() throws {
    let dictionary = CustomDictionary(preview: true)
    let notice = DictionarySuggestions(dictionary: dictionary, preview: true)
    let first = UUID(), second = UUID()
    let changes = [WordCorrection(original: "Cartick", corrected: "Karthik"), WordCorrection(original: "supper base", corrected: "Supabase")]
    dictionary.suggest(changes, session: first)
    #expect(notice.current?.word == "Karthik" && notice.remaining == 1)
    dictionary.suggest(changes, session: second)
    #expect(notice.current?.word == "Karthik" && notice.remaining == 1)
    notice.setHovering(true); #expect(notice.hovering)
    notice.setHovering(false); #expect(!notice.hovering)
    notice.finishPresentation() // Timeout behaves like closing, not rejection.
    #expect(notice.current == nil && dictionary.possible.count == 2)
    dictionary.suggest(changes, session: UUID())
    #expect(notice.current == nil && notice.remaining == 0)
    dictionary.suggest([.init(original: "prismack", corrected: "Prismac")], session: UUID())
    #expect(notice.current?.word == "Prismac")
}

@Test @MainActor func wordNoticeApprovalConfirmsThenAdvancesAndDismissalPersists() throws {
    let dictionary = CustomDictionary(preview: true)
    let notice = DictionarySuggestions(dictionary: dictionary, preview: true)
    dictionary.suggest([.init(original: "Cartick", corrected: "Karthik"), .init(original: "supper base", corrected: "Supabase")], session: UUID())
    notice.approve()
    #expect(notice.added && notice.current?.word == "Karthik")
    #expect(dictionary.vocabulary == ["Karthik"] && notice.remaining == 1)
    notice.approve() // Repeated clicks cannot re-approve or skip the confirmation.
    #expect(notice.added && notice.current?.word == "Karthik")
    notice.finishPresentation()
    #expect(!notice.added && notice.current?.word == "Supabase")
    notice.dismissWord()
    #expect(notice.current == nil && dictionary.possible.isEmpty)
    dictionary.suggest([.init(original: "supper base", corrected: "Supabase")], session: UUID())
    #expect(notice.current == nil && dictionary.possible.isEmpty)
}

@Test @MainActor func wordNoticeRemovesUndoneCandidatesAndDoesNotReplayOnLaunch() throws {
    let dictionary = CustomDictionary(preview: true)
    let session = UUID()
    dictionary.suggest([.init(original: "Cartick", corrected: "Karthik")], session: session)
    let notice = DictionarySuggestions(dictionary: dictionary, preview: true)
    #expect(notice.current == nil)
    let nextSession = UUID()
    dictionary.suggest([.init(original: "supper base", corrected: "Supabase")], session: nextSession)
    #expect(notice.current?.word == "Supabase")
    dictionary.suggest([], session: nextSession)
    #expect(notice.current == nil)
    dictionary.suggest([.init(original: "supper base", corrected: "Supabase")], session: nextSession)
    #expect(notice.current == nil) // Undo/redo does not repeatedly interrupt work.
}

@Test @MainActor func wordNoticeReviewOpensDictionaryAndLearningOffClosesIt() throws {
    let controller = DictationController(preview: true)
    let model = AppModel(preview: true)
    defer { try? FileManager.default.removeItem(at: model.root) }
    controller.attach(model); model.openSettings()
    var opened = false
    controller.showDictionaryWindow = { opened = true }
    controller.dictionary.suggest([.init(original: "Cartick", corrected: "Karthik")], session: UUID())
    #expect(controller.wordSuggestions.current != nil)
    controller.wordSuggestions.review()
    #expect(opened && !model.showSettings && controller.workspaceSection == "Dictionary")
    #expect(controller.wordSuggestions.current == nil && controller.dictionary.possible.count == 1)
    controller.dictionary.suggest([.init(original: "supper base", corrected: "Supabase")], session: UUID())
    controller.learnWords = false
    #expect(controller.wordSuggestions.current == nil && controller.dictionary.possible.count == 2)
}

@Test @MainActor func wordNoticeSaveFailureStaysVisibleForRecovery() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let dictionary = CustomDictionary(root: root, preview: true)
    let notice = DictionarySuggestions(dictionary: dictionary, preview: true)
    dictionary.suggest([.init(original: "Cartick", corrected: "Karthik")], session: UUID())
    // Replace the destination file with a directory to induce a real write error.
    let file = root.appendingPathComponent("words.json")
    try FileManager.default.removeItem(at: file)
    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
    notice.approve()
    #expect(!notice.added && notice.current?.word == "Karthik" && notice.error != nil)
    #expect(dictionary.vocabulary.isEmpty)
    try FileManager.default.removeItem(at: file)
    notice.approve()
    #expect(notice.added && notice.error == nil && dictionary.vocabulary == ["Karthik"])
}

@Test @MainActor func noticePanelCannotTakeKeyboardFocusAndRendersSuggestionAndConfirmation() throws {
    _ = NSApplication.shared
    let dictionary = CustomDictionary(preview: true)
    let notice = DictionarySuggestions(dictionary: dictionary, preview: true)
    dictionary.suggest([.init(original: "Cartick", corrected: "Karthik"), .init(original: "supper base", corrected: "Supabase")], session: UUID())
    let popup = DictionarySuggestionWindow(notice: notice)
    #expect(!popup.panel.canBecomeKey && !popup.panel.canBecomeMain)
    #expect(popup.panel.styleMask.contains(.nonactivatingPanel))
    func render(_ name: String) throws {
        let host = NSHostingView(rootView: DictionarySuggestionCard(notice: notice))
        host.frame = CGRect(x: 0, y: 0, width: 392, height: 264); host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: .now.addingTimeInterval(0.15))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/coda-word-notice-\(name).png"))
    }
    try render("suggestion")
    notice.approve(); try render("added")
    notice.finishPresentation(); notice.close()
    dictionary.suggest([.init(original: "cartick", corrected: "Karthik Rajagopalan-Somasundaram")], session: UUID())
    try render("long-word")
}
