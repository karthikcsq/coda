import Foundation

/// One dictation the user edited after Coda pasted it. `input` is what the
/// cleanup model received, `inserted` what Coda pasted, `edited` the pasted
/// passage after the user's changes. Stored locally for personal fine-tuning;
/// the tuner decides which edits are cleanup fixes (it ignores rewording).
public struct CleanupEdit: Codable, Equatable, Sendable {
    public var id: UUID
    public var created: Date
    public var input: String
    public var inserted: String
    public var edited: String
    public init(id: UUID, created: Date = .now, input: String, inserted: String, edited: String) {
        self.id = id; self.created = created; self.input = input; self.inserted = inserted; self.edited = edited
    }
    /// True when the user changed the pasted text, beyond surrounding whitespace.
    public var changed: Bool {
        edited.trimmingCharacters(in: .whitespacesAndNewlines) != inserted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct CleanupEditStore: Sendable {
    public let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    /// Saves or replaces the edit for one dictation (the latest field state wins).
    public func save(_ edit: CleanupEdit) throws {
        let file = root.appendingPathComponent(edit.id.uuidString + ".json")
        try JSONEncoder().encode(edit).write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    public func load() -> [CleanupEdit] {
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(CleanupEdit.self, from: Data(contentsOf: $0)) }
            .sorted { $0.created < $1.created }
    }
    public func removeAll() throws {
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            try FileManager.default.removeItem(at: file)
        }
    }
}

public enum PersonalTuningPolicy {
    /// New edits needed before an automatic tune. The tuner may still find too
    /// few usable cleanup fixes among them and skip training.
    public static let newEditsBeforeTuning = 10
    public static func shouldTune(enabled: Bool, newEdits: Int, running: Bool, dictating: Bool) -> Bool {
        enabled && !running && !dictating && newEdits >= newEditsBeforeTuning
    }
}
