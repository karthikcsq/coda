import Foundation
import Testing
@testable import CodaCore

private let everydayWords: Set<String> = ["we", "use", "and", "at", "the", "meet", "tomorrow", "today", "send", "please", "hello", "there", "a", "name", "is", "our", "now", "later", "looks", "great"]
private func candidates(_ original: String, _ edited: String) -> [WordCorrection] {
    CorrectionCandidates.extract(original: original, edited: edited, isCommon: { everydayWords.contains($0.lowercased()) })
}

@Test func correctionsExtractNamesAndSplitJoinedTerms() {
    #expect(candidates("Please meet Cartick tomorrow.", "Please meet Karthik tomorrow.") == [.init(original: "Cartick", corrected: "Karthik")])
    #expect(candidates("We use supper base today.", "We use Supabase today.") == [.init(original: "supper base", corrected: "Supabase")])
    #expect(candidates("We use whisperflow today.", "We use Wispr Flow today.") == [.init(original: "whisperflow", corrected: "Wispr Flow")])
    #expect(candidates("Cartick and supper base look great.", "Karthik and Supabase look great.").map(\.corrected) == ["Karthik", "Supabase"])
    #expect(candidates("Cartick", "Karthik").first?.corrected == "Karthik")
}

@Test func correctionsIgnoreOrdinaryEditsAndAppendedProse() {
    #expect(candidates("We meet tomorrow.", "We meet today.").isEmpty)
    #expect(candidates("hello there", "Hello there!").isEmpty)
    #expect(candidates("We meet tomorrow.", "We meet tomorrow at Supabase.").isEmpty)
    #expect(candidates("We meet Cartick tomorrow.", "We meet tomorrow.").isEmpty)
    #expect(candidates("We use this for our work every day.", "Supabase makes everything completely different from before.").isEmpty)
    #expect(candidates(String(repeating: "word ", count: 520), "Karthik").isEmpty)
}

@Test func correctionsExcludeIdentifiersPathsAndNumbers() {
    for pair in [("See cartick.com today", "See karthik.com today"),
                 ("Send to cartick@example.com", "Send to karthik@example.com"),
                 ("Open /tmp/cartick now", "Open /tmp/karthik now"),
                 ("Use cartick_id now", "Use karthik_id now"),
                 ("Use `cartick` now", "Use `karthik` now"),
                 ("We meet 12345 tomorrow", "We meet 54321 tomorrow")] {
        #expect(candidates(pair.0, pair.1).isEmpty, Comment(rawValue: pair.1))
    }
    #expect(candidates("We meet Cartick.", "We meet Karthik.").count == 1)
}

@Test func unicodeWordsAndDictionaryValidation() {
    #expect(candidates("Please meet Josee tomorrow", "Please meet José tomorrow").first?.corrected == "José")
    #expect(CustomVocabulary.key("  O’Connor  ") == CustomVocabulary.key("o'connor"))
    #expect(CustomVocabulary.key("Jose\u{301}") == CustomVocabulary.key("José"))
    for word in ["Karthik", "Wispr Flow", "O’Connor", "Jean-Luc", "张伟"] { #expect(CustomVocabulary.valid(word)) }
    for word in ["", "  ", "x.com", "a@b", "abc123", "five words are too many", String(repeating: "x", count: 61)] { #expect(!CustomVocabulary.valid(word)) }
}

@Test func contentRewritesAreNotVocabularyCorrections() {
    for pair in [("We use Postgres today.", "We use Supabase today."),
                 ("Please meet Cartick tomorrow.", "Please meet Supabase tomorrow."),
                 ("We use React today.", "We use Svelte today."),
                 ("We need an analytics dashboard.", "We need a Supabase dashboard.")] {
        #expect(candidates(pair.0, pair.1).isEmpty, Comment(rawValue: pair.1))
    }
    let strong = WordCorrection(original: "Cartick", corrected: "Karthik")
    let uncertain = WordCorrection(original: "Mira", corrected: "Nira")
    let unrelated = WordCorrection(original: "Postgres", corrected: "Supabase")
    #expect(CorrectionEvidence.strength(strong) == .strong)
    #expect(CorrectionEvidence.strength(uncertain) == .plausible)
    #expect(CorrectionEvidence.strength(unrelated) == .unrelated)
    #expect(CorrectionEvidence.filter([strong, uncertain, unrelated], judgments: nil) == [strong])
    #expect(CorrectionEvidence.filter([strong, uncertain, unrelated], judgments: [false, true, true]) == [uncertain])
    #expect(CorrectionEvidence.filter([uncertain], judgments: []) == [])
}

@Test func passageRequiresObservedPasteAndRejectsChangesOutsideSpan() throws {
    let before = "🦋 Before OLD after."
    let selection = (before as NSString).range(of: "OLD")
    var passage = try #require(CorrectionPassage(before: before, selection: selection, dictated: "Meet Cartick"))
    #expect(passage.sample(before, elapsed: 0.1) == .waiting)
    #expect(passage.sample("🦋 Before Meet Cartick after.", elapsed: 0.2) == .passage("Meet Cartick"))
    #expect(passage.sample("🦋 Before Meet Karthik after.", elapsed: 1) == .passage("Meet Karthik"))
    #expect(passage.sample("🐝 Before Meet Karthik after.", elapsed: 2) == .stop)
    #expect(passage.sample("🦋 Before Meet Karthik changed.", elapsed: 2) == .stop)
}

@Test func passageStopsForMissingTextClearTimeoutAndInvalidRanges() throws {
    func fresh() throws -> CorrectionPassage { try #require(CorrectionPassage(before: "", selection: NSRange(location: 0, length: 0), dictated: "Cartick")) }
    var missing = try fresh(); #expect(missing.sample(nil, elapsed: 0) == .stop)
    var unobserved = try fresh(); #expect(unobserved.sample("Karthik", elapsed: 2) == .stop)
    var expired = try fresh(); #expect(expired.sample("Cartick", elapsed: 60) == .stop)
    var cleared = try fresh()
    #expect(cleared.sample("Cartick", elapsed: 0) == .passage("Cartick"))
    #expect(cleared.sample("", elapsed: 1) == .stop)
    #expect(CorrectionPassage(before: "🦋", selection: NSRange(location: 1, length: 0), dictated: "name") == nil)
    #expect(CorrectionPassage(before: "text", selection: NSRange(location: 10, length: 0), dictated: "name") == nil)
}

@Test func dictionaryStorageRoundTripsAndKeepsCorruptData() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try CustomDictionaryStore(root: root)
    #expect(try store.load().isEmpty)
    let words = [CustomWord(word: "Karthik", original: "Cartick", status: .possible, observations: [UUID()]), CustomWord(word: "Supabase", status: .approved)]
    try store.save(words)
    #expect(try store.load() == words)
    let mode = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? Int
    #expect(mode == 0o600)
    let corrupt = Data("not json".utf8); try corrupt.write(to: store.file)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try Data(contentsOf: store.file) == corrupt)
}
