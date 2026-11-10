import Foundation
import Security

// MARK: - Keychain Item Keys

private enum KeychainItemKey: String {
    case rootKeyWrapped = "com.example.clouddrive.root_key_wrapped"
    case recoveryWrapped = "com.example.clouddrive.recovery_wrapped"
    case userSalt = "com.example.clouddrive.user_salt"
    case recoverySalt = "com.example.clouddrive.recovery_salt"
}

// MARK: - Keychain Manager

public final class KeychainManager {
    // Shared access group for app and extension
    private let accessGroup: String

    // Service name for keychain items
    private let serviceName = "com.example.clouddrive.keychain"

    // Team ID
    public static let teamID = "RYDF99JX85"

    // MARK: - Initialization

    public init(accessGroup: String? = nil) {
        self.accessGroup = accessGroup ?? KeychainManager.teamID + ".com.garv.CloudDriveProject.shared"
        KeychainManager.shared = self
    }

    // MARK: - Shared Instance

    public static var shared = KeychainManager()

    // MARK: - Root Key Operations

    /// Stores the KEK-wrapped root key in the keychain
    /// - Parameter wrappedKey: The KEK-wrapped SymmetricKey data
    public func storeRootKeyWrapped(_ wrappedKey: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.rootKeyWrapped.rawValue,
            kSecValueData as String: wrappedKey,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    /// Retrieves the KEK-wrapped root key from the keychain
    /// - Returns: The wrapped key data, or nil if not found
    public func retrieveRootKeyWrapped() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.rootKeyWrapped.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data
        else {
            return nil
        }

        return data
    }

    /// Removes the KEK-wrapped root key from the keychain
    /// - Returns: Whether the removal was successful
    public func removeRootKeyWrapped() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.rootKeyWrapped.rawValue,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Recovery Wrapped Root Key Operations

    /// Stores the recovery-wrapped root key in the keychain
    /// - Parameter wrappedKey: The recovery-wrapped root key data
    public func storeRecoveryWrappedRootKey(_ wrappedKey: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.recoveryWrapped.rawValue,
            kSecValueData as String: wrappedKey,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    /// Retrieves the recovery-wrapped root key from the keychain
    /// - Returns: The wrapped key data, or nil if not found
    public func retrieveRecoveryWrappedRootKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.recoveryWrapped.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data
        else {
            return nil
        }

        return data
    }

    /// Removes the recovery-wrapped root key from the keychain
    /// - Returns: Whether the removal was successful
    public func removeRecoveryWrappedRootKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.recoveryWrapped.rawValue,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - User Salt Operations

    /// Stores the Argon2id user salt in the keychain
    /// - Parameter salt: The user salt data
    public func storeUserSalt(_ salt: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.userSalt.rawValue,
            kSecValueData as String: salt,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    /// Retrieves the user salt from the keychain
    /// - Returns: The salt data, or nil if not found
    public func retrieveUserSalt() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.userSalt.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data
        else {
            return nil
        }

        return data
    }

    /// Removes the user salt from the keychain
    /// - Returns: Whether the removal was successful
    public func removeUserSalt() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.userSalt.rawValue,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Recovery Salt Operations

    /// Stores the recovery salt in the keychain
    /// Note: recovery_salt is primarily stored server-side, but we also store a copy in keychain
    /// - Parameter salt: The recovery salt data
    public func storeRecoverySalt(_ salt: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.recoverySalt.rawValue,
            kSecValueData as String: salt,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    /// Retrieves the recovery salt from the keychain
    /// - Returns: The recovery salt data, or nil if not found
    public func retrieveRecoverySalt() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.recoverySalt.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data
        else {
            return nil
        }

        return data
    }

    /// Removes the recovery salt from the keychain
    /// - Returns: Whether the removal was successful
    public func removeRecoverySalt() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: KeychainItemKey.recoverySalt.rawValue,
            kSecAttrAccessGroup as String: accessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Keychain Error Handling

    public enum KeychainError: Error {
        case saveFailed(status: OSStatus)
        case retrieveFailed(status: OSStatus)
        case deleteFailed(status: OSStatus)
        case itemNotFound

        public var localizedDescription: String {
            switch self {
            case .saveFailed(let status):
                return "Failed to save keychain item: \(status)"
            case .retrieveFailed(let status):
                return "Failed to retrieve keychain item: \(status)"
            case .deleteFailed(let status):
                return "Failed to delete keychain item: \(status)"
            case .itemNotFound:
                return "Keychain item not found"
            }
        }
    }
}
