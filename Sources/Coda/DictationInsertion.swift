import AppKit
import ApplicationServices
import Carbon
import CodaCore

@MainActor final class DictationInsertion {
    private(set) var targetDisplayFrame: CGRect?
    private var element: AXUIElement?
    private var pid: pid_t?
    private var targetWindow: AXUIElement?
    private var delivering = false
    private(set) var deliveryAttempted = false
    private var selection: CFRange?
    private var activationToken: NSObjectProtocol?
    private var focusChanged = false
    private var observer: AXObserver?
    private var contentFingerprint: Data?
    private var monitor: Task<Void, Never>?
    private(set) var reason = "Click an editable field in another app, then use the dictation shortcut."
    private var observedApp: AXUIElement?
    private(set) var targetName = "Copy result"

    func captureTarget() {
        clear()
        guard AXIsProcessTrusted() else { reason = "This running Coda process lacks Accessibility access. If the system toggle is already on, quit and reopen Coda; see Settings for this build’s access status."; return }
        guard !IsSecureEventInputEnabled() else { reason = "Secure input is active. Coda will not insert into protected fields."; return }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { reason = "Focus a text field in another app and start with your dictation shortcut."; return }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.3)
        targetName = app.localizedName ?? "Original app"
        // Electron documents this attribute for assistive clients. Unsupported
        // apps ignore it; no OS permission or persistent app setting is changed.
        _ = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let focused = focusedElement(application)
        guard focused.map({ !secure($0) && acceptsPaste($0) }) ?? true else {
            reason = "Click inside a non-secure text field and use the shortcut."; return
        }
        targetWindow = focused.flatMap { elementAttribute($0, kAXWindowAttribute) }
            ?? elementAttribute(application, kAXFocusedWindowAttribute)
        guard focused != nil || targetWindow != nil else {
            reason = "The destination has no focused window. Click its text field and try again."; return
        }
        if let window = targetWindow {
            if let position = attribute(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID() {
                var point = CGPoint.zero
                if AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point) {
                    let top = NSScreen.screens.first?.frame.maxY ?? 0
                    let cocoaPoint = CGPoint(x: point.x + 30, y: top - point.y - 30)
                    targetDisplayFrame = NSScreen.screens.first(where: { $0.frame.contains(cocoaPoint) })?.visibleFrame
                }
            }
        }
        contentFingerprint = focused.flatMap { attribute($0, kAXValueAttribute) as? String }.map(InsertionObservation.fingerprint)
        element = focused; pid = app.processIdentifier; selection = focused.flatMap(selectedRange)
        activationToken = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSnapshot() }
        }
        var newObserver: AXObserver?
        let result = AXObserverCreate(app.processIdentifier, { _, _, notification, context in
            guard let context else { return }
            let owner = Unmanaged<DictationInsertion>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                guard !owner.delivering else { return }
                if notification as String != kAXFocusedUIElementChangedNotification && owner.contentFingerprint == nil {
                    owner.reject("The destination text or selection changed. Your text is saved in History.")
                } else { owner.checkSnapshot() }
            }
        }, &newObserver)
        // Notifications improve latency, but unsupported notifications must not
        // disable otherwise ordinary paste. Polling and the final check remain active.
        if result == .success, let newObserver {
            observer = newObserver; observedApp = application
            let context = Unmanaged.passUnretained(self).toOpaque()
            _ = AXObserverAddNotification(newObserver, application, kAXFocusedUIElementChangedNotification as CFString, context)
            if let focused {
                _ = AXObserverAddNotification(newObserver, focused, kAXSelectedTextChangedNotification as CFString, context)
                _ = AXObserverAddNotification(newObserver, focused, kAXValueChangedNotification as CFString, context)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        }
        reason = "Ready to insert into the original field."
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self else { return }
                self.checkSnapshot()
            }
        }
        if let focused { AXUIElementSetMessagingTimeout(focused, 0.3) }
    }
    /// One paste mechanism for native, browser, Electron and opaque editors.
    /// AX value/selection are optional evidence, never prerequisites for Command-V.
    func insertWithFallback(_ text: String, observeCorrections: ((DictationCorrectionTarget) -> Void)? = nil) async -> Bool {
        guard !deliveryAttempted, pid != nil, !text.isEmpty, !Task.isCancelled else { return false }
        checkSnapshot()
        guard !focusChanged, AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return false }
        let expected = element.flatMap { attribute($0, kAXValueAttribute) as? String }.flatMap { original in
            selection.flatMap { PlainTextInsertion.replacing(original, range: NSRange(location: $0.location, length: $0.length), with: text) }
        }
        let correctionTarget: DictationCorrectionTarget?
        if let element, let pid, let window = targetWindow, let selection,
           let before = attribute(element, kAXValueAttribute) as? String,
           let passage = CorrectionPassage(before: before, selection: NSRange(location: selection.location, length: selection.length), dictated: text) {
            correctionTarget = DictationCorrectionTarget(element: element, window: window, pid: pid, passage: passage, dictated: text)
        } else { correctionTarget = nil }
        let paste = GuardedPaste(board: .general)
        guard paste.publish(text) else { reason = "Clipboard could not be preserved safely. Use Copy text."; return false }
        defer { paste.restore() }
        let sent = await ForegroundPasteChord.send(validate: { [self] in
            checkSnapshot()
            return !focusChanged && paste.ownsClipboard && AXIsProcessTrusted() && !IsSecureEventInputEnabled()
                && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        }, injected: { [self] in
            delivering = true
            monitor?.cancel(); monitor = nil
            deliveryAttempted = true
        })
        guard sent else {
            if !focusChanged { reason = "Paste was not sent. Release your shortcut keys and try Insert from History." }
            return false
        }
        if let correctionTarget { observeCorrections?(correctionTarget) }
        let postedAt = Date()
        while !InsertionEvidence.pasteWaitIsComplete(elapsed: Date().timeIntervalSince(postedAt),
                firstReadAge: paste.readAt.map { Date().timeIntervalSince($0) }, ownsClipboard: paste.ownsClipboard) {
            do { try await Task.sleep(for: .milliseconds(25)) } catch { break }
        }
        let actual = element.flatMap { attribute($0, kAXValueAttribute) as? String }
        let verified = expected != nil && actual == expected
        reason = verified ? "Paste sent. The destination reports matching text. Check the field before retrying." : "Paste sent. Check the destination before retrying; your text is saved in History."
        // Cached AX text and clipboard receipts cannot prove visible editor state.
        return false
    }
    private func checkSnapshot() {
        guard !delivering, !focusChanged, let pid else { return }
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { reject("Automatic insertion access is unavailable or secure input is active. Your text is saved in History."); return }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.3)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { reject("The destination app lost focus. Your text is saved in History."); return }
        let focused = focusedElement(application)
        if let targetWindow {
            let currentWindow = focused.flatMap { elementAttribute($0, kAXWindowAttribute) }
                ?? elementAttribute(application, kAXFocusedWindowAttribute)
            guard currentWindow.map({ CFEqual($0, targetWindow) }) == true else { reject("The destination window changed. Your text is saved in History."); return }
        }
        if let element {
            guard let focused, CFEqual(focused, element) else { reject("The destination field changed or stopped responding. Your text is saved in History."); return }
            guard !secure(focused), acceptsPaste(focused) else { reject("The destination is no longer an editable, non-secure field."); return }
            let current = selectedRange(focused).map { NSRange(location: $0.location, length: $0.length) }
            let original = selection.map { NSRange(location: $0.location, length: $0.length) }
            guard InsertionObservation.selectionUnchanged(original: original, current: current) else { reject("The destination cursor or selection changed. Select a fresh destination from History."); return }
            guard InsertionObservation.unchanged(original: contentFingerprint, current: contentFingerprint == nil ? nil : attribute(focused, kAXValueAttribute) as? String) else { reject("The destination text changed. Your dictation is saved in History."); return }
        } else if let focused {
            // An initially opaque editor can expose its focused field later.
            // Scope subsequent checks to that field without inventing a caret.
            guard !secure(focused), acceptsPaste(focused) else { reject("Click inside a non-secure text field and try again."); return }
            element = focused
            selection = selectedRange(focused)
            contentFingerprint = (attribute(focused, kAXValueAttribute) as? String).map(InsertionObservation.fingerprint)
        }
    }
    private func reject(_ explanation: String) { focusChanged = true; reason = explanation }
    func clear() {
        monitor?.cancel(); monitor = nil; contentFingerprint = nil; targetDisplayFrame = nil
        if let activationToken { NSWorkspace.shared.notificationCenter.removeObserver(activationToken) }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        activationToken = nil; observer = nil; observedApp = nil; element = nil; pid = nil; selection = nil; focusChanged = false
        targetName = "Copy result"; targetWindow = nil; delivering = false; deliveryAttempted = false
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }; return value
    }
    private func focusedElement(_ app: AXUIElement) -> AXUIElement? {
        guard let value = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    private func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(ax) == .cfRange else { return nil }
        var range = CFRange(); guard AXValueGetValue(ax, .cfRange, &range), range.location >= 0, range.location != NSNotFound, range.length >= 0 else { return nil }; return range
    }
    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    private func secure(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let node = current else { break }
            if attribute(node, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { return true }
            current = elementAttribute(node, kAXParentAttribute)
        }
        return false
    }
    private func acceptsPaste(_ element: AXUIElement) -> Bool {
        // Opaque web/terminal containers can own a real editor without exposing
        // selection or value. Known buttons, menus, and other controls cannot.
        guard let role = attribute(element, kAXRoleAttribute) as? String else { return true }
        return [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXWebArea",
                kAXGroupRole, kAXScrollAreaRole, kAXUnknownRole].contains(role)
    }
}
