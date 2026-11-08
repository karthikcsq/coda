import Foundation

/// Readiness is derived from actual capabilities, never a dismissed setup screen.
public struct SetupReadiness: Equatable, Sendable {
    public var modelConsent: Bool
    public var modelPrepared: Bool
    public var microphoneAllowed: Bool
    public var shortcutAssigned: Bool
    public var modifierShortcut: Bool
    public var accessibilityAllowed: Bool
    public init(modelConsent: Bool, modelPrepared: Bool, microphoneAllowed: Bool,
                shortcutAssigned: Bool, modifierShortcut: Bool, accessibilityAllowed: Bool) {
        self.modelConsent = modelConsent; self.modelPrepared = modelPrepared
        self.microphoneAllowed = microphoneAllowed; self.shortcutAssigned = shortcutAssigned
        self.modifierShortcut = modifierShortcut; self.accessibilityAllowed = accessibilityAllowed
    }
    public var canPractice: Bool { modelConsent && modelPrepared && microphoneAllowed }
    public var canDictate: Bool { canPractice && shortcutAssigned && (!modifierShortcut || accessibilityAllowed) }
    public var canInsert: Bool { canDictate && accessibilityAllowed }
    public var completedSteps: Int {
        [modelConsent && modelPrepared, microphoneAllowed, shortcutAssigned && (!modifierShortcut || accessibilityAllowed)].filter { $0 }.count
    }
    public var nextAction: String {
        if !modelConsent { return "Review local model terms" }
        if !modelPrepared { return "Prepare speech recognition" }
        if !microphoneAllowed { return "Enable your microphone" }
        if !shortcutAssigned { return "Choose your shortcut" }
        if modifierShortcut && !accessibilityAllowed { return "Enable your shortcut access" }
        return "Try your first dictation"
    }
}
