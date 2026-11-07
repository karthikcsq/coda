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
