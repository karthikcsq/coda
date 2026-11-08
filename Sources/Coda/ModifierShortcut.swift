import AppKit
import ApplicationServices
import CodaCore

@MainActor final class ModifierShortcut {
    struct KeyboardState {
        var flags: NSEvent.ModifierFlags = []
        var otherKey = false
        var chordHeld: Bool { chordHeld(requiringShift: false) }
        func chordHeld(requiringShift: Bool) -> Bool {
            flags.contains(requiringShift ? [.control, .option, .shift] : [.control, .option])
                && flags.intersection(requiringShift ? [.command, .function] : [.command, .shift, .function]).isEmpty && !otherKey
        }
    }
    private var eventTap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var timer: Timer?
    private var chord = ModifierChord()
    private var pending: Task<Void, Never>?
    private var generation = UUID()
    private let action: (ModifierChord.Action) -> Void
    private let readState: () -> KeyboardState
    private let canListen: () -> Bool
    private let requiresShift: Bool
    private let activationDelay: Duration
    var available = false
    static var voiceOverConflict: Bool {
        (CFPreferencesCopyAppValue("voiceOverOn" as CFString, "com.apple.universalaccess" as CFString) as? Bool == true)
        || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.VoiceOver").isEmpty
    }
    init(readState: @escaping () -> KeyboardState = { physicalState() },
         canListen: @escaping () -> Bool = { AXIsProcessTrusted() && !voiceOverConflict },
         requiresShift: Bool = false,
         activationDelay: Duration = .milliseconds(30),
         action: @escaping (ModifierChord.Action) -> Void) {
        self.action = action; self.readState = readState
        self.requiresShift = requiresShift
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
        // A listen-only CGEvent tap does not participate in AppKit's local
        // event queue. NSEvent global/local monitors can disrupt menu tracking
        // on the installed macOS build, even after they are removed.
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ModifierShortcut>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated {
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        monitor.interrupt()
                        if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    } else if monitor.canListen() {
                        monitor.update(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)), otherKey: type == .keyDown)
                    } else { monitor.interrupt() }
                }
                return Unmanaged.passUnretained(event) // Never consume or modify input.
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let eventTap {
            let source = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
            tapSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
        // Physical-state polling is also a fallback if macOS refuses a tap.
        available = true
        // Recover both presses and releases when AppKit misses flagsChanged.
        // stop() requires a full release before a fresh chord can arm.
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    isolated deinit {
        if let eventTap { CFMachPortInvalidate(eventTap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        timer?.invalidate()
        pending?.cancel()
    }
    func poll() {
        guard canListen() else { interrupt(); return }
        let state = readState()
        update(state.flags, otherKey: state.otherKey)
    }
    func stop() {
        pending?.cancel(); generation = UUID(); timer?.invalidate(); timer = nil
        if let eventTap { CFMachPortInvalidate(eventTap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        eventTap = nil; tapSource = nil; available = false
        _ = chord.interrupt()
    }
    func interrupt() {
        pending?.cancel(); generation = UUID()
        let event = chord.interrupt()
        if event != .none { action(event) }
    }
    private func update(_ flags: NSEvent.ModifierFlags, otherKey: Bool) {
        let event = chord.update(control: flags.contains(.control) && (!requiresShift || flags.contains(.shift)), option: flags.contains(.option),
            extraModifier: !flags.intersection(requiresShift ? [.command, .function] : [.command, .shift, .function]).isEmpty, otherKey: otherKey)
        if event == .arm {
            let token = UUID(); generation = token; pending?.cancel()
            let delay = activationDelay
            pending = Task { [weak self] in
                do { try await Task.sleep(for: delay) } catch { return }
                guard let self, token == generation, !Task.isCancelled else { return }
                // Recheck physical flags so quick releases during scheduling never start capture.
                guard readState().chordHeld(requiringShift: requiresShift), canListen() else { self.interrupt(); return }
                action(chord.activate())
            }
        } else if event != .none { pending?.cancel(); generation = UUID(); action(event) }
    }
}
