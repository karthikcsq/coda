import Testing
@testable import CodaCore

@Test func chordStartsOnceAndReleasesEitherKey() {
    for releaseControl in [true, false] {
        var chord = ModifierChord()
        #expect({ chord.update(control: true, option: false, extraModifier: false) == .none }())
        #expect({ chord.update(control: true, option: true, extraModifier: false) == .arm }())
        #expect({ chord.activate() == .down }())
        #expect({ chord.activate() == .none }())
        #expect({ chord.update(control: true, option: true, extraModifier: false) == .none }())
        #expect({ chord.update(control: !releaseControl, option: releaseControl, extraModifier: false) == .up }())
        #expect({ chord.update(control: true, option: true, extraModifier: false) == .none }())
        #expect({ chord.update(control: false, option: false, extraModifier: false) == .none }())
        #expect({ chord.update(control: true, option: true, extraModifier: false) == .arm }())
    }
}
@Test func chordQuickReleaseRejectsDelayedActivation() {
    var chord = ModifierChord()
    _ = chord.update(control: true, option: true, extraModifier: false)
    _ = chord.update(control: true, option: false, extraModifier: false)
    #expect({ chord.activate() == .none }())
}
@Test func chordDoesNotActivateForAnotherShortcut() {
    var chord = ModifierChord()
    _ = chord.update(control: true, option: true, extraModifier: false)
    _ = chord.update(control: true, option: true, extraModifier: false, otherKey: true)
    #expect({ chord.activate() == .none }())
    #expect({ chord.update(control: true, option: true, extraModifier: false) == .none }())
    _ = chord.update(control: false, option: false, extraModifier: false)
    #expect({ chord.update(control: true, option: true, extraModifier: true) == .none }())
}
@Test func chordInterruptionCancelsOnceAndNeedsRelease() {
    var chord = ModifierChord()
    _ = chord.update(control: true, option: true, extraModifier: false); _ = chord.activate()
    #expect({ chord.interrupt() == .cancel }())
    #expect({ chord.interrupt() == .none }())
    #expect({ chord.update(control: true, option: true, extraModifier: false) == .none }())
    _ = chord.update(control: false, option: false, extraModifier: false)
    #expect({ chord.update(control: true, option: true, extraModifier: false) == .arm }())
}
@Test func modifierHoldReleaseDuringStartupInvalidatesOldCapture() throws {
    var chord = ModifierChord(); var flow = DictationLifecycle()
    _ = chord.update(control: true, option: true, extraModifier: false)
    #expect({ chord.activate() == .down }())
    #expect({ flow.keyDown(mode: .hold) == .begin }())
    let id = try #require({ flow.begin(meetingBusy: false, modelReady: true) }())
    #expect({ chord.update(control: false, option: true, extraModifier: false) == .up }())
    #expect({ flow.keyUp(mode: .hold) == .cancel }()); flow.cancel()
    #expect({ !flow.listening(id) }())
    #expect({ !flow.accepts(id) }())
}
@Test func modifierHoldProcessingAndToggleReuseExistingLifecycle() throws {
    for mode in [DictationMode.hold, .toggle] {
        var chord = ModifierChord(); var flow = DictationLifecycle()
        _ = chord.update(control: true, option: true, extraModifier: false); _ = chord.activate()
        #expect({ flow.keyDown(mode: mode) == .begin }())
        let id = try #require({ flow.begin(meetingBusy: false, modelReady: true) }())
        #expect({ flow.listening(id) }())
        #expect({ chord.update(control: false, option: false, extraModifier: false) == .up }())
        let intent = flow.keyUp(mode: mode)
        #expect(intent == (mode == .hold ? .finish : .none))
        if mode == .toggle { #expect({ flow.keyDown(mode: mode) == .finish }()) }
        #expect({ flow.processing() == id }())
        #expect({ flow.keyDown(mode: mode) == .none }())
    }
}
