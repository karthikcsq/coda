import Foundation
import Testing
import CodaCore
@testable import Coda

@Test func dictationFailureNeverExposesRawErrorDescriptions() {
    let error = NSError(domain: NSCocoaErrorDomain, code: 260,
                        userInfo: [NSLocalizedDescriptionKey: "private transcript /Users/person/private.m4a secret"])
    let failure = DictationFailure.modelLoad(DictationFailure.diagnosticCode(error))
    #expect(failure.message.contains("NSCocoaErrorDomain 260"))
    #expect(!failure.message.contains("private"))
    #expect(!failure.message.contains("secret"))
    #expect(!failure.message.contains("/Users/"))
    #expect(DictationFailure.noWords.title == "No words recognized")
    #expect(DictationFailure.invalidAudio.title != DictationFailure.noWords.title)
}

@Test @MainActor func transcriptionFailureShowsItsRealCategoryAndRejectsStaleErrors() throws {
    let controller = DictationController(preview: true)
    let firstStart = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let first = try #require(firstStart)
    _ = controller.lifecycle.listening(first); _ = controller.lifecycle.processing()
    #expect(controller.reportTranscriptionFailure(DictationFailure.noWords, for: first))
    let hud = DictationHUD(controller: controller)
    #expect(hud.statusTitle == "No words recognized")
    #expect(hud.statusDetail.contains("returned no words"))
    let nextStart = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let next = try #require(nextStart)
    _ = controller.lifecycle.listening(next)
    #expect(!controller.reportTranscriptionFailure(DictationFailure.invalidAudio, for: first))
    #expect(controller.lifecycle.phase == .listening && controller.lifecycle.id == next)
    controller.cancel()
}

@Test func captureDiagnosticsBoundInvalidNumbersWithoutRetainingContent() {
    let stats = DictationCaptureStats(seconds: .nan, peakDB: -.infinity, bytes: -10)
    #expect(stats.description == "Captured 0.0 seconds; audio 0 bytes.")
    let recorded = DictationCaptureStats(seconds: 2.5, peakDB: -18, bytes: 12000)
    #expect(recorded.description.contains("2.5 seconds"))
    #expect(recorded.description.contains("-18 dBFS"))
}
