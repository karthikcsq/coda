import Foundation
import Testing
@testable import CodaCore

private let entries = [
    CustomWord(word: "LeetCode", status: .approved, heardAs: ["lead code", "leet code"]),
    CustomWord(word: "Wispr Flow", status: .approved, heardAs: ["Whisperflow", "whisper flow"]),
    CustomWord(word: "Google Meet", status: .approved, heardAs: ["Google Me"]),
    CustomWord(word: "LaTeX", status: .approved, heardAs: ["latex"]),
    CustomWord(word: "O'Neill", status: .approved, heardAs: ["o'neil"]),
    CustomWord(word: "Supabase", original: "supper base", status: .possible, heardAs: ["supper base"]),
    CustomWord(word: "Karthik", status: .dismissed, heardAs: ["cartick"])
]
private func fix(_ text: String) -> String { SoundAlikeCorrections.apply(text, rules: SoundAlikeCorrections.rules(entries)).text }

@Test func soundAlikeReplacesWholeWordsAndPhrasesCaseInsensitively() {
    #expect(fix("I practice lead code daily") == "I practice LeetCode daily")
    #expect(fix("Lead Code first. Then leet  code.") == "LeetCode first. Then LeetCode.")
    #expect(fix("I use whisperflow and Whisper Flow.") == "I use Wispr Flow and Wispr Flow.")
    #expect(fix("Join the google me call (latex), then later.") == "Join the Google Meet call (LaTeX), then later.")
    #expect(fix("lead code's editor") == "LeetCode's editor")
    #expect(fix("Ask o’neil today") == "Ask O'Neill today")
    let result = SoundAlikeCorrections.apply("lead code, lead code and latex", rules: SoundAlikeCorrections.rules(entries))
    #expect(result.applied.map(\.replacement) == ["LeetCode", "LaTeX"])
}

@Test func soundAlikeRespectsWordBoundaries() {
    for text in ["misleading code", "leadcode", "lead codes", "lead-code", "pre-lead code", "Google Meet",
                 "Google Meetup", "latexes", "the lead coder"] {
        #expect(fix(text) == text, Comment(rawValue: text))
    }
    // Already-correct spelling is not reported as a change.
    #expect(SoundAlikeCorrections.apply("LaTeX and LeetCode", rules: SoundAlikeCorrections.rules(entries)).applied.isEmpty)
}

@Test func soundAlikeNeverRewritesQuotesCodeOrLinks() {
    for text in ["He said \"lead code\" exactly", "He said “lead code” exactly", "He said ‘lead code’ exactly",
                 "He said 'lead code' exactly", "Run `latex main` now", "```\nlatex build\n```",
                 "Open https://example.com/latex now", "Visit www.latex.org", "Mail latex@example.com",
                 "Edit /Users/me/latex today", "Edit ~/latex today", "Open latex.tex", "Set latex_mode on",
                 "Set latex=true", "Quote \"unfinished lead code"] {
        #expect(fix(text) == text, Comment(rawValue: text))
    }
    // Only the protected span is skipped; the rest of the sentence is still corrected.
    #expect(fix("Use latex, not \"latex\".") == "Use LaTeX, not \"latex\".")
    #expect(fix("Open latex.tex in latex") == "Open latex.tex in LaTeX")
}

@Test func soundAlikeRulesComeOnlyFromApprovedEntries() {
    let rules = SoundAlikeCorrections.rules(entries)
    #expect(!rules.contains { $0.replacement == "Supabase" || $0.replacement == "Karthik" })
    #expect(fix("supper base and cartick") == "supper base and cartick")
    #expect(SoundAlikeCorrections.apply("lead code", rules: []).text == "lead code")
    // A variant claimed twice keeps the first entry; an exact copy of the word is ignored.
    let clash = [CustomWord(word: "Alpha", status: .approved, heardAs: ["alfa", "Alpha"]),
                 CustomWord(word: "Alfa Romeo", status: .approved, heardAs: ["Alfa"])]
    #expect(SoundAlikeCorrections.rules(clash) == [.init(heard: "alfa", replacement: "Alpha")])
}

@Test func soundAlikeVariantValidation() {
    let words = [CustomWord(word: "LeetCode", status: .approved, heardAs: ["lead code"]),
                 CustomWord(word: "Wispr Flow", status: .approved)]
    #expect(SoundAlikeCorrections.parse(" lead  code, Lead Code;\nleet code ,, ") == ["lead code", "leet code"])
    #expect(SoundAlikeCorrections.problem(["latex"], word: "LaTeX", id: nil, in: words) == nil)
    #expect(SoundAlikeCorrections.problem(["LaTeX"], word: "LaTeX", id: nil, in: words) == .sameAsWord("LaTeX"))
    #expect(SoundAlikeCorrections.problem(["late.x"], word: "LaTeX", id: nil, in: words) == .invalid("late.x"))
    #expect(SoundAlikeCorrections.problem(["one two three four five"], word: "LaTeX", id: nil, in: words) != nil)
    #expect(SoundAlikeCorrections.problem(["Lead Code"], word: "LaTeX", id: nil, in: words) == .conflict("Lead Code", word: "LeetCode"))
    #expect(SoundAlikeCorrections.problem(["wispr flow"], word: "LaTeX", id: nil, in: words) == .conflict("wispr flow", word: "Wispr Flow"))
    // An entry may keep its own variants when edited.
    #expect(SoundAlikeCorrections.problem(["lead code"], word: "LeetCode", id: words[0].id, in: words) == nil)
    #expect(SoundAlikeCorrections.problem((1...7).map { "variant\(String(repeating: "a", count: $0))" }, word: "X", id: nil, in: words) == .tooMany)
}

@Test func dictionaryFilesWithoutVariantsStillLoadAndVariantsPersist() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try CustomDictionaryStore(root: root)
    let id = UUID(), session = UUID()
    // The exact shape written before heard-as variants existed.
    let legacy = #"[{"id":"\#(id.uuidString)","word":"LeetCode","original":"lead code","status":"approved","observations":["\#(session.uuidString)"]},"# +
        #"{"id":"\#(UUID().uuidString)","word":"Supabase","status":"possible","observations":[]}]"#
    try Data(legacy.utf8).write(to: store.file)
    let loaded = try store.load()
    #expect(loaded.map(\.word) == ["LeetCode", "Supabase"] && loaded.allSatisfy(\.heardAs.isEmpty))
    #expect(loaded[0].original == "lead code" && loaded[0].observations == [session])
    // Entries without variants are written without the new key.
    try store.save(loaded)
    #expect(!(try String(contentsOf: store.file, encoding: .utf8)).contains("heardAs"))
    var updated = loaded; updated[0].heardAs = ["lead code", "leet code"]
    try store.save(updated)
    #expect(try store.load()[0].heardAs == ["lead code", "leet code"])
    // A hand-edited invalid variant is dropped rather than making the file unreadable.
    let edited = #"[{"id":"\#(id.uuidString)","word":"LeetCode","status":"approved","observations":[],"heardAs":["lead code","https://x.y","LeetCode","Lead Code"]}]"#
    try Data(edited.utf8).write(to: store.file)
    #expect(try store.load()[0].heardAs == ["lead code"])
}

@Test func proposalsCarryWordAlignedWindowsForReview() throws {
    let rules = SoundAlikeCorrections.rules(entries)
    let text = "Talk to you later. I compile the latex file and join the google me call."
    let found = SoundAlikeCorrections.proposals(text, rules: rules)
    #expect(found.map(\.rule.replacement) == ["LaTeX", "Google Meet"]) // "later" is not a listed variant.
    let first = try #require(found.first)
    #expect(first.heardPassage == text)
    #expect(first.fixedPassage == "Talk to you later. I compile the LaTeX file and join the google me call.")
    // Long dictations are cut to whole words around the match.
    let long = String(repeating: "alpha beta ", count: 60) + "open latex now " + String(repeating: "gamma delta ", count: 60)
    let window = try #require(SoundAlikeCorrections.proposals(long, rules: rules, window: 40).first)
    #expect(window.heardPassage.count <= 40 * 2 + 5 && window.heardPassage.contains("open latex now"))
    #expect(window.heardPassage.split(separator: " ").allSatisfy { ["alpha", "beta", "gamma", "delta", "open", "latex", "now"].contains($0) })
    #expect(window.fixedPassage == window.heardPassage.replacingOccurrences(of: "latex", with: "LaTeX"))
    // Review is bounded per dictation; extra matches stay as recognized.
    let many = Array(repeating: "latex", count: 9).joined(separator: " and ")
    #expect(SoundAlikeCorrections.proposals(many, rules: rules).count == SoundAlikeCorrections.proposalLimit)
}

@Test func onlyAcceptedProposalsAreApplied() {
    let rules = SoundAlikeCorrections.rules(entries)
    let text = "Can you google me a recipe before the google me call?"
    let found = SoundAlikeCorrections.proposals(text, rules: rules)
    #expect(found.count == 2)
    let result = SoundAlikeCorrections.apply(text, proposals: found, accepted: [false, true])
    #expect(result.text == "Can you google me a recipe before the Google Meet call?")
    #expect(result.applied.map(\.replacement) == ["Google Meet"])
    #expect(SoundAlikeCorrections.apply(text, proposals: found, accepted: [false, false]).text == text)
    // A verdict that does not line up with the proposals changes nothing.
    #expect(SoundAlikeCorrections.apply(text, proposals: found, accepted: [true]).text == text)
}
