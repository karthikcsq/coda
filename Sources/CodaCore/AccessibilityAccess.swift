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
        if !trusted { guidance = "This Coda process cannot currently use Accessibility. If the system toggle is already on, quit and reopen Coda after saving your work. Rebuilt ad-hoc apps may need their permission reviewed by macOS." }
    }
    public func refresh() {
        let previous = trusted
        trusted = check()
        if trusted { guidance = "Access enabled. Focus your destination and start a new dictation. Existing text remains available to Copy." }
        else if previous { guidance = "This running Coda process cannot use Accessibility. If the macOS toggle is already on, quit and reopen Coda; a rebuilt app may have a different signature." }
    }
    public func requestFromUserAction() {
        refresh()
        guard !trusted else { return }
        if !prompted { prompted = true; prompt() }
        // The trust API returns before the user responds; never treat a request as approval.
        refresh()
        guard !trusted else { return }
        guidance = openSettings()
            ? "Review Coda in Accessibility, then return here. If the toggle is already on, do not repeat it: save your work and restart this build. Only you can approve macOS permission changes."
            : "macOS could not open the pane. Open System Settings → Privacy & Security → Accessibility and turn on Coda."
    }
}
