import Foundation
import Testing
@testable import CodaCore

@Test func trainingKeepsAudioOriginalAndLatestEdit() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try DictationTrainingStore(root: root)
    let audio = root.appendingPathComponent("source.m4a")
    try Data([1, 2, 3]).write(to: audio)
    let id = UUID()
    try store.save(id: id, audio: audio, rawText: "raw words", insertedText: "Raw words.")
    try FileManager.default.removeItem(at: audio)
    try store.updateFinalText(id: id, text: "Correct words.")
    var pair = try #require(store.load().first)
    #expect(pair.rawText == "raw words")
    #expect(pair.insertedText == "Raw words.")
    #expect(pair.finalText == "Correct words.")
    #expect(pair.userEdited)
    #expect(try Data(contentsOf: root.appendingPathComponent(pair.audioFile)) == Data([1, 2, 3]))
    try store.updateFinalText(id: id, text: "Raw words.")
    pair = try #require(store.load().first)
    #expect(!pair.userEdited)
    let permissions = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(pair.audioFile).path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
}

@Test func acousticLabelsRequireExplicitReviewAndSurviveObservedEdits() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try DictationTrainingStore(root: root)
    let audio = root.appendingPathComponent("source.m4a")
    try Data([1]).write(to: audio)
    let id = UUID()
    try store.save(id: id, audio: audio, rawText: "machine output", insertedText: "Polished text.")
    #expect(try store.load().first?.reviewedTranscript == nil)
    try store.review(id: id, transcript: "  actual spoken words  ")
    try store.updateFinalText(id: id, text: "A later rewrite")
    #expect(try store.load().first?.reviewedTranscript == "actual spoken words")
    try store.review(id: id, transcript: nil)
    #expect(try store.load().first?.reviewedTranscript == nil)
    try store.remove(id: id)
    #expect(try store.load().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(id.uuidString + ".m4a").path))
}
