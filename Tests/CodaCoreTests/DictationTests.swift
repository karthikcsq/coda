import Testing
import Foundation
@testable import CodaCore

@Test func dictationToggleIgnoresRepeatsAndStopsOnSecondPress() throws {
    var flow = DictationLifecycle()
    #expect({ flow.keyDown(mode: .toggle) == .begin }())
    let id = try #require({ flow.begin(meetingBusy: false, modelReady: true) }())
    #expect({ flow.keyDown(mode: .toggle) == .none }())
    #expect({ flow.listening(id) }())
    #expect({ flow.keyUp(mode: .toggle) == .none }())
    #expect({ flow.keyDown(mode: .toggle) == .finish }())
    #expect({ flow.processing() == id }())
    #expect({ flow.keyDown(mode: .toggle) == .none }())
    #expect({ flow.complete(id) }()); #expect({ !flow.busy }())
}
@Test func holdReleaseDuringPermissionPromptNeverStartsCapture() throws {
    var flow = DictationLifecycle()
    #expect({ flow.keyDown(mode: .hold) == .begin }())
    let old = try #require({ flow.begin(meetingBusy: false, modelReady: true) }())
    #expect({ flow.keyUp(mode: .hold) == .cancel }())
    flow.cancel()
    #expect({ !flow.listening(old) }()); #expect({ !flow.accepts(old) }()); #expect({ !flow.busy }())
}
@Test func holdReleaseFinishesExactlyOnce() throws {
    var flow = DictationLifecycle()
    #expect({ flow.keyDown(mode: .hold) == .begin }())
    let id = try #require({ flow.begin(meetingBusy: false, modelReady: true) }()); #expect({ flow.listening(id) }())
    #expect({ flow.keyUp(mode: .hold) == .finish }())
    #expect({ flow.processing() == id }())
    #expect({ flow.keyUp(mode: .hold) == .none }())
}
@Test func cancellingInferenceBlocksRestartAndLateInsertion() throws {
    var flow = DictationLifecycle()
    let old = try #require({ flow.begin(meetingBusy: false, modelReady: true) }()); #expect({ flow.listening(old) }()); #expect({ flow.processing() == old }())
    flow.cancel()
    #expect({ flow.busy }()); #expect({ flow.phase == .cancelling }())
    #expect({ flow.begin(meetingBusy: false, modelReady: true) == nil }())
    #expect({ !flow.complete(old) }()); #expect({ !flow.accepts(old) }())
    flow.settled(old)
    let next = try #require({ flow.begin(meetingBusy: false, modelReady: true) }())
    #expect({ next != old }()); #expect({ !flow.complete(old) }()); flow.fail(old)
    #expect({ flow.phase == .arming }()); #expect({ flow.accepts(next) }())
}
@Test func escapeWhileKeyHeldDoesNotRestartFromRepeat() throws {
    var flow = DictationLifecycle()
    #expect({ flow.keyDown(mode: .hold) == .begin }())
    let id = try #require({ flow.begin(meetingBusy: false, modelReady: true) }()); #expect({ flow.listening(id) }())
    flow.cancel()
    #expect({ flow.keyDown(mode: .hold) == .none }())
    #expect({ flow.keyUp(mode: .hold) == .none }())
    #expect({ flow.keyDown(mode: .hold) == .begin }())
}
@Test func meetingAndMissingModelPreventDictation() {
    var flow = DictationLifecycle()
    #expect({ flow.begin(meetingBusy: true, modelReady: true) == nil }())
    #expect({ flow.begin(meetingBusy: false, modelReady: false) == nil }())
    #expect({ !flow.busy }()); #expect({ flow.id == nil }())
}
@Test func permissionDenialIsRecoverableAndOldFailureCannotCancelNewSession() throws {
    var flow = DictationLifecycle()
    let old = try #require({ flow.begin(meetingBusy: false, modelReady: true) }()); flow.fail(old)
    #expect({ flow.phase == .failed }()); #expect({ !flow.busy }())
    let next = try #require({ flow.begin(meetingBusy: false, modelReady: true) }()); flow.fail(old)
    #expect({ flow.listening(next) }())
}
@Test func dismissDuringArmingRejectsLatePermissionAndSleepResetsKeyLatch() throws {
    var flow = DictationLifecycle()
    #expect({ flow.keyDown(mode: .toggle) == .begin }())
    let old = try #require({ flow.begin(meetingBusy: false, modelReady: true) }())
    flow.cancel(); flow.resetKeys()
    #expect({ !flow.listening(old) }()); #expect({ flow.keyDown(mode: .toggle) == .begin }())
}
@Test func safeInsertionRequiresEveryGuardAndNeverAcceptsSecureFields() {
    let safe = InsertionConditions(trusted: true, secure: false, originalAppFocused: true, sameElement: true, sameSelection: true, focusUnchanged: true, writable: true)
    #expect({ safe.mayInsert }())
    let mutations: [(inout InsertionConditions) -> Void] = [
        { $0.trusted = false }, { $0.secure = true }, { $0.originalAppFocused = false },
        { $0.sameElement = false }, { $0.sameSelection = false }, { $0.focusUnchanged = false }, { $0.writable = false }
    ]
    for mutate in mutations { var condition = safe; mutate(&condition); #expect({ !condition.mayInsert }()) }
}

@Test func displaySleepDuringInferenceDiscardsResultBeforeNextSession() throws {
    var flow = DictationLifecycle()
    let pending = flow.begin(meetingBusy: false, modelReady: true)
    let id = try #require(pending)
    _ = flow.listening(id); _ = flow.processing()
    flow.cancel(); flow.resetKeys()
    let late = flow.complete(id)
    #expect(!late); #expect(flow.busy)
    flow.settled(id)
    let resumed = flow.begin(meetingBusy: false, modelReady: true)
    #expect(resumed != nil); #expect(resumed != id)
}
