import AppKit
import Testing
@testable import Coda

@Test @MainActor func statusMenuDispatchesSetupAndOpenThroughNativeTargets() async throws {
    _ = NSApplication.shared
    let model = AppModel(preview: true)
    let controller = DictationController(preview: true)
    let delegate = AppDelegate()
    var opened = 0
    delegate.reopenMain = { opened += 1 }
    let status = StatusMenuController(model: model, dictation: controller, delegate: delegate, install: false)
    for command in [StatusMenuController.Command.open, .setup] {
        let row = try #require(status.menu.items.first { $0.action != nil && $0.tag == command.rawValue })
        #expect(row.isEnabled && row.target === status)
        status.menu.performActionForItem(at: status.menu.index(of: row))
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        let expected = command == .open ? 1 : 2
        while opened < expected && ContinuousClock.now < deadline { await Task.yield() }
        #expect(opened == expected)
    }
    #expect(controller.showOnboarding)
}

@Test @MainActor func statusMenuRefreshesBusyControlsAndKeepsRecoveryCommandsEnabled() throws {
    _ = NSApplication.shared
    let model = AppModel(preview: true)
    let controller = DictationController(preview: true)
    let delegate = AppDelegate()
    let status = StatusMenuController(model: model, dictation: controller, delegate: delegate, install: false)
    model.startingCapture = true
    status.rebuild()
    for command in [StatusMenuController.Command.setup, .dictate, .meeting] {
        #expect(status.menu.items.first { $0.action != nil && $0.tag == command.rawValue }?.isEnabled == false)
    }
    for command in [StatusMenuController.Command.open, .quit] {
        #expect(status.menu.items.first { $0.action != nil && $0.tag == command.rawValue }?.isEnabled == true)
    }
    #expect(status.menu.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.action != nil })
    #expect(status.menu.items.first { $0.tag == StatusMenuController.Command.about.rawValue }?.isEnabled == true)
}
