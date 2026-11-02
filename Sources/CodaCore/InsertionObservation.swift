import Foundation
import CryptoKit

/// Available text evidence strengthens app/window/field focus checks. Missing
/// cursor or text attributes must not disable an editor's normal paste command.
public enum InsertionObservation {
    public static func selectionUnchanged(original: NSRange?, current: NSRange?) -> Bool {
        guard let original else { return true }
        return original == current
    }
    public static func fingerprint(_ text: String) -> Data {
        Data(SHA256.hash(data: Data(text.utf8)))
    }
    public static func unchanged(original: Data?, current: String?) -> Bool {
        guard let original else { return true }
        guard let current else { return false }
        return original == fingerprint(current)
    }
}
