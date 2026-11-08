import Foundation
import Observation

/// All OS side effects are explicit and injectable; refresh never requests access.
@MainActor @Observable public final class AccessibilityAccess {
    public private(set) var trusted: Bool
    public private(set) var guidance = "Allow Coda to insert text into other apps. macOS requires your approval."
    private var prompted = false
    private let check: () -> Bool
    private let prompt: () -> Void
    private let openSettings: () -> Bool
    public init(check: @escaping () -> Bool, prompt: @escaping () -> Void, openSettings: @escaping () -> Bool) {
        self.check = check; self.prompt = prompt; self.openSettings = openSettings; trusted = check()
        if !trusted { guidance = "Allow Coda in System Settings to insert your dictation into other apps. You can still copy results without this access." }
    }
    public func refresh() {
        let previous = trusted
        trusted = check()
        if trusted { guidance = "Access enabled. Focus your destination and start a new dictation. Existing text remains available to Copy." }
        else if previous { guidance = "Accessibility access is off. Review Coda in System Settings. If it is already enabled, save your work and reopen Coda." }
    }
    public func requestFromUserAction() {
        refresh()
        guard !trusted else { return }
        if !prompted { prompted = true; prompt() }
        // The trust API returns before the user responds; never treat a request as approval.
        refresh()
        guard !trusted else { return }
        guidance = openSettings()
            ? "Enable Coda in Accessibility, then return here. If it is already enabled, save your work and reopen Coda. Only you can approve this access in macOS."
            : "macOS could not open the pane. Open System Settings → Privacy & Security → Accessibility and turn on Coda."
    }
}
