import AppKit
import SwiftUI
import Testing
import CodaCore
@testable import Coda

@Test @MainActor func audioReviewRendersAndDoesNotEnableUntrainedModel() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let tuning = PersonalAudioTuning(root: root, pairsRoot: root.appendingPathComponent("pairs"))
    #expect(!tuning.installed && !tuning.prepared && !tuning.enabled)
    let source = root.appendingPathComponent("synthetic.m4a")
    try Data([0]).write(to: source)
    try tuning.store?.save(id: UUID(), audio: source, rawText: "Synthetic raw text", insertedText: "Synthetic result.")
    tuning.refresh()
    #expect(tuning.reviewedCount == 0)
    let host = NSHostingView(rootView: PersonalAudioView(tuning: tuning, preview: true).environment(\.colorScheme, .dark))
    host.frame = CGRect(x: 0, y: 0, width: 900, height: 950)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: .now.addingTimeInterval(0.1))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/coda-personal-audio-review.png"))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CODA_AUDIO_SMOKE_ROOT"] != nil))
@MainActor func personalAudioLoadsSavedModelAndTranscribesOffline() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["CODA_AUDIO_SMOKE_ROOT"])
    let root = URL(fileURLWithPath: path)
    let tuning = PersonalAudioTuning(root: root, pairsRoot: root.appendingPathComponent("pairs"))
    tuning.enabled = true
    let audio = try #require(FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("pairs"), includingPropertiesForKeys: nil).first { $0.pathExtension == "m4a" })
    let text = try await tuning.transcribe(audio)
    #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
}

@Test @MainActor func cancellingPersonalInferenceStopsItsWorker() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("{}".utf8).write(to: root.appendingPathComponent("active.json"))
    let worker = root.appendingPathComponent("worker.py")
    try """
    import sys, time, pathlib, os
    root = pathlib.Path(sys.argv[sys.argv.index('--root') + 1])
    (root / 'started').write_text(str(os.getpid()))
    time.sleep(30)
    """.write(to: worker, atomically: true, encoding: .utf8)
    let tuning = PersonalAudioTuning(root: root, pairsRoot: root.appendingPathComponent("pairs"), worker: worker, python: URL(fileURLWithPath: "/usr/bin/python3"))
    tuning.enabled = true
    let inference = Task { try await tuning.transcribe(root.appendingPathComponent("unused.m4a")) }
    for _ in 0..<100 {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("started").path) { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("started").path))
    inference.cancel()
    await #expect(throws: CancellationError.self) { try await inference.value }
}

@Test @MainActor func returningToGenericKeepsPersonalModelAvailable() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("{}".utf8).write(to: root.appendingPathComponent("active.json"))
    let tuning = PersonalAudioTuning(root: root, pairsRoot: root.appendingPathComponent("pairs"))
    tuning.enabled = true
    tuning.reset()
    #expect(!tuning.enabled)
    #expect(tuning.installed)
}
