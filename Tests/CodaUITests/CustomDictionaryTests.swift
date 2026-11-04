import AppKit
import SwiftUI
import Testing
import CodaCore
@testable import Coda

@Test @MainActor func dictionaryReviewPersistsAndOnlyApprovedWordsBecomeHints() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let dictionary = CustomDictionary(root: root, preview: true)
    let session = UUID()
    dictionary.suggest([.init(original: "Cartick", corrected: "Karthik")], session: session)
    let suggested = try #require(dictionary.possible.first)
    #expect(dictionary.vocabulary.isEmpty)
    dictionary.suggest([.init(original: "Cartick", corrected: "Karthik")], session: session)
    #expect(dictionary.possible.count == 1 && dictionary.possible[0].observations.count == 1)
    #expect(dictionary.approve(suggested.id))
    #expect(dictionary.vocabulary == ["Karthik"] && dictionary.possible.isEmpty)
    let reloaded = CustomDictionary(root: root, preview: true)
    #expect(reloaded.vocabulary == ["Karthik"])
    reloaded.dismiss(suggested.id)
    reloaded.suggest([.init(original: "Cartick", corrected: "Karthik")], session: UUID())
    #expect(reloaded.possible.isEmpty && reloaded.vocabulary.isEmpty)
    #expect(reloaded.add("Karthik"))
    #expect(reloaded.vocabulary == ["Karthik"])
    #expect(!reloaded.add(" karthik "))
    #expect(!reloaded.add("https://example.com"))
    #expect(reloaded.approve(suggested.id, spelling: "Karthik R"))
    reloaded.suggest([.init(original: "Cartick", corrected: "Karthik")], session: UUID())
    #expect(reloaded.possible.isEmpty && reloaded.vocabulary == ["Karthik R"])
    #expect(CustomDictionary(root: root, preview: true).vocabulary == ["Karthik R"])
}

@Test @MainActor func dictionaryUndoReconcilesEvidenceAcrossSessionsAndOffStopsLearning() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let dictionary = CustomDictionary(root: root, preview: true)
    let first = UUID(), second = UUID(), change = WordCorrection(original: "Cartick", corrected: "Karthik")
    dictionary.suggest([change], session: first); dictionary.suggest([change], session: second)
    dictionary.suggest([], session: first)
    #expect(dictionary.possible.first?.observations == [second])
    dictionary.suggest([], session: second)
    #expect(dictionary.possible.isEmpty)
    dictionary.learningEnabled = false
    dictionary.suggest([change], session: first)
    #expect(dictionary.possible.isEmpty)
    #expect(dictionary.add("Supabase"))
    #expect(dictionary.vocabulary == ["Supabase"]) // Turning learning off keeps approved hints.
}

@Test @MainActor func corruptDictionaryIsNeverOverwrittenByNewWords() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try CustomDictionaryStore(root: root)
    let corrupt = Data("broken".utf8); try corrupt.write(to: store.file)
    let dictionary = CustomDictionary(root: root, preview: true)
    #expect(dictionary.error != nil && !dictionary.add("Karthik"))
    #expect(try Data(contentsOf: store.file) == corrupt)
}

@Test @MainActor func trackerDebouncesCorrectionsHandlesUndoAndReleasesOnStop() throws {
    let tracker = DictationCorrections()
    let passage = try #require(CorrectionPassage(before: "Before ", selection: NSRange(location: 7, length: 0), dictated: "Meet Cartick tomorrow."))
    var reported: [[WordCorrection]] = []
    tracker.configure(passage: passage, original: "Meet Cartick tomorrow.", isCommon: { ["meet", "tomorrow"].contains($0.lowercased()) }) { reported.append($0) }
    tracker.sample("Before Meet Cartick tomorrow.", elapsed: 0)
    tracker.sample("Before Meet Kart tomorrow.", elapsed: 0.2)
    tracker.sample("Before Meet Karthik tomorrow.", elapsed: 0.4)
    #expect(reported.isEmpty)
    tracker.sample("Before Meet Karthik tomorrow.", elapsed: 1.3)
    #expect(reported.last == [.init(original: "Cartick", corrected: "Karthik")])
    tracker.sample("Before Meet Cartick tomorrow.", elapsed: 2)
    tracker.stop() // Undo immediately before a focus change is reconciled, too.
    #expect(reported.last == [] && !tracker.active)
    let count = reported.count
    tracker.sample("Before Meet Something tomorrow.", elapsed: 3)
    #expect(reported.count == count)
}

@Test @MainActor func trackerNeverLearnsWithoutPasteAndStopsOnFieldClearAndDeadline() throws {
    let passage = try #require(CorrectionPassage(before: "", selection: NSRange(location: 0, length: 0), dictated: "Cartick"))
    let tracker = DictationCorrections()
    var reported: [[WordCorrection]] = []
    tracker.configure(passage: passage, original: "Cartick", isCommon: { _ in false }) { reported.append($0) }
    tracker.sample("Karthik", elapsed: 0.2); tracker.sample("Karthik", elapsed: 2.1)
    #expect(!tracker.active && reported.isEmpty)
    tracker.configure(passage: passage, original: "Cartick", isCommon: { _ in false }) { reported.append($0) }
    tracker.sample("Cartick", elapsed: 0); tracker.sample("Karthik", elapsed: 1)
    tracker.sample("", elapsed: 1.2)
    #expect(!tracker.active && reported.last == [.init(original: "Cartick", corrected: "Karthik")])
    tracker.configure(passage: passage, original: "Cartick", isCommon: { _ in false }) { reported.append($0) }
    tracker.sample("Cartick", elapsed: 0); tracker.sample("Karthik", elapsed: 60)
    #expect(!tracker.active && reported.last == [])
}

@Test @MainActor func renderDictionaryAtMinimumWorkspaceWidth() throws {
    _ = NSApplication.shared
    let controller = DictationController(preview: true)
    controller.dictionary.suggest([.init(original: "Cartick", corrected: "Karthik"), .init(original: "supper base", corrected: "Supabase")], session: UUID())
    #expect(controller.dictionary.add("Wispr Flow"))
    #expect(controller.dictionary.add("LeetCode", heardAs: ["lead code", "leet code"]))
    controller.workspaceSection = "Dictionary"
    let model = AppModel(preview: true)
    defer { try? FileManager.default.removeItem(at: model.root) }
    let host = NSHostingView(rootView: WorkspaceView(model: model, controller: controller, delegate: AppDelegate()))
    host.frame = CGRect(x: 0, y: 0, width: 980, height: 680); host.appearance = NSAppearance(named: .darkAqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host; host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: renderDirectory.appendingPathComponent("coda-dictionary-review.png"))
    #expect(controller.dictionary.possible.count == 2 && controller.dictionary.vocabulary == ["LeetCode", "Wispr Flow"])
}

/// Renders go to CODA_RENDER_DIR when set, otherwise the temporary directory.
private var renderDirectory: URL {
    ProcessInfo.processInfo.environment["CODA_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.temporaryDirectory
}

@Test @MainActor func renderHeardAsEditorWithObservedSuggestionAndEverydayWarning() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let dictionary = CustomDictionary(root: root, preview: true)
    dictionary.suggest([.init(original: "lead code", corrected: "LeetCode")], session: UUID())
    #expect(dictionary.add("LaTeX", heardAs: ["later"]))
    let learned = try #require(dictionary.possible.first)
    let latex = try #require(dictionary.approved.first)
    let everyday: Set<String> = ["later", "lead", "code"]
    for (name, word) in [("suggestion", learned), ("everyday", latex)] {
        let host = NSHostingView(rootView: DictionaryWordEditor(dictionary: dictionary, word: word, isCommon: { everyday.contains($0.lowercased()) })
            .background(Color(white: 0.16)).environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: .now.addingTimeInterval(0.1))
        #expect(host.bounds.width == 460 && host.bounds.height < 520)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: renderDirectory.appendingPathComponent("coda-dictionary-editor-\(name).png"))
    }
}

@Test @MainActor func heardAsVariantsPersistAndOnlyApprovedEntriesReplace() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let dictionary = CustomDictionary(root: root, preview: true)
    dictionary.suggest([.init(original: "lead code", corrected: "LeetCode")], session: UUID())
    let suggested = try #require(dictionary.possible.first)
    // A learned misspelling is only offered; nothing replaces until the user approves it.
    #expect(suggested.heardAs.isEmpty && dictionary.soundAlikeRules.isEmpty)
    #expect(dictionary.approve(suggested.id))
    #expect(dictionary.soundAlikeRules.isEmpty && dictionary.vocabulary == ["LeetCode"])
    #expect(dictionary.approve(suggested.id, heardAs: [suggested.original!, "leet code"]))
    #expect(dictionary.add("Wispr Flow", heardAs: ["whisperflow"]))
    let reloaded = CustomDictionary(root: root, preview: true)
    #expect(Set(reloaded.soundAlikeRules.map(\.heard)) == ["lead code", "leet code", "whisperflow"])
    #expect(reloaded.vocabulary == ["LeetCode", "Wispr Flow"]) // Variants never become recognition hints.
    // Approving without a variant list keeps the current variants.
    #expect(reloaded.approve(suggested.id, spelling: "LeetCode"))
    #expect(reloaded.words.first { $0.id == suggested.id }?.heardAs == ["lead code", "leet code"])
    // Conflicts are rejected without saving.
    #expect(!reloaded.add("Leetcode Pro", heardAs: ["Lead Code"]) && reloaded.error?.contains("LeetCode") == true)
    #expect(!reloaded.add("Whisperflow"))
    #expect(!reloaded.approve(suggested.id, heardAs: ["LeetCode"]))
    // Removing a word stops its replacements, and re-adding starts with none.
    let flow = try #require(reloaded.approved.first { $0.word == "Wispr Flow" })
    #expect(reloaded.dismiss(flow.id) && reloaded.soundAlikeRules.map(\.heard).sorted() == ["lead code", "leet code"])
    #expect(reloaded.add("Wispr Flow") && CustomDictionary(root: root, preview: true).soundAlikeRules.count == 2)
}

@Test @MainActor func heardAsRunsBeforeCleanupAndHistoryKeepsRawWords() throws {
    // A missing worker keeps Smart mode from starting any local model process.
    let controller = DictationController(preview: true, formatter: SmartFormatter(python: URL(fileURLWithPath: "/no-runtime"),
                                                                                  script: URL(fileURLWithPath: "/no-worker")))
    defer { controller.cancel() }
    #expect(controller.dictionary.add("LeetCode", heardAs: ["lead code"]))
    #expect(controller.dictionary.add("Google Meet", heardAs: ["google me"]))
    for mode in [DictationCleanupMode.light, .smart, .none] {
        controller.cleanupMode = mode
        let begun = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
        let id = try #require(begun)
        _ = controller.lifecycle.listening(id); _ = controller.lifecycle.processing()
        let raw = "practice lead code on the google me call, not \"lead code\""
        #expect(controller.acceptTranscription(raw, for: id))
        let record = try #require(controller.records.first { $0.id == id })
        #expect(record.rawText == raw)
        if mode == .none {
            #expect(controller.text == raw && record.text == raw)
        } else {
            #expect(controller.text == "practice LeetCode on the Google Meet call, not \"lead code\"", Comment(rawValue: mode.rawValue))
            #expect(record.detail.contains("Dictionary corrected 2 misheard terms"))
        }
        _ = controller.lifecycle.complete(id); controller.lifecycle.settled(id)
    }
    controller.cleanupMode = .light
}
