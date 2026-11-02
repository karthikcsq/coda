import Foundation
import ScreenCaptureKit

/// Safe capture diagnostics: never display arbitrary NSError userInfo, file paths or device details.
public struct RecordingStartFailure: Error, LocalizedError, Sendable {
    public enum Stage: String, Sendable {
        case microphone = "microphone setup"
        case sources = "system-audio source discovery"
        case setup = "audio writer setup"
        case stream = "system/microphone stream startup"
    }
    public let stage: Stage
    public let code: Int
    public let detail: String
    public let systemAudioPermissionDenied: Bool
    public init(stage: Stage, underlying: Error) {
        self.stage = stage
        let error = underlying as NSError
        code = error.code
        systemAudioPermissionDenied = error.domain == SCStreamErrorDomain && error.code == -3801 && stage != .microphone
        if let known = underlying as? CodaError { detail = known.localizedDescription; return }
        if error.domain == SCStreamErrorDomain {
            switch error.code {
            case -3801: detail = "macOS declined system-audio capture. Review Coda in Screen & System Audio Recording settings. Microphone access is a separate permission."
            case -3820: detail = "The system could not start microphone capture. Check that an input device is connected and available. This error alone does not mean permission is missing."
            case -3818: detail = "The system could not start meeting-audio capture. Check the audio output device and retry."
            case -3812, -3810: detail = "macOS rejected the capture configuration. This is a capture setup error, not proof of missing permission."
            case -3813, -3814, -3815: detail = "No usable display or system-audio capture source was available."
            case -3803: detail = "macOS rejected the app's capture entitlements. Changing microphone permission will not fix this build issue."
            default: detail = "macOS could not start the capture stream. The error does not establish that a permission is missing."
            }
        } else if error.domain == NSCocoaErrorDomain {
            detail = "The recording file could not be prepared. Check available disk space and access to Coda's local storage."
        } else {
            detail = "The audio device or capture service could not start. Check that the input/output devices are available and retry."
        }
    }
    public var errorDescription: String? {
        "Recording did not start during \(stage.rawValue) (code \(code)). \(detail) Existing saved meetings were not changed."
    }
}
