import AppKit
import ApplicationServices
import Carbon
import CodaCore

struct DictationCorrectionTarget {
    let element: AXUIElement
    let window: AXUIElement
    let pid: pid_t
    let passage: CorrectionPassage
    let dictated: String
}

/// The target is handed off before clipboard settling and survives insertion's
/// cleanup. Polling also covers editors which omit AX value-change notifications.
@MainActor final class DictationCorrections {
    private var task: Task<Void, Never>?
    private var passage: CorrectionPassage?
    private var original = ""
    private var latest: String?
    private var reported: String?
    private var changedAt: TimeInterval = 0
    private var onChange: (([WordCorrection]) -> Void)?
    private var isCommon: @MainActor (String) -> Bool = CustomDictionary.isCommon
    private(set) var active = false

    func start(_ target: DictationCorrectionTarget, onChange: @escaping ([WordCorrection], String, String) -> Void) {
        stop()
        configure(passage: target.passage, original: target.dictated) { [weak self] changes in
            guard let self, let edited = self.latest else { return }
            onChange(changes, self.original, edited)
        }
        AXUIElementSetMessagingTimeout(target.element, 0.08)
        let began = ContinuousClock.now
        task = Task { [weak self] in
            while !Task.isCancelled {
                let age = began.duration(to: .now)
                let elapsed = Double(age.components.seconds) + Double(age.components.attoseconds) / 1e18
                guard let self, self.active else { return }
                guard elapsed < 60, Self.targetIsCurrent(target) else { self.stop(); return }
                self.sample(Self.attribute(target.element, kAXValueAttribute) as? String, elapsed: elapsed)
                guard self.active else { return }
                do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            }
        }
    }
    // The same state machine is exercised with synthetic field snapshots in tests.
    func configure(passage: CorrectionPassage, original: String, isCommon: @escaping @MainActor (String) -> Bool = CustomDictionary.isCommon,
                   onChange: @escaping ([WordCorrection]) -> Void) {
        self.passage = passage; self.original = original; self.isCommon = isCommon; self.onChange = onChange; active = true
        latest = nil; reported = nil; changedAt = 0
    }
    func sample(_ value: String?, elapsed: TimeInterval) {
        guard active, var passage else { return }
        let sample = passage.sample(value, elapsed: elapsed); self.passage = passage
        switch sample {
        case .waiting: break
        case .stop: stop()
        case .passage(let text):
            if latest != text { latest = text; changedAt = elapsed }
            if elapsed - changedAt >= 0.8 { report() }
        }
    }
    func stop(flush: Bool = true) {
        if flush { report() }
        task?.cancel(); task = nil; passage = nil; onChange = nil; original = ""; latest = nil; reported = nil; active = false
    }
    private func report() {
        guard let latest, reported != latest else { return }
        reported = latest
        onChange?(CorrectionCandidates.extract(original: original, edited: latest, isCommon: { self.isCommon($0) }))
    }
    private static func targetIsCurrent(_ target: DictationCorrectionTarget) -> Bool {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(), NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid else { return false }
        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let focused = element(app, kAXFocusedUIElementAttribute), CFEqual(focused, target.element),
              let window = element(focused, kAXWindowAttribute), CFEqual(window, target.window) else { return false }
        var node: AXUIElement? = focused
        for _ in 0..<12 {
            guard let current = node else { return true }
            AXUIElementSetMessagingTimeout(current, 0.04)
            if attribute(current, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { return false }
            node = element(current, kAXParentAttribute)
        }
        // Unknown ancestry is insufficient evidence to observe text.
        return false
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(parent, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}
