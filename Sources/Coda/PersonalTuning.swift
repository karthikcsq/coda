import Foundation
import Observation
import CodaCore

/// Collects the user's edits to Smart-cleaned dictations and periodically
/// fine-tunes the local cleanup model on them in a background process
/// (scripts/smart-cleanup/finetune/auto_tune.py, bundled). The tuned model is
/// installed only if it passes the tuner's gate; Reset returns to the
/// open-weight model. Everything stays on this Mac.
@MainActor @Observable final class PersonalTuning {
    struct Status: Decodable, Equatable {
        var state: String
        var message: String?
        var finished: Double?
        var edits_seen: Int?
        var edits_used: Int?
        var last_edit_created: Double?
    }
    private(set) var editCount = 0
    private(set) var newEdits = 0
    private(set) var running = false
    private(set) var status: Status?
    private(set) var personalInstalled = false
    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey); if enabled { scheduleCheck() } else { pendingCheck?.cancel() } }
    }
    /// Set by the dictation controller: tuning never starts during a dictation.
    var isDictating: () -> Bool = { false }
    /// Called after a tuned model is installed or reset, so the worker reloads.
    var modelChanged: () -> Void = {}

    static let enabledKey = "learnFromEdits"
    private let root: URL
    private let python: URL
    private let script: URL?
    private let store: CleanupEditStore?
    private var process: Process?
    private var pendingCheck: Task<Void, Never>?
    private let idleDelay: Duration

    init(root: URL? = nil, script: URL? = nil, idleDelay: Duration = .seconds(120)) {
        let base = root ?? BuildIdentity.dataRoot.appendingPathComponent("SmartCleanup")
        self.root = base
        python = base.appendingPathComponent("v1/runtime/bin/python")
        self.script = script ?? Bundle.main.url(forResource: "auto_tune", withExtension: "py")
        store = try? CleanupEditStore(root: base.appendingPathComponent("edits"))
        self.idleDelay = idleDelay
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        refresh()
    }

    private var personalModel: URL { root.appendingPathComponent("v1/cleanup-personal") }
    private var statusFile: URL { root.appendingPathComponent("tuning/status.json") }

    /// Saves the latest state of one edited dictation. Unchanged text is ignored.
    func record(_ edit: CleanupEdit) {
        guard enabled, edit.changed, let store else { return }
        try? store.save(edit)
        refresh(); scheduleCheck()
    }

    func refresh() {
        let edits = store?.load() ?? []
        editCount = edits.count
        if let data = try? Data(contentsOf: statusFile) { status = try? JSONDecoder().decode(Status.self, from: data) }
        let since = status?.last_edit_created ?? -.infinity
        // A run that was interrupted leaves "running"; it does not count as done.
        let done = status.map { $0.state != "running" } ?? false
        newEdits = done ? edits.filter { $0.created.timeIntervalSinceReferenceDate > since }.count : edits.count
        personalInstalled = FileManager.default.fileExists(atPath: personalModel.appendingPathComponent("config.json").path)
    }

    /// Waits for a quiet period after the latest edit, then tunes if due.
    private func scheduleCheck() {
        pendingCheck?.cancel()
        guard enabled, PersonalTuningPolicy.shouldTune(enabled: enabled, newEdits: newEdits, running: running, dictating: false) else { return }
        pendingCheck = Task { [weak self] in
            guard let delay = self?.idleDelay else { return }
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, PersonalTuningPolicy.shouldTune(enabled: enabled, newEdits: newEdits, running: running, dictating: isDictating()) else {
                self?.scheduleCheck(); return
            }
            start()
        }
    }

    func tuneNow() { pendingCheck?.cancel(); start() }

    private func start() {
        guard !running, editCount > 0, let script, FileManager.default.isExecutableFile(atPath: python.path) else { return }
        let worker = Process()
        worker.executableURL = python; worker.arguments = [script.path, root.path]
        worker.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "HF_HUB_DISABLE_TELEMETRY": "1", "TOKENIZERS_PARALLELISM": "false",
            "PYTHONDONTWRITEBYTECODE": "1"]
        worker.standardInput = FileHandle.nullDevice; worker.standardOutput = FileHandle.nullDevice; worker.standardError = FileHandle.nullDevice
        worker.qualityOfService = .background
        let wasInstalled = personalInstalled
        worker.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                process = nil; running = false; refresh()
                if status?.state == "installed" || wasInstalled != personalInstalled { modelChanged() }
            }
        }
        do { try worker.run(); process = worker; running = true; status = Status(state: "running", message: "Tuning on your edits…") }
        catch { status = Status(state: "failed", message: "Tuning could not start.") }
    }

    /// Removes the tuned model; dictation returns to the open-weight model.
    /// Collected edits are kept unless `forgetEdits` is set.
    func reset(forgetEdits: Bool = false) {
        guard !running else { return }
        try? FileManager.default.removeItem(at: personalModel)
        try? FileManager.default.removeItem(at: statusFile)
        if forgetEdits { try? store?.removeAll() }
        refresh(); modelChanged()
    }

    var summary: String {
        if running { return status?.message ?? "Tuning on your edits…" }
        var parts = ["\(editCount) edit\(editCount == 1 ? "" : "s") collected"]
        if let used = status?.edits_used, status?.state != "running" { parts.append("\(used) used for cleanup") }
        parts.append(personalInstalled ? "using your tuned model" : "using the open-weight model")
        var text = parts.joined(separator: " · ")
        if let message = status?.message, status?.state != "installed" || !personalInstalled { text += "\n" + message }
        return text
    }
}
