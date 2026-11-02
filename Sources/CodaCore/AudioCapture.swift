import AVFoundation
import ScreenCaptureKit

/// Each SC stream owns its own writer and original timestamp. Never append incompatible microphone/system formats together.
final class AudioSink: @unchecked Sendable {
    let url: URL
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private(set) var firstTime: CMTime?
    private(set) var failure: Error?
    init(url: URL) { self.url = url }
    func append(_ sample: CMSampleBuffer) {
        guard failure == nil, CMSampleBufferDataIsReady(sample), CMSampleBufferGetNumSamples(sample) > 0,
              CMSampleBufferGetPresentationTimeStamp(sample).isNumeric, let description = CMSampleBufferGetFormatDescription(sample),
              let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              format.mSampleRate > 0, format.mChannelsPerFrame > 0 else { return }
        do {
            if writer == nil {
                let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: format.mSampleRate, AVNumberOfChannelsKey: Int(format.mChannelsPerFrame), AVEncoderBitRateKey: 128_000])
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else { throw CodaError.message("Unsupported capture audio format.") }
                writer.add(input)
                guard writer.startWriting() else { throw writer.error ?? CodaError.emptyAudio }
                firstTime = CMSampleBufferGetPresentationTimeStamp(sample)
                writer.startSession(atSourceTime: firstTime!)
                self.writer = writer; self.input = input
            }
            guard let input, let writer else { return }
            guard input.isReadyForMoreMediaData else { throw CodaError.message("Audio capture could not keep up. Stop and retry with fewer running apps.") }
            guard input.append(sample) else { throw writer.error ?? CodaError.emptyAudio }
        } catch { failure = error }
    }
    func finish() async throws -> (URL, CMTime)? {
        guard let writer, let input, let firstTime else {
            if let failure { throw failure }
            return nil
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let failure { throw failure }
        guard writer.status == .completed else { throw writer.error ?? CodaError.emptyAudio }
        return (url, firstTime)
    }
}

public final class MeetingCapture: NSObject, SCStreamOutput, SCStreamDelegate, AVAudioRecorderDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "coda.capture.audio")
    private var stream: SCStream?
    private var system: AudioSink?
    private var microphone: AudioSink?
    private var recorder: AVAudioRecorder?
    private var tempDirectory: URL?
    private var acceptingSamples = true
    private var reportedFailure = false
    public override init() { super.init() }
    public var onFailure: (@Sendable () -> Void)?

    @MainActor public func start(url: URL, includeSystem: Bool) async throws {
        var stage = RecordingStartFailure.Stage.microphone
        do {
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard allowed else { throw CodaError.message("Microphone permission is required. Enable Coda in System Settings → Privacy & Security → Microphone.") }
        if !includeSystem {
            let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000])
            recorder.delegate = self
            guard recorder.record() else { throw CodaError.message("The microphone could not begin recording.") }
            self.recorder = recorder
            return
        }
        stage = .sources
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CodaError.message("No display is available for system audio capture.") }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.width = 2; config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false
        stage = .setup
        let temp = url.deletingLastPathComponent().appendingPathComponent("capture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        tempDirectory = temp
        system = AudioSink(url: temp.appendingPathComponent("system.m4a"))
        microphone = AudioSink(url: temp.appendingPathComponent("microphone.m4a"))
        stage = .stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        // No screen output is registered or persisted. macOS still requires Screen & System Audio Recording permission.
        self.stream = stream
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            // Start can fail after a writer has received samples. Use the same drain/finalize
            // path and retain recovery files instead of deleting them while callbacks run.
            try? await stop(url: url)
            self.stream = nil
            throw error
        }
        } catch { throw RecordingStartFailure(stage: stage, underlying: error) }
    }
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard acceptingSamples else { return }
        if type == .audio { system?.append(sampleBuffer) }
        else if type == .microphone { microphone?.append(sampleBuffer) }
        if !reportedFailure, system?.failure != nil || microphone?.failure != nil {
            reportedFailure = true; onFailure?()
        }
    }
    public func stream(_ stream: SCStream, didStopWithError error: Error) { onFailure?() }
    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) { onFailure?() }
    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) { if !flag { onFailure?() } }
    @MainActor public func stop(url: URL) async throws {
        if let recorder { recorder.stop(); self.recorder = nil; return }
        guard let stream else { throw CodaError.message("There is no active recording.") }
        defer { self.stream = nil }
        // Even an already-interrupted stream may throw on stop. Always detach/drain and
        // finish BOTH writers before surfacing an error, preserving usable recovery tracks.
        let tracks = try await CaptureFinalization.finish(
            stop: { try await stream.stopCapture() },
            detach: {
                try? stream.removeStreamOutput(self, type: .audio)
                try? stream.removeStreamOutput(self, type: .microphone)
                await withCheckedContinuation { continuation in
                    self.queue.async { self.acceptingSamples = false; continuation.resume() }
                }
            },
            writers: [{ try await self.system?.finish() }, { try await self.microphone?.finish() }])
        try await CaptureMixer.mix(tracks, to: url)
        cleanup()
    }
    private func cleanup() {
        if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
        tempDirectory = nil; system = nil; microphone = nil
    }
}

@MainActor enum CaptureMixer {
    static func mix(_ tracks: [(URL, CMTime)], to url: URL) async throws {
        guard !tracks.isEmpty else { throw CodaError.emptyAudio }
        let origin = tracks.map(\.1).min { CMTimeCompare($0, $1) < 0 }!
        let composition = AVMutableComposition()
        let mix = AVMutableAudioMix()
        var parameters: [AVMutableAudioMixInputParameters] = []
        for (file, first) in tracks {
            let asset = AVURLAsset(url: file)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw CodaError.emptyAudio }
            let range = try await source.load(.timeRange)
            try destination.insertTimeRange(range, of: source, at: CMTimeSubtract(first, origin))
            let parameter = AVMutableAudioMixInputParameters(track: destination)
            parameter.setVolume(tracks.count > 1 ? 0.5 : 1, at: .zero)
            parameters.append(parameter)
        }
        mix.inputParameters = parameters
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else { throw CodaError.emptyAudio }
        export.audioMix = mix
        try await export.export(to: url, as: .m4a)
    }
}
