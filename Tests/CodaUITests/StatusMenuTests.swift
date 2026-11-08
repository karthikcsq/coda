import AppKit
import Testing
@preconcurrency @testable import KeyboardShortcuts
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

@Test @MainActor func nativeMenuTrackingSuspendsShortcutInterceptionAndRestoresItOnCancel() throws {
    _ = NSApplication.shared
    let previous = KeyboardShortcuts.isEnabled
    defer { KeyboardShortcuts.isEnabled = previous }
    KeyboardShortcuts.isEnabled = true
    enum Cancelled: Error { case tracking }
    #expect(throws: Cancelled.self) {
        try MenuShortcutSuspension.perform {
            #expect(!KeyboardShortcuts.isEnabled)
            // Exercise the library's real tracking-notification path. It must
            // stay disabled instead of starting its event-queue observer.
            NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
            #expect(!KeyboardShortcuts.isEnabled)
            NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: NSMenu())
            throw Cancelled.tracking
        }
    }
    #expect(KeyboardShortcuts.isEnabled)
    KeyboardShortcuts.isEnabled = false
    MenuShortcutSuspension.perform { #expect(!KeyboardShortcuts.isEnabled) }
    #expect(!KeyboardShortcuts.isEnabled)
}

@Test @MainActor func shortcutTrackingNeverDequeuesOrRepostsMenuMouseEvents() throws {
    let mouse = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
    let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 2, windowNumber: 0, context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7))
    var queue = [mouse, key]
    var taken: [NSEvent] = []
    RunLoopLocalEventMonitor.processPendingEvents(matching: [.keyDown, .keyUp], peek: { queue.first }, take: { let event = queue.removeFirst(); taken.append(event); return event }, callback: { _ in nil }, restoreAtFront: { queue.insert($0, at: 0) })
    #expect(taken.isEmpty)
    #expect(queue.count == 2 && queue[0] === mouse && queue[1] === key)
    queue = [key, mouse]
    RunLoopLocalEventMonitor.processPendingEvents(matching: [.keyDown, .keyUp], peek: { queue.first }, take: { queue.removeFirst() }, callback: { $0 }, restoreAtFront: { queue.insert($0, at: 0) })
    #expect(queue.count == 2 && queue[0] === key && queue[1] === mouse)
}
