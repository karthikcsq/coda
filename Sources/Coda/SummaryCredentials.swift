import Foundation
import Security
import Observation
import CodaCore

/// The UI never reads back a stored secret. Only an explicit summary request does.
@MainActor @Observable final class SummaryCredentials {
    private(set) var hasKey = false
    private(set) var message = ""
    private(set) var messageIsError = false
    private func fail(_ text: String) { message = text; messageIsError = true }
    private func succeed(_ text: String) { message = text; messageIsError = false }
    private let preview: Bool
    var model: String
    private var savedModel: String
    private let service = "app.coda.notebook.summaries"
    private let account = "openai-api-key"
    init(preview: Bool) {
        self.preview = preview
        let storedModel = preview ? "gpt-4.1-mini" : UserDefaults.standard.string(forKey: "summaryModel") ?? "gpt-4.1-mini"
        model = storedModel; savedModel = storedModel
    }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func refresh() {
        guard !preview else { return }
        var request = query; request[kSecReturnAttributes as String] = true
        request[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        hasKey = SecItemCopyMatching(request as CFDictionary, nil) == errSecSuccess
    }
    @discardableResult func save(_ input: String) -> Bool {
        guard !preview else { return false }
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = Configuration(contents: "", environment: ["OPENAI_API_KEY": key, "OPENAI_MODEL": modelName])
        do { try config.validate() } catch { fail("Enter a valid API key. It is never shown after saving."); return false }
        guard !modelName.isEmpty, modelName.count <= 200, !modelName.contains(where: \.isNewline), key.count <= 1024 else {
            fail("Enter a model name and a key without line breaks."); return false
        }
        let value = Data(key.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = value
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(entry as CFDictionary, nil)
        }
        guard status == errSecSuccess else { fail("Coda could not save to Keychain. Unlock your Mac and try again."); return false }
        model = modelName; savedModel = modelName; UserDefaults.standard.set(modelName, forKey: "summaryModel")
        hasKey = true; succeed("Saved in macOS Keychain. No transcript has been sent."); return true
    }
    func saveModel() {
        guard !preview else { return }
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 200, !name.contains(where: \.isNewline) else { fail("Enter a model name without line breaks."); return }
        model = name; savedModel = name; UserDefaults.standard.set(name, forKey: "summaryModel")
        succeed("Summary model saved. No transcript has been sent.")
    }
    func remove() {
        guard !preview else { return }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { fail("The saved key could not be removed. Try again after unlocking your Mac."); return }
        hasKey = false; succeed("Saved key removed. An existing .env configuration still works.")
    }
    func configuration() throws -> Configuration? {
        guard !preview else { throw CodaError.missingKey }
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw CodaError.message("The summary key is unavailable. Unlock your Mac or update it in Settings.")
        }
        return Configuration(contents: "", environment: ["OPENAI_API_KEY": key, "OPENAI_MODEL": savedModel])
    }
}
