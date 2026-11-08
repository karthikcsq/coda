import Foundation

public struct DictationRecord: Codable, Identifiable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable { case saved, inserted, deliveryUnconfirmed, copyRequired, cancelled, failed }
    public var id: UUID
    public var created: Date
    public var text: String
    public var rawText: String?
    public var cleanupMode: DictationCleanupMode?
    public var snippetTrigger: String?
    public var target: String
    public var outcome: Outcome
    public var detail: String
    /// What the user said they meant, entered after marking the dictation wrong.
    /// `text` and `rawText` keep what Coda produced and inserted.
    public var correctedText: String?
    public var correctedAt: Date?
    /// The text the user wants: their correction when present, otherwise what Coda produced.
    public var finalText: String { correctedText ?? text }
    public init(id: UUID = UUID(), created: Date = .now, text: String, target: String, outcome: Outcome, detail: String, rawText: String? = nil, cleanupMode: DictationCleanupMode? = nil, snippetTrigger: String? = nil) {
        self.rawText = rawText; self.cleanupMode = cleanupMode; self.snippetTrigger = snippetTrigger
        self.id = id; self.created = created; self.text = text; self.target = target; self.outcome = outcome; self.detail = detail
    }
}
public struct DictationHistory {
    public let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public func load() throws -> (records: [DictationRecord], skipped: Int) {
        var records: [DictationRecord] = []; var skipped = 0
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
            do { records.append(try JSONDecoder().decode(DictationRecord.self, from: Data(contentsOf: url))) }
            catch { skipped += 1 }
        }
        return (records.sorted { $0.created > $1.created }, skipped)
    }
    public func save(_ record: DictationRecord) throws {
        let file = root.appendingPathComponent(record.id.uuidString + ".json")
        try JSONEncoder().encode(record).write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

public enum DictationPlacement {
    /// Preserve the current position where possible; clamp only after display changes.
    public static func frame(current: CGRect?, visible: CGRect, size: CGSize) -> CGRect {
        let width = min(size.width, visible.width), height = min(size.height, visible.height)
        let x = current?.minX ?? (visible.midX - width / 2)
        let y = current?.minY ?? (visible.minY + 28)
        return CGRect(x: min(max(x, visible.minX), visible.maxX - width), y: min(max(y, visible.minY), visible.maxY - height), width: width, height: height)
    }
}

public enum PlainTextInsertion {
    /// Accessibility ranges use UTF-16 offsets. Reject invalid/split-surrogate ranges.
    public static func replacing(_ original: String, range: NSRange, with text: String) -> String? {
        guard range.location >= 0, range.length >= 0, range.location <= original.utf16.count,
              range.length <= original.utf16.count - range.location,
              let lower16 = original.utf16.index(original.utf16.startIndex, offsetBy: range.location, limitedBy: original.utf16.endIndex),
              let upper16 = original.utf16.index(lower16, offsetBy: range.length, limitedBy: original.utf16.endIndex),
              let lower = String.Index(lower16, within: original), let upper = String.Index(upper16, within: original)
        else { return nil }
        return original.replacingCharacters(in: lower..<upper, with: text)
    }
}
