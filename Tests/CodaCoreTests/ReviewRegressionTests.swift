import Testing
import Foundation
import AVFoundation
@testable import CodaCore

@Test @MainActor func stopFailureStillDetachesAndFinalizesEveryWriter() async throws {
    var events: [String] = []
    await #expect(throws: CodaError.emptyAudio) {
        let _: [Int] = try await CaptureFinalization.finish(
            stop: { events.append("stop"); throw CodaError.emptyAudio },
            detach: { events.append("detach") },
            writers: [{ events.append("system"); return 1 }, { events.append("microphone"); return 2 }])
    }
    #expect(events == ["stop", "detach", "system", "microphone"])
}
@Test @MainActor func writerFailureDoesNotLeaveSiblingUnfinished() async throws {
    var finalized = false
    await #expect(throws: CodaError.emptyAudio) {
        let _: [Int] = try await CaptureFinalization.finish(stop: {}, detach: {},
            writers: [{ throw CodaError.emptyAudio }, { finalized = true; return 2 }])
    }
    #expect(finalized)
}
@Test func historyRestartPreservesValidMeetingsBesideCorruptFile() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try MeetingStore(root: root)
    var meeting = Meeting(title: "Synthetic restart", audioFile: "fixture.m4a")
    meeting.speakerNames = ["0": "Synthetic speaker"]
    meeting.segments = [Segment(id: "s1", start: 0, end: 1, speakers: [0], text: "Test only")]
    meeting.summary = MeetingSummary(overview: [SummaryItem(text: "Test", evidence: ["s1"])], decisions: [], actions: [])
    try store.save(meeting)
    let corrupt = root.appendingPathComponent("corrupt.json")
    try Data("not JSON".utf8).write(to: corrupt)
    let restarted = try MeetingStore(root: root).loadRecovering()
    #expect(restarted.meetings.count == 1)
    #expect(restarted.meetings[0].id == meeting.id)
    #expect(restarted.meetings[0].summary == meeting.summary)
    #expect(restarted.meetings[0].speakerNames == meeting.speakerNames)
    #expect(restarted.unreadableCount == 1)
    #expect(try String(contentsOf: corrupt, encoding: .utf8) == "not JSON")
}
@Test func cloudConsentDefaultsToDeniedBeforeTransport() async throws {
    let transport = StubTransport(statuses: [], data: Data())
    await #expect(throws: CodaError.consentRequired) {
        try await Summarizer(transport: transport).summarize(Meeting(title: "Synthetic", audioFile: "fixture"), configuration: Configuration(contents: "OPENAI_API_KEY=synthetic-only"))
    }
    #expect(await transport.count() == 0)
}
@Test func strictSummaryRejectsMissingNullableFieldsAndExtraKeys() throws {
    let segments = [Segment(id: "s1", start: 0, end: 1, speakers: [], text: "Test")]
    for payload in [
        #"{"overview":[{"text":"Test","evidence":["s1"]}],"decisions":[],"actions":[]}"#,
        #"{"overview":[],"decisions":[],"actions":[],"unexpected":"data"}"#
    ] {
        let response = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": payload]]]]])
        #expect(throws: CodaError.invalidSummary) { try Summarizer.parse(response, segments: segments) }
    }
}
actor CancellingTransport: HTTPTransport {
    var called = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        called = true
        // A misbehaving network layer returns a completed response despite task cancellation.
        withUnsafeCurrentTask { $0?.cancel() }
        return (Data(#"{"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"{\"overview\":[],\"decisions\":[],\"actions\":[]}"}]}]}"#.utf8), 200)
    }
}
@Test func lateResponseAfterCancellationIsDiscarded() async throws {
    var meeting = Meeting(title: "Synthetic", audioFile: "fixture")
    meeting.segments = [Segment(id: "s1", start: 0, end: 1, speakers: [], text: "Test")]
    let client = Summarizer(transport: CancellingTransport())
    let task = Task { try await client.summarize(meeting, configuration: Configuration(contents: "OPENAI_API_KEY=synthetic-only"), consent: true) }
    await #expect(throws: CancellationError.self) { try await task.value }
}

private func syntheticAudio(channels: UInt32, timestamp: Double) throws -> CMSampleBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: channels, interleaved: true)!
    let frames = 4800
    let bytes = frames * Int(channels) * MemoryLayout<Float>.size
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes, blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block) == noErr, let block else { throw CodaError.emptyAudio }
    let samples = [Float](repeating: 0, count: frames * Int(channels))
    let copied = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) }
    guard copied == noErr else { throw CodaError.emptyAudio }
    var buffer: CMSampleBuffer?
    let result = CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format.formatDescription, sampleCount: frames, presentationTimeStamp: CMTime(seconds: timestamp, preferredTimescale: 48_000), packetDescriptions: nil, sampleBufferOut: &buffer)
    guard result == noErr, let buffer else { throw CodaError.emptyAudio }
    return buffer
}
@Test @MainActor func separateCaptureWritersPreserveFormatsAndTimelineOrigins() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let system = AudioSink(url: root.appendingPathComponent("system.m4a"))
    let microphone = AudioSink(url: root.appendingPathComponent("microphone.m4a"))
    system.append(try syntheticAudio(channels: 2, timestamp: 1000))
    microphone.append(try syntheticAudio(channels: 1, timestamp: 1000.25))
    let first = try #require(await system.finish())
    let second = try #require(await microphone.finish())
    #expect(abs(CMTimeSubtract(second.1, first.1).seconds - 0.25) < 0.0001)
    let mixed = root.appendingPathComponent("mixed.m4a")
    try await CaptureMixer.mix([first, second], to: mixed)
    let duration = try await AVURLAsset(url: mixed).load(.duration).seconds
    #expect(duration > 0.30 && duration < 0.45) // 0.1s microphone begins 0.25s after system.
    for (file, _) in [first, second] {
        let asset = AVURLAsset(url: file)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await asset.load(.duration).seconds > 0)
    }
}
