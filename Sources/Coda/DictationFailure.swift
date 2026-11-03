import Foundation
import Voz

/// Safe, actionable categories. SDK descriptions may contain paths or other user
/// data, so retain only the stage and a bounded system error identifier.
enum DictationFailure: Error, Equatable {
    case modelNotReady, noWords, invalidAudio, modelLoad(String), recognition(String)

    static func diagnosticCode(_ error: Error) -> String {
        if let error = error as? VozError {
            switch error {
            case .invalidAudio: return "Voz.invalidAudio"
            case .invalidModel: return "Voz.invalidModel"
            case .unsupportedPlatform: return "Voz.unsupportedPlatform"
            }
        }
        let error = error as NSError
        let domain = [NSCocoaErrorDomain, NSOSStatusErrorDomain, NSPOSIXErrorDomain, "com.apple.CoreML"]
            .contains(error.domain) ? error.domain : "system"
        return "\(domain) \(error.code)"
    }
    static func decodingOrRecognition(_ error: Error) -> Self {
        if case .invalidAudio = error as? VozError { return .invalidAudio }
        return .recognition(diagnosticCode(error))
    }
    var title: String {
        switch self {
        case .noWords: "No words recognized"
        case .invalidAudio: "Recording couldn’t be read"
        case .modelNotReady, .modelLoad: "Speech model unavailable"
        case .recognition: "Transcription failed"
        }
    }
    var message: String {
        switch self {
        case .modelNotReady: "Prepare the local speech model in Settings, then retry."
        case .noWords: "The speech model returned no words. Wait for Listening, then speak and check your Mac’s selected microphone."
        case .invalidAudio: "The recorded audio could not be decoded. Check the input device and retry."
        case .modelLoad(let code): "The local speech model could not load (\(code)). Reopen Coda or prepare the model in Settings."
        case .recognition(let code): "Local speech recognition failed (\(code)). Retry the dictation."
        }
    }
}

struct DictationCaptureStats {
    var seconds: Double = 0
    var peakDB: Double?
    var bytes = 0
    var description: String {
        let duration = seconds.isFinite ? max(0, seconds) : 0
        var detail = String(format: "Captured %.1f seconds", duration)
        if let peakDB, peakDB.isFinite { detail += String(format: "; peak input %.0f dBFS", peakDB) }
        return detail + "; audio \(max(0, bytes)) bytes."
    }
}
