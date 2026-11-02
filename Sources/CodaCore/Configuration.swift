import Foundation
public struct Configuration: Sendable {
    public let apiKey: String
    public let model: String
    public init(contents: String, environment: [String: String] = [:]) {
        let values = Self.parse(contents).merging(environment) { _, new in new }
        apiKey = values["OPENAI_API_KEY"] ?? ""
        model = values["OPENAI_MODEL"].flatMap { $0.isEmpty ? nil : $0 } ?? "gpt-4.1-mini"
    }
    public static func parse(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for raw in contents.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
            guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            guard ["OPENAI_API_KEY", "OPENAI_MODEL"].contains(key) else { continue }
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, (first == "\"" || first == "'"), value.last == first {
                value = String(value.dropFirst().dropLast())
            } else if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces) }
            values[key] = value // Deliberately no shell execution or variable interpolation.
        }
        return values
    }
    public func validate() throws {
        guard !apiKey.isEmpty, apiKey != "your-key-here", !apiKey.contains("\n"), !apiKey.contains("\r") else { throw CodaError.missingKey }
    }
}
public struct MeetingStore: Sendable {
    public let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public func save(_ meeting: Meeting) throws {
        let file = root.appendingPathComponent(meeting.id.uuidString + ".json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meeting).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    public struct LoadReport: Sendable {
        public let meetings: [Meeting]
        public let unreadableCount: Int
    }
    public func loadRecovering() throws -> LoadReport {
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        var meetings: [Meeting] = []
        var unreadable = 0
        for file in files {
            do { meetings.append(try JSONDecoder().decode(Meeting.self, from: Data(contentsOf: file))) }
            catch { unreadable += 1 } // Preserve the unreadable file; do not hide other meetings.
        }
        return LoadReport(meetings: meetings.sorted { $0.created > $1.created }, unreadableCount: unreadable)
    }
    public func load() throws -> [Meeting] { try loadRecovering().meetings }
    public func remove(_ meeting: Meeting) throws {
        let metadata = root.appendingPathComponent(meeting.id.uuidString + ".json")
        let audio = root.appendingPathComponent(meeting.audioFile)
        guard audio.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { throw CodaError.message("Invalid recording path.") }
        if FileManager.default.fileExists(atPath: audio.path) { try FileManager.default.removeItem(at: audio) }
        try FileManager.default.removeItem(at: metadata)
    }
}
