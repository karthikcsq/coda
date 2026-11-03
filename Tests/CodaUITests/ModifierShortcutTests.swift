import AppKit
import Testing
import CodaCore
@testable import Coda

@MainActor private final class ShortcutHarness {
    var state = ModifierShortcut.KeyboardState()
    var allowed = true
    var actions: [ModifierChord.Action] = []
    lazy var monitor = ModifierShortcut(readState: { [unowned self] in state },
        canListen: { [unowned self] in allowed }, activationDelay: .milliseconds(10)) {
            [unowned self] in actions.append($0)
        }
    init() { monitor.stop(); monitor.poll() }
    func waitForDown() async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !actions.contains(.down) && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@Test @MainActor func missedModifierPressAndReleaseRecoverWithoutAppKitEvents() async {
    let h = ShortcutHarness()
    defer { h.monitor.stop() }
    h.state.flags = [.control, .option]
    h.monitor.poll() // No flagsChanged callback at all.
    await h.waitForDown()
    #expect(h.actions == [.down])
    h.monitor.poll(); h.monitor.poll()
    #expect(h.actions == [.down])
    h.state.flags = [.option]; h.monitor.poll()
    h.state.flags = []; h.monitor.poll()
    #expect(h.actions == [.down, .up])
}

@Test @MainActor func recoveredChordDoesNotStartForOtherKeysOrRestartBeforeRelease() async {
    let h = ShortcutHarness()
    defer { h.monitor.stop() }
    h.state = .init(flags: [.control, .option], otherKey: true)
    h.monitor.poll()
    h.state.otherKey = false; h.monitor.poll()
    try? await Task.sleep(for: .milliseconds(40))
    #expect(h.actions.isEmpty) // Releasing D alone must not start dictation.
    h.state.flags = []; h.monitor.poll()
    h.state.flags = [.control, .option]; h.monitor.poll()
    await h.waitForDown()
    #expect(h.actions == [.down])
    h.state.otherKey = true; h.monitor.poll()
    #expect(h.actions == [.down, .cancel])
}

@Test @MainActor func delayedChordRechecksOtherKeysAndPermissionBeforeActivation() async {
    for losePermission in [true, false] {
        let h = ShortcutHarness()
        h.state.flags = [.control, .option]; h.monitor.poll()
        if losePermission { h.allowed = false } else { h.state.otherKey = true }
        // No intervening event or poll: the delayed callback must check hardware again.
        try? await Task.sleep(for: .milliseconds(40))
        #expect(!h.actions.contains(.down))
        h.monitor.stop()
    }
}

@Test @MainActor func listenerRestartRequiresReleaseAndQuickTapCannotActivate() async {
    let h = ShortcutHarness()
    defer { h.monitor.stop() }
    h.monitor.stop()
    h.state.flags = [.control, .option]; h.monitor.poll()
    try? await Task.sleep(for: .milliseconds(40))
    #expect(h.actions.isEmpty) // Held keys at restart are not a fresh request.
    h.state.flags = []; h.monitor.poll()
    h.state.flags = [.control, .option]; h.monitor.poll()
    h.state.flags = []; h.monitor.poll()
    try? await Task.sleep(for: .milliseconds(40))
    #expect(h.actions.isEmpty)
}

@Test @MainActor func hudShowsStartupAndFailureInsteadOfReady() throws {
    let controller = DictationController(preview: true)
    controller.message = "Prepare Voz in Settings before dictating."
    let hud = DictationHUD(controller: controller)
    #expect(hud.statusTitle != "Ready to dictate")
    #expect(hud.statusDetail == controller.message)
    let begun = controller.lifecycle.begin(meetingBusy: false, modelReady: true)
    let token = try #require(begun)
    controller.message = "Preparing microphone…"
    #expect(hud.statusTitle == "Starting microphone")
    #expect(hud.statusDetail == controller.message)
    controller.lifecycle.fail(token)
    controller.message = "Microphone could not start. Check your input device and permission, then retry."
    #expect(hud.statusTitle == "Dictation failed")
    #expect(hud.statusDetail == controller.message)
}

@Test @MainActor func stoppingListenerCancelsPendingStart() async {
    let h = ShortcutHarness()
    h.state.flags = [.control, .option]; h.monitor.poll()
    h.monitor.stop()
    try? await Task.sleep(for: .milliseconds(40))
    #expect(!h.actions.contains(.down))
}

@Test @MainActor func shortcutStaysPausedUntilBothLockAndSleepEnd() {
    let controller = DictationController(preview: true)
    let lock = Notification.Name("com.apple.screenIsLocked")
    let sleep = NSWorkspace.willSleepNotification
    controller.pauseShortcut(for: lock)
    controller.pauseShortcut(for: sleep)
    controller.resumeShortcut(for: sleep)
    #expect(controller.modifierShortcutStatus.hasPrefix("Shortcut paused"))
    controller.resumeShortcut(for: lock)
    #expect(!controller.modifierShortcutStatus.hasPrefix("Shortcut paused"))
}
