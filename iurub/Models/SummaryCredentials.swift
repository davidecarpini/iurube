import Foundation
import Security

/// Stored separately from the app bundle, defaults and conversation files.
enum SummaryCredentials {
    private static let service = "it.davidecarpini.iurub.openrouter"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "api-key"]
    }
    static func read() throws -> String? {
        var lookup = query
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
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else {
                throw SummaryFailure.credentials
            }
        } else if status != errSecSuccess { throw SummaryFailure.credentials }
    }
    /// A development install can provision the user's key once through the app's
    /// private data container. Never distribute this file with an app or archive.
    static func importProvisionedKey() {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let file = directory.appendingPathComponent(".iurub-openrouter-key")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let key = try String(contentsOf: file, encoding: .utf8)
            try save(key)
            try FileManager.default.removeItem(at: file)
        } catch { /* Keep the provision file for a retry when the device is unlocked. */ }
    }
}
