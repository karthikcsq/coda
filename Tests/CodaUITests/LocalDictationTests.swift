import Foundation
import AVFoundation
import Testing
@testable import Coda

/// Opt-in inference against the user's already prepared cache. Supply a synthetic
/// audio fixture, never a private recording. No downloads or microphone use.
@Test(.enabled(if: ProcessInfo.processInfo.environment["CODA_SYNTHETIC_DICTATION_FIXTURE"] != nil,
               "Opt-in prepared-model check with synthetic audio."))
func preparedModelRecognizesRepeatedSyntheticAACDictations() async throws {
    let fixture = try #require(ProcessInfo.processInfo.environment["CODA_SYNTHETIC_DICTATION_FIXTURE"])
    let cache = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Coda/Models")
    let pipeline = LocalPipeline(cache: cache)
    for attempt in 1...3 {
        let result = try await pipeline.dictate(URL(fileURLWithPath: fixture), consent: true)
        #expect(result.lowercased().contains("local dictation test"))
        print("Synthetic AAC dictation \(attempt): recognized expected phrase (\(result.count) characters).")
    }
    let silence = FileManager.default.temporaryDirectory.appendingPathComponent("Coda-synthetic-silence-" + UUID().uuidString + ".wav")
    defer { try? FileManager.default.removeItem(at: silence) }
    try autoreleasepool {
        let file = try AVAudioFile(forWriting: silence, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16000))
        buffer.frameLength = 16000
        let channel = try #require(buffer.floatChannelData?[0])
        channel.initialize(repeating: 0, count: 16000)
        try file.write(from: buffer)
    }
    await #expect(throws: DictationFailure.noWords) {
        try await pipeline.dictate(silence, consent: true)
    }
}
