import Foundation
import ScreenCaptureKit
import Testing
@testable import CodaCore

@Test func capturePermissionErrorDoesNotBlameMicrophone() {
    let error = RecordingStartFailure(stage: .sources, underlying: NSError(domain: SCStreamErrorDomain, code: -3801))
    #expect(error.localizedDescription.contains("system-audio source discovery"))
    #expect(error.localizedDescription.contains("Microphone access is a separate"))
    #expect(error.systemAudioPermissionDenied)
}
@Test func captureDeviceAndConfigurationFailuresAreDistinct() {
    for code in [-3820, -3818, -3812, -3803] {
        let error = RecordingStartFailure(stage: .stream, underlying: NSError(domain: SCStreamErrorDomain, code: code))
        #expect(error.localizedDescription.contains("code \(code)"))
        #expect(!error.localizedDescription.contains("Check Microphone and Screen"))
        #expect(!error.systemAudioPermissionDenied)
    }
}
@Test func recordingDiagnosticsNeverExposeUnderlyingPrivateDetails() {
    let error = RecordingStartFailure(stage: .setup, underlying: NSError(domain: "private-device-name", code: 27, userInfo: [NSLocalizedDescriptionKey:"private audio path / secret contents"]))
    #expect(!error.localizedDescription.contains("private"))
    #expect(!error.localizedDescription.contains("secret"))
    #expect(error.localizedDescription.contains("audio writer setup"))
}
@Test func knownMicrophoneDenialRemainsActionable() {
    let error = RecordingStartFailure(stage: .microphone, underlying: CodaError.message("Microphone permission is required."))
    #expect(error.localizedDescription.contains("Microphone permission is required."))
    #expect(!error.localizedDescription.contains("Screen"))
    #expect(!error.systemAudioPermissionDenied)
}

@Test func unrelatedErrorCodeCannotEnableSystemAudioPermissionRecovery() {
    let error = RecordingStartFailure(stage: .sources, underlying: NSError(domain: "synthetic-device-error", code: -3801))
    #expect(!error.systemAudioPermissionDenied)
}
