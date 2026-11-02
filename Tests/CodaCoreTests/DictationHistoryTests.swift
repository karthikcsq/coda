import Foundation
import Testing
@testable import CodaCore

@Test func dictationHistorySurvivesRestartUpdatesAndCorruption() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try DictationHistory(root: root)
    var item = DictationRecord(text: "Synthetic words", target: "Fixture", outcome: .saved, detail: "Saved before insertion")
    try store.save(item); item.outcome = .copyRequired; item.detail = "Fixture unavailable"; try store.save(item)
    let cancelled = DictationRecord(text: "", target: "Fixture", outcome: .cancelled, detail: "Cancelled")
    try store.save(cancelled)
    try Data("invalid".utf8).write(to: root.appendingPathComponent("corrupt.json"))
    let loaded = try DictationHistory(root: root).load()
    #expect(loaded.records.count == 2); #expect(loaded.skipped == 1)
    #expect(loaded.records.first(where: { $0.id == item.id }) == item)
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("corrupt.json").path))
}
@Test func overlayPlacementPreservesDragAndClampsAfterDisplayChange() {
    let display = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let size = CGSize(width: 440, height: 300)
    let initial = DictationPlacement.frame(current: nil, visible: display, size: size)
    #expect(initial.midX == display.midX); #expect(initial.minY == 28)
    let dragged = CGRect(x: -1500, y: 400, width: 440, height: 300)
    #expect(DictationPlacement.frame(current: dragged, visible: display, size: size) == dragged)
    let reduced = CGRect(x: 0, y: 0, width: 800, height: 600)
    let clamped = DictationPlacement.frame(current: dragged, visible: reduced, size: size)
    #expect(reduced.contains(clamped)); #expect(clamped.minX == 0); #expect(clamped.maxY == 600)
}
@Test func plainFieldInsertionPreservesUnicodeAndRejectsInvalidRanges() {
    #expect(PlainTextInsertion.replacing("A🦋B", range: NSRange(location: 1, length: 2), with: "new") == "AnewB")
    #expect(PlainTextInsertion.replacing("A🦋B", range: NSRange(location: 2, length: 1), with: "bad") == nil)
    #expect(PlainTextInsertion.replacing("abc", range: NSRange(location: 12, length: 0), with: "bad") == nil)
    #expect(PlainTextInsertion.replacing("before after", range: NSRange(location: 7, length: 0), with: "new ") == "before new after")
}
