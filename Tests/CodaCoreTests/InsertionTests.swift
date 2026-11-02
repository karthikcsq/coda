import Testing
import Foundation
@testable import CodaCore

@Test func pasteAllowsMissingSelectionButChecksAvailableEvidence() {
    #expect(InsertionObservation.selectionUnchanged(original: nil, current: nil))
    #expect(InsertionObservation.selectionUnchanged(original: nil, current: NSRange(location: 3, length: 0)))
    #expect(InsertionObservation.selectionUnchanged(original: NSRange(location: 3, length: 2), current: NSRange(location: 3, length: 2)))
    #expect(!InsertionObservation.selectionUnchanged(original: NSRange(location: 3, length: 2), current: nil))
    #expect(!InsertionObservation.selectionUnchanged(original: NSRange(location: 3, length: 2), current: NSRange(location: 3, length: 0)))
    #expect(!InsertionObservation.selectionUnchanged(original: NSRange(location: 3, length: 2), current: NSRange(location: 4, length: 2)))
}
@Test func sameSelectionButChangedTextRejectsInsertion() {
    let original = InsertionObservation.fingerprint("Synthetic 🦋 note")
    #expect(InsertionObservation.unchanged(original: original, current: "Synthetic 🦋 note"))
    #expect(!InsertionObservation.unchanged(original: original, current: "Synthetic 🐝 note"))
    #expect(!InsertionObservation.unchanged(original: original, current: nil))
    #expect(original.count == 32)
}
