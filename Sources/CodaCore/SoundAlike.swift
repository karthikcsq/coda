import Foundation

/// A user-approved "heard as" variant for a custom word, such as
/// "lead code" -> "LeetCode". Rules come only from approved dictionary entries.
public struct SoundAlikeRule: Equatable, Sendable {
    public let heard: String
    public let replacement: String
    public init(heard: String, replacement: String) { self.heard = heard; self.replacement = replacement }
}

public struct SoundAlikeResult: Equatable, Sendable {
    public let text: String
    /// The rules that changed the text, once each, in first-occurrence order.
    public let applied: [SoundAlikeRule]
    public init(text: String, applied: [SoundAlikeRule]) { self.text = text; self.applied = applied }
}

/// One exact match of a heard-as variant, for the local model to review in
/// context. `heardPassage` and `fixedPassage` are the same bounded window
/// around the match, as recognized and with the custom term.
public struct SoundAlikeProposal: Equatable, Sendable {
    public let range: NSRange
    public let rule: SoundAlikeRule
    public let heardPassage: String
    public let fixedPassage: String
}

/// Exact matching proposes; a model reviews. A variant only ever becomes a
/// proposal where it matches whole words outside quoted text, code, URLs,
/// email addresses and path- or identifier-like tokens. Nothing is replaced
/// unless its proposal is accepted.
public enum SoundAlikeCorrections {
    public static let variantLimit = 6
    /// Proposals reviewed per dictation; further matches stay as recognized.
    public static let proposalLimit = 6

    public static func rules(_ words: [CustomWord]) -> [SoundAlikeRule] {
        var seen = Set<String>()
        return words.filter { $0.status == .approved }.flatMap { word in
            word.heardAs.compactMap { variant -> SoundAlikeRule? in
                let key = CustomVocabulary.key(variant)
                // A case-only variant ("latex" -> "LaTeX") fixes capitalization.
                guard CustomVocabulary.valid(variant), variant != word.word, seen.insert(key).inserted else { return nil }
                return SoundAlikeRule(heard: variant, replacement: word.word)
            }
        }
    }

    public static func proposals(_ text: String, rules: [SoundAlikeRule], window: Int = 160) -> [SoundAlikeProposal] {
        guard !rules.isEmpty, !text.isEmpty, text.utf16.count <= 20_000 else { return [] }
        var byKey: [String: SoundAlikeRule] = [:]
        for rule in rules where byKey[matchKey(rule.heard)] == nil { byKey[matchKey(rule.heard)] = rule }
        // Longest phrase first, so "google me" never pre-empts "google meet up".
        let ordered = byKey.values.sorted {
            let a = $0.heard.split(separator: " ").count, b = $1.heard.split(separator: " ").count
            return a != b ? a > b : $0.heard.count > $1.heard.count
        }
        let alternation = ordered.map { rule in
            rule.heard.split(whereSeparator: \.isWhitespace).map { word in
                word.map { "'’".contains($0) ? "['’]" : NSRegularExpression.escapedPattern(for: String($0)) }.joined()
            }.joined(separator: #"[ \t]+"#)
        }.joined(separator: "|")
        let pattern = #"(?<![\p{L}\p{M}\p{N}_'’\-.@/\\])(?:"# + alternation + #")"# +
            #"(?:(?=['’]s(?![\p{L}\p{M}\p{N}]))|(?![\p{L}\p{M}\p{N}_@/\\]|['’\-.][\p{L}\p{M}\p{N}]))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let source = text as NSString
        let protected = protectedRanges(text)
        var result: [SoundAlikeProposal] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let range = match.range, heard = source.substring(with: range)
            guard !protected.contains(where: { NSIntersectionRange($0, range).length > 0 }),
                  let rule = byKey[matchKey(heard)], heard != rule.replacement else { continue }
            guard result.count < proposalLimit else { break }
            // Whole words of context on each side, bounded for the model.
            var lower = max(0, range.location - window), upper = min(source.length, range.location + range.length + window)
            while lower > 0, !isSpace(source.character(at: lower - 1)) { lower += 1; if lower >= range.location { break } }
            while upper < source.length, !isSpace(source.character(at: upper)) { upper -= 1; if upper <= range.location + range.length { break } }
            let before = source.substring(with: NSRange(location: lower, length: range.location - lower))
            let after = source.substring(with: NSRange(location: range.location + range.length, length: upper - range.location - range.length))
            let trim = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
            result.append(.init(range: range, rule: rule, heardPassage: trim(before + heard + after), fixedPassage: trim(before + rule.replacement + after)))
        }
        return result
    }

    /// Applies only the proposals marked accepted; `accepted` pairs with `proposals`.
    public static func apply(_ text: String, proposals: [SoundAlikeProposal], accepted: [Bool]) -> SoundAlikeResult {
        guard proposals.count == accepted.count else { return .init(text: text, applied: []) }
        let source = text as NSString
        var output = "", cursor = 0, applied: [SoundAlikeRule] = []
        for (proposal, ok) in zip(proposals, accepted) where ok {
            guard proposal.range.location >= cursor, NSMaxRange(proposal.range) <= source.length else { continue }
            output += source.substring(with: NSRange(location: cursor, length: proposal.range.location - cursor)) + proposal.rule.replacement
            cursor = NSMaxRange(proposal.range)
            if !applied.contains(proposal.rule) { applied.append(proposal.rule) }
        }
        guard !applied.isEmpty else { return .init(text: text, applied: []) }
        return .init(text: output + source.substring(from: cursor), applied: applied)
    }

    /// Accept-all, for testing what matching alone would propose.
    static func apply(_ text: String, rules: [SoundAlikeRule]) -> SoundAlikeResult {
        let found = proposals(text, rules: rules)
        return apply(text, proposals: found, accepted: found.map { _ in true })
    }

    private static func isSpace(_ unit: unichar) -> Bool {
        unit == 32 || unit == 9 || unit == 10 || unit == 13
    }

    /// Spans that must stay literal. Unclosed quotes and code protect to the end.
    static func protectedRanges(_ text: String) -> [NSRange] {
        let patterns = [
            #"```[\s\S]*?(?:```|$)"#, #"`[^`]*(?:`|$)"#,
            #""[^"]*(?:"|$)"#, #"“[^”]*(?:”|$)"#, #"‘[^’]*(?:’|$)"#,
            #"(?<![\p{L}\p{N}])'[^'\n]+'(?![\p{L}\p{N}])"#,
            #"\b[A-Za-z][A-Za-z0-9+.\-]*://\S*"#, #"\bwww\.\S*"#, #"\S+@\S+"#,
            #"(?<!\S)[~.]{0,2}/\S*"#,
            // Identifier-like tokens: file.swift, a_b, key=value, C:\path, <tag>, {x}.
            #"\S*(?:[\p{L}\p{N}][./\\:@#=+~][\p{L}\p{N}]|[_{}\[\]<>|^*$\\=])\S*"#
        ]
        let range = NSRange(location: 0, length: (text as NSString).length)
        return patterns.flatMap { pattern -> [NSRange] in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            return regex.matches(in: text, range: range).map(\.range).filter { $0.length > 0 }
        }
    }

    /// Normalizes user-entered or edited variants: split on commas, semicolons
    /// and new lines, clean whitespace, drop duplicates (case-insensitively).
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: { ",;\n".contains($0) }).map { CustomVocabulary.cleaned(String($0)) }
            .filter { !$0.isEmpty && seen.insert(CustomVocabulary.key($0)).inserted }
    }

    public enum Problem: Equatable, Sendable {
        case invalid(String)
        case sameAsWord(String)
        case tooMany
        /// The variant is another custom word, or already a variant of one.
        case conflict(String, word: String)
    }

    /// Checks variants for an entry `id` (nil when adding) against the other approved words.
    public static func problem(_ variants: [String], word: String, id: UUID?, in words: [CustomWord]) -> Problem? {
        guard variants.count <= variantLimit else { return .tooMany }
        let others = words.filter { $0.id != id && $0.status == .approved }
        for variant in variants {
            let key = CustomVocabulary.key(variant)
            guard CustomVocabulary.valid(variant) else { return .invalid(variant) }
            guard variant != CustomVocabulary.cleaned(word) else { return .sameAsWord(variant) }
            if let other = others.first(where: { CustomVocabulary.key($0.word) == key || $0.heardAs.contains { CustomVocabulary.key($0) == key } }) {
                return .conflict(variant, word: other.word)
            }
        }
        return nil
    }

    private static func matchKey(_ value: String) -> String { CustomVocabulary.key(value) }
}
