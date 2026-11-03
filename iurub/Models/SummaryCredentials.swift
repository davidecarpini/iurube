import Foundation
import Security

/// Stored separately from the app bundle, defaults and conversation files.
enum SummaryCredentials {
    private static var service: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return "it.davidecarpini.iurub.uitests.openrouter" }
        #endif
        return "it.davidecarpini.iurub.openrouter"
    }
    private static func query(account: String = "personal-api-key") -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func read() throws -> String? {
        var lookup = query()
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw SummaryFailure.credentials }
        return value
    }
    static func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-or-"), key.count > 24, !key.contains(where: { $0.isWhitespace }) else {
            throw SummaryFailure.invalidKey
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query() as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query().merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else {
                throw SummaryFailure.credentials
            }
        } else if status != errSecSuccess { throw SummaryFailure.credentials }
    }
    static func remove() throws {
        let status = SecItemDelete(query() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SummaryFailure.credentials }
    }

    /// Older builds could import a file into the same item as a manually entered key.
    /// Start a new, user-only slot. Never read or migrate the old secret.
    static func discardLegacyProvisioning() {
        SecItemDelete(query(account: "api-key") as CFDictionary)
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(".iurub-openrouter-key"))
    }
}
