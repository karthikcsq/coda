import Foundation

public struct Word: Sendable {
    public let text: String
    public let start: Double
    public let end: Double
    public init(_ text: String, _ start: Double, _ end: Double) { self.text = text; self.start = start; self.end = end }
}
public struct SpeakerTurn: Sendable {
    public let speaker: Int
    public let start: Double
    public let end: Double
    public init(_ speaker: Int, _ start: Double, _ end: Double) { self.speaker = speaker; self.start = start; self.end = end }
}
public struct Segment: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var start: Double
    public var end: Double
    public var speakers: [Int]
    public var text: String
    public init(id: String, start: Double, end: Double, speakers: [Int], text: String) {
        self.id = id; self.start = start; self.end = end; self.speakers = speakers; self.text = text
    }
}
public struct SummaryItem: Codable, Sendable, Equatable {
    public let text: String
    public let evidence: [String]
    public let owner: String?
    public let dueDate: String?
    /// Short heading for a reference note. Nil elsewhere and in summaries saved before headings existed.
    public let topic: String?
    public init(text: String, evidence: [String], owner: String? = nil, dueDate: String? = nil, topic: String? = nil) {
        self.text = text; self.evidence = evidence; self.owner = owner; self.dueDate = dueDate; self.topic = topic
    }
    func keeping(owner keepOwner: Bool, topic keepTopic: Bool) -> SummaryItem {
        SummaryItem(text: text, evidence: evidence, owner: keepOwner ? owner : nil, dueDate: keepOwner ? dueDate : nil,
                    topic: keepTopic ? topic : nil)
    }
}
/// Bottom line first (brief, takeaways), then outcomes, then topic notes for reference.
public struct MeetingSummary: Codable, Sendable, Equatable {
    /// One or two sentences: what the meeting was for and what came of it. Nil for older summaries.
    public let brief: SummaryItem?
    /// The few things most worth remembering, most important first.
    public let takeaways: [SummaryItem]
    /// Topic notes in first-discussed order. Kept under the original key so older summaries still load.
    public let overview: [SummaryItem]
    public let decisions: [SummaryItem]
    public let actions: [SummaryItem]
    public let openQuestions: [SummaryItem]
    public init(brief: SummaryItem? = nil, takeaways: [SummaryItem] = [], overview: [SummaryItem],
                decisions: [SummaryItem], actions: [SummaryItem], openQuestions: [SummaryItem] = []) {
        self.brief = brief; self.takeaways = takeaways; self.overview = overview
        self.decisions = decisions; self.actions = actions; self.openQuestions = openQuestions
    }
    enum CodingKeys: String, CodingKey { case brief, takeaways, overview, decisions, actions, openQuestions }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        brief = try values.decodeIfPresent(SummaryItem.self, forKey: .brief)
        takeaways = try values.decodeIfPresent([SummaryItem].self, forKey: .takeaways) ?? []
        overview = try values.decode([SummaryItem].self, forKey: .overview)
        decisions = try values.decode([SummaryItem].self, forKey: .decisions)
        actions = try values.decode([SummaryItem].self, forKey: .actions)
        openQuestions = try values.decodeIfPresent([SummaryItem].self, forKey: .openQuestions) ?? []
    }
    /// False for summaries generated before the brief and takeaways existed.
    public var leadsWithTakeaways: Bool { brief != nil }
    public func validated(for segments: [Segment]) throws -> Self {
        let ids = Set(segments.map(\.id))
        for item in [brief].compactMap({ $0 }) + takeaways + overview + decisions + actions + openQuestions {
            guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.evidence.isEmpty, item.evidence.allSatisfy(ids.contains) else { throw CodaError.invalidSummary }
        }
        return self
    }
}
public struct Meeting: Codable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var created: Date
    public var audioFile: String
    public var segments: [Segment]
    public var speakerNames: [String: String]
    public var summary: MeetingSummary?
    /// Nil preserves automatic speaker discovery, including for older saved meetings.
    public var expectedSpeakerCount: Int?
    /// The summary exactly as generated, and the speaker labels it was generated with. Renaming a
    /// speaker rewrites `summary` from these, so names follow edits without summarizing again.
    public var summarySource: MeetingSummary?
    public var summarySpeakerLabels: [String: String]?
    /// Names typed before recording, in the order people are expected to first speak.
    public var plannedSpeakerNames: [String]?
    public init(title: String, audioFile: String) {
        id = UUID(); self.title = title; created = Date(); self.audioFile = audioFile
        segments = []; speakerNames = [:]
    }
    public func speakerLabel(_ speakers: [Int]) -> String {
        if speakers.isEmpty { return "Unknown speaker" }
        return speakers.map { speakerNames[String($0)] ?? "Speaker \($0 + 1)" }.joined(separator: " / ")
            + (speakers.count > 1 ? " (overlap / uncertain)" : "")
    }
}
public enum CodaError: Error, LocalizedError, Equatable {
    case message(String), consentRequired, missingKey, invalidSummary, refused, incomplete, http(Int), emptyAudio
    public var errorDescription: String? {
        switch self {
        case .message(let message): return message
        case .consentRequired: return "Transcript sharing requires explicit consent before contacting OpenAI."
        case .missingKey: return "Add your OpenAI key to the selected .env file. Local transcription still works without it."
        case .invalidSummary: return "The summary response was malformed or cited unknown transcript segments. Nothing was saved."
        case .refused: return "OpenAI declined to summarize this transcript."
        case .incomplete: return "OpenAI returned an incomplete response. Try again or use a shorter recording."
        case .http(let code): return "OpenAI request failed (HTTP \(code)). Check your model, key, connection, and account limits."
        case .emptyAudio: return "No usable audio or words were found. Check the input and try again."
        }
    }
}
public enum Alignment {
    /// Greatest overlap wins. Near-ties preserve ambiguity. A word within `edgeTolerance` of one voice's turn joins it;
    /// words farther from every turn are never attributed to the nearest voice.
    /// How far outside a speaker turn a recognized word may start or end and still be that speaker's.
    public static let edgeTolerance = 0.5
    public static func align(words: [Word], turns: [SpeakerTurn]) -> [Segment] {
        var result: [Segment] = []
        for word in words.sorted(by: { $0.start < $1.start }) where word.start.isFinite && word.end.isFinite && word.end >= word.start && word.start >= 0 {
            var overlap: [Int: Double] = [:]
            for turn in turns where turn.start.isFinite && turn.end.isFinite && turn.end > turn.start {
                let amount = max(0, min(word.end, turn.end) - max(word.start, turn.start))
                if amount > 0 { overlap[turn.speaker] = max(overlap[turn.speaker, default: 0], amount) }
            }
            let best = overlap.values.max() ?? 0
            var speakers = overlap.filter { $0.value >= best * 0.8 }.keys.sorted()
            // A recognized word just outside a turn edge belongs to that turn; real silence stays unattributed.
            if speakers.isEmpty {
                let gaps = turns.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
                    .map { (speaker: $0.speaker, gap: max($0.start - word.end, word.start - $0.end)) }
                if let nearest = gaps.map(\.gap).min(), nearest <= edgeTolerance {
                    // Equidistant voices stay ambiguous, as near-tied overlaps do.
                    speakers = Set(gaps.filter { $0.gap - nearest < 1e-9 }.map(\.speaker)).sorted()
                }
            }
            if let last = result.last, last.speakers == speakers, word.start - last.end < 1.2, word.end - last.start < 22 {
                result[result.count - 1].text += " " + word.text
                result[result.count - 1].end = max(last.end, word.end)
            } else {
                result.append(Segment(id: "s\(result.count + 1)", start: word.start, end: word.end, speakers: speakers, text: word.text))
            }
        }
        return result
    }
}
public func timestamp(_ seconds: Double) -> String {
    let total = Int(max(0, seconds.isFinite ? seconds : 0))
    return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) : String(format: "%02d:%02d", total / 60, total % 60)
}
public enum Export {
    public static func render(_ meeting: Meeting, markdown: Bool) -> String {
        var lines = [markdown ? "# \(meeting.title)" : meeting.title, meeting.created.formatted(), ""]
        if let summary = meeting.summary {
            let references = { (item: SummaryItem) in
                " [" + item.evidence.compactMap { id in meeting.segments.first { $0.id == id } }.map { timestamp($0.start) }.joined(separator: ", ") + "]"
            }
            if let brief = summary.brief { lines += [markdown ? "## Summary" : "Summary", brief.text + references(brief), ""] }
            if !summary.takeaways.isEmpty {
                lines.append(markdown ? "## Key takeaways" : "Key takeaways")
                for (index, item) in summary.takeaways.enumerated() { lines.append("\(index + 1). " + item.text + references(item)) }
                lines.append("")
            }
            var sections = [("Decisions", summary.decisions), ("Action items", summary.actions)]
            if !summary.openQuestions.isEmpty { sections.append(("Open questions", summary.openQuestions)) }
            sections.append((summary.leadsWithTakeaways ? "Notes" : "Summary", summary.overview))
            for (name, items) in sections {
                lines += [markdown ? "## \(name)" : name]
                for item in items {
                    let attribution = [item.owner.map { "Owner: \($0)" }, item.dueDate.map { "Due: \($0)" }].compactMap { $0 }.joined(separator: "; ")
                    let heading = item.topic.map { markdown ? "**\($0).** " : "\($0): " } ?? ""
                    lines.append("- " + heading + item.text + references(item) + (attribution.isEmpty ? "" : " — " + attribution))
                }
                lines.append("")
            }
        }
        lines.append(markdown ? "## Transcript" : "Transcript")
        for segment in meeting.segments { lines.append("[\(timestamp(segment.start))] \(meeting.speakerLabel(segment.speakers)): \(segment.text)") }
        return lines.joined(separator: "\n") + "\n"
    }
}


extension Meeting {
    /// Local search includes the words and speaker names, not just a recording's title.
    public func matchesSearch(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return true }
        let fields = [title] + segments.map(\.text) + Array(speakerNames.values)
        return terms.allSatisfy { term in fields.contains { $0.localizedCaseInsensitiveContains(term) } }
    }
}
