import Foundation
import Observation
import CodaCore
import Voz

/// Owns only the dictation acoustic model. Meeting inference never reads it.
@MainActor @Observable final class PersonalAudioTuning {
    let root: URL
    let store: DictationTrainingStore?
    private(set) var pairs: [DictationTrainingPair] = []
    private(set) var running = false
    private(set) var message = "Review recordings before training your voice model."
    private let persistSelection: Bool
    var enabled = false {
        didSet { if persistSelection { UserDefaults.standard.set(enabled, forKey: "personalVozEnabled") } }
    }
    var busy: Bool { isBusy() }
    var isBusy: () -> Bool = { false }
    struct Selection: Decodable { var backend: String; var model: String }
    private var selection: Selection? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("active.json")),
              let value = try? JSONDecoder().decode(Selection.self, from: data),
              value.backend == "voz-v0.4.0", UUID(uuidString: value.model) != nil else { return nil }
        return value
    }
    var installed: Bool { selection != nil }
    var sourceModel: () async throws -> URL = { throw CodaError.message("Prepare Voz and accept its model terms first.") }
    private let recognizer = PersonalVozRecognizer()
    private var evaluationTool: URL? {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/CodaVozTool"),
            project.appendingPathComponent(".build/out/Products/Debug/CodaVozTool"), project.appendingPathComponent(".build/debug/CodaVozTool")]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    var prepared: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("prepared.json").path) }
    var reviewedCount: Int { pairs.filter { $0.reviewedTranscript != nil }.count }
    private var operation: Task<Void, Never>?
    func cancel() { operation?.cancel() }
    private var python: URL { root.appendingPathComponent("runtime/bin/python3") }
    private var worker: URL? { Bundle.main.url(forResource: "personal_audio_worker", withExtension: "py") ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("scripts/personal-audio/worker.py") }

    init(root: URL? = nil, pairsRoot: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Coda")
        persistSelection = root == nil
        self.root = root ?? support.appendingPathComponent("PersonalVoz")
        store = try? DictationTrainingStore(root: pairsRoot ?? support.appendingPathComponent("Dictations/Training"))
        refresh()
        enabled = persistSelection && installed && UserDefaults.standard.bool(forKey: "personalVozEnabled")
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
        message = prepare ? "Preparing the local runtime and a personal copy of Voz…" : "Training and evaluating your voice model locally…"
        operation = Task {
            defer { running = false; operation = nil; refresh() }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let source = prepare ? try await sourceModel() : nil
                if prepare {
                    let candidates = ["/opt/homebrew/bin/python3.13", "/opt/homebrew/bin/python3.12", "/opt/homebrew/bin/python3.11", "/usr/local/bin/python3.12", "/usr/bin/python3"]
                    guard let system = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw CodaError.message("Install Python 3.10 or newer to prepare audio training.") }
                    try await Self.run(URL(fileURLWithPath: system), ["-m", "venv", root.appendingPathComponent("runtime").path], root: root)
                    try await Self.run(python, ["-m", "pip", "install", "torch==2.15.0", "coremltools==9.0", "numpy==2.5.4"], root: root)
                }
                var args = [worker.path, prepare ? "prepare" : "train", "--root", root.path]
                if let source { args += ["--source", source.path] }
                else {
                    guard let store, let tool = evaluationTool else { throw CodaError.message("The bundled Voz evaluation tool is unavailable.") }
                    args += ["--pairs", store.root.path, "--tool", tool.path]
                }
                try await Self.run(python, args, root: root, offline: !prepare)
                if prepare { message = "Voz is ready. Review at least 15 distinct clips of up to 15 seconds." }
                else {
                    struct Report: Decodable { var installed: Bool; var baselineWER: Double; var candidateWER: Double }
                    let report = try JSONDecoder().decode(Report.self, from: Data(contentsOf: root.appendingPathComponent("report.json")))
                    message = String(format: "Held-out Voz word error: %.1f%% → %.1f%%. %@", report.baselineWER * 100, report.candidateWER * 100, report.installed ? "Personal model saved; enable it to try dictation." : "No improvement; current model kept.")
                }
            } catch is CancellationError { message = "Cancelled. Your current model was kept." }
            catch { message = error.localizedDescription }
        }
    }
    func transcribe(_ audio: URL, vocabulary: [String] = []) async throws -> String {
        guard enabled, let selection else { throw CodaError.message("Personal Voz model is unavailable.") }
        let directory = root.appendingPathComponent("models").appendingPathComponent(selection.model)
        return try await recognizer.transcribe(audio, directory: directory, modelID: selection.model, vocabulary: vocabulary)
    }

    nonisolated static func run(_ executable: URL, _ arguments: [String], root: URL, offline: Bool = false) async throws {
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


private actor PersonalVozRecognizer {
    private var model: Voz?
    private var modelID: String?
    func transcribe(_ audio: URL, directory: URL, modelID: String, vocabulary: [String]) async throws -> String {
        try Task.checkCancellation()
        if self.modelID != modelID {
            model = try Voz(modelDirectory: directory)
            self.modelID = modelID
        }
        guard let model else { throw CodaError.message("Personal Voz could not load.") }
        let result = try await model.transcribe(audio, vocabulary: vocabulary)
        try Task.checkCancellation()
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DictationFailure.noWords }
        return result.text
    }
}
