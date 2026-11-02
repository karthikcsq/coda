import Testing
import Foundation
@testable import CodaCore

@Test func alignmentPreservesSilenceOverlapAndBoundaries() {
    let words = [Word("Hello", 0, 1), Word("there", 1, 2), Word("both", 2, 3), Word("unknown", 4, 5), Word("zero", 6, 6)]
    let turns = [SpeakerTurn(0, 0, 1), SpeakerTurn(1, 1, 3), SpeakerTurn(0, 2, 3)]
    let segments = Alignment.align(words: words, turns: turns)
    #expect(segments[0].speakers == [0])
    #expect(segments[1].speakers == [1])
    #expect(segments[2].speakers == [0, 1])
    #expect(segments[3].speakers == [])
    #expect(segments.last?.text.contains("zero") == true)
}
@Test func alignmentUsesGreatestOverlapAndRejectsInvalidTimes() {
    let segments = Alignment.align(words: [Word("clear", 0, 1), Word("bad", .nan, 2)], turns: [SpeakerTurn(0, 0, 1), SpeakerTurn(1, 0, 0.2)])
    #expect(segments.count == 1)
    #expect(segments[0].speakers == [0])
}
@Test func envIsDataAndHandlesQuotesCommentsAndPrecedence() {
    let contents = """
    # nothing here
    OPENAI_API_KEY='synthetic=only'
    export OPENAI_MODEL="model-with-spaces"
    OTHER=$(touch /tmp/never-run)
    OPENAI_MODEL=gpt-4.1-mini # comment
    """
    let config = Configuration(contents: contents)
    #expect(config.apiKey == "synthetic=only")
    #expect(config.model == "gpt-4.1-mini")
    #expect(Configuration(contents: contents, environment: ["OPENAI_MODEL": "override"]).model == "override")
    #expect(Configuration(contents: "OPENAI_API_KEY=$(echo literal)").apiKey == "$(echo literal)")
    #expect(throws: CodaError.missingKey) { try Configuration(contents: "").validate() }
    #expect(throws: CodaError.missingKey) { try Configuration(contents: "OPENAI_API_KEY=your-key-here").validate() }
}
private func meeting() -> Meeting {
    var meeting = Meeting(title: "Synthetic meeting", audioFile: "synthetic.m4a")
    meeting.segments = [Segment(id: "s1", start: 62, end: 65, speakers: [0], text: "We decided to ship the draft.")]
    meeting.speakerNames = ["0": "Alex"]
    return meeting
}
private func response(evidence: String = "s1", status: String = "completed") throws -> Data {
    let summary = MeetingSummary(overview: [SummaryItem(text: "The draft will ship.", evidence: [evidence])], decisions: [], actions: [])
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as! [String: Any]
    for key in ["overview", "decisions", "actions"] {
        object[key] = (object[key] as! [[String: Any]]).map { item in
            var item = item; item["owner"] = item["owner"] ?? NSNull(); item["dueDate"] = item["dueDate"] ?? NSNull(); return item
        }
    }
    let text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    return try JSONSerialization.data(withJSONObject: ["status": status, "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]])
}
@Test func parseStructuredSummaryAndValidateEvidence() throws {
    let result = try Summarizer.parse(response(), segments: meeting().segments)
    #expect(result.overview.first?.owner == nil)
    #expect(throws: CodaError.invalidSummary) { try Summarizer.parse(response(evidence: "made-up"), segments: meeting().segments) }
    #expect(throws: CodaError.incomplete) { try Summarizer.parse(response(status: "incomplete"), segments: meeting().segments) }
    #expect(throws: CodaError.invalidSummary) { try Summarizer.parse(Data("garbage".utf8), segments: []) }
    let refusal = Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"refusal"}]}]}"#.utf8)
    #expect(throws: CodaError.refused) { try Summarizer.parse(refusal, segments: []) }
}
actor StubTransport: HTTPTransport {
    var statuses: [Int]
    let data: Data
    var requests: [URLRequest] = []
    init(statuses: [Int], data: Data) { self.statuses = statuses; self.data = data }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (data, statuses.removeFirst())
    }
    func count() -> Int { requests.count }
    func bodyString() -> String { String(decoding: requests.first!.httpBody!, as: UTF8.self) }
}
@Test func retriesRateLimitsAndServerFailuresWithoutUploadingAudio() async throws {
    let transport = StubTransport(statuses: [429, 503, 200], data: try response())
    let client = Summarizer(transport: transport, pause: { _ in })
    let summary = try await client.summarize(meeting(), configuration: Configuration(contents: "OPENAI_API_KEY=synthetic-only"), consent: true)
    #expect(summary.overview.count == 1)
    #expect(await transport.count() == 3)
    let bodyText = await transport.bodyString()
    let body = try JSONSerialization.jsonObject(with: Data(bodyText.utf8)) as! [String: Any]
    #expect(body["store"] as? Bool == false)
    #expect(!bodyText.contains("synthetic-only"))
    #expect(body["input"] as? String != nil)
    #expect(bodyText.contains("synthetic.m4a") == false)
}
@Test func authenticationFailureDoesNotRetry() async throws {
    let transport = StubTransport(statuses: [401], data: Data())
    await #expect(throws: CodaError.http(401)) {
        try await Summarizer(transport: transport).summarize(meeting(), configuration: Configuration(contents: "OPENAI_API_KEY=synthetic-only"), consent: true)
    }
    #expect(await transport.count() == 1)
}
@Test func cancellationStopsRetries() async throws {
    let transport = StubTransport(statuses: [429, 200], data: try response())
    let client = Summarizer(transport: transport, pause: { _ in throw CancellationError() })
    await #expect(throws: CancellationError.self) { try await client.summarize(meeting(), configuration: Configuration(contents: "OPENAI_API_KEY=synthetic-only"), consent: true) }
    #expect(await transport.count() == 1)
}
@Test func missingKeyNeverTouchesNetwork() async throws {
    let transport = StubTransport(statuses: [], data: Data())
    await #expect(throws: CodaError.missingKey) { try await Summarizer(transport: transport).summarize(meeting(), configuration: Configuration(contents: ""), consent: true) }
    #expect(await transport.count() == 0)
}
@Test func historyAndExportsRoundTrip() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try MeetingStore(root: root)
    var item = meeting(); item.summary = try Summarizer.parse(response(), segments: item.segments)
    try store.save(item)
    #expect(try store.load().first?.speakerNames["0"] == "Alex")
    let markdown = Export.render(item, markdown: true)
    #expect(markdown.contains("# Synthetic meeting"))
    #expect(markdown.contains("[01:02] Alex:"))
    #expect(markdown.contains("The draft will ship. [01:02]"))
    #expect(!Export.render(item, markdown: false).hasPrefix("#"))
    try store.remove(item)
    #expect(try store.load().isEmpty)
}
@Test func timestampsIncludeHours() { #expect(timestamp(3661) == "1:01:01"); #expect(timestamp(.nan) == "00:00") }
