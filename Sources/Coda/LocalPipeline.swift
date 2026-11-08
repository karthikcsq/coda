import Foundation
import CodaCore
import Voz
import CodaWho

actor LocalPipeline {
    private var voz: Voz?
    private var who: Who?
    private let vozLoader: SharedResourceLoader<Voz, Double?>
    private let cache: String
    init(cache: URL) {
        self.cache = cache.path
        let cacheRoot = cache.path
        vozLoader = SharedResourceLoader { progress in
            try await Voz(cacheRoot: cacheRoot) { progress($0.fraction) }
        }
    }
    private func loadVoz(progress: @escaping @Sendable (String, Double?) -> Void) async throws -> Voz {
        let prepared = try await vozLoader.get { progress("Preparing speech recognition", $0) }
        try Task.checkCancellation()
        voz = prepared
        return prepared
    }
    func prepareVoz(consent: Bool, progress: @escaping @Sendable (String, Double?) -> Void) async throws {
        guard consent else { throw CodaError.message("Accept model terms before preparing Voz.") }
        try Task.checkCancellation()
        _ = try await loadVoz(progress: progress)
        try Task.checkCancellation()
    }
    func dictate(_ audio: URL, consent: Bool, vocabulary: [String] = []) async throws -> String {
        guard consent, Voz.isDownloaded(cacheRoot: cache) else { throw DictationFailure.modelNotReady }
        try Task.checkCancellation()
        // The prepared cache is required: no first-use downloads during a dictation session.
        if voz == nil {
            do { voz = try await loadVoz { _, _ in } }
            catch is CancellationError { throw CancellationError() }
            catch { throw DictationFailure.modelLoad(DictationFailure.diagnosticCode(error)) }
        }
        guard let voz else { throw DictationFailure.modelNotReady }
        let result: Voz.Result
        do { result = try await voz.transcribe(audio, vocabulary: vocabulary) }
        catch is CancellationError { throw CancellationError() }
        catch { throw DictationFailure.decodingOrRecognition(error) }
        try Task.checkCancellation()
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DictationFailure.noWords }
        return result.text
    }
    func process(_ audio: URL, consent: Bool, speakerCount: Int? = nil, progress: @escaping @Sendable (String, Double?) -> Void) async throws -> [Segment] {
        guard consent else { throw CodaError.message("Review and accept the model license in Settings before processing.") }
        try Task.checkCancellation()
        if voz == nil {
            progress("Preparing Voz • first use downloads the model", nil)
            voz = try await loadVoz(progress: progress)
        }
        try Task.checkCancellation()
        guard let voz else { throw CodaError.message("Voz could not load.") }
        progress("Transcribing on your Mac", 0)
        let transcript = try await voz.transcribe(audio) { value in progress("Transcribing on your Mac", value.fractionCompleted) }
        try Task.checkCancellation()
        if who == nil { who = Who(directory: nil, cacheRoot: cache) }
        guard let who else { throw CodaError.message("Who could not load.") }
        if !who.isDownloaded() {
            progress("Downloading Who", nil)
            try await who.download { value in progress("Downloading Who", value) }
        }
        try Task.checkCancellation()
        progress("Finding speaker turns on your Mac", nil)
        let diarization = try await who.diarize(contentsOf: audio, speakerCount: speakerCount)
        try Task.checkCancellation()
        let segments = Alignment.align(words: transcript.words.map { CodaCore.Word($0.text, $0.start, $0.end) },
            turns: diarization.turns.map { SpeakerTurn($0.speaker, $0.start, $0.end) })
        guard !segments.isEmpty else { throw CodaError.emptyAudio }
        return segments
    }
}
