import Foundation

/// An AX return code or readback alone does not establish visible editor state.
public enum InsertionEvidence {
    /// Clipboard consumption determines when restoration can settle, not whether
    /// a possibly cached Accessibility wrapper reports the visible paste.
    public static func pasteWaitIsComplete(elapsed: TimeInterval, firstReadAge: TimeInterval?, ownsClipboard: Bool) -> Bool {
        if !ownsClipboard || elapsed >= 3 { return true }
        guard elapsed >= 0.15, let firstReadAge else { return false }
        return firstReadAge >= 0.35
    }
}
