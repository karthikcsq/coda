import SwiftUI
import AVFoundation
import AppKit
@preconcurrency import ApplicationServices
import KeyboardShortcuts
import CodaCore

extension KeyboardShortcuts.Name {
    static let codaDictation = Self("codaDictation")
    static let codaCancelDictation = Self("codaCancelDictation")
}

@MainActor @Observable final class DictationController: NSObject, AVAudioRecorderDelegate {
    let accessibility = AccessibilityAccess(
        check: { AXIsProcessTrusted() },
        prompt: {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        openSettings: {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    )
    private var awaitingAccessibility = false
    func refreshAccessibility() {
        accessibility.refresh()
        if modifierShortcut, modifierMonitor?.available != true, !visualReview { configureModifierShortcut() }
        if awaitingAccessibility, accessibility.trusted, !lifecycle.busy {
            awaitingAccessibility = false
            message = "Automatic insertion is ready. Focus your destination and dictate again; existing text can still be copied."
        }
    }
    func enableAutomaticInsertion() {
        guard !visualReview else { return }
        guard !lifecycle.busy else { return }
        autoInsert = true
        awaitingAccessibility = true
        accessibility.requestFromUserAction()
        message = accessibility.guidance
        refreshAccessibility()
    }
    var records: [DictationRecord] = []
    var historyWarning: String?
    var selectedRecord: UUID?
    var pendingInsertion: UUID?
    var workspaceSection = "Home"
    var showOnboarding = false
    private(set) var onboardingSeen = false
    private(set) var practiceSession = false
    var practiceShortcutActive = false
    var practiceText = ""
    var practiceMessage = ""
    var practiceCompleted = false
    func finishOnboarding() {
        guard !lifecycle.busy else { return }
        showOnboarding = false; onboardingSeen = true
        if !visualReview { UserDefaults.standard.set(true, forKey: "onboardingSeen-v1") }
    }
    func practice() {
        guard !visualReview else { return }
        if practiceSession && lifecycle.phase == .listening { finish(); return }
        guard !lifecycle.busy, pendingInsertion == nil else { return }
        practiceSession = true; practiceText = ""; practiceMessage = ""; practiceCompleted = false
        begin()
        if !lifecycle.busy { practiceSession = false }
    }
    private var history: DictationHistory?
    private var sessionID: UUID?
    private var retryGeneration: UUID?
    private var retryTimeout: Task<Void, Never>?
    private var dismissal: Task<Void, Never>?
    private var presentationID = UUID()
    var overlayIsVisible: Bool { overlay?.isVisible == true }
    private var retryTask: Task<Void, Never>?
    func dismissAfterResult(after delay: Duration = .seconds(4)) {
        dismissal?.cancel()
        let presentation = presentationID
        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self, self.presentationID == presentation, !self.lifecycle.busy, self.pendingInsertion == nil else { return }
            self.overlay?.hide()
        }
    }
    private func saveRecord(_ record: DictationRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) { records[index] = record }
        else { records.insert(record, at: 0) }
        selectedRecord = record.id
        do { guard let history else { throw CodaError.emptyAudio }; try history.save(record) }
        catch { historyWarning = "Could not save dictation history to disk. Keep this window open and copy any text you need." }
    }
    private func saveSession(outcome: DictationRecord.Outcome, detail: String) {
        guard let sessionID else { return }
        saveRecord(DictationRecord(id: sessionID, text: text, target: targetName, outcome: outcome, detail: detail, rawText: rawText.isEmpty ? nil : rawText, cleanupMode: cleanupMode, snippetTrigger: sessionSnippetTrigger))
    }
    func copyRecord(_ record: DictationRecord) {
        guard !visualReview else { message = "Visual review • clipboard unchanged"; return }
        guard !record.text.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.text, forType: .string)
        message = "Copied • paste wherever you choose"
    }
    func copyOriginal(_ record: DictationRecord) {
        guard let original = record.rawText else { return }
        var copy = record; copy.text = original; copyRecord(copy)
    }
    func armInsertion(_ record: DictationRecord) {
        guard !visualReview else { message = "Visual review • insertion disabled"; return }
        guard !lifecycle.busy, retryTask == nil, model?.isOccupied != true, !record.text.isEmpty else { return }
        corrections.stop()
        stopCorrectionReview()
        wordSuggestions.close()
        pendingInsertion = record.id; text = record.text; targetName = "Choose a destination"
        message = "Click your destination field, then press your shortcut or Insert text here. No recording will start."
        KeyboardShortcuts.enable(.codaCancelDictation)
        retryTimeout?.cancel()
        let generation = UUID(); retryGeneration = generation
        retryTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard !Task.isCancelled, let self, self.retryGeneration == generation else { return }; self.pendingInsertion = nil; self.retryGeneration = nil
            self.message = "Insertion selection expired. Your text is saved in History."
            self.overlay?.hide()
            KeyboardShortcuts.disable(.codaCancelDictation)
        }
        show()
    }
    private func insertPending() {
        guard retryTask == nil else { return }
        guard let id = pendingInsertion, let index = records.firstIndex(where: { $0.id == id }), model?.isOccupied != true else { return }
        pendingInsertion = nil; retryGeneration = nil; retryTimeout?.cancel(); KeyboardShortcuts.disable(.codaCancelDictation)
        insertion.captureTarget(); targetName = insertion.targetName
        var record = records[index]
        KeyboardShortcuts.enable(.codaCancelDictation)
        retryTask = Task { [weak self] in
        guard let self else { return }
        defer { retryTask = nil; KeyboardShortcuts.disable(.codaCancelDictation) }
        let cleanupInput = record.cleanupMode == .smart ? record.rawText : nil
        let success = await insertion.insertWithFallback(record.text, observeCorrections: record.snippetTrigger != nil ? nil : { [weak self] in self?.observeCorrections($0, cleanupInput: cleanupInput) })
        record.outcome = success ? .inserted : insertion.deliveryAttempted ? .deliveryUnconfirmed : .copyRequired
        record.target = targetName
        record.detail = insertion.reason
        message = record.detail; saveRecord(record); insertion.clear(); dismissAfterResult()
        }
    }
    func dismissOverlay() {
        if lifecycle.busy || pendingInsertion != nil || retryTask != nil { cancel() }
        else { overlay?.hide() }
    }
    var lifecycle = DictationLifecycle()
    var message = "Ready to dictate"
    var failureTitle = "Dictation failed"
    private var captureStats = DictationCaptureStats()
    var text = ""
    private var rawText = ""
    let smartFormatter: SmartFormatter
    let personalTuning: PersonalTuning
    let preferences: DictationPreferences
    private var targetBundleID: String?
    var activeStyleLabel: String { cleanupMode == .none ? "Raw text" : sessionPreferences.style(forBundleID: targetBundleID).title }
    private var sessionPreferences = DictationPreferenceSettings()
    private var sessionSnippetTrigger: String?
    func snapshotPreferences(bundleID: String?) {
        sessionPreferences = preferences.settings; targetBundleID = bundleID
    }
    func deliveryText(recognized: String, cleaned: String) -> DictationPersonalizationResult {
        DictationPersonalization.forDelivery(recognized: recognized, cleaned: cleaned, mode: cleanupMode,
                                              bundleID: targetBundleID, settings: sessionPreferences)
    }
    private var cleanupDetail = ""
    var cleanupMode: DictationCleanupMode {
        didSet { if !visualReview {
            UserDefaults.standard.set(cleanupMode.rawValue, forKey: "dictationCleanupMode")
            if cleanupMode == .smart { smartFormatter.warm() } else { smartFormatter.stop() }
        } }
    }
    var level: Double = 0
    var started: Date?
    var targetName = "Copy result"
    var mode: DictationMode {
        didSet { if !visualReview { UserDefaults.standard.set(mode.rawValue, forKey: "dictationMode"); cancel() } }
    }
    var modifierShortcut = false {
        didSet {
            if !visualReview {
                UserDefaults.standard.set(modifierShortcut, forKey: "dictationModifierShortcut")
                cancel(); lifecycle.resetKeys(); configureModifierShortcut()
            }
        }
    }
    var modifierShortcutStatus: String {
        if !shortcutPauses.isEmpty { return "Shortcut paused while this Mac is locked, asleep or inactive." }
        if ModifierShortcut.voiceOverConflict { return "Control–Option is reserved while VoiceOver is active. Choose a custom shortcut." }
        if accessibility.trusted, !visualReview, modifierMonitor?.available != true { return "Shortcut listener unavailable. Refresh Accessibility status in System settings." }
        return accessibility.trusted ? "Hold Control + Option alone briefly to dictate. Release either to finish. Other keys cancel the chord; events are never intercepted." : "Control–Option needs Coda’s existing Accessibility access."
    }
    private var modifierMonitor: ModifierShortcut?
    private var shortcutPauses = Set<Notification.Name>()
    private func configureModifierShortcut() {
        modifierMonitor?.stop()
        guard shortcutPauses.isEmpty else { return }
        if modifierShortcut {
            KeyboardShortcuts.disable(.codaDictation)
            let monitor = ModifierShortcut { [weak self] event in
                guard let self else { return }
                switch event {
                case .down: self.handle(self.lifecycle.keyDown(mode: self.mode))
                case .up: self.handle(self.lifecycle.keyUp(mode: self.mode))
                case .cancel: self.cancel(); self.lifecycle.resetKeys()
                default: break
                }
            }
            modifierMonitor = monitor; monitor.start()
        } else { KeyboardShortcuts.enable(.codaDictation) }
    }
    var autoInsert: Bool {
        didSet { if !visualReview { UserDefaults.standard.set(autoInsert, forKey: "dictationAutoInsert") } }
    }
    private let previewMicrophoneAllowed: Bool
    var permissionGranted: Bool { visualReview ? previewMicrophoneAllowed : AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    var shortcutLabel: String { modifierShortcut ? "⌃⌥ Control + Option" : KeyboardShortcuts.getShortcut(for: .codaDictation)?.description ?? "Choose a shortcut" }
    private var visualReview = false
    private weak var model: AppModel?
    private let insertion = DictationInsertion()
    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    private var task: Task<Void, Never>?
    private var meterTask: Task<Void, Never>?
    private var overlay: DictationOverlay?
    private var observers: [NSObjectProtocol] = []
    let dictionary: CustomDictionary
    let wordSuggestions: DictionarySuggestions
    var showDictionaryWindow: (() -> Void)?
    private let corrections = DictationCorrections()
    private var correctionReview: Task<Void, Never>?
    private var correctionReviewGeneration = UUID()
    private func stopCorrectionReview() {
        correctionReviewGeneration = UUID(); correctionReview?.cancel(); correctionReview = nil
    }
    var learnWords: Bool {
        get { dictionary.learningEnabled }
        set {
            if !newValue { corrections.stop(); stopCorrectionReview(); wordSuggestions.close() }
            dictionary.learningEnabled = newValue
        }
    }
    /// Watches the destination field after insertion. Word changes feed dictionary
    /// suggestions; when the text was Smart-cleaned, the edited passage is also kept
    /// for personal fine-tuning (`cleanupInput` is what the cleanup model received).
    private func observeCorrections(_ target: DictationCorrectionTarget, cleanupInput: String?) {
        let tuneOnEdits = personalTuning.enabled && cleanupInput != nil
        guard learnWords || tuneOnEdits, !visualReview else { return }
        wordSuggestions.preferredFrame = insertion.targetDisplayFrame
        let session = UUID()
        corrections.start(target) { [weak self] changes, original, edited in
            guard let self else { return }
            if learnWords { reviewCorrections(changes, original: original, edited: edited, session: session) }
            if tuneOnEdits, let cleanupInput {
                personalTuning.record(CleanupEdit(id: session, input: cleanupInput, inserted: original, edited: edited))
            }
        }
    }
    func reviewCorrections(_ changes: [WordCorrection], original: String, edited: String, session: UUID) {
        stopCorrectionReview()
        // Reconcile undo immediately, before an asynchronous classifier can finish.
        let strong = changes.filter { CorrectionEvidence.strength($0) == .strong }
        let ambiguous = changes.filter { CorrectionEvidence.strength($0) == .plausible }
        dictionary.suggest(strong, session: session)
        guard learnWords, !ambiguous.isEmpty else { return }
        let generation = correctionReviewGeneration
        correctionReview = Task { [weak self] in
            guard let self else { return }
            let decisions = await smartFormatter.classifyCorrections(original: original, edited: edited, pairs: ambiguous)
            guard !Task.isCancelled, correctionReviewGeneration == generation, learnWords else { return }
            let accepted = strong + CorrectionEvidence.filter(ambiguous, judgments: decisions)
            dictionary.suggest(accepted, session: session)
            correctionReview = nil
        }
    }

    override convenience init() { self.init(preview: false) }
    init(preview: Bool, formatter: SmartFormatter? = nil, previewMicrophoneAllowed: Bool = false) {
        self.previewMicrophoneAllowed = preview && previewMicrophoneAllowed
        let dictionary = CustomDictionary(preview: preview || ProcessInfo.processInfo.arguments.contains("--ui-preview"))
        self.dictionary = dictionary
        smartFormatter = formatter ?? SmartFormatter()
        let previewRun = preview || ProcessInfo.processInfo.arguments.contains("--ui-preview")
        preferences = DictationPreferences(preview: previewRun)
        personalTuning = PersonalTuning(root: previewRun ? FileManager.default.temporaryDirectory.appendingPathComponent("Coda-Tuning-Preview-" + UUID().uuidString) : nil)
        wordSuggestions = DictionarySuggestions(dictionary: dictionary, preview: preview || ProcessInfo.processInfo.arguments.contains("--ui-preview"))
        cleanupMode = DictationCleanupMode(rawValue: UserDefaults.standard.string(forKey: "dictationCleanupMode") ?? "light") ?? .light
        mode = DictationMode(rawValue: UserDefaults.standard.string(forKey: "dictationMode") ?? "toggle") ?? .toggle
        autoInsert = UserDefaults.standard.object(forKey: "dictationAutoInsert") as? Bool ?? true
        super.init()
        personalTuning.isDictating = { [weak self] in self?.lifecycle.busy ?? false }
        personalTuning.modelChanged = { [weak self] in self?.smartFormatter.reloadModel() }
        wordSuggestions.onReview = { [weak self] in
            self?.model?.closeSettings()
            self?.workspaceSection = "Dictionary"
            self?.showDictionaryWindow?()
        }
        visualReview = previewRun
        onboardingSeen = UserDefaults.standard.bool(forKey: "onboardingSeen-v1")
        modifierShortcut = UserDefaults.standard.bool(forKey: "dictationModifierShortcut")
        do {
            let base = preview || ProcessInfo.processInfo.arguments.contains("--ui-preview")
                ? FileManager.default.temporaryDirectory.appendingPathComponent("Coda-Preview-" + UUID().uuidString)
                : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Coda/Dictations")
            let history = try DictationHistory(root: base); self.history = history
            let loaded = try history.load(); records = loaded.records; selectedRecord = records.first?.id
            if loaded.skipped > 0 { historyWarning = "Some history files could not be read. They were preserved on disk." }
        } catch { historyWarning = "Dictation history is unavailable. New text will remain in memory until you quit." }
        if preview { return } // Offscreen tests never register shortcuts, observers or permission actions.
        _ = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessibility() }
        }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLocked(_:)), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenUnlocked(_:)), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        KeyboardShortcuts.onKeyDown(for: .codaDictation) { [weak self] in
            guard let self, !self.modifierShortcut else { return }; handle(lifecycle.keyDown(mode: mode))
        }
        KeyboardShortcuts.onKeyUp(for: .codaDictation) { [weak self] in
            guard let self, !self.modifierShortcut else { return }; handle(lifecycle.keyUp(mode: mode))
        }
        KeyboardShortcuts.setShortcut(.init(.escape, modifiers: []), for: .codaCancelDictation)
        KeyboardShortcuts.onKeyDown(for: .codaCancelDictation) { [weak self] in self?.cancel() }
        KeyboardShortcuts.disable(.codaCancelDictation)
        configureModifierShortcut()
        if cleanupMode == .smart { smartFormatter.warm() }
        for (pause, resume) in [(NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification),
                                (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification),
                                (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification)] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: pause, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pauseShortcut(for: pause) }
            })
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: resume, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeShortcut(for: pause) }
            })
        }
    }
    // macOS also posts this lock notification when the session locks without system sleep.
    @objc private func screenLocked(_ notification: Notification) { pauseShortcut(for: notification.name) }
    @objc private func screenUnlocked(_ notification: Notification) {
        resumeShortcut(for: NSNotification.Name("com.apple.screenIsLocked"))
    }
    func pauseShortcut(for reason: Notification.Name) {
        shortcutPauses.insert(reason); modifierMonitor?.stop()
        cancel(); lifecycle.resetKeys()
    }
    func resumeShortcut(for reason: Notification.Name) {
        guard shortcutPauses.remove(reason) != nil, shortcutPauses.isEmpty, !visualReview else { return }
        configureModifierShortcut()
    }
    func attach(_ model: AppModel) { self.model = model }
    func useSuggestedShortcut() {
        guard !visualReview else { return }
        let candidate = KeyboardShortcuts.Shortcut(.d, modifiers: [.control, .option, .command])
        guard !candidate.isTakenBySystem else { message = "The suggested shortcut is used by macOS. Choose another in the recorder."; return }
        modifierShortcut = false
        KeyboardShortcuts.setShortcut(candidate, for: .codaDictation)
        message = "Shortcut set. Other apps' custom shortcuts cannot all be detected."
    }
    func button() {
        if pendingInsertion != nil { insertPending(); return }
        if lifecycle.phase == .listening { finish() }
        else if !lifecycle.busy { begin() }
    }
    private func handle(_ intent: DictationIntent) {
        switch intent { case .begin:
            if pendingInsertion != nil { insertPending() }
            else if showOnboarding && NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() {
                if practiceShortcutActive { practice() }
                else { message = "Continue to Try it out to test your shortcut." }
            }
            else { begin() }; case .finish: finish(); case .cancel: cancel(); case .none: break }
    }
    private func show() {
        presentationID = UUID()
        dismissal?.cancel()
        refreshAccessibility()
        if overlay == nil { overlay = DictationOverlay(controller: self) }
        overlay?.show(preferredFrame: insertion.targetDisplayFrame)
    }
    func previewOverlay() {
        guard !lifecycle.busy else { return }
        if text.isEmpty { message = "Ready when you are" }; show()
    }
    private func begin() {
        guard !visualReview else { message = "Visual review only • microphone stays off"; show(); return }
        guard let model, !lifecycle.busy, retryTask == nil else { return }
        guard !model.isOccupied else { message = "Finish the meeting operation before dictating."; show(); dismissAfterResult(); return }
        guard model.modelConsent, model.dictationModelReady else {
            message = "Prepare Voz in Settings & privacy before dictating. No microphone is running."; show(); dismissAfterResult(); return
        }
        guard let id = lifecycle.begin(meetingBusy: false, modelReady: true) else { return }
        corrections.stop()
        stopCorrectionReview()
        wordSuggestions.close()
        // Overlap a cold formatter start with listening instead of delaying insertion
        // after the transcript is ready. This never downloads models or captures audio.
        if cleanupMode == .smart { smartFormatter.warm() }
        // Heard-as review needs the local model itself; load it while listening.
        if cleanupMode != .none, !dictionary.soundAlikeRules.isEmpty { Task { await smartFormatter.prepareModel() } }
        snapshotPreferences(bundleID: practiceSession ? nil : NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        model.warmDictation()
        sessionID = id; sessionSnippetTrigger = nil
        model.dictationBusy = true; text = ""; rawText = ""; level = 0
        failureTitle = "Dictation failed"; captureStats = DictationCaptureStats()
        if practiceSession { insertion.clear(); targetName = "Coda practice" }
        else { insertion.captureTarget(); targetName = insertion.targetName }
        message = "Preparing microphone…"; show()
        // Escape is scoped to a live Coda operation, never registered while idle.
        KeyboardShortcuts.enable(.codaCancelDictation)
        task = Task { [weak self] in
            guard let self else { return }
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard lifecycle.accepts(id), !Task.isCancelled else { return }
            guard allowed else {
                lifecycle.fail(id); model.dictationBusy = false; practiceSession = false
                message = "Microphone access is off. Enable Coda in System Settings → Privacy & Security → Microphone."
                saveSession(outcome: .failed, detail: message); sessionID = nil
                insertion.clear(); KeyboardShortcuts.disable(.codaCancelDictation); dismissAfterResult(); return
            }
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Coda-Dictation-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let url = directory.appendingPathComponent("speech.m4a")
                audioURL = url
                let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000])
                recorder.delegate = self; recorder.isMeteringEnabled = true
                guard lifecycle.accepts(id), !Task.isCancelled, recorder.record() else { throw CodaError.emptyAudio }
                self.recorder = recorder
                guard lifecycle.listening(id) else { recorder.stop(); cleanupAudio(); return }
                started = Date(); message = "Listening • Esc to cancel"
                meterTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(90))
                        guard let self, self.lifecycle.id == id, self.lifecycle.phase == .listening else { return }
                        self.recorder?.updateMeters()
                        if let peak = self.recorder?.peakPower(forChannel: 0), peak.isFinite {
                            self.captureStats.peakDB = max(self.captureStats.peakDB ?? -160, Double(peak))
                        }
                        self.level = min(1, max(0, (Double(self.recorder?.averagePower(forChannel: 0) ?? -60) + 50) / 50))
                        if Date().timeIntervalSince(self.started ?? .now) > 120 { self.finish(); return }
                    }
                }
            } catch {
                lifecycle.fail(id); model.dictationBusy = false; practiceSession = false; recorder?.stop(); recorder = nil; cleanupAudio()
                message = "Microphone could not start. Check your input device and permission, then retry."
                saveSession(outcome: .failed, detail: message); sessionID = nil
                insertion.clear(); KeyboardShortcuts.disable(.codaCancelDictation); dismissAfterResult()
            }
        }
    }
    private func finish() {
        guard let id = lifecycle.processing(), let url = audioURL, let model else { return }
        let isPractice = practiceSession
        captureStats.seconds = recorder?.currentTime ?? 0
        recorder?.updateMeters()
        if let peak = recorder?.peakPower(forChannel: 0), peak.isFinite {
            captureStats.peakDB = max(captureStats.peakDB ?? -160, Double(peak))
        }
        recorder?.stop(); recorder = nil; meterTask?.cancel(); meterTask = nil; level = 0
        captureStats.bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        message = "Transcribing locally… • Esc to cancel"
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                cleanupAudio(); insertion.clear(); lifecycle.settled(id); sessionID = nil
                if isPractice { practiceMessage = message }
                practiceSession = false
                model.dictationBusy = lifecycle.busy
                KeyboardShortcuts.disable(.codaCancelDictation)
            }
            do {
                let vocabulary = dictionary.vocabulary
                let result = try await model.transcribeDictation(url, vocabulary: vocabulary)
                try Task.checkCancellation()
                guard lifecycle.accepts(id), lifecycle.phase == .processing else { return }
                refreshAccessibility()
                guard acceptTranscription(result, for: id) else { return }
                var cleanupInput: String?
                let initialDelivery = deliveryText(recognized: result, cleaned: text)
                let expandedSnippet = initialDelivery.snippet != nil
                if let snippet = initialDelivery.snippet {
                    // Authored text bypasses cleanup and all correction learning.
                    text = snippet.expansion; sessionSnippetTrigger = snippet.trigger
                    cleanupDetail = "Voice snippet: " + snippet.trigger
                } else {
                    let proposals = soundAlikeProposals(for: result)
                    if !proposals.isEmpty {
                        let decisions = await smartFormatter.reviewSoundAlikes(result, proposals: proposals)
                        try Task.checkCancellation()
                        guard acceptSoundAlikeReview(decisions, proposals: proposals, raw: result, for: id) else { return }
                    }
                    if cleanupMode == .smart {
                        cleanupInput = text
                        let formatted = await smartFormatter.format(text, timeout: SmartFormatter.cleanupTimeout(for: text))
                        try Task.checkCancellation()
                        guard acceptSmartFormatting(formatted, for: id) else { return }
                    }
                    text = deliveryText(recognized: result, cleaned: text).text
                }
                saveSession(outcome: .saved, detail: "Saved locally before insertion. " + cleanupDetail)
                if text.isEmpty {
                    guard lifecycle.complete(id) else { return }
                    message = "Only speech fillers detected. Nothing inserted. Original saved in History."
                    saveSession(outcome: .saved, detail: message)
                    return
                }
                if isPractice {
                    guard lifecycle.complete(id) else { return }
                    practiceText = text; practiceCompleted = true
                    message = "Practice complete. No text was pasted into another app."
                    saveSession(outcome: .saved, detail: message)
                    overlay?.hide()
                    return
                }
                let inserted: Bool
                if autoInsert {
                    inserted = await insertion.insertWithFallback(text, observeCorrections: expandedSnippet ? nil : { [weak self] in self?.observeCorrections($0, cleanupInput: cleanupInput) })
                } else { inserted = false }
                guard lifecycle.complete(id) else { return }
                message = inserted ? insertion.reason + " Saved in History." : (autoInsert ? insertion.reason : "Saved in History. Automatic insertion is off.")
                saveSession(outcome: inserted ? .inserted : insertion.deliveryAttempted ? .deliveryUnconfirmed : .copyRequired, detail: message + (cleanupDetail.isEmpty ? "" : " " + cleanupDetail))
            } catch is CancellationError { message = "Cancelled • nothing inserted"; lifecycle.settled(id) }
            catch {
                if lifecycle.phase == .cancelling { message = "Cancelled • nothing inserted"; lifecycle.fail(id) }
                else { reportTranscriptionFailure(error, for: id) }
            }
        }
    }
    @discardableResult
    func reportTranscriptionFailure(_ error: Error, for id: UUID) -> Bool {
        guard lifecycle.accepts(id), lifecycle.phase == .processing else { return false }
        let failure = (error as? DictationFailure) ?? .decodingOrRecognition(error)
        lifecycle.fail(id); failureTitle = failure.title
        message = failure.message
        if sessionID != nil { saveSession(outcome: .failed, detail: message + " " + captureStats.description) }
        show(); dismissAfterResult(after: .seconds(10))
        return true
    }
    // Presentation ends at transcription completion, independently of insertion latency.
    // Keep the lifecycle busy until delivery settles so insertion remains serialized.
    @discardableResult
    func acceptTranscription(_ result: String, for id: UUID) -> Bool {
        guard lifecycle.accepts(id), lifecycle.phase == .processing else { return false }
        cleanupDetail = ""
        let cleaned = DictationCleanup.apply(result, mode: cleanupMode)
        rawText = cleaned.raw
        text = cleaned.text
        saveRecord(DictationRecord(id: id, text: text, target: targetName, outcome: .saved,
            detail: cleaned.changed ? "Light cleanup applied. Original preserved in History." : "Saved locally before insertion.",
            rawText: rawText, cleanupMode: cleanupMode))
        dismissal?.cancel()
        presentationID = UUID()
        overlay?.hide()
        return true
    }
    /// Exact heard-as matches to review. "None · raw text" stays exact.
    func soundAlikeProposals(for result: String) -> [SoundAlikeProposal] {
        cleanupMode == .none ? [] : SoundAlikeCorrections.proposals(result, rules: dictionary.soundAlikeRules)
    }
    /// Applies only the replacements the local model accepted, then reruns Light
    /// cleanup from the corrected words. History keeps the recognizer's words.
    @discardableResult
    func acceptSoundAlikeReview(_ decisions: [Bool]?, proposals: [SoundAlikeProposal], raw: String, for id: UUID) -> Bool {
        guard lifecycle.accepts(id), lifecycle.phase == .processing else { return false }
        guard let decisions, decisions.count == proposals.count else { return true }
        let replaced = SoundAlikeCorrections.apply(raw, proposals: proposals, accepted: decisions)
        guard !replaced.applied.isEmpty else { return true }
        let cleaned = DictationCleanup.apply(replaced.text, mode: cleanupMode)
        text = cleaned.text
        let count = replaced.applied.count
        cleanupDetail = "Dictionary corrected \(count == 1 ? "1 misheard term" : "\(count) misheard terms")."
        saveRecord(DictationRecord(id: id, text: text, target: targetName, outcome: .saved,
            detail: cleanupDetail + (cleaned.changed ? " Light cleanup applied." : "") + " Original preserved in History.",
            rawText: raw, cleanupMode: cleanupMode))
        return true
    }
    @discardableResult
    func acceptSmartFormatting(_ formatted: SmartFormatResult, for id: UUID) -> Bool {
        guard lifecycle.accepts(id), lifecycle.phase == .processing else { return false }
        text = formatted.text
        cleanupDetail = cleanupDetail.isEmpty ? formatted.reason : cleanupDetail + " " + formatted.reason
        saveRecord(DictationRecord(id: id, text: text, target: targetName, outcome: .saved,
            detail: cleanupDetail + ". Original preserved in History.", rawText: rawText, cleanupMode: .smart))
        return true
    }
    func cancel() {
        model?.cancelDictationWarmup()
        corrections.stop()
        stopCorrectionReview()
        wordSuggestions.close()
        if lifecycle.busy { saveSession(outcome: .cancelled, detail: "Cancelled. If insertion had already begun, check the destination before retrying."); sessionID = nil }
        dismissal?.cancel(); retryTask?.cancel()
        pendingInsertion = nil; retryGeneration = nil; retryTimeout?.cancel()
        let wasProcessing = lifecycle.phase == .processing || lifecycle.phase == .cancelling
        lifecycle.cancel(); task?.cancel(); recorder?.stop(); recorder = nil
        meterTask?.cancel(); meterTask = nil; level = 0; started = nil; insertion.clear()
        if !wasProcessing { cleanupAudio(); model?.dictationBusy = false }
        if practiceSession { practiceMessage = "Practice cancelled. Start again when you are ready." }
        practiceSession = false
        message = wasProcessing ? "Cancelling local inference…" : "Cancelled • nothing inserted"
        KeyboardShortcuts.disable(.codaCancelDictation)
        overlay?.hide()
    }
    func copyResult() {
        guard !visualReview else { return }
        guard !text.isEmpty, !lifecycle.busy else { return }
        // An explicit Copy command is the only path that changes the clipboard.
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        message = "Copied • paste wherever you choose"
        overlay?.hide()
    }
    private func cleanupAudio() {
        if let audioURL { try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent()) }
        audioURL = nil
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in guard let self, self.recorder === recorder else { return }; self.cancel() }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag { Task { @MainActor [weak self] in guard let self, self.recorder === recorder else { return }; self.cancel() } }
    }
}
