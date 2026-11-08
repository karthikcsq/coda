import Foundation

// Dictation personalization primitives: writing styles, per-app style rules and
// whole-utterance voice snippets. Everything here is deterministic and local.
// Nothing calls a model, rewrites wording, or executes commands.

// MARK: - Writing style

/// A surface-formatting choice applied to finished dictation text. Styles only
/// change whitespace, capitalization and terminal punctuation; they never add,
/// remove or reorder words, and never touch quoted text, code, URLs, paths or
/// identifier-like tokens.
public enum DictationWritingStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Leaves the text exactly as it arrives, i.e. as produced by the cleanup mode.
    /// (Raw recognition only when cleanup is None, where callers skip personalization.)
    case preserve
    /// Lowercase opener for a few conversational words; drops a lone final period.
    case casual
    /// Sentence capitals, standalone "I", and a final period when one is missing.
    case formal
    /// Tidy spacing, sentence capitals and "I"; never adds punctuation.
    case prompt

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .preserve: "Keep formatting"
        case .casual: "Casual"
        case .formal: "Formal"
        case .prompt: "Prompt"
        }
    }
    public var summary: String {
        switch self {
        case .preserve: "Keep the formatting produced by your cleanup mode."
        case .casual: "Relaxed messages: no closing period on a single sentence."
        case .formal: "Capitalized sentences with closing punctuation."
        case .prompt: "Clean spacing and capitals for AI prompts, without added punctuation."
        }
    }
}

public enum DictationStyleFormatter {
    /// Longer text is returned unchanged.
    public static let characterLimit = 20_000

    public static func apply(_ text: String, style: DictationWritingStyle) -> String {
        guard style != .preserve, !text.isEmpty, text.utf16.count <= characterLimit,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        var parts = segments(text)
        for index in parts.indices where !parts[index].protected { parts[index].text = tidySpacing(parts[index].text) }
        trimEdges(&parts)
        switch style {
        case .preserve: return text
        case .casual: casual(&parts)
        case .formal: capitalizeSentences(&parts); capitalizeI(&parts); addFinalPeriod(&parts)
        case .prompt: capitalizeSentences(&parts); capitalizeI(&parts)
        }
        let result = parts.map(\.text).joined()
        // Safety net: formatting must keep every word, in order, and never empty the text.
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, words(result) == words(text) else { return text }
        return result
    }

    /// Lowercased letter/number runs. Styles must leave this sequence unchanged.
    public static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    struct Part: Equatable { var text: String; var protected: Bool }

    static func segments(_ text: String) -> [Part] {
        let ns = text as NSString
        let ranges = SoundAlikeCorrections.protectedRanges(text).sorted { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in ranges {
            if let last = merged.last, range.location <= NSMaxRange(last) {
                merged[merged.count - 1] = NSRange(location: last.location, length: max(NSMaxRange(last), NSMaxRange(range)) - last.location)
            } else { merged.append(range) }
        }
        var parts: [Part] = [], cursor = 0
        for range in merged {
            if range.location > cursor { parts.append(Part(text: ns.substring(with: NSRange(location: cursor, length: range.location - cursor)), protected: false)) }
            parts.append(Part(text: ns.substring(with: range), protected: true))
            cursor = NSMaxRange(range)
        }
        if cursor < ns.length { parts.append(Part(text: ns.substring(from: cursor), protected: false)) }
        return parts
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func tidySpacing(_ text: String) -> String {
        var text = replace(text, #"[ \t]{2,}"#, " ")
        text = replace(text, #"[ \t]+\n"#, "\n")
        text = replace(text, #"\n{3,}"#, "\n\n")
        // "word ," -> "word,"; only after a letter/number so leading symbols stay put.
        return replace(text, #"(?<=[\p{L}\p{N}])[ \t]+(?=[,.;:!?](?:\s|$))"#, "")
    }

    private static func trimEdges(_ parts: inout [Part]) {
        if let first = parts.indices.first, !parts[first].protected {
            parts[first].text = String(parts[first].text.drop(while: \.isWhitespace))
        }
        if let last = parts.indices.last, !parts[last].protected {
            var text = parts[last].text
            while text.last?.isWhitespace == true { text.removeLast() }
            parts[last].text = text
        }
    }

    private static let abbreviations: Set<String> = ["etc", "vs", "approx", "incl", "cf", "eg", "ie"]

    private static func capitalizeSentences(_ parts: inout [Part]) {
        enum State { case start, terminal, mid }
        var state = State.start, word = ""
        for index in parts.indices {
            guard !parts[index].protected else { state = .mid; word = ""; continue }
            var out = ""
            for character in parts[index].text {
                if character.isLetter {
                    if state == .start && character.isLowercase { out += character.uppercased() } else { out.append(character) }
                    state = .mid; word.append(character); continue
                }
                out.append(character)
                if character == "\n" { state = .start }
                else if "!?".contains(character) { state = .terminal }
                else if character == "." { state = abbreviations.contains(word.lowercased()) ? .mid : .terminal }
                else if character.isWhitespace { if state == .terminal { state = .start } }
                else if character.isNumber { state = .mid }
                // Opening quotes, brackets and dashes keep the current state.
                if !character.isLetter { word = "" }
            }
            parts[index].text = out
        }
    }

    private static func capitalizeI(_ parts: inout [Part]) {
        for index in parts.indices where !parts[index].protected {
            parts[index].text = replace(parts[index].text, #"(?<![\p{L}\p{N}_'’\-])i(?=(?:['’](?:m|ve|ll|d))?(?![\p{L}\p{N}_'’\-]))"#, "I")
        }
    }

    private static func addFinalPeriod(_ parts: inout [Part]) {
        guard let last = parts.indices.last, !parts[last].protected,
              let final = parts[last].text.last, final.isLetter || final.isNumber else { return }
        parts[last].text.append(".")
    }

    private static let casualOpeners: Set<String> = ["ok", "okay", "yeah", "yes", "yep", "no", "nope", "so", "and", "but", "sure", "thanks", "hey", "hi", "sounds", "that", "this", "it", "just", "also", "well", "cool", "nice", "lol"]

    private static func casual(_ parts: inout [Part]) {
        // Lowercase a capitalized conversational opener ("Okay" -> "okay"); never names or "I".
        if let first = parts.indices.first, !parts[first].protected {
            let text = parts[first].text
            let opener = text.prefix(while: \.isLetter)
            if opener.count > 1, opener.first?.isUppercase == true, opener.dropFirst().allSatisfy(\.isLowercase),
               casualOpeners.contains(opener.lowercased()) {
                parts[first].text = opener.lowercased() + text.dropFirst(opener.count)
            }
        }
        // Drop the closing period only for a single sentence, never an ellipsis.
        let free = parts.filter { !$0.protected }.map(\.text).joined()
        guard let last = parts.indices.last, !parts[last].protected, parts[last].text.hasSuffix("."),
              !parts[last].text.hasSuffix(".."), free.filter({ ".!?".contains($0) }).count == 1 else { return }
        let before = parts[last].text.dropLast().last
        guard before?.isLetter == true || before?.isNumber == true else { return }
        parts[last].text.removeLast()
    }
}

// MARK: - Per-app rules

public struct DictationAppRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var bundleID: String
    /// Display name captured when the rule was created; informational only.
    public var appName: String?
    public var style: DictationWritingStyle
    public init(id: UUID = UUID(), bundleID: String, appName: String? = nil, style: DictationWritingStyle) {
        self.id = id; self.bundleID = bundleID; self.appName = appName; self.style = style
    }
}

public enum DictationBundleID {
    public static let limit = 255
    public static func cleaned(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    public static func key(_ value: String) -> String { cleaned(value).lowercased() }
    public static func valid(_ value: String) -> Bool {
        let value = cleaned(value)
        return value.utf8.count <= limit &&
            value.range(of: #"^[A-Za-z0-9][A-Za-z0-9\-]*(?:\.[A-Za-z0-9\-]+)+$"#, options: .regularExpression) != nil
    }
}

// MARK: - Voice snippets

/// Saying exactly `trigger` as a whole dictation inserts `expansion` instead.
/// Triggers never match inside longer dictations, and expansions are inserted
/// as plain text, never run.
public struct DictationSnippet: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var trigger: String
    public var expansion: String
    public init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id; self.trigger = trigger; self.expansion = expansion
    }
}

public enum DictationSnippets {
    public static let triggerCharacterLimit = 60
    public static let triggerWordLimit = 8
    public static let expansionCharacterLimit = 5_000
    public static let snippetLimit = 200

    private static let edges = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

    /// Display form: single spaces, outer whitespace removed; case kept.
    public static func cleanedTrigger(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Matching form: case-, whitespace- and edge-punctuation-insensitive.
    /// "Sign off." and "  sign   OFF " share a key; "sign-off" does not equal "sign off".
    public static func key(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: edges)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .lowercased()
    }

    /// The expansion for a whole utterance, or nil. An empty key never matches.
    public static func match(_ utterance: String, in snippets: [DictationSnippet]) -> DictationSnippet? {
        guard utterance.count <= triggerCharacterLimit * 2 else { return nil }
        let key = key(utterance)
        guard !key.isEmpty else { return nil }
        return snippets.first { !self.key($0.trigger).isEmpty && self.key($0.trigger) == key }
    }
}

// MARK: - Validation

public enum DictationPreferenceProblem: Error, Equatable, Sendable {
    case emptyTrigger
    case triggerTooLong
    case triggerNeedsLetters
    case triggerHasLineBreak
    case duplicateTrigger(existing: String)
    case emptyExpansion
    case expansionTooLong
    case tooManySnippets
    case invalidBundleID(String)
    case duplicateApp(String)
    case tooManyRules
    case notFound

    public var message: String {
        switch self {
        case .emptyTrigger: "Enter a phrase to say."
        case .triggerTooLong: "Use a phrase of up to \(DictationSnippets.triggerWordLimit) words and \(DictationSnippets.triggerCharacterLimit) characters."
        case .triggerNeedsLetters: "The phrase needs at least two letters or numbers."
        case .triggerHasLineBreak: "The phrase must be on one line."
        case .duplicateTrigger(let existing): "“\(existing)” already uses that phrase."
        case .emptyExpansion: "Enter the text to insert."
        case .expansionTooLong: "Inserted text can be up to \(DictationSnippets.expansionCharacterLimit) characters."
        case .tooManySnippets: "You can save up to \(DictationSnippets.snippetLimit) snippets."
        case .invalidBundleID(let value): "“\(value)” isn't an app bundle identifier, such as com.apple.mail."
        case .duplicateApp(let name): "\(name) already has a style."
        case .tooManyRules: "You can save up to \(DictationPreferenceSettings.ruleLimit) app styles."
        case .notFound: "That item no longer exists."
        }
    }
}

// MARK: - Settings

public struct DictationPreferenceSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let ruleLimit = 200

    public var version: Int
    /// Used for any app without its own rule.
    public var globalStyle: DictationWritingStyle
    public private(set) var appRules: [DictationAppRule]
    public private(set) var snippets: [DictationSnippet]

    public init(globalStyle: DictationWritingStyle = .preserve, appRules: [DictationAppRule] = [], snippets: [DictationSnippet] = []) {
        version = Self.currentVersion; self.globalStyle = globalStyle; self.appRules = appRules; self.snippets = snippets
    }

    /// The rule's style for an exact (case-insensitive) bundle ID, else the global style.
    public func style(forBundleID bundleID: String?) -> DictationWritingStyle {
        guard let bundleID, !DictationBundleID.cleaned(bundleID).isEmpty else { return globalStyle }
        let key = DictationBundleID.key(bundleID)
        return appRules.first { DictationBundleID.key($0.bundleID) == key }?.style ?? globalStyle
    }
    public func rule(forBundleID bundleID: String) -> DictationAppRule? {
        let key = DictationBundleID.key(bundleID)
        return appRules.first { DictationBundleID.key($0.bundleID) == key }
    }

    // MARK: Rules

    /// Adds a rule, or changes the style of the app's existing rule.
    @discardableResult
    public mutating func setRule(bundleID: String, appName: String? = nil, style: DictationWritingStyle) -> Result<DictationAppRule, DictationPreferenceProblem> {
        let cleaned = DictationBundleID.cleaned(bundleID)
        guard DictationBundleID.valid(cleaned) else { return .failure(.invalidBundleID(cleaned)) }
        if let index = appRules.firstIndex(where: { DictationBundleID.key($0.bundleID) == DictationBundleID.key(cleaned) }) {
            appRules[index].style = style
            if let appName = Self.cleanedName(appName) { appRules[index].appName = appName }
            return .success(appRules[index])
        }
        guard appRules.count < Self.ruleLimit else { return .failure(.tooManyRules) }
        let rule = DictationAppRule(bundleID: cleaned, appName: Self.cleanedName(appName), style: style)
        appRules.append(rule)
        return .success(rule)
    }

    @discardableResult
    public mutating func updateRule(_ id: UUID, bundleID: String? = nil, style: DictationWritingStyle? = nil) -> Result<DictationAppRule, DictationPreferenceProblem> {
        guard let index = appRules.firstIndex(where: { $0.id == id }) else { return .failure(.notFound) }
        var rule = appRules[index]
        if let bundleID {
            let cleaned = DictationBundleID.cleaned(bundleID)
            guard DictationBundleID.valid(cleaned) else { return .failure(.invalidBundleID(cleaned)) }
            if let other = appRules.first(where: { $0.id != id && DictationBundleID.key($0.bundleID) == DictationBundleID.key(cleaned) }) {
                return .failure(.duplicateApp(other.appName ?? other.bundleID))
            }
            if DictationBundleID.key(cleaned) != DictationBundleID.key(rule.bundleID) { rule.appName = nil }
            rule.bundleID = cleaned
        }
        if let style { rule.style = style }
        appRules[index] = rule
        return .success(rule)
    }

    @discardableResult
    public mutating func removeRule(_ id: UUID) -> Bool {
        guard let index = appRules.firstIndex(where: { $0.id == id }) else { return false }
        appRules.remove(at: index); return true
    }

    // MARK: Snippets

    public static func problem(trigger: String, expansion: String, excluding id: UUID?, in snippets: [DictationSnippet]) -> DictationPreferenceProblem? {
        guard !trigger.contains(where: \.isNewline) else { return .triggerHasLineBreak }
        let cleaned = DictationSnippets.cleanedTrigger(trigger), key = DictationSnippets.key(trigger)
        guard !cleaned.isEmpty, !key.isEmpty else { return .emptyTrigger }
        guard cleaned.count <= DictationSnippets.triggerCharacterLimit,
              cleaned.split(separator: " ").count <= DictationSnippets.triggerWordLimit else { return .triggerTooLong }
        guard key.filter({ $0.isLetter || $0.isNumber }).count >= 2 else { return .triggerNeedsLetters }
        if let other = snippets.first(where: { $0.id != id && DictationSnippets.key($0.trigger) == key }) {
            return .duplicateTrigger(existing: other.trigger)
        }
        guard !expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .emptyExpansion }
        guard expansion.count <= DictationSnippets.expansionCharacterLimit else { return .expansionTooLong }
        return nil
    }

    @discardableResult
    public mutating func addSnippet(trigger: String, expansion: String) -> Result<DictationSnippet, DictationPreferenceProblem> {
        if let problem = Self.problem(trigger: trigger, expansion: expansion, excluding: nil, in: snippets) { return .failure(problem) }
        guard snippets.count < DictationSnippets.snippetLimit else { return .failure(.tooManySnippets) }
        // Expansions are stored verbatim, including line breaks and edge spaces.
        let snippet = DictationSnippet(trigger: DictationSnippets.cleanedTrigger(trigger), expansion: expansion)
        snippets.append(snippet)
        return .success(snippet)
    }

    @discardableResult
    public mutating func updateSnippet(_ id: UUID, trigger: String? = nil, expansion: String? = nil) -> Result<DictationSnippet, DictationPreferenceProblem> {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return .failure(.notFound) }
        let newTrigger = trigger ?? snippets[index].trigger, newExpansion = expansion ?? snippets[index].expansion
        if let problem = Self.problem(trigger: newTrigger, expansion: newExpansion, excluding: id, in: snippets) { return .failure(problem) }
        snippets[index].trigger = DictationSnippets.cleanedTrigger(newTrigger)
        snippets[index].expansion = newExpansion
        return .success(snippets[index])
    }

    @discardableResult
    public mutating func removeSnippet(_ id: UUID) -> Bool {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return false }
        snippets.remove(at: index); return true
    }

    private static func cleanedName(_ name: String?) -> String? {
        guard let name = name?.split(whereSeparator: \.isWhitespace).joined(separator: " "), !name.isEmpty else { return nil }
        return String(name.prefix(80))
    }

    // MARK: Lenient decoding

    /// Something in a saved file that could not be used as-is.
    public enum LoadIssue: Equatable, Sendable {
        case unknownGlobalStyle(String)
        case unreadableRule(index: Int)
        case invalidRule(bundleID: String)
        case duplicateRule(bundleID: String)
        case unreadableSnippet(index: Int)
        case invalidSnippet(trigger: String, DictationPreferenceProblem)
        case overLimit(String, dropped: Int)
    }

    public enum LoadFailure: Error, Equatable, Sendable {
        /// Written by a newer Coda; must not be rewritten by this version.
        case newerVersion(Int)
    }

    private enum CodingKeys: String, CodingKey { case version, globalStyle, appRules, snippets }

    public init(from decoder: Decoder) throws { self = try Self.lenient(from: decoder).settings }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version); try values.encode(globalStyle, forKey: .globalStyle)
        try values.encode(appRules, forKey: .appRules); try values.encode(snippets, forKey: .snippets)
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
    private struct RawRule: Decodable {
        let id: UUID?, bundleID: String, appName: String?, style: String?
        enum CodingKeys: String, CodingKey { case id, bundleID, appName, style }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try? values.decodeIfPresent(UUID.self, forKey: .id); bundleID = try values.decode(String.self, forKey: .bundleID)
            appName = try? values.decodeIfPresent(String.self, forKey: .appName); style = try? values.decodeIfPresent(String.self, forKey: .style)
        }
    }
    private struct RawSnippet: Decodable {
        let id: UUID?, trigger: String, expansion: String
        enum CodingKeys: String, CodingKey { case id, trigger, expansion }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try? values.decodeIfPresent(UUID.self, forKey: .id)
            trigger = try values.decode(String.self, forKey: .trigger); expansion = try values.decode(String.self, forKey: .expansion)
        }
    }

    /// Missing fields take defaults; each unusable entry is reported, not silently lost.
    static func lenient(from decoder: Decoder) throws -> (settings: Self, issues: [LoadIssue]) {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = (try? values.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
        guard version <= Self.currentVersion else { throw LoadFailure.newerVersion(version) }
        var issues: [LoadIssue] = [], settings = Self()
        if let raw = try? values.decodeIfPresent(String.self, forKey: .globalStyle) {
            if let style = DictationWritingStyle(rawValue: raw) { settings.globalStyle = style } else { issues.append(.unknownGlobalStyle(raw)) }
        }
        let rawRules = (try? values.decodeIfPresent([Lossy<RawRule>].self, forKey: .appRules)) ?? []
        var ids = Set<UUID>(), dropped = 0
        for (index, entry) in rawRules.enumerated() {
            guard let raw = entry.value else { issues.append(.unreadableRule(index: index)); continue }
            let cleaned = DictationBundleID.cleaned(raw.bundleID)
            guard DictationBundleID.valid(cleaned), let style = raw.style.flatMap(DictationWritingStyle.init(rawValue:)) else {
                issues.append(.invalidRule(bundleID: cleaned)); continue
            }
            guard settings.rule(forBundleID: cleaned) == nil else { issues.append(.duplicateRule(bundleID: cleaned)); continue }
            guard settings.appRules.count < Self.ruleLimit else { dropped += 1; continue }
            var id = raw.id ?? UUID()
            if !ids.insert(id).inserted { id = UUID(); ids.insert(id) }
            settings.appRules.append(DictationAppRule(id: id, bundleID: cleaned, appName: cleanedName(raw.appName), style: style))
        }
        if dropped > 0 { issues.append(.overLimit("app styles", dropped: dropped)) }
        let rawSnippets = (try? values.decodeIfPresent([Lossy<RawSnippet>].self, forKey: .snippets)) ?? []
        dropped = 0
        for (index, entry) in rawSnippets.enumerated() {
            guard let raw = entry.value else { issues.append(.unreadableSnippet(index: index)); continue }
            if let problem = problem(trigger: raw.trigger, expansion: raw.expansion, excluding: nil, in: settings.snippets) {
                issues.append(.invalidSnippet(trigger: raw.trigger, problem)); continue
            }
            guard settings.snippets.count < DictationSnippets.snippetLimit else { dropped += 1; continue }
            var id = raw.id ?? UUID()
            if !ids.insert(id).inserted { id = UUID(); ids.insert(id) }
            settings.snippets.append(DictationSnippet(id: id, trigger: DictationSnippets.cleanedTrigger(raw.trigger), expansion: raw.expansion))
        }
        if dropped > 0 { issues.append(.overLimit("snippets", dropped: dropped)) }
        return (settings, issues)
    }

    public struct Loaded: Equatable, Sendable {
        public var settings: DictationPreferenceSettings
        public var issues: [LoadIssue]
    }
    private struct LoadedBox: Decodable {
        let loaded: Loaded
        init(from decoder: Decoder) throws {
            let (settings, issues) = try DictationPreferenceSettings.lenient(from: decoder)
            loaded = Loaded(settings: settings, issues: issues)
        }
    }
    /// Throws for non-JSON, a non-object top level, or a newer version.
    public static func decode(_ data: Data) throws -> Loaded {
        try JSONDecoder().decode(LoadedBox.self, from: data).loaded
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Pipeline step

public struct DictationPersonalizationResult: Equatable, Sendable {
    public let text: String
    /// Set when a whole-utterance snippet replaced the dictation.
    public let snippet: DictationSnippet?
    public let style: DictationWritingStyle
}

public enum DictationPersonalization {
    /// A matching snippet inserts its expansion verbatim; otherwise the app's
    /// style (or the global style) formats the text.
    public static func apply(_ text: String, bundleID: String?, settings: DictationPreferenceSettings) -> DictationPersonalizationResult {
        let style = settings.style(forBundleID: bundleID)
        if let snippet = DictationSnippets.match(text, in: settings.snippets) {
            return .init(text: snippet.expansion, snippet: snippet, style: style)
        }
        return .init(text: DictationStyleFormatter.apply(text, style: style), snippet: nil, style: style)
    }
}

// MARK: - Storage

/// Owner-only, atomically replaced `settings.json`. Unusable files are copied
/// aside before the first rewrite so nothing a user wrote is lost.
public struct DictationPreferenceStore: Sendable {
    public let root: URL
    public var file: URL { root.appendingPathComponent("settings.json") }

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    /// nil when no file exists yet.
    public func load() throws -> DictationPreferenceSettings.Loaded? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try DictationPreferenceSettings.decode(Data(contentsOf: file))
    }

    public func save(_ settings: DictationPreferenceSettings) throws {
        let data = try settings.encoded()
        let temporary = root.appendingPathComponent(".settings-\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary.path, file.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// Copies the current file to `settings.preserved-<timestamp>.json`.
    @discardableResult
    public func preserveCurrentFile(now: Date = Date()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let stamp = Int(now.timeIntervalSince1970)
        var target = root.appendingPathComponent("settings.preserved-\(stamp).json"), attempt = 1
        while FileManager.default.fileExists(atPath: target.path) {
            attempt += 1; target = root.appendingPathComponent("settings.preserved-\(stamp)-\(attempt).json")
        }
        try FileManager.default.copyItem(at: file, to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        return target
    }
}
