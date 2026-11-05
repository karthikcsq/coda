import Foundation
import Observation
import CodaCore

struct SmartFormatResult: Sendable {
    var text: String
    var accepted: Bool
    var reason: String
    var correctionJudgments: [Bool]? = nil
}

/// One local worker, one request at a time. Stdio only; no HTTP server or transcript logs.
@MainActor @Observable final class SmartFormatter {
    private(set) var status = "Local model idle"
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private struct Request {
        let id: UUID
        let raw: String
        let correctionPairs: [WordCorrection]?
        let soundAlikes: [SoundAlikeProposal]?
        let expires: ContinuousClock.Instant
        let continuation: CheckedContinuation<SmartFormatResult, Never>
    }
    private var pending: Request?
    private var deadline: Task<Void, Never>?
    private var idle: Task<Void, Never>?
    private var generation = UUID()
    private let python: URL
    private let script: URL?
    private let model: URL
    init(python: URL? = nil, script: URL? = nil, model: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Coda/SmartCleanup/v1")
        self.python = python ?? base.appendingPathComponent("runtime/bin/python")
        self.model = model ?? base.appendingPathComponent("model")
        self.script = script ?? Bundle.main.url(forResource: "smart_cleanup_worker", withExtension: "py")
    }
    func warm() {
        guard process == nil else { return }
        guard let script, FileManager.default.isExecutableFile(atPath: python.path), FileManager.default.fileExists(atPath: script.path), FileManager.default.fileExists(atPath: model.path) else {
            status = "Local model unavailable · raw text fallback"; return
        }
        let worker = Process(), stdin = Pipe(), stdout = Pipe()
        let token = UUID(); generation = token; buffer = Data()
        worker.executableURL = python; worker.arguments = [script.path, model.path]
        worker.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1", "HF_HUB_DISABLE_IMPLICIT_TOKEN": "1", "HF_HUB_DISABLE_TELEMETRY": "1", "ORT_DISABLE_TELEMETRY": "1", "TOKENIZERS_PARALLELISM": "false", "PYTHONUNBUFFERED": "1", "PYTHONDONTWRITEBYTECODE": "1"]
        worker.standardInput = stdin; worker.standardOutput = stdout; worker.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in self?.receive(data, generation: token) }
        }
        worker.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.stop(reason: "Local model stopped · raw text fallback")
            }
        }
        do { try worker.run(); process = worker; input = stdin.fileHandleForWriting; status = "Starting local cleanup…"; scheduleIdle() }
        catch { status = "Local model unavailable · raw text fallback" }
    }
    /// The cleanup model reads every dictation, so long dictations get proportionally
    /// longer (the worker's own budget is 0.5 s + 6 ms per word, capped at 3 s).
    nonisolated static func cleanupTimeout(for text: String) -> Duration {
        let words = text.split(whereSeparator: \.isWhitespace).count
        return .milliseconds(min(3500, 900 + 10 * words))
    }
    // Slow/cold/long requests retain the already-saved raw transcript;
    // warm-up overlaps dictation recording.
    func format(_ raw: String, timeout: Duration = .milliseconds(900), correctionPairs: [WordCorrection]? = nil, edited: String? = nil,
                soundAlikes: [SoundAlikeProposal]? = nil) async -> SmartFormatResult {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .init(text: raw, accepted: false, reason: "Empty text") }
        guard raw.count <= 4000 else { return .init(text: raw, accepted: false, reason: "Long dictation · raw text retained") }
        guard !Task.isCancelled else { return .init(text: raw, accepted: false, reason: "Cancelled") }
        if correctionPairs == nil && soundAlikes == nil {
            let urlText = SpokenURL.normalize(raw)
            if urlText != raw { return .init(text: urlText, accepted: true, reason: "Spoken URL formatted locally") }
        }
        guard pending == nil else { return .init(text: raw, accepted: false, reason: "Local model busy · raw text retained") }
        warm()
        guard process != nil, let input else { return .init(text: raw, accepted: false, reason: "Local model unavailable · raw text retained") }
        let id = UUID(); idle?.cancel()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending = Request(id: id, raw: raw, correctionPairs: correctionPairs, soundAlikes: soundAlikes, expires: .now.advanced(by: timeout), continuation: continuation)
                deadline = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard let self, self.pending?.id == id else { return }
                    self.stop(reason: "Local formatting timed out · raw text retained")
                }
                do {
                    var request: [String: Any] = ["id": id.uuidString, "text": raw]
                    if let correctionPairs {
                        request["kind"] = "corrections"; request["edited"] = edited ?? ""
                        request["pairs"] = correctionPairs.map { ["original": $0.original, "corrected": $0.corrected] }
                    } else if let soundAlikes, soundAlikes.isEmpty {
                        request["kind"] = "warm"
                    } else if let soundAlikes {
                        request["kind"] = "sound_alikes"
                        request["proposals"] = soundAlikes.map { ["heard": $0.heardPassage, "fixed": $0.fixedPassage] }
                    }
                    var data = try JSONSerialization.data(withJSONObject: request); data.append(10)
                    try input.write(contentsOf: data)
                } catch { stop(reason: "Local formatter failed · raw text retained") }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.pending?.id == id else { return }
                self?.stop(reason: "Cancelled")
            }
        }
    }
    func classifyCorrections(original: String, edited: String, pairs: [WordCorrection], timeout: Duration = .milliseconds(1300)) async -> [Bool]? {
        guard !pairs.isEmpty, pairs.count <= 4, edited.count <= 4000 else { return nil }
        return await format(original, timeout: timeout, correctionPairs: pairs, edited: edited).correctionJudgments
    }
    /// The local model reviews each exact heard-as match in context. Nil means
    /// no verdict (model missing, warming, busy or slow): nothing is replaced.
    func reviewSoundAlikes(_ text: String, proposals: [SoundAlikeProposal], timeout: Duration = .milliseconds(1300)) async -> [Bool]? {
        guard !proposals.isEmpty, proposals.count <= SoundAlikeCorrections.proposalLimit,
              proposals.allSatisfy({ $0.heardPassage.count <= 480 && $0.fixedPassage.count <= 480 }) else { return nil }
        return await format(text, timeout: timeout, soundAlikes: proposals).correctionJudgments
    }
    /// Starts loading the local model while the user is still speaking.
    func prepareModel() async {
        guard pending == nil else { return }
        _ = await format("warm", timeout: .milliseconds(800), soundAlikes: [])
    }
    private func receive(_ data: Data, generation token: UUID) {
        guard generation == token else { return }
        guard !data.isEmpty else { return }
        buffer.append(data)
        guard buffer.count <= 65536 else { stop(reason: "Invalid model response · raw text retained"); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { stop(reason: "Invalid model response · raw text retained"); return }
            if object["ready"] as? Bool == true {
                status = object["cleanup_personal"] as? Bool == true ? "Spokenly Cleanup 1, tuned on your edits · ready" :
                    object["cleanup_ready"] as? Bool == true ? "Spokenly Cleanup 1 · ready" :
                    object["model_ready"] as? Bool == true ? "Local cleanup + Qwen3.5 2B · ready" :
                    object["model_warming"] as? Bool == true ? "Local cleanup ready · model warming" : "Local cleanup ready"
                continue
            }
            guard let active = pending, object["id"] as? String == active.id.uuidString else { continue }
            // A busy UI thread may delay the timer callback. Late model output still
            // must not win the race against the interactive latency deadline.
            guard ContinuousClock.now < active.expires else { stop(reason: "Local formatting timed out · raw text retained"); return }
            if let count = active.correctionPairs?.count ?? active.soundAlikes?.count {
                let decisions = object["decisions"] as? [Bool]
                let valid = object["accepted"] as? Bool == true && decisions?.count == count
                pending = nil; deadline?.cancel(); deadline = nil
                active.continuation.resume(returning: .init(text: active.raw, accepted: false,
                    reason: valid ? "Corrections checked locally" : "Local correction check unavailable", correctionJudgments: valid ? decisions : nil))
                scheduleIdle(); continue
            }
            let accepted = object["accepted"] as? Bool == true
            let fillerOnly = accepted && object["reason"] as? String == "filler-only" &&
                active.raw.range(of: #"^[\s,.;:!?]*(?:(?:[Uu]m|[Uu]h|[Ee]rm)[\s,.;:!?]*)+$"#, options: .regularExpression) != nil
            guard let text = object["text"] as? String, (!text.isEmpty || fillerOnly), text.utf8.count <= 16000 else { stop(reason: "Invalid model response · raw text retained"); return }
            pending = nil; deadline?.cancel(); deadline = nil
            status = "Local cleanup ready"
            active.continuation.resume(returning: .init(text: accepted ? text : active.raw, accepted: accepted,
                reason: accepted ? "Smart formatting validated locally" : "Smart validation kept original words"))
            scheduleIdle()
        }
    }
    private var reloadAfterRequest = false
    /// Restarts the worker so it loads the current cleanup model (after personal
    /// tuning installs or resets one). An in-flight request finishes first.
    func reloadModel() {
        if pending == nil { stop(reason: "Cleanup model updated · loads on next use") } else { reloadAfterRequest = true }
    }
    private func scheduleIdle() {
        if reloadAfterRequest, pending == nil { reloadAfterRequest = false; stop(reason: "Cleanup model updated · loads on next use"); return }
        idle?.cancel(); idle = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(300)) } catch { return }
            guard let self, self.pending == nil else { return }; self.stop(reason: "Local model idle · warms on next use")
        }
    }
    func stop(reason: String = "Local model idle") {
        generation = UUID(); deadline?.cancel(); deadline = nil; idle?.cancel(); idle = nil
        let active = pending; pending = nil
        if let pipe = process?.standardOutput as? Pipe { pipe.fileHandleForReading.readabilityHandler = nil }
        process?.terminationHandler = nil
        try? input?.close(); input = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; buffer = Data(); status = reason
        if let active { active.continuation.resume(returning: .init(text: active.raw, accepted: false, reason: reason)) }
    }
}
