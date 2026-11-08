import AppKit
import Observation
import CodaCore

@MainActor @Observable final class CustomDictionary {
    private(set) var words: [CustomWord] = []
    private(set) var error: String?
    private var store: CustomDictionaryStore?
    private let preview: Bool
    @ObservationIgnored var onPossibleWordsChanged: (() -> Void)?
    var learningEnabled: Bool {
        didSet { if !preview { UserDefaults.standard.set(learningEnabled, forKey: "dictationLearnWords") } }
    }
    var possible: [CustomWord] { words.filter { $0.status == .possible } }
    var approved: [CustomWord] { words.filter { $0.status == .approved }.sorted { $0.word.localizedStandardCompare($1.word) == .orderedAscending } }
    var vocabulary: [String] { approved.map(\.word) }
    /// Only approved entries with user-entered variants produce replacements.
    var soundAlikeRules: [SoundAlikeRule] { SoundAlikeCorrections.rules(approved) }

    init(root: URL? = nil, preview: Bool = false) {
        self.preview = preview
        learningEnabled = preview ? true : UserDefaults.standard.object(forKey: "dictationLearnWords") as? Bool ?? true
        let root = root ?? (preview ? FileManager.default.temporaryDirectory.appendingPathComponent("Coda-Dictionary-Preview-" + UUID().uuidString)
            : BuildIdentity.dataRoot.appendingPathComponent("Dictionary"))
        do {
            let storage = try CustomDictionaryStore(root: root)
            words = try storage.load(); store = storage
        } catch { self.error = "Could not read your dictionary. Its files were preserved. Reopen Coda after checking the dictionary folder." }
    }
    /// `heardAs` nil keeps the entry's current variants; an empty list clears them.
    @discardableResult func approve(_ id: UUID, spelling: String? = nil, heardAs: [String]? = nil) -> Bool {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return false }
        let word = CustomVocabulary.cleaned(spelling ?? words[index].word)
        let variants = heardAs.map { SoundAlikeCorrections.parse($0.joined(separator: ",")) } ?? words[index].heardAs
        guard validate(word, excluding: id), validate(variants, for: word, excluding: id) else { return false }
        var updated = words
        // A dismissed spelling can be restored explicitly, without duplicate entries.
        updated.removeAll { $0.id != id && CustomVocabulary.key($0.word) == CustomVocabulary.key(word) && $0.status == .dismissed }
        guard let target = updated.firstIndex(where: { $0.id == id }) else { return false }
        if CustomVocabulary.key(word) != CustomVocabulary.key(words[index].word) {
            updated.append(CustomWord(word: words[index].word, status: .dismissed))
        }
        updated[target].word = word; updated[target].status = .approved; updated[target].heardAs = variants
        return commit(updated)
    }
    @discardableResult func add(_ spelling: String, heardAs: [String] = []) -> Bool {
        let word = CustomVocabulary.cleaned(spelling)
        let variants = SoundAlikeCorrections.parse(heardAs.joined(separator: ","))
        guard validate(word, excluding: nil) else { return false }
        if let existing = words.first(where: { CustomVocabulary.key($0.word) == CustomVocabulary.key(word) }) {
            return approve(existing.id, spelling: word, heardAs: variants)
        }
        guard validate(variants, for: word, excluding: nil) else { return false }
        return commit(words + [CustomWord(word: word, status: .approved, heardAs: variants)])
    }
    /// Removing a word also stops its replacements; re-adding it starts clean.
    @discardableResult func dismiss(_ id: UUID) -> Bool {
        guard let index = words.firstIndex(where: { $0.id == id }) else { return false }
        var updated = words; updated[index].status = .dismissed; updated[index].heardAs = []
        return commit(updated)
    }
    /// Replace a session's evidence. An undo removes its pending suggestion;
    /// suggestions supported by another dictation remain available.
    func suggest(_ corrections: [WordCorrection], session: UUID) {
        guard learningEnabled else { return }
        let corrections = corrections.filter { CustomVocabulary.valid($0.corrected) && CustomVocabulary.valid($0.original) }
        let keys = Set(corrections.map { CustomVocabulary.key($0.corrected) })
        var updated = words
        for index in updated.indices where updated[index].status == .possible && !keys.contains(CustomVocabulary.key(updated[index].word)) {
            updated[index].observations.removeAll { $0 == session }
        }
        updated.removeAll { $0.status == .possible && $0.observations.isEmpty }
        for correction in corrections {
            let key = CustomVocabulary.key(correction.corrected)
            if let index = updated.firstIndex(where: { CustomVocabulary.key($0.word) == key }) {
                if updated[index].status == .possible && !updated[index].observations.contains(session) { updated[index].observations.append(session) }
            } else {
                updated.append(CustomWord(word: correction.corrected, original: correction.original, status: .possible, observations: [session]))
            }
        }
        if updated != words { _ = commit(updated) }
    }
    static func isCommon(_ word: String) -> Bool {
        let text = word.lowercased()
        let range = NSSpellChecker.shared.checkSpelling(of: text, startingAt: 0, language: nil, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location == NSNotFound
    }
    private func validate(_ word: String, excluding id: UUID?) -> Bool {
        guard CustomVocabulary.valid(word) else { error = "Use a word or phrase of up to 60 characters and four words. Letters, apostrophes and hyphens are supported."; return false }
        guard !words.contains(where: { $0.id != id && $0.status != .dismissed && CustomVocabulary.key($0.word) == CustomVocabulary.key(word) }) else {
            error = "That word is already in your dictionary."; return false
        }
        if let other = words.first(where: { $0.id != id && $0.status == .approved && $0.heardAs.contains { CustomVocabulary.key($0) == CustomVocabulary.key(word) } }) {
            error = "“\(word)” is listed as heard-as for \(other.word). Remove it there first."; return false
        }
        return true
    }
    private func validate(_ variants: [String], for word: String, excluding id: UUID?) -> Bool {
        switch SoundAlikeCorrections.problem(variants, word: word, id: id, in: words) {
        case nil: return true
        case .tooMany: error = "Use up to \(SoundAlikeCorrections.variantLimit) heard-as spellings per word."
        case .invalid(let variant): error = "“\(variant)” can't be a heard-as spelling. Use up to four words of letters, apostrophes and hyphens."
        case .sameAsWord(let variant): error = "“\(variant)” is already the word's own spelling."
        case .conflict(let variant, let other): error = "“\(variant)” is already used by \(other)."
        }
        return false
    }
    private func commit(_ updated: [CustomWord]) -> Bool {
        guard let store else { error = "Dictionary storage is unavailable. Existing files have not been overwritten."; return false }
        do {
            try store.save(updated); words = updated; error = nil
            onPossibleWordsChanged?()
            return true
        }
        catch { self.error = "Could not save your dictionary. Check storage and try again."; return false }
    }
}
