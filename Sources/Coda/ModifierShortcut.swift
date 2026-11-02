import AppKit
import ApplicationServices
import CodaCore

@MainActor final class ModifierShortcut {
    private var global: Any?
    private var local: Any?
    private var timer: Timer?
    private var chord = ModifierChord()
    private var pending: Task<Void, Never>?
    private var generation = UUID()
    private let action: (ModifierChord.Action) -> Void
    var available = false
    static var voiceOverConflict: Bool {
        (CFPreferencesCopyAppValue("voiceOverOn" as CFString, "com.apple.universalaccess" as CFString) as? Bool == true)
        || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.VoiceOver").isEmpty
    }
    init(action: @escaping (ModifierChord.Action) -> Void) { self.action = action }
    func start() {
        stop()
        guard AXIsProcessTrusted(), !Self.voiceOverConflict else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }; return event
        }
        available = global != nil && local != nil
        guard available else { stop(); return }
        // Release watchdog: survives missed flagsChanged events and focus changes.
        // It never starts a recording, only releases or cancels an existing chord.
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let flags = NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
                if Self.voiceOverConflict || !AXIsProcessTrusted() { self.interrupt(); return }
                if !flags.contains([.control, .option]) || !flags.intersection([.command, .shift, .function]).isEmpty {
                    self.update(flags, otherKey: false)
                }
            }
        }
    }
    func stop() {
        pending?.cancel(); generation = UUID(); timer?.invalidate(); timer = nil
        if let global { NSEvent.removeMonitor(global) }; if let local { NSEvent.removeMonitor(local) }
        global = nil; local = nil; available = false
        _ = chord.interrupt()
    }
    func interrupt() {
        pending?.cancel(); generation = UUID()
        let event = chord.interrupt(); action(event)
    }
    private func receive(_ event: NSEvent) {
        if Self.voiceOverConflict { interrupt(); return }
        update(event.modifierFlags, otherKey: event.type == .keyDown)
    }
    private func update(_ flags: NSEvent.ModifierFlags, otherKey: Bool) {
        let event = chord.update(control: flags.contains(.control), option: flags.contains(.option),
            extraModifier: !flags.intersection([.command, .shift, .function]).isEmpty, otherKey: otherKey)
        if event == .arm {
            let token = UUID(); generation = token; pending?.cancel()
            pending = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard let self, token == generation, !Task.isCancelled else { return }
                // Recheck physical flags so quick releases during scheduling never start capture.
                let flags = CGEventSource.flagsState(.combinedSessionState)
                guard flags.contains([.maskControl, .maskAlternate]),
                      flags.intersection([.maskCommand, .maskShift, .maskSecondaryFn]).isEmpty,
                      !Self.voiceOverConflict, AXIsProcessTrusted() else { self.interrupt(); return }
                action(chord.activate())
            }
        } else if event != .none { pending?.cancel(); generation = UUID(); action(event) }
    }
}
