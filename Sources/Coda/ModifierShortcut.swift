import AppKit
import ApplicationServices
import CodaCore

@MainActor final class ModifierShortcut {
    struct KeyboardState {
        var flags: NSEvent.ModifierFlags = []
        var otherKey = false
        var chordHeld: Bool {
            flags.contains([.control, .option])
                && flags.intersection([.command, .shift, .function]).isEmpty && !otherKey
        }
    }
    private var global: Any?
    private var local: Any?
    private var timer: Timer?
    private var chord = ModifierChord()
    private var pending: Task<Void, Never>?
    private var generation = UUID()
    private let action: (ModifierChord.Action) -> Void
    private let readState: () -> KeyboardState
    private let canListen: () -> Bool
    private let activationDelay: Duration
    var available = false
    static var voiceOverConflict: Bool {
        (CFPreferencesCopyAppValue("voiceOverOn" as CFString, "com.apple.universalaccess" as CFString) as? Bool == true)
        || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.VoiceOver").isEmpty
    }
    init(readState: @escaping () -> KeyboardState = { physicalState() },
         canListen: @escaping () -> Bool = { AXIsProcessTrusted() && !voiceOverConflict },
         activationDelay: Duration = .milliseconds(30),
         action: @escaping (ModifierChord.Action) -> Void) {
        self.action = action; self.readState = readState
        self.canListen = canListen; self.activationDelay = activationDelay
    }
    private static func physicalState() -> KeyboardState {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
        // A Boolean only: no key contents are retained. Check non-modifier keys so
        // recovery polling cannot turn another Control–Option shortcut into dictation.
        let otherKey = flags.contains([.control, .option]) && (0..<128).contains { code in
            !(54...63).contains(code) && CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
        }
        return KeyboardState(flags: flags, otherKey: otherKey)
    }
    func start() {
        stop()
        guard canListen() else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }; return event
        }
        available = global != nil && local != nil
        guard available else { stop(); return }
        // Recover both presses and releases when AppKit misses flagsChanged.
        // stop() requires a full release before a fresh chord can arm.
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func poll() {
        guard canListen() else { interrupt(); return }
        let state = readState()
        update(state.flags, otherKey: state.otherKey)
    }
    func stop() {
        pending?.cancel(); generation = UUID(); timer?.invalidate(); timer = nil
        if let global { NSEvent.removeMonitor(global) }; if let local { NSEvent.removeMonitor(local) }
        global = nil; local = nil; available = false
        _ = chord.interrupt()
    }
    func interrupt() {
        pending?.cancel(); generation = UUID()
        let event = chord.interrupt()
        if event != .none { action(event) }
    }
    private func receive(_ event: NSEvent) {
        guard canListen() else { interrupt(); return }
        update(event.modifierFlags, otherKey: event.type == .keyDown)
    }
    private func update(_ flags: NSEvent.ModifierFlags, otherKey: Bool) {
        let event = chord.update(control: flags.contains(.control), option: flags.contains(.option),
            extraModifier: !flags.intersection([.command, .shift, .function]).isEmpty, otherKey: otherKey)
        if event == .arm {
            let token = UUID(); generation = token; pending?.cancel()
            let delay = activationDelay
            pending = Task { [weak self] in
                do { try await Task.sleep(for: delay) } catch { return }
                guard let self, token == generation, !Task.isCancelled else { return }
                // Recheck physical flags so quick releases during scheduling never start capture.
                guard readState().chordHeld, canListen() else { self.interrupt(); return }
                action(chord.activate())
            }
        } else if event != .none { pending?.cancel(); generation = UUID(); action(event) }
    }
}
