import Foundation

/// Audio and text from a single dictation. Final text is an observed edit, not
/// necessarily a verbatim transcript suitable for acoustic model training.
public struct DictationTrainingPair: Codable, Equatable, Sendable {
    public var id: UUID
    public var created: Date
    public var rawText: String
    public var insertedText: String
    public var finalText: String
    public var userEdited: Bool
    public var audioFile: String
}

/// Separate from meeting storage and from the cleanup model's text-only edits.
public struct DictationTrainingStore: Sendable {
    public let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public func save(id: UUID, audio: URL, rawText: String, insertedText: String) throws {
        let name = id.uuidString + ".m4a"
        let destination = root.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try FileManager.default.copyItem(at: audio, to: destination)
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            try write(DictationTrainingPair(id: id, created: .now, rawText: rawText,
                insertedText: insertedText, finalText: insertedText, userEdited: false, audioFile: name))
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
    public func updateFinalText(id: UUID, text: String) throws {
        let file = root.appendingPathComponent(id.uuidString + ".json")
        var pair = try JSONDecoder().decode(DictationTrainingPair.self, from: Data(contentsOf: file))
        pair.finalText = text
        pair.userEdited = text != pair.insertedText
        try write(pair)
    }
    public func load() throws -> [DictationTrainingPair] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try JSONDecoder().decode(DictationTrainingPair.self, from: Data(contentsOf: $0)) }
            .sorted { $0.created < $1.created }
    }
    private func write(_ pair: DictationTrainingPair) throws {
        let file = root.appendingPathComponent(pair.id.uuidString + ".json")
        try JSONEncoder().encode(pair).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
