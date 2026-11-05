import Foundation
import Testing
@testable import CodaCore

@Test func cleanupEditsSaveLatestStatePerDictationWithPrivatePermissions() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try CleanupEditStore(root: root)
    let id = UUID()
    var edit = CleanupEdit(id: id, input: "my manager asked would ask", inserted: "My manager asked would ask.", edited: "My manager asked would ask")
    try store.save(edit)
    edit.edited = "My manager would ask."
    try store.save(edit)
    try store.save(CleanupEdit(id: UUID(), input: "ship it", inserted: "Ship it.", edited: "Ship it today."))
    let loaded = store.load()
    #expect(loaded.count == 2)
    #expect(loaded.first(where: { $0.id == id })?.edited == "My manager would ask.")
    let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(id.uuidString + ".json").path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    try store.removeAll()
    #expect(store.load().isEmpty)
}

@Test func cleanupEditChangeIgnoresSurroundingWhitespace() {
    #expect(!CleanupEdit(id: UUID(), input: "a", inserted: "Ship it.", edited: " Ship it.\n").changed)
    #expect(CleanupEdit(id: UUID(), input: "a", inserted: "Ship it.", edited: "Ship it").changed)
}

@Test func personalTuningStartsOnlyWhenEnabledIdleAndEnoughNewEdits() {
    let enough = PersonalTuningPolicy.newEditsBeforeTuning
    #expect(PersonalTuningPolicy.shouldTune(enabled: true, newEdits: enough, running: false, dictating: false))
    #expect(!PersonalTuningPolicy.shouldTune(enabled: true, newEdits: enough - 1, running: false, dictating: false))
    #expect(!PersonalTuningPolicy.shouldTune(enabled: false, newEdits: enough, running: false, dictating: false))
    #expect(!PersonalTuningPolicy.shouldTune(enabled: true, newEdits: enough, running: true, dictating: false))
    #expect(!PersonalTuningPolicy.shouldTune(enabled: true, newEdits: enough, running: false, dictating: true))
}
