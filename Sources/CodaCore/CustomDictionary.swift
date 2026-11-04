import Foundation

public struct WordCorrection: Equatable, Sendable {
    public var original: String
    public var corrected: String
    public init(original: String, corrected: String) { self.original = original; self.corrected = corrected }
}

/// A replacement must plausibly repair recognition of the same spoken term.
/// This is an evidence gate, not proof of intent; ambiguous pairs need a local
/// contextual judgment and all surviving words still require user approval.
public enum CorrectionEvidence {
    public enum Strength: Equatable, Sendable { case strong, plausible, unrelated }
    public static func strength(_ correction: WordCorrection) -> Strength {
        let a = compact(correction.original), b = compact(correction.corrected)
        guard min(a.count, b.count) >= 3 else { return .unrelated }
        if a == b { return .strong }
        let ratio = Double(distance(a, b)) / Double(max(a.count, b.count))
        let phoneticA = pronunciation(a), phoneticB = pronunciation(b)
        if ratio <= 0.3 && phoneticA.first == phoneticB.first || (phoneticA == phoneticB && ratio <= 0.55) { return .strong }
        let skeletonA = phoneticA.filter { !"aeiouy".contains($0) }, skeletonB = phoneticB.filter { !"aeiouy".contains($0) }
        if ratio <= 0.3 || a.first == b.first && ratio <= 0.45 { return .plausible }
        if skeletonA.count >= 2, skeletonA == skeletonB, ratio <= 0.6 { return .plausible }
        return .unrelated
    }
    public static func filter(_ corrections: [WordCorrection], judgments: [Bool]?) -> [WordCorrection] {
        corrections.enumerated().compactMap { index, correction in
            let evidence = strength(correction)
            guard evidence != .unrelated else { return nil }
            if let judgments, judgments.count == corrections.count { return judgments[index] ? correction : nil }
            return evidence == .strong ? correction : nil
        }
    }
    private static func compact(_ value: String) -> String {
        let letters = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).filter(\.isLetter)
        return letters.reduce(into: "") { if $0.last != $1 { $0.append($1) } }
    }
    private static func pronunciation(_ value: String) -> String {
        var text = value
        for (from, to) in [("ph", "f"), ("ck", "k"), ("qu", "k"), ("wh", "w"), ("th", "t"), ("c", "k"), ("q", "k")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return text
    }
    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var row = [i + 1] + [Int](repeating: 0, count: b.count)
            for (j, y) in b.enumerated() { row[j + 1] = min(row[j] + 1, previous[j + 1] + 1, previous[j] + (x == y ? 0 : 1)) }
            previous = row
        }
        return previous[b.count]
    }
}

public struct CustomWord: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case possible, approved, dismissed }
    public var id: UUID
    public var word: String
    public var original: String?
    public var status: Status
    public var observations: [UUID]
    /// User-approved misrecognitions replaced by `word` after transcription.
    /// Absent in dictionaries written before sound-alike corrections existed.
    public var heardAs: [String]
    public init(id: UUID = UUID(), word: String, original: String? = nil, status: Status, observations: [UUID] = [], heardAs: [String] = []) {
        self.id = id; self.word = word; self.original = original; self.status = status; self.observations = observations; self.heardAs = heardAs
    }
    private enum CodingKeys: String, CodingKey { case id, word, original, status, observations, heardAs }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id); word = try values.decode(String.self, forKey: .word)
        original = try values.decodeIfPresent(String.self, forKey: .original); status = try values.decode(Status.self, forKey: .status)
        observations = try values.decode([UUID].self, forKey: .observations)
        heardAs = try values.decodeIfPresent([String].self, forKey: .heardAs) ?? []
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(word, forKey: .word)
        try values.encodeIfPresent(original, forKey: .original); try values.encode(status, forKey: .status)
        try values.encode(observations, forKey: .observations)
        if !heardAs.isEmpty { try values.encode(heardAs, forKey: .heardAs) }
    }
}

public enum CustomVocabulary {
    public static func key(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
    public static func cleaned(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    public static func valid(_ word: String) -> Bool {
        !word.isEmpty && word.count <= 60 && word.split(separator: " ").count <= 4 &&
            word.range(of: #"^[\p{L}\p{M}]+(?:['’\-][\p{L}\p{M}]+)*(?: [\p{L}\p{M}]+(?:['’\-][\p{L}\p{M}]+)*)*$"#, options: .regularExpression) != nil
    }
}

/// Only dictionary entries and correction pairs are persisted, never field snapshots.
public struct CustomDictionaryStore {
    public let file: URL
    public init(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        file = root.appendingPathComponent("words.json")
    }
    public func load() throws -> [CustomWord] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let words = try JSONDecoder().decode([CustomWord].self, from: Data(contentsOf: file))
        guard words.allSatisfy({ CustomVocabulary.valid($0.word) }), Set(words.map { CustomVocabulary.key($0.word) }).count == words.count,
              Set(words.map(\.id)).count == words.count else { throw CocoaError(.fileReadCorruptFile) }
        // A hand-edited variant must not make the whole dictionary unreadable:
        // keep only variants that could have been saved through the app.
        return words.map { word in
            var word = word, seen = Set<String>()
            word.heardAs = word.heardAs.filter { CustomVocabulary.valid($0) && $0 != word.word && seen.insert(CustomVocabulary.key($0)).inserted }
                .prefix(SoundAlikeCorrections.variantLimit).map { $0 }
            return word
        }
    }
    public func save(_ words: [CustomWord]) throws {
        try JSONEncoder().encode(words).write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

/// Matches word runs rather than character keystrokes, so split/join corrections
/// such as "supper base" -> "Supabase" remain one suggestion.
public enum CorrectionCandidates {
    private struct Token { let text: String; let range: Range<String.Index> }
    public static func extract(original: String, edited: String, isCommon: (String) -> Bool) -> [WordCorrection] {
        guard original.count <= 4000, edited.count <= 4000 else { return [] }
        let old = tokens(original), new = tokens(edited)
        guard !old.isEmpty, !new.isEmpty, old.count <= 512, new.count <= 512 else { return [] }
        let a = old.map { CustomVocabulary.key($0.text) }, b = new.map { CustomVocabulary.key($0.text) }
        // Bounded LCS alignment. Matching words anchor changes inside the passage.
        let width = b.count + 1
        var lengths = [Int](repeating: 0, count: (a.count + 1) * width)
        for i in (0..<a.count).reversed() {
            for j in (0..<b.count).reversed() {
                lengths[i * width + j] = a[i] == b[j] ? 1 + lengths[(i + 1) * width + j + 1]
                    : max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
            }
        }
        let matched = lengths[0]
        guard min(a.count, b.count) < 4 || matched * 2 >= max(a.count, b.count) else { return [] }
        var anchors: [(Int, Int)] = []; var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { anchors.append((i, j)); i += 1; j += 1 }
            else if lengths[(i + 1) * width + j] >= lengths[i * width + j + 1] { i += 1 }
            else { j += 1 }
        }
        anchors.append((a.count, b.count))
        var oldStart = 0, newStart = 0, changes = 0
        var result: [WordCorrection] = []
        for (oldEnd, newEnd) in anchors {
            defer { oldStart = oldEnd + 1; newStart = newEnd + 1 }
            guard oldEnd > oldStart || newEnd > newStart else { continue }
            changes += 1
            guard changes <= 4 else { return [] }
            // Added prose, deletions and long rewrites are not spelling evidence.
            guard oldEnd > oldStart, newEnd > newStart, oldEnd - oldStart <= 4, newEnd - newStart <= 4 else { continue }
            let before = String(original[old[oldStart].range.lowerBound..<old[oldEnd - 1].range.upperBound])
            let after = CustomVocabulary.cleaned(String(edited[new[newStart].range.lowerBound..<new[newEnd - 1].range.upperBound]))
            guard CustomVocabulary.valid(before), CustomVocabulary.valid(after), CustomVocabulary.key(before) != CustomVocabulary.key(after),
                  !new[newStart..<newEnd].allSatisfy({ isCommon($0.text) }),
                  !embeddedInIdentifier(edited, range: new[newStart].range.lowerBound..<new[newEnd - 1].range.upperBound),
                  !embeddedInIdentifier(original, range: old[oldStart].range.lowerBound..<old[oldEnd - 1].range.upperBound)
            else { continue }
            let correction = WordCorrection(original: before, corrected: after)
            guard CorrectionEvidence.strength(correction) != .unrelated else { continue }
            result.append(correction)
        }
        return result
    }
    private static func tokens(_ text: String) -> [Token] {
        let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}]+(?:['’\-][\p{L}\p{M}\p{N}]+)*"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range, in: text) else { return nil }
            return Token(text: String(text[range]), range: range)
        }
    }
    private static func embeddedInIdentifier(_ text: String, range: Range<String.Index>) -> Bool {
        let disallowed = "@/\\_#`=:+~"
        let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
        let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
        if before.map({ disallowed.contains($0) || $0 == "." }) == true || after.map({ disallowed.contains($0) }) == true { return true }
        // A sentence-ending period is fine; a domain or filename is not.
        if after == "." {
            let next = text.index(after: range.upperBound)
            if next < text.endIndex && (text[next].isLetter || text[next].isNumber) { return true }
        }
        return false
    }
}

/// An ephemeral field snapshot. Prefix/suffix anchors reject edits outside the
/// inserted span. Learning cannot start until the exact paste is observed.
public struct CorrectionPassage: Sendable {
    public enum Sample: Equatable, Sendable { case waiting, passage(String), stop }
    private let prefix: String
    private let suffix: String
    private let expected: String
    private var observedPaste = false
    public init?(before: String, selection: NSRange, dictated: String) {
        guard before.utf16.count <= 32000, dictated.count <= 4000, !dictated.isEmpty,
              let range = Range(selection, in: before),
              let expected = PlainTextInsertion.replacing(before, range: selection, with: dictated) else { return nil }
        prefix = String(before[..<range.lowerBound]); suffix = String(before[range.upperBound...]); self.expected = expected
    }
    public mutating func sample(_ value: String?, elapsed: TimeInterval) -> Sample {
        guard elapsed < 60, let value, value.utf16.count <= 36000 else { return .stop }
        if !observedPaste {
            guard value == expected else { return elapsed < 2 ? .waiting : .stop }
            observedPaste = true
        }
        guard value.hasPrefix(prefix), value.hasSuffix(suffix), value.count >= prefix.count + suffix.count else { return .stop }
        let passage = String(value.dropFirst(prefix.count).dropLast(suffix.count))
        guard !passage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, passage.count <= 4000 else { return .stop }
        return .passage(passage)
    }
}
