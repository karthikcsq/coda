import Foundation
import Testing
@testable import CodaCore
@Test func unconfirmedHistoryRoundTripsWithoutLosingText() throws {
    let record = DictationRecord(text: "synthetic sentence", target: "Synthetic editor", outcome: .deliveryUnconfirmed, detail: "Check destination")
    let restored = try JSONDecoder().decode(DictationRecord.self, from: JSONEncoder().encode(record))
    #expect(restored == record)
}

@Test func pasteConsumptionSettlesWithoutAccessibilityReadback() {
    // Matching AX text is deliberately not a requirement: web editors may expose
    // a stale wrapper even after they have consumed and inserted the paste.
    #expect(!InsertionEvidence.pasteWaitIsComplete(elapsed: 0.05, firstReadAge: 0.5, ownsClipboard: true))
    #expect(!InsertionEvidence.pasteWaitIsComplete(elapsed: 0.4, firstReadAge: 0.2, ownsClipboard: true))
    #expect(InsertionEvidence.pasteWaitIsComplete(elapsed: 0.4, firstReadAge: 0.35, ownsClipboard: true))
    #expect(!InsertionEvidence.pasteWaitIsComplete(elapsed: 2.9, firstReadAge: nil, ownsClipboard: true))
    #expect(InsertionEvidence.pasteWaitIsComplete(elapsed: 3, firstReadAge: nil, ownsClipboard: true))
    #expect(InsertionEvidence.pasteWaitIsComplete(elapsed: 0.01, firstReadAge: nil, ownsClipboard: false))
}
