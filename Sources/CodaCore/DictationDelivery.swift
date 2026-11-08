import Foundation

extension DictationPersonalization {
    /// Match authored snippets against recognition, before cleanup can remove words.
    /// Raw mode is an exact bypass of both snippets and surface formatting.
    public static func forDelivery(recognized: String, cleaned: String, mode: DictationCleanupMode,
                                   bundleID: String?, settings: DictationPreferenceSettings) -> DictationPersonalizationResult {
        guard mode != .none else { return .init(text: recognized, snippet: nil, style: .preserve) }
        let style = settings.style(forBundleID: bundleID)
        if let snippet = DictationSnippets.match(recognized, in: settings.snippets) {
            return .init(text: snippet.expansion, snippet: snippet, style: style)
        }
        return .init(text: DictationStyleFormatter.apply(cleaned, style: style), snippet: nil, style: style)
    }
}
