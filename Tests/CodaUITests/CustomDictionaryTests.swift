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
    controller.workspaceSection = "Dictionary"
    let model = AppModel(preview: true)
    defer { try? FileManager.default.removeItem(at: model.root) }
    let host = NSHostingView(rootView: WorkspaceView(model: model, controller: controller, delegate: AppDelegate()))
    host.frame = CGRect(x: 0, y: 0, width: 980, height: 680); host.appearance = NSAppearance(named: .darkAqua)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host; host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/coda-dictionary-review.png"))
    #expect(controller.dictionary.possible.count == 2 && controller.dictionary.vocabulary == ["Wispr Flow"])
}
