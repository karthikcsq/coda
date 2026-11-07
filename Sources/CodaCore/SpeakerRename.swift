import Foundation

extension Meeting {
    /// Every speaker that appears in the transcript or has a name.
    public var knownSpeakers: [Int] {
        Set(segments.flatMap(\.speakers) + speakerNames.keys.compactMap { Int($0) }).sorted()
    }
    public func speakerDisplayName(_ speaker: Int) -> String { speakerNames[String(speaker)] ?? "Speaker \(speaker + 1)" }
    var speakerLabels: [String: String] {
        Dictionary(uniqueKeysWithValues: knownSpeakers.map { (String($0), speakerDisplayName($0)) })
    }

    /// Stores a freshly generated summary along with the names it was written with.
    public mutating func setSummary(_ summary: MeetingSummary?) {
        self.summary = summary
        summarySource = summary
        summarySpeakerLabels = summary == nil ? nil : speakerLabels
    }

    /// Renames a speaker and carries the new name into the existing summary. Empty clears the name.
    public mutating func renameSpeaker(_ speaker: Int, to name: String) {
        // Summaries saved before this existed: their current text is the baseline.
        if let summary, summarySource == nil || summarySpeakerLabels == nil {
            summarySource = summary; summarySpeakerLabels = speakerLabels
        }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        speakerNames[String(speaker)] = name.isEmpty ? nil : name
        guard let source = summarySource, let baseline = summarySpeakerLabels else { return }
        var mapping: [String: String] = [:]
        for (id, old) in baseline {
            let current = speakerNames[id] ?? Int(id).map { "Speaker \($0 + 1)" } ?? old
            if current != old { mapping[old] = current }
        }
        summary = source.renamingSpeakers(mapping)
    }
}

extension MeetingSummary {
    /// Whole-word, simultaneous replacement, so swapping two names or a name that prefixes another is safe.
    public func renamingSpeakers(_ mapping: [String: String]) -> MeetingSummary {
        let mapping = mapping.filter { !$0.key.isEmpty }
        guard !mapping.isEmpty else { return self }
        let alternatives = mapping.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_])(?:"# + alternatives.joined(separator: "|") + #")(?![\p{L}\p{N}_])"#) else { return self }
        func rename(_ text: String) -> String {
            let source = text as NSString
            var result = "", cursor = 0
            for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
                result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                let found = source.substring(with: match.range)
                result += mapping[found] ?? found
                cursor = match.range.location + match.range.length
            }
            return result + source.substring(from: cursor)
        }
        func item(_ value: SummaryItem) -> SummaryItem {
            SummaryItem(text: rename(value.text), evidence: value.evidence, owner: value.owner.map(rename),
                        dueDate: value.dueDate, topic: value.topic.map(rename))
        }
        return MeetingSummary(brief: brief.map(item), takeaways: takeaways.map(item), overview: overview.map(item),
                              decisions: decisions.map(item), actions: actions.map(item), openQuestions: openQuestions.map(item))
    }
}
