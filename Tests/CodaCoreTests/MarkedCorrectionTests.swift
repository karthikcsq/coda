import Foundation
import Testing
@testable import CodaCore

private func record(_ text: String, _ outcome: DictationRecord.Outcome, minutesAgo: Double) -> DictationRecord {
    DictationRecord(created: Date(timeIntervalSinceNow: -minutesAgo * 60), text: text, target: "Notes", outcome: outcome, detail: "")
}

@Test func latestInsertedSkipsUninsertedEmptyAndOlderRecords() {
    let older = record("older insert", .inserted, minutesAgo: 10)
    let unconfirmed = record("maybe inserted", .deliveryUnconfirmed, minutesAgo: 5)
    let records = [record("saved only", .saved, minutesAgo: 1), record("", .inserted, minutesAgo: 2),
                   record("copy", .copyRequired, minutesAgo: 3), record("x", .cancelled, minutesAgo: 0),
                   record("x", .failed, minutesAgo: 0), older, unconfirmed]
    #expect(MarkedCorrection.latestInserted(records) == unconfirmed)
    #expect(MarkedCorrection.latestInserted([older, record("newer", .inserted, minutesAgo: 1)])?.text == "newer")
    #expect(MarkedCorrection.latestInserted([record("saved", .saved, minutesAgo: 0)]) == nil)
    #expect(MarkedCorrection.latestInserted([]) == nil)
}

@Test func applyingACorrectionPreservesTheInsertedTextAndRejectsBlankInput() throws {
    var original = record("Meet with Cartick at noon", .inserted, minutesAgo: 1)
    original.rawText = "meet with cartick at noon"
    #expect(MarkedCorrection.apply("  \n ", to: original) == .empty)
    #expect(MarkedCorrection.apply(" Meet with Cartick at noon\n", to: original) == .unchanged)
    let at = Date(timeIntervalSince1970: 1_000)
    guard case .saved(let corrected, let learn) = MarkedCorrection.apply("  Meet with Karthik at noon. ", to: original, at: at) else {
        Issue.record("Expected a saved correction"); return
    }
    #expect(learn)
    #expect(corrected.correctedText == "Meet with Karthik at noon." && corrected.correctedAt == at)
    #expect(corrected.text == original.text && corrected.rawText == original.rawText && corrected.id == original.id)
    #expect(corrected.finalText == "Meet with Karthik at noon.")
    // Saving the current correction again does nothing; restoring the inserted text withdraws it.
    #expect(MarkedCorrection.apply("Meet with Karthik at noon.", to: corrected) == .unchanged)
    guard case .saved(let restored, let relearn) = MarkedCorrection.apply(original.text, to: corrected) else {
        Issue.record("Expected the correction to be withdrawn"); return
    }
    #expect(!relearn && restored.correctedText == nil && restored.correctedAt == nil && restored.finalText == original.text)
}

@Test func correctedRecordsRoundTripAndOlderHistoryStillLoads() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try DictationHistory(root: root)
    var item = record("Inserted words", .inserted, minutesAgo: 0)
    item.correctedText = "Intended words"; item.correctedAt = Date(timeIntervalSince1970: 2_000)
    try store.save(item)
    // A record written before corrections existed has neither key.
    let legacy = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","created":0,"text":"Old","target":"Mail","outcome":"inserted","detail":""}"#
    try Data(legacy.utf8).write(to: root.appendingPathComponent("6F9619FF-8B86-D011-B42D-00C04FC964FF.json"))
    let loaded = try DictationHistory(root: root).load()
    #expect(loaded.skipped == 0)
    #expect(loaded.records.first { $0.id == item.id } == item)
    let old = try #require(loaded.records.first { $0.text == "Old" })
    #expect(old.correctedText == nil && old.finalText == "Old")
}
