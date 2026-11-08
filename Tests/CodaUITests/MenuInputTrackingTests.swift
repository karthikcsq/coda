import AppKit
import Testing
import CodaCore
@preconcurrency import KeyboardShortcuts
@testable import Coda

@Test @MainActor func menuTrackingPausesAllShortcutsUntilTheOutermostMenuCloses() throws {
    let before = KeyboardShortcuts.isEnabled
    defer { KeyboardShortcuts.isEnabled = before }
    KeyboardShortcuts.isEnabled = true
    let controller = DictationController(preview: true)
    controller.mode = .toggle
    let begun = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let id = try #require(begun)
    let listening = controller.lifecycle.listening(id)
    #expect(listening)
    controller.beginMenuTracking()
    controller.beginMenuTracking()
    #expect(!KeyboardShortcuts.isEnabled && controller.menuTrackingDepth == 2)
    #expect(controller.lifecycle.phase == .listening)
    controller.endMenuTracking()
    #expect(!KeyboardShortcuts.isEnabled && controller.menuTrackingDepth == 1)
    controller.endMenuTracking()
    #expect(KeyboardShortcuts.isEnabled && controller.menuTrackingDepth == 0)
    #expect(controller.lifecycle.phase == .listening)
    controller.endMenuTracking()
    #expect(controller.menuTrackingDepth == 0)
}

@Test @MainActor func menuTrackingPreservesPreviouslyDisabledShortcutState() {
    let before = KeyboardShortcuts.isEnabled
    defer { KeyboardShortcuts.isEnabled = before }
    KeyboardShortcuts.isEnabled = false
    let controller = DictationController(preview: true)
    controller.beginMenuTracking(); controller.endMenuTracking()
    #expect(!KeyboardShortcuts.isEnabled)
}
