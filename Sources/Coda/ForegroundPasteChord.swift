import AppKit
import Carbon

/// Use the same foreground event route as a physical Command-V. Some web
/// editors ignore key events delivered directly to their parent process.
@MainActor enum ForegroundPasteChord {
    static func events() -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        source.localEventsSuppressionInterval = 0
        let keys: [(CGKeyCode, Bool, CGEventFlags)] = [
            (55, true, .maskCommand), (9, true, .maskCommand),
            (9, false, .maskCommand), (55, false, [])
        ]
        var result: [CGEvent] = []
        for (key, down, flags) in keys {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return nil }
            event.flags = flags
            result.append(event)
        }
        return result
    }

    static func send(validate: () -> Bool, injected: () -> Void) async -> Bool {
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        // A history retry can run on shortcut key-down, before the user has
        // released Control/Option. Never let those keys turn Paste into another command.
        while !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
            guard !Task.isCancelled, ContinuousClock.now < deadline, validate() else { return false }
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return false }
        }
        guard !Task.isCancelled, validate(), let events = events() else { return false }
        // Keep the chord synchronous and always release Command once started.
        // There is no Enter event and no retry after any delivery attempt.
        injected()
        post(events)
        return true
    }

    private static func post(_ events: [CGEvent]) {
        for (index, event) in events.enumerated() {
            event.post(tap: .cghidEventTap)
            if index < events.count - 1 { Thread.sleep(forTimeInterval: 0.01) }
        }
    }
}
