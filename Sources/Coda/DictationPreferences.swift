import Foundation
import Observation
import CodaCore

/// Writing style, per-app styles and voice snippets, persisted to
/// Application Support/Coda/DictationPreferences/settings.json.
/// Every edit is validated; failures leave settings unchanged and set `error`.
@MainActor @Observable final class DictationPreferences {
    private(set) var settings = DictationPreferenceSettings()
    /// The latest validation or storage failure, phrased for display.
    private(set) var error: String?
    /// Set when the saved file had entries that could not be used. The original
    /// file is copied aside before the first change is saved.
    private(set) var notice: String?
    /// False when the saved file can't be read or was written by a newer Coda.
    /// Edits are then refused so that file is never overwritten.
    private(set) var isEditable = true

    @ObservationIgnored private var store: DictationPreferenceStore?
    @ObservationIgnored private var preserveBeforeSave = false
    private let preview: Bool

    var globalStyle: DictationWritingStyle { settings.globalStyle }
    var appRules: [DictationAppRule] {
        settings.appRules.sorted { ($0.appName ?? $0.bundleID).localizedStandardCompare($1.appName ?? $1.bundleID) == .orderedAscending }
    }
    var snippets: [DictationSnippet] {
        settings.snippets.sorted { $0.trigger.localizedStandardCompare($1.trigger) == .orderedAscending }
    }

    /// `preview` keeps everything in memory, for SwiftUI previews and render tests.
    init(root: URL? = nil, preview: Bool = false, settings initial: DictationPreferenceSettings? = nil) {
        self.preview = preview
        if preview { settings = initial ?? DictationPreferenceSettings(); return }
        let root = root ?? BuildIdentity.dataRoot.appendingPathComponent("DictationPreferences")
        do {
            let storage = try DictationPreferenceStore(root: root)
            store = storage
            if let loaded = try storage.load() {
                settings = loaded.settings
                if !loaded.issues.isEmpty {
                    preserveBeforeSave = true
                    notice = Self.describe(loaded.issues)
                }
            } else if let initial { settings = initial }
        } catch DictationPreferenceSettings.LoadFailure.newerVersion {
            isEditable = false
            error = "These dictation settings were saved by a newer version of Coda. They are in use read-only and won't be changed."
        } catch {
            isEditable = false
            self.error = "Could not read your dictation settings. The file was preserved; dictation keeps your cleanup formatting until it's fixed or reset."
        }
    }

    // MARK: Lookup used by dictation

    func style(forBundleID bundleID: String?) -> DictationWritingStyle { settings.style(forBundleID: bundleID) }
    func personalize(_ text: String, bundleID: String?) -> DictationPersonalizationResult {
        DictationPersonalization.apply(text, bundleID: bundleID, settings: settings)
    }

    // MARK: Style

    @discardableResult func setGlobalStyle(_ style: DictationWritingStyle) -> Bool {
        guard style != settings.globalStyle else { return true }
        var updated = settings; updated.globalStyle = style
        return commit(updated)
    }

    // MARK: Per-app rules

    @discardableResult func setStyle(_ style: DictationWritingStyle, forBundleID bundleID: String, appName: String? = nil) -> Bool {
        var updated = settings
        return apply(updated.setRule(bundleID: bundleID, appName: appName, style: style), updated)
    }
    @discardableResult func updateRule(_ id: UUID, bundleID: String? = nil, style: DictationWritingStyle? = nil) -> Bool {
        var updated = settings
        return apply(updated.updateRule(id, bundleID: bundleID, style: style), updated)
    }
    /// The app then follows the global style.
    @discardableResult func removeRule(_ id: UUID) -> Bool {
        var updated = settings
        guard updated.removeRule(id) else { error = DictationPreferenceProblem.notFound.message; return false }
        return commit(updated)
    }

    // MARK: Snippets

    /// Validation message for an in-progress edit, without saving. `id` is the snippet being edited.
    func problem(trigger: String, expansion: String, editing id: UUID? = nil) -> String? {
        DictationPreferenceSettings.problem(trigger: trigger, expansion: expansion, excluding: id, in: settings.snippets)?.message
    }
    @discardableResult func addSnippet(trigger: String, expansion: String) -> Bool {
        var updated = settings
        return apply(updated.addSnippet(trigger: trigger, expansion: expansion), updated)
    }
    @discardableResult func updateSnippet(_ id: UUID, trigger: String? = nil, expansion: String? = nil) -> Bool {
        var updated = settings
        return apply(updated.updateSnippet(id, trigger: trigger, expansion: expansion), updated)
    }
    @discardableResult func removeSnippet(_ id: UUID) -> Bool {
        var updated = settings
        guard updated.removeSnippet(id) else { error = DictationPreferenceProblem.notFound.message; return false }
        return commit(updated)
    }

    func clearError() { error = nil }

    /// For an unreadable file: copy it aside, then start from defaults.
    @discardableResult func resetPreservingFile() -> Bool {
        if preview { settings = DictationPreferenceSettings(); isEditable = true; error = nil; notice = nil; return true }
        guard let store else { error = "Dictation settings storage is unavailable."; return false }
        do {
            try store.preserveCurrentFile()
            try store.save(DictationPreferenceSettings())
            settings = DictationPreferenceSettings(); isEditable = true; preserveBeforeSave = false
            error = nil; notice = nil
            return true
        } catch { self.error = "Could not reset dictation settings. Nothing was changed."; return false }
    }

    // MARK: Private

    private func apply<T>(_ result: Result<T, DictationPreferenceProblem>, _ updated: DictationPreferenceSettings) -> Bool {
        switch result {
        case .success: return commit(updated)
        case .failure(let problem): error = problem.message; return false
        }
    }

    private func commit(_ updated: DictationPreferenceSettings) -> Bool {
        guard isEditable else { error = error ?? "Dictation settings are read-only."; return false }
        if preview { settings = updated; error = nil; return true }
        guard let store else { error = "Dictation settings storage is unavailable. Existing files have not been overwritten."; return false }
        do {
            if preserveBeforeSave { try store.preserveCurrentFile(); preserveBeforeSave = false }
            try store.save(updated)
            settings = updated; error = nil
            return true
        } catch {
            self.error = "Could not save your dictation settings. Check storage and try again."
            return false
        }
    }

    private static func describe(_ issues: [DictationPreferenceSettings.LoadIssue]) -> String {
        let count = issues.reduce(0) { total, issue in
            if case .overLimit(_, let dropped) = issue { return total + dropped }
            return total + 1
        }
        let noun = count == 1 ? "entry" : "entries"
        return "\(count) saved dictation \(noun) couldn't be used and \(count == 1 ? "is" : "are") turned off. A copy of the original file is kept in the DictationPreferences folder when you next make a change."
    }
}
