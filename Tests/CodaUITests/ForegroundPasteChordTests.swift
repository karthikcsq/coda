import AppKit
import Testing
@testable import Coda

@Test @MainActor func pasteChordContainsOnlyCommandVAndReleasesCommand() throws {
    let events = try #require(ForegroundPasteChord.events())
    #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [55, 9, 9, 55])
    #expect(events.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
    #expect(events.map(\.flags.rawValue) == [CGEventFlags.maskCommand.rawValue, CGEventFlags.maskCommand.rawValue, CGEventFlags.maskCommand.rawValue, 0])
}

@Test @MainActor func invalidDestinationNeverPostsPaste() async {
    var posted = false
    let sent = await ForegroundPasteChord.send(validate: { false }, injected: { posted = true })
    #expect(!sent)
    #expect(!posted)
}

@Test @MainActor func cancelledInsertionNeverPostsPaste() async {
    var posted = false
    let task = Task { @MainActor in
        await ForegroundPasteChord.send(validate: { true }, injected: { posted = true })
    }
    task.cancel()
    #expect(await !task.value)
    #expect(!posted)
}
