import Foundation
import Observation
import CodaCore

/// Owns only the dictation acoustic model. Meeting inference never reads it.
@MainActor @Observable final class PersonalAudioTuning {
    let root: URL
    let store: DictationTrainingStore?
    private(set) var pairs: [DictationTrainingPair] = []
    private(set) var running = false
    private(set) var message = "Review recordings before training your voice model."
    private let persistSelection: Bool
    var enabled = false {
        didSet { if persistSelection { UserDefaults.standard.set(enabled, forKey: "personalAudioEnabled") } }
    }
    var busy: Bool { isBusy() }
    var isBusy: () -> Bool = { false }
    var installed: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("active.json").path) }
    var prepared: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("prepared.json").path) }
    var reviewedCount: Int { pairs.filter { $0.reviewedTranscript != nil }.count }
    private var operation: Task<Void, Never>?
    func cancel() { operation?.cancel() }
    private let pythonOverride: URL?
    private let workerOverride: URL?
    private var python: URL { pythonOverride ?? root.appendingPathComponent("runtime/bin/python3") }
    private var worker: URL? { workerOverride ?? Bundle.main.url(forResource: "personal_audio_worker", withExtension: "py") ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/personal-audio/worker.py") }

    init(root: URL? = nil, pairsRoot: URL? = nil, worker: URL? = nil, python: URL? = nil) {
        pythonOverride = python; workerOverride = worker
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Coda")
        persistSelection = root == nil
        self.root = root ?? support.appendingPathComponent("PersonalAudio")
        store = try? DictationTrainingStore(root: pairsRoot ?? support.appendingPathComponent("Dictations/Training"))
        refresh()
        enabled = persistSelection && installed && UserDefaults.standard.bool(forKey: "personalAudioEnabled")
    }
    func refresh() {
        do { pairs = try store?.load() ?? [] }
        catch { message = "Some saved training pairs could not be read." }
    }
    func review(_ id: UUID, transcript: String?) {
        guard !running else { return }
        do { try store?.review(id: id, transcript: transcript); refresh() }
        catch { message = "Could not save the reviewed transcript." }
    }
    func remove(_ id: UUID) {
        guard !running else { return }
        do { try store?.remove(id: id); refresh() }
        catch { message = "Could not delete the saved pair." }
    }
    func reset() {
        guard !running, !isBusy() else { return }
        enabled = false
        message = "Dictation uses generic Voz. Your personal model and recordings are kept."
    }
    func start(prepare: Bool) {
        guard !running, !isBusy(), let worker else { return }
        running = true
        message = prepare ? "Downloading the local training runtime and Whisper base…" : "Training and evaluating your voice model locally…"
        operation = Task {
            defer { running = false; operation = nil; refresh() }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                if prepare {
                    let candidates = ["/opt/homebrew/bin/python3.13", "/opt/homebrew/bin/python3.12", "/opt/homebrew/bin/python3.11", "/usr/local/bin/python3.12", "/usr/bin/python3"]
                    guard let system = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw CodaError.message("Install Python 3.10 or newer to prepare audio training.") }
                    try await Self.run(URL(fileURLWithPath: system), ["-m", "venv", root.appendingPathComponent("runtime").path], root: root)
                    try await Self.run(python, ["-m", "pip", "install", "torch==2.15.0", "transformers==4.57.6", "numpy==2.5.4"], root: root)
                }
                var args = [worker.path, prepare ? "prepare" : "train", "--root", root.path]
                if !prepare, let store { args += ["--pairs", store.root.path] }
                try await Self.run(python, args, root: root, offline: !prepare)
                if prepare { message = "Whisper base is ready. Review at least 15 distinct clips of up to 30 seconds." }
                else {
                    struct Report: Decodable { var installed: Bool; var baselineWER: Double; var candidateWER: Double }
                    let report = try JSONDecoder().decode(Report.self, from: Data(contentsOf: root.appendingPathComponent("report.json")))
                    message = String(format: "Held-out Whisper word error: %.1f%% → %.1f%%. %@", report.baselineWER * 100, report.candidateWER * 100, report.installed ? "Personal model saved; enable it to try dictation." : "No improvement; current model kept.")
                }
            } catch is CancellationError { message = "Cancelled. Your current model was kept." }
            catch { message = error.localizedDescription }
        }
    }
    func transcribe(_ audio: URL) async throws -> String {
        guard enabled, installed, let worker else { throw CodaError.message("Personal voice model is unavailable.") }
        let output = root.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: output) }
        try await Self.run(python, [worker.path, "transcribe", "--root", root.path, "--audio", audio.path, "--output", output.path], root: root, offline: true)
        try Task.checkCancellation()
        struct Result: Decodable { var text: String }
        return try JSONDecoder().decode(Result.self, from: Data(contentsOf: output)).text
    }
    nonisolated private static func run(_ executable: URL, _ arguments: [String], root: URL, offline: Bool = false) async throws {
        let operation = Task.detached(priority: .utility) {
            let log = root.appendingPathComponent(UUID().uuidString + ".log")
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
            let process = Process()
            process.executableURL = executable; process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["HF_HUB_DISABLE_TELEMETRY"] = "1"; env["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"; env["TOKENIZERS_PARALLELISM"] = "false"
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            if offline { env["HF_HUB_OFFLINE"] = "1"; env["TRANSFORMERS_OFFLINE"] = "1" }
            process.environment = env
            process.standardInput = FileHandle.nullDevice; process.standardOutput = handle; process.standardError = handle
            try Task.checkCancellation()
            try process.run()
            let deadline = Date().addingTimeInterval(3600)
            while process.isRunning {
                if Task.isCancelled || Date() > deadline {
                    process.terminate(); process.waitUntilExit()
                    throw CancellationError()
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                struct Failure: Decodable { var message: String }
                if let data = try? Data(contentsOf: root.appendingPathComponent("error.json")),
                   let failure = try? JSONDecoder().decode(Failure.self, from: data) {
                    throw CodaError.message(failure.message)
                }
                throw CodaError.message("Audio model operation failed. Check Python 3.10+, available disk space and reviewed clips; your current model was kept.")
            }
        }
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }
}
