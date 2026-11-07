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

    /// Planned names for a fresh transcript: the diarizer numbers voices by first appearance,
    /// so the first name goes to the first voice heard. Blank entries stay unnamed.
    public func plannedNames(for segments: [Segment]) -> [String: String] {
        let found = Set(segments.flatMap(\.speakers))
        var names: [String: String] = [:]
        for (index, name) in (plannedSpeakerNames ?? []).enumerated() where found.contains(index) {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { names[String(index)] = name }
        }
        return names
    }

    /// Names for a re-transcription of the same audio: names already given carry over to the
    /// same speaker number, and planned names fill any number still unnamed. Names for voices
    /// the new transcript no longer has are dropped.
    public func retainedNames(for segments: [Segment]) -> [String: String] {
        let found = Set(segments.flatMap(\.speakers))
        var names = plannedNames(for: segments)
        for (key, name) in speakerNames {
            guard let index = Int(key), found.contains(index) else { continue }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { names[key] = name }
        }
        return names
    }

    /// Stores a freshly generated summary along with the names it was written with.
    public mutating func setSummary(_ summary: MeetingSummary?) {
        self.summary = summary
        summarySource = summary
        summarySpeakerLabels = summary == nil ? nil : speakerLabels
    }

    /// Renames a speaker and carries the new name into the existing summary. Empty clears the name.
    public mutating func renameSpeaker(_ speaker: Int, to name: String) {
        changeNames { names in
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            names[String(speaker)] = name.isEmpty ? nil : name
        }
    }

    /// Exchanges two speakers' names, for when the voices were labelled the wrong way round.
    /// The transcript is untouched; the summary keeps its content with the names exchanged.
    public mutating func swapSpeakers(_ first: Int, _ second: Int) {
        guard first != second else { return }
        changeNames { names in
            let a = names[String(first)], b = names[String(second)]
            names[String(first)] = b; names[String(second)] = a
        }
    }

    /// Attributes one transcript line to different speakers without changing its text.
    /// The summary is left alone: its citations still point at the same line.
    public mutating func reassignSegment(_ id: String, to speakers: [Int]) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        // Pin the summary's names first, so a speaker that disappears keeps its name in the text.
        if let summary, summarySource == nil || summarySpeakerLabels == nil {
            summarySource = summary; summarySpeakerLabels = speakerLabels
        }
        segments[index].speakers = Array(Set(speakers)).sorted()
    }

    private mutating func changeNames(_ change: (inout [String: String]) -> Void) {
        // Summaries saved before this existed: their current text is the baseline.
        if let summary, summarySource == nil || summarySpeakerLabels == nil {
            summarySource = summary; summarySpeakerLabels = speakerLabels
        }
        change(&speakerNames)
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
