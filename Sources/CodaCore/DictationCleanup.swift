import Foundation

public enum DictationCleanupMode: String, Codable, CaseIterable, Sendable { case none, light, smart }
public struct DictationCleanupResult: Equatable, Sendable {
    public let raw: String
    public let text: String
    public var changed: Bool { raw != text }
}

/// Clean-room, deterministic Light mode. No model, app context, or command execution.
/// Limited grammars reduce accidental edits; None remains the exact-text option.
public enum DictationCleanup {
    public static func apply(_ raw: String, mode: DictationCleanupMode) -> DictationCleanupResult {
        guard mode == .light, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              raw.utf16.count <= 20_000 else { return .init(raw: raw, text: raw) }
        // A safe fallback is preferable to changing quoted speech, identifiers, URLs or code.
        guard !matches(raw, #"["“”‘’`\\]|https?://|\b[\w]+[./@][\w]+"#) else { return .init(raw: raw, text: raw) }
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cue = #"(?:no\s*,?\s+actually|actually|sorry|I\s+mean|scratch\s+that)"#
        let day = #"(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)"#
        let number = #"(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|[0-9]+(?:\.[0-9]+)?)"#
        text = replace(text, #"\b"# + day + #"\s*,?\s+"# + cue + #"\s*,?\s+("# + day + #")\b"#, "$1")
        // Require the same unit/noun on both sides; never delete an unrelated clause.
        text = replace(text, #"\b"# + number + #"\s+([A-Za-z]+)\s*,?\s+"# + cue + #"\s*,?\s+("# + number + #"\s+\1)\b"#, "$2")
        text = replace(text, #"\b"# + number + #"\s*,?\s+"# + cue + #"\s*,?\s+("# + number + #")\b"#, "$1")
        let color = #"(?:blue|green|red|yellow|black|white|orange|purple|pink|brown|gray|grey)"#
        // Bare 'no' can mean exclusion. Require an explicit restatement cue.
        text = replace(text, #"\b(bring|take|use|choose|pick|send|order)\s+(?:the\s+)?"# + color + #"\s+([A-Za-z]+)\s*,?\s+(?:scratch\s+that|I\s+mean)\s*,?\s+((?:the\s+)?"# + color + #"\s+\2)\b"#, "$1 $3")
        // Spoken layout/punctuation and ordinal words also occur in literal prose.
        // Without an explicit separate formatting mode, preserve them verbatim.
        if text != raw {
            text = replace(text, #"[ \t]+"#, " ").trimmingCharacters(in: .whitespacesAndNewlines)
            text = capitalizeKnownStarts(text)
        }
        // Never turn a non-empty dictation into an empty paste.
        if text.isEmpty { text = raw }
        return .init(raw: raw, text: text)
    }
    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func replace(_ text: String, _ pattern: String, _ replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
    }
    private static func capitalizeKnownStarts(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            guard matches(line, #"^(send|book|bring|take|use|choose|pick|order|hello|hi|dear|can|could|would|will|please|i)\b"#), let first = line.first else { return line }
            return String(first).uppercased() + line.dropFirst()
        }.joined(separator: "\n")
    }
}
