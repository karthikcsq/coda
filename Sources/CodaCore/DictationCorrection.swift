import Foundation

/// Marking a dictation wrong: choosing which saved record it refers to and
/// applying the user's intended text without losing what Coda inserted.
public enum MarkedCorrection {
    /// Outcomes whose text reached, or may have reached, another app.
    public static let insertedOutcomes: Set<DictationRecord.Outcome> = [.inserted, .deliveryUnconfirmed]

    /// The newest record whose text was inserted. Saved-only, failed and
    /// cancelled sessions are skipped, as are records without text.
    public static func latestInserted(_ records: [DictationRecord]) -> DictationRecord? {
        records.filter { insertedOutcomes.contains($0.outcome) && !trimmed($0.text).isEmpty }
            .max { $0.created < $1.created }
    }

    public enum Result: Equatable, Sendable {
        /// The record to save. `learn` is false when the text returns to what was inserted.
        case saved(DictationRecord, learn: Bool)
        /// Same as the text already stored; nothing to save.
        case unchanged
        /// Blank input never replaces a dictation.
        case empty
    }

    public static func apply(_ input: String, to record: DictationRecord, at date: Date = .now) -> Result {
        let corrected = trimmed(input)
        guard !corrected.isEmpty else { return .empty }
        guard corrected != trimmed(record.finalText) else { return .unchanged }
        var updated = record
        if corrected == trimmed(record.text) {
            // Restoring the inserted text withdraws the earlier correction.
            updated.correctedText = nil; updated.correctedAt = nil
            return .saved(updated, learn: false)
        }
        updated.correctedText = corrected; updated.correctedAt = date
        return .saved(updated, learn: true)
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}
