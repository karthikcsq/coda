import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CodaCore
import Voz
@preconcurrency import ApplicationServices

@MainActor @Observable final class AppModel {
    private var visualReview = false
    var isVisualReview: Bool { visualReview }
    var dictationBusy = false
    var meetings: [Meeting] = []
    var selection: UUID?
    var status = "Ready when you are"
    var progress: Double?
    var busy = false
    var recording = false
    var startingCapture = false
    var recordingStarted: Date?
    var error: String?
    var showSettings = false
    var settingsChangesLocked: Bool { busy || recording || startingCapture || dictationBusy }
    func openSettings() { showSettings = true }
    func closeSettings() { showSettings = false }
    var showSummaryConsent = false
    var showRecordConsent = false
    var showingMeetingDetail = false
    private(set) var recordingStartFailure: RecordingStartFailure?
    var includeSystem = true
    var recordingSpeakerCount = 0
    var useDetectedSpeakerCount = true
    var detectedMeeting: DetectedMeeting?
    var recordingDetectedMeeting: DetectedMeeting?
    var meetingDetectionAvailable = false
    var detectMeetings = UserDefaults.standard.object(forKey: "detectMeetings") as? Bool ?? true {
        didSet { if !visualReview { UserDefaults.standard.set(detectMeetings, forKey: "detectMeetings") } }
    }
    var resolvedRecordingSpeakerCount: Int? {
        SpeakerCountSelection.resolve(manual: recordingSpeakerCount == 0 ? nil : recordingSpeakerCount,
            detected: recordingDetectedMeeting?.participantCount, useDetected: includeSystem && useDetectedSpeakerCount && detectMeetings)
    }
    func requestMeetingDetectionAccess() {
        guard !visualReview else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    var search = ""
    var modelConsent: Bool {
        didSet { if !visualReview { UserDefaults.standard.set(modelConsent, forKey: "modelConsent-v1.0") } }
    }
    var autoSummary: Bool {
        didSet { if !visualReview { UserDefaults.standard.set(autoSummary, forKey: "autoSummary") } }
    }
    var envPath: String {
        didSet { if !visualReview { UserDefaults.standard.set(envPath, forKey: "envPath") } }
    }
    let root: URL
    private let store: MeetingStore?
    private let pipeline: LocalPipeline
    private var operation: Task<Void, Never>?
    private var operationID: UUID?
    private var capture: MeetingCapture?
    private var activeRecording: Meeting?
    var selected: Meeting? { meetings.first { $0.id == selection } }
    var isOccupied: Bool { visualReview || busy || recording || startingCapture || dictationBusy }
    var filteredMeetings: [Meeting] { meetings.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }
    var meetingOperationInProgress: Bool { recording || busy || startingCapture }

    func openMeeting(_ id: UUID) {
        guard meetings.contains(where: { $0.id == id }) else { return }
        selection = id
        showingMeetingDetail = true
        closeSettings()
    }
    func showMeetingLibrary() {
        guard !meetingOperationInProgress else { return }
        showingMeetingDetail = false
    }
    func requestMeetingRecording() {
        guard !isOccupied else { return }
        recordingSpeakerCount = 0
        useDetectedSpeakerCount = true
        recordingDetectedMeeting = detectedMeeting
        showingMeetingDetail = true
        showRecordConsent = true
    }
    func dismissError() { error = nil; recordingStartFailure = nil }
    func presentRecordingStartFailure(_ failure: Error) {
        status = "Recording did not start"
        recordingStartFailure = failure as? RecordingStartFailure
        if recordingStartFailure?.systemAudioPermissionDenied == true {
            error = "macOS blocked meeting audio before recording started. Allow Coda in Screen & System Audio Recording, or choose Microphone only to record your voice without audio from other apps. Your saved meetings are still available."
        } else {
            error = recordingStartFailure?.localizedDescription ?? "Recording startup failed. Existing saved meetings were preserved."
        }
    }
    func reviewRecordingOptions(microphoneOnly: Bool = false) {
        guard !meetingOperationInProgress, !dictationBusy else { return }
        if microphoneOnly {
            guard recordingStartFailure?.systemAudioPermissionDenied == true else { return }
            includeSystem = false
        }
        dismissError()
        showingMeetingDetail = true
        showRecordConsent = true
    }
    func reviewSystemAudioPermission() {
        guard !visualReview, recordingStartFailure?.systemAudioPermissionDenied == true else { return }
        dismissError()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    init(preview: Bool = ProcessInfo.processInfo.arguments.contains("--ui-preview")) {
        visualReview = preview
        root = preview ? FileManager.default.temporaryDirectory.appendingPathComponent("Coda-UI-Preview-" + UUID().uuidString) : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Coda/Meetings", isDirectory: true)
        pipeline = LocalPipeline(cache: root.deletingLastPathComponent().appendingPathComponent("Models"))
        modelConsent = UserDefaults.standard.bool(forKey: "modelConsent-v1.0")
        autoSummary = UserDefaults.standard.bool(forKey: "autoSummary")
        // Build script embeds the project path, so Finder launches do not depend on a shell working directory.
        envPath = UserDefaults.standard.string(forKey: "envPath") ?? ((Bundle.main.object(forInfoDictionaryKey: "CodaProjectDirectory") as? String).map { $0 + "/.env" } ?? FileManager.default.currentDirectoryPath + "/.env")
        do {
            let store = try MeetingStore(root: root)
            let report = try store.loadRecovering()
            self.store = store; meetings = report.meetings
            if report.unreadableCount > 0 { error = "Some history files could not be read. They were preserved on disk; other meetings are available." }
        }
        catch { store = nil; self.error = "Local history could not be loaded. Existing files were preserved. Check access to ~/Library/Application Support/Coda/Meetings." }
        if preview {
            modelConsent = false; autoSummary = false; envPath = "/no-credentials-in-ui-preview/.env"
            var sample = Meeting(title: "Launch planning · synthetic preview", audioFile: "no-audio.m4a")
            sample.speakerNames = ["0": "Alex", "1": "Sam"]
            sample.segments = [
                Segment(id: "s1", start: 0, end: 7, speakers: [0], text: "Let's keep the first release focused on recording, a clear transcript, and useful next steps."),
                Segment(id: "s2", start: 8, end: 15, speakers: [1], text: "Agreed. I will review the onboarding copy. We have not set a deadline yet."),
                Segment(id: "s3", start: 16, end: 23, speakers: [0], text: "Then we have a decision: finish the local notebook before adding collaboration."),
                Segment(id: "s4", start: 24, end: 27, speakers: [0, 1], text: "Yes, let's start with that.")
            ]
            sample.summary = MeetingSummary(overview: [SummaryItem(text: "The first release focuses on a local meeting notebook.", evidence: ["s1", "s3"])], decisions: [SummaryItem(text: "Finish the local notebook before adding collaboration.", evidence: ["s3"])], actions: [SummaryItem(text: "Review onboarding copy.", evidence: ["s2"], owner: "Sam")])
            meetings = [sample]; try? store?.save(sample)
            status = "Synthetic UI preview • no audio, models, or network used"
        }
        selection = meetings.first?.id
    }
    var dictationModelReady: Bool { Voz.isDownloaded(cacheRoot: root.deletingLastPathComponent().appendingPathComponent("Models").path) }
    func transcribeDictation(_ audio: URL, vocabulary: [String] = []) async throws -> String { try await pipeline.dictate(audio, consent: modelConsent, vocabulary: vocabulary) }
    func prepareDictation() {
        guard !isOccupied, modelConsent else { return }
        busy = true
        let id = UUID(); operationID = id
        operation = Task {
            defer { busy = false; progress = nil; operation = nil; operationID = nil }
            do {
                try await pipeline.prepareVoz(consent: modelConsent) { [weak self] text, value in
                    Task { @MainActor in guard self?.operationID == id else { return }; self?.status = text; self?.progress = value }
                }
                status = "Voz is ready for local dictation"
            } catch is CancellationError { status = "Preparation cancelled" }
            catch { self.error = safeMessage(error); status = "Model preparation failed" }
        }
    }
    private func save(_ meeting: Meeting) throws {
        guard let store else { throw CodaError.message("Local storage is unavailable.") }
        try store.save(meeting)
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) { meetings[index] = meeting }
        else { meetings.insert(meeting, at: 0) }
    }
    func renameSpeaker(_ speaker: Int, name: String) {
        guard !isOccupied, var meeting = selected else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        meeting.speakerNames[String(speaker)] = name.isEmpty ? nil : name
        // A previous summary may use the prior name; avoid retaining stale attribution.
        meeting.summary = nil
        do { try save(meeting) } catch { self.error = "Could not save the speaker name." }
    }
    func renameMeeting(_ title: String) {
        guard !isOccupied, var meeting = selected, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        meeting.title = title
        do { try save(meeting) } catch { self.error = "Could not save the meeting title." }
    }
    func importAudio() {
        guard !visualReview else { status = "Visual review only • import is disabled"; return }
        guard !isOccupied else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]; panel.allowsMultipleSelection = false
        panel.message = "Import audio locally. Nothing is sent to OpenAI unless you enable automatic summaries or choose Send transcript."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let name = UUID().uuidString + "." + (url.pathExtension.isEmpty ? "audio" : url.pathExtension)
            try FileManager.default.copyItem(at: url, to: root.appendingPathComponent(name))
            var meeting = Meeting(title: url.deletingPathExtension().lastPathComponent, audioFile: name)
            meeting.created = Date()
            try save(meeting); openMeeting(meeting.id)
            if modelConsent { process(meeting) } else { openSettings(); status = "Imported locally • review model license to transcribe" }
        } catch { self.error = "Could not import the audio. Check storage and file access." }
    }
    func processSelected() { if let meeting = selected { process(meeting) } }
    func setSelectedSpeakerCount(_ count: Int) {
        guard !isOccupied, var meeting = selected, count == 0 || (1...4).contains(count) else { return }
        meeting.expectedSpeakerCount = count == 0 ? nil : count
        do { try save(meeting) } catch { self.error = "Could not save the speaker count." }
    }
    private func process(_ meeting: Meeting) {
        guard !isOccupied else { return }
        guard modelConsent else { openSettings(); return }
        busy = true; progress = nil
        let id = UUID(); operationID = id
        operation = Task {
            defer { busy = false; progress = nil; operation = nil; operationID = nil }
            do {
                let segments = try await pipeline.process(root.appendingPathComponent(meeting.audioFile), consent: modelConsent, speakerCount: meeting.expectedSpeakerCount) { [weak self] text, fraction in
                    Task { @MainActor in guard self?.operationID == id, self?.busy == true else { return }; self?.status = text; self?.progress = fraction }
                }
                try Task.checkCancellation()
                var updated = meeting; updated.segments = segments; updated.summary = nil; updated.speakerNames = [:]
                try save(updated)
                status = "Transcript saved locally"
                if autoSummary { try await summarize(updated, consent: autoSummary) }
            } catch is CancellationError { status = "Cancelled • audio and saved transcript retained" }
            catch { status = "Processing stopped"; self.error = safeMessage(error) }
        }
    }
    private func configuration() throws -> Configuration {
        // Only runtime reads this explicitly selected file. Never log contents or expose the key in the UI.
        let contents: String
        do { contents = try String(contentsOfFile: envPath, encoding: .utf8) }
        catch { throw CodaError.missingKey }
        return Configuration(contents: contents)
    }
    private func summarize(_ meeting: Meeting, consent: Bool) async throws {
        try Task.checkCancellation()
        guard consent else { throw CodaError.consentRequired }
        let config = try configuration()
        status = "Summarizing with OpenAI • transcript text only"
        progress = nil
        let result = try await Summarizer().summarize(meeting, configuration: config, consent: consent)
        try Task.checkCancellation()
        var updated = meeting; updated.summary = result
        try save(updated); status = "Summary saved • review against the transcript"
    }
    func sendSummary() {
        guard !isOccupied, let meeting = selected else { return }
        busy = true
        operation = Task {
            defer { busy = false; progress = nil; operation = nil; operationID = nil }
            do { try await summarize(meeting, consent: true) }
            catch is CancellationError { status = "Summary cancelled" }
            catch { status = "Transcript saved • summary unavailable"; self.error = safeMessage(error) }
        }
    }
    func cancel() { operationID = nil; operation?.cancel(); status = "Cancelling • an in-flight model operation may need to finish" }
    func startRecording() {
        guard !isOccupied else { return }
        let speakerCount = resolvedRecordingSpeakerCount
        let recordingIncludesSystem = includeSystem
        recordingStartFailure = nil
        showingMeetingDetail = true
        startingCapture = true
        status = "Waiting for recording permissions"
        Task {
            defer { startingCapture = false }
            do {
                var meeting = Meeting(title: "Meeting " + Date().formatted(date: .abbreviated, time: .shortened), audioFile: UUID().uuidString + ".m4a")
                meeting.expectedSpeakerCount = speakerCount
                let capture = MeetingCapture()
                capture.onFailure = { [weak self = self] in Task { @MainActor in self?.captureFailed() } }
                try await capture.start(url: root.appendingPathComponent(meeting.audioFile), includeSystem: recordingIncludesSystem)
                self.capture = capture; activeRecording = meeting
                recording = true; recordingStarted = Date(); status = includeSystem ? "Recording microphone + system audio" : "Recording microphone"
            } catch { presentRecordingStartFailure(error) }
        }
    }
    private func captureFailed() {
        guard recording else { return }
        error = "System audio capture was interrupted. Stopping and attempting to save the recording."
        stopRecording()
    }
    func stopRecording() {
        guard recording, let capture, let meeting = activeRecording else { return }
        recording = false; busy = true; status = "Finalizing recording"
        Task {
            do {
                try await capture.stop(url: root.appendingPathComponent(meeting.audioFile))
                try save(meeting); openMeeting(meeting.id)
                self.capture = nil; activeRecording = nil; recordingStarted = nil; busy = false
                if modelConsent { process(meeting) } else { status = "Recording saved locally"; openSettings() }
            } catch { self.capture = nil; activeRecording = nil; recordingStarted = nil; busy = false; status = "Recording could not be finalized"; self.error = safeMessage(error) }
        }
    }
    func export(markdown: Bool) {
        guard let meeting = selected else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = markdown ? [UTType(filenameExtension: "md")!] : [.plainText]
        panel.nameFieldStringValue = meeting.title.replacingOccurrences(of: "/", with: "-") + (markdown ? ".md" : ".txt")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Export.render(meeting, markdown: markdown).write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = "The export could not be saved." }
    }
    func deleteSelected() {
        guard !isOccupied, let meeting = selected else { return }
        do { try store?.remove(meeting); meetings.removeAll { $0.id == meeting.id }; selection = meetings.first?.id }
        catch { self.error = "Could not delete this meeting completely. Check local storage." }
    }
    func chooseEnv() {
        let panel = NSOpenPanel(); panel.showsHiddenFiles = true; panel.allowsMultipleSelection = false
        panel.message = "Choose your .env file. Coda reads it only when you request a summary."
        if panel.runModal() == .OK, let url = panel.url { envPath = url.path }
    }
    private func safeMessage(_ error: Error) -> String {
        if let known = error as? CodaError { return known.localizedDescription }
        if error is URLError { return "Network request failed. Check your connection and retry. Your saved transcript is safe." }
        return "The operation failed. Check that the audio is supported and the models have downloaded, then retry. Your saved files were preserved."
    }
}
