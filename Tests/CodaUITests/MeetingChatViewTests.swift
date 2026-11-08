import Testing
import CodaCore
@testable import Coda

private let segments = [
    Segment(id: "s1", start: 0, end: 7, speakers: [0], text: "Scope."),
    Segment(id: "s2", start: 8, end: 15, speakers: [1], text: "Review."),
    Segment(id: "s3", start: 75, end: 90, speakers: [0], text: "Decision.")
]

@Test func chatCitationsLinkToTheMatchingTranscriptSegment() {
    let linked = MeetingChatView.linkCitations("Sam owns it [00:08] and it was settled [01:20].", segments: segments)
    #expect(linked == "Sam owns it [00:08](coda-segment://s2) and it was settled [01:20](coda-segment://s3).")
}

@Test func chatCitationsLeaveUnknownOrExistingLinksAlone() {
    #expect(MeetingChatView.segment(at: "00:03", in: segments)?.id == "s1")
    #expect(MeetingChatView.linkCitations("See [link](https://x.test) and [note]", segments: segments) == "See [link](https://x.test) and [note]")
    #expect(MeetingChatView.linkCitations("[00:08](coda-segment://s2)", segments: segments) == "[00:08](coda-segment://s2)")
}

@Test @MainActor func previewChatNeverContactsCodex() {
    let model = AppModel(preview: true)
    struct Fail: ChatBackend { func reply(to prompt: String) async throws -> String { Issue.record("Backend called in preview"); return "" } }
    model.chatBackend = Fail()
    let before = model.chats[model.selection!]?.count
    model.askChat("Anything?")
    #expect(model.chats[model.selection!]?.count == before)
    #expect(!model.showChatConsent)
}
