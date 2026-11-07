import Foundation
import Testing
@testable import CodaCore

private func summarized() -> Meeting {
    var meeting = Meeting(title: "Sync", audioFile: "none.m4a")
    meeting.segments = [Segment(id: "s1", start: 0, end: 4, speakers: [0], text: "Hi."),
                        Segment(id: "s2", start: 5, end: 9, speakers: [1], text: "Hello.")]
    meeting.speakerNames = ["1": "Sam"]
    meeting.setSummary(MeetingSummary(
        brief: SummaryItem(text: "A sync where Speaker 1 and Sam agreed on scope.", evidence: ["s1"]),
        overview: [SummaryItem(text: "Sam's plan: ship it. Samantha is unrelated.", evidence: ["s2"], topic: "Sam's plan")],
        decisions: [], actions: [SummaryItem(text: "Speaker 1 sends notes.", evidence: ["s1"], owner: "Speaker 1", dueDate: "Friday")]))
    return meeting
}

@Test func renamingASpeakerUpdatesTheSummaryInPlace() throws {
    var meeting = summarized()
    meeting.renameSpeaker(0, to: "Alex")
    let summary = try #require(meeting.summary)
    #expect(summary.brief?.text == "A sync where Alex and Sam agreed on scope.")
    #expect(summary.actions.first?.text == "Alex sends notes.")
    #expect(summary.actions.first?.owner == "Alex")
    #expect(summary.actions.first?.dueDate == "Friday")
    #expect(meeting.speakerNames["0"] == "Alex")
}

@Test func renamingMatchesWholeNamesOnly() throws {
    var meeting = summarized()
    meeting.renameSpeaker(1, to: "Jordan")
    let note = try #require(meeting.summary?.overview.first)
    #expect(note.text == "Jordan's plan: ship it. Samantha is unrelated.")
    #expect(note.topic == "Jordan's plan")
}

@Test func typingANameOneKeyAtATimeNeverRewritesOtherWords() throws {
    var meeting = summarized()
    // Every intermediate value is saved as the user types, including one that is a common word.
    for partial in ["A", "Al", "Ale", "Alex"] { meeting.renameSpeaker(0, to: partial) }
    #expect(meeting.summary?.brief?.text == "A sync where Alex and Sam agreed on scope.")
}

@Test func swappingAndClearingNamesStaySimultaneousAndReversible() throws {
    var meeting = summarized()
    meeting.renameSpeaker(0, to: "Sam"); meeting.renameSpeaker(1, to: "Speaker 1")
    #expect(meeting.summary?.brief?.text == "A sync where Sam and Speaker 1 agreed on scope.")
    meeting.renameSpeaker(0, to: ""); meeting.renameSpeaker(1, to: "Sam")
    #expect(meeting.summary == meeting.summarySource)
}

@Test func olderSummariesAdoptTheirCurrentTextAsTheBaseline() throws {
    var meeting = summarized()
    meeting.summarySource = nil; meeting.summarySpeakerLabels = nil
    meeting.renameSpeaker(1, to: "Riley")
    #expect(meeting.summary?.brief?.text == "A sync where Speaker 1 and Riley agreed on scope.")
    let reloaded = try JSONDecoder().decode(Meeting.self, from: JSONEncoder().encode(meeting))
    #expect(reloaded.summarySpeakerLabels?["1"] == "Sam")
}

@Test func renamingWithoutASummaryOnlyChangesTheName() {
    var meeting = summarized(); meeting.setSummary(nil)
    meeting.renameSpeaker(0, to: "Alex")
    #expect(meeting.summary == nil && meeting.speakerNames["0"] == "Alex")
}

@Test func plannedNamesGoToVoicesInFirstToSpeakOrder() {
    var meeting = Meeting(title: "Call", audioFile: "none.m4a")
    meeting.plannedSpeakerNames = ["Karthik", "  ", "Wyatt", "Absent"]
    let segments = [Segment(id: "s1", start: 0, end: 1, speakers: [0], text: "a"),
                    Segment(id: "s2", start: 1, end: 2, speakers: [1, 2], text: "b")]
    #expect(meeting.plannedNames(for: segments) == ["0": "Karthik", "2": "Wyatt"])
    meeting.plannedSpeakerNames = nil
    #expect(meeting.plannedNames(for: segments).isEmpty)
}

@Test func transcribingAgainKeepsExistingNamesOnTheSameSpeakers() {
    var meeting = Meeting(title: "Call", audioFile: "none.m4a")
    meeting.plannedSpeakerNames = ["Planned", "Bea"]
    meeting.speakerNames = ["0": "Karthik", "2": "Wyatt", "3": "  "]
    let segments = [Segment(id: "s1", start: 0, end: 1, speakers: [0], text: "a"),
                    Segment(id: "s2", start: 1, end: 2, speakers: [1], text: "b")]
    // Given names win, planned names fill gaps, and speakers no longer heard are dropped.
    #expect(meeting.retainedNames(for: segments) == ["0": "Karthik", "1": "Bea"])
}

@Test func swappingSpeakersExchangesNamesInTheSummaryAndKeepsTheTranscript() {
    var meeting = summarized()
    let transcript = meeting.segments
    meeting.renameSpeaker(0, to: "Alex"); meeting.renameSpeaker(1, to: "Sam")
    let named = meeting.summary
    meeting.swapSpeakers(0, 1)
    #expect(meeting.segments == transcript)
    #expect(meeting.speakerNames == ["0": "Sam", "1": "Alex"])
    #expect(meeting.summary?.brief?.text == "A sync where Sam and Alex agreed on scope.")
    #expect(meeting.summary?.actions.first?.owner == "Sam")
    meeting.swapSpeakers(1, 0)
    #expect(meeting.summary == named)
}

@Test func reassigningALineChangesOnlyItsSpeaker() {
    var meeting = summarized()
    let summary = meeting.summary
    let line = meeting.segments[0]
    meeting.reassignSegment(line.id, to: [3, 3])
    #expect(meeting.segments[0].speakers == [3])
    #expect(meeting.segments[0].text == line.text && meeting.segments[0].start == line.start)
    #expect(meeting.summary == summary)
}

@Test func swappingWithAnUnnamedSpeakerMovesTheName() {
    var meeting = summarized()
    meeting.swapSpeakers(0, 1)
    #expect(meeting.speakerNames == ["0": "Sam"])
    #expect(meeting.summary?.brief?.text == "A sync where Sam and Speaker 2 agreed on scope.")
}
