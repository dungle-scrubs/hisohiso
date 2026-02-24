import Foundation
import Security

/// Manages secure storage of API keys and sensitive data in macOS Keychain.
///
/// ## Thread safety
/// All operations delegate to the Security framework (`SecItem*`), which is
/// internally thread-safe. This type holds no mutable state of its own.
final class KeychainManager: @unchecked Sendable {
    static let shared = KeychainManager()

    private let service = "com.hisohiso.app"

    private init() {}

    // MARK: - API Keys

    enum APIKeyType: String {
        case openAI = "openai-api-key"
        case groq = "groq-api-key"
    }

    /// Get an API key from Keychain
    /// - Parameter type: The type of API key to retrieve
    /// - Returns: The API key if found, nil otherwise
    func getAPIKey(_ type: APIKeyType) -> String? {
        getData(forKey: type.rawValue).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Store an API key in Keychain
    /// - Parameters:
    ///   - key: The API key to store
    ///   - type: The type of API key
    /// - Returns: Result indicating success or failure
    @discardableResult
    func setAPIKey(_ key: String, type: APIKeyType) -> Result<Void, KeychainError> {
        guard let data = key.data(using: .utf8) else {
            return .failure(.encodingError)
        }
        return setData(data, forKey: type.rawValue)
    }

    /// Delete an API key from Keychain
    /// - Parameter type: The type of API key to delete
    /// - Returns: Result indicating success or failure
    @discardableResult
    func deleteAPIKey(_ type: APIKeyType) -> Result<Void, KeychainError> {
        deleteData(forKey: type.rawValue)
    }

    /// Check if an API key exists
    /// - Parameter type: The type of API key
    /// - Returns: True if the key exists
    func hasAPIKey(_ type: APIKeyType) -> Bool {
        getAPIKey(type) != nil
    }

    // MARK: - Generic Data Storage

    /// Get data from Keychain
    /// - Parameter key: The key to retrieve
    /// - Returns: The data if found
    func getData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }

        return result as? Data
    }

    /// Store data in Keychain
    /// - Parameters:
    ///   - data: The data to store
    ///   - key: The key to store it under
    /// - Returns: Result indicating success or failure
    @discardableResult
    func setData(_ data: Data, forKey key: String) -> Result<Void, KeychainError> {
        // First try to delete existing item
        _ = deleteData(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            logDebug("Keychain: stored data for key '\(key)'")
            return .success(())
        case errSecDuplicateItem:
            // Try to update instead
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
            if updateStatus == errSecSuccess {
                logDebug("Keychain: updated data for key '\(key)'")
                return .success(())
            } else {
                logError("Keychain: failed to update key '\(key)': \(updateStatus)")
                return .failure(.unableToStore(status: updateStatus))
            }
        default:
            logError("Keychain: failed to store key '\(key)': \(status)")
            return .failure(.unableToStore(status: status))
        }
    }

    /// Delete data from Keychain
    /// - Parameter key: The key to delete
    /// - Returns: Result indicating success or failure
    @discardableResult
    func deleteData(forKey key: String) -> Result<Void, KeychainError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            logDebug("Keychain: deleted key '\(key)'")
            return .success(())
        default:
            logError("Keychain: failed to delete key '\(key)': \(status)")
            return .failure(.unableToDelete(status: status))
        }
    }
}

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
    case encodingError
    case unableToStore(status: OSStatus)
    case unableToDelete(status: OSStatus)
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .encodingError:
            return "Failed to encode data"
        case .unableToStore(let status):
            return "Failed to store in Keychain (status: \(status))"
        case .unableToDelete(let status):
            return "Failed to delete from Keychain (status: \(status))"
        case .itemNotFound:
            return "Item not found in Keychain"
        }
    }
}
