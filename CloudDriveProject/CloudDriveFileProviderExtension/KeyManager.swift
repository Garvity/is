import Foundation
import CryptoKit
import Security

// MARK: - KeyManager

/// Manages the root encryption key with KEK wrapping and recovery mechanisms.
/// Integrates with KeychainManager for secure storage with App Group access.
public final class KeyManager {
    // Private init for singleton
    private init() {}

    // Shared instance
    public static let shared = KeyManager()

    // Dependencies
    private let keychain = KeychainManager.shared

// MARK: - KDF Structure (Preparatory for Argon2id)

internal protocol KDFProvider {
    func deriveKey(password: String, salt: Data) throws -> SymmetricKey
}

internal struct SHA256KDFProvider: KDFProvider {
    func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        let combined = password.data(using: .utf8)! + salt
        let hash = SHA256.hash(data: combined)
        return SymmetricKey(data: hash)
    }
}

// In production, replace with Argon2idKDFProvider
internal struct DefaultKDFProvider: KDFProvider {
    private let provider: KDFProvider = SHA256KDFProvider()
    
    func deriveKey(password: String, salt: Data) throws -> SymmetricKey {
        return try provider.deriveKey(password: password, salt: salt)
    }
}

    private var _cachedKEK: SymmetricKey?

    // Dependencies
    /// Retrieves the KEK, deriving it if not already cached.
    private func getKEK() throws -> SymmetricKey {
        if let cached = _cachedKEK { return cached }
        
        // Note: For now, we use a placeholder password. 
        // In a real implementation, this should be provided by authentication flow.
        let password = "placeholder_password" 
        let saltData = keychain.retrieveUserSalt() ?? Data(count: 16)
        
        let derived = try DefaultKDFProvider().deriveKey(password: password, salt: saltData)
        _cachedKEK = derived
        return derived
    }

    /// Invalidates the cached KEK (e.g. on logout or password change).
    public func invalidateKEK() {
        _cachedKEK = nil
    }

    /// The root key that encrypts/decrypts user data.
    /// This is stored wrapped (encrypted) in the keychain.
    private func unwrappedRootKey() throws -> SymmetricKey {
        // Try to retrieve wrapped root key first
        if let wrappedData = keychain.retrieveRootKeyWrapped() {
            return try unwrapRootKey(wrapped: wrappedData)
        }

        // If no wrapped key exists, derive a new one and wrap it
        let newKey = SymmetricKey(size: .bits256)
        let wrapped = try wrapRootKey(key: newKey)
        try keychain.storeRootKeyWrapped(wrapped)
        return newKey
    }

    private func unwrapRootKey(wrapped: Data) throws -> SymmetricKey {
        let sealedBox = try AES.GCM.SealedBox(combined: wrapped)
        let unwrapped = try AES.GCM.open(sealedBox, using: try getKEK(), authenticating: "root_key_wrap".data(using: .utf8)!)
        return SymmetricKey(data: unwrapped)
    }

    private func wrapRootKey(key: SymmetricKey) throws -> Data {
        // Wrap the key using KEK with AES-GCM
        let keyData = key.withUnsafeBytes { Data($0) }
        let sealedBox = try AES.GCM.seal(keyData, using: try getKEK(), nonce: AES.GCM.Nonce(), authenticating: "root_key_wrap".data(using: .utf8)!)
        return sealedBox.combined!
    }

    // MARK: - Recovery Operations

    /// The recovery-wrapped root key, used for mnemonic-based recovery.
    private func getRecoveryWrappedRootKey() throws -> SymmetricKey? {
        if let wrappedData = keychain.retrieveRecoveryWrappedRootKey() {
            return try unwrapRecoveryRootKey(wrapped: wrappedData, wrapKey: try getKEK())
        }
        return nil
    }

    private func setRecoveryWrappedRootKey(_ key: SymmetricKey) throws {
        // Wrap the root key for recovery using the KEK
        let wrapped = try wrapRootKeyForRecovery(key: key)
        try keychain.storeRecoveryWrappedRootKey(wrapped)
    }

    private func wrapRootKeyForRecovery(key: SymmetricKey) throws -> Data {
        // Wrap the root key for recovery using the KEK
        let keyData = key.withUnsafeBytes { Data($0) }
        let sealedBox = try AES.GCM.seal(keyData, using: try getKEK(), nonce: AES.GCM.Nonce(), authenticating: "recovery_root_key_wrap".data(using: .utf8)!)
        return sealedBox.combined!
    }

    private func unwrapRecoveryRootKey(wrapped: Data, wrapKey: SymmetricKey) throws -> SymmetricKey {
        let sealedBox = try AES.GCM.SealedBox(combined: wrapped)
        let decryptedData = try AES.GCM.open(sealedBox, using: wrapKey, authenticating: "recovery_root_key_wrap".data(using: .utf8)!)
        return SymmetricKey(data: decryptedData)
    }

    // MARK: - Public API

    /// Returns the root key, creating/wrapping it if needed.
    /// - Throws: KeychainError if operations fail
    public func getRootKey() throws -> SymmetricKey {
        return try unwrappedRootKey()
    }

    /// Re-wraps the root key with a new KEK (e.g., after password change).
    /// Call this after re-deriving the KEK (e.g., on password change).
    /// - Parameter newKEK: The new Key Encryption Key
    /// - Throws: KeychainError if operations fail
    public func rewrapRootKey(withNewKEK newKEK: SymmetricKey) throws {
        // Get the current unwrapped root key
        let currentRootKey = try unwrappedRootKey()

        // Re-wrap with the new KEK
        let keyData = currentRootKey.withUnsafeBytes { Data($0) }

        let sealedBox = try AES.GCM.seal(keyData, using: newKEK, nonce: AES.GCM.Nonce(), authenticating: "root_key_wrap".data(using: .utf8)!)
        try keychain.storeRootKeyWrapped(sealedBox.combined!)
    }

    /// Sets up recovery with a BIP39 mnemonic.
    /// - Parameter mnemonic: The 24-word BIP39 mnemonic phrase
    /// - Returns: The recovery key hash and recovery wrap key
    public func setupRecovery(withMnemonic mnemonic: String) throws -> (Data, SymmetricKey) {
        // 1. Compute recovery key hash = SHA-256(mnemonic)
        let recoveryKeyHash = Data(SHA256.hash(data: mnemonic.data(using: .utf8) ?? Data()))
        // SHA256.hash returns Data in CryptoKit, so this is already Data type

        // 2. Derive recovery wrap key via HKDF from the mnemonic
        let ikm = mnemonic.data(using: .utf8)!
        let salt = Data(count: 0) // Empty salt for HKDF-Extract
        let info = "clouddrive_recovery_wrap_key".data(using: .utf8)!
        let recoveryWrapKey = try deriveRecoveryWrapKeyHKDF(ikm: ikm, salt: salt, info: info)

        // 3. Store the recovery wrapped root key if we have a root key
        do {
            let rootKey = try unwrappedRootKey()
            let wrappedForRecovery = try wrapRootKeyForRecovery(key: rootKey)
            try keychain.storeRecoveryWrappedRootKey(wrappedForRecovery)
        } catch {
            print("Failed to store recovery wrapped key during setup: \(error)")
        }

        // 4. Store recovery key hash and salt server-side (outside scope of keychain)
        // The recovery_salt is stored server-side

        return (recoveryKeyHash, recoveryWrapKey)
    }

    /// Attempts to recover the root key using a BIP39 mnemonic.
    /// - Parameter mnemonic: The 24-word BIP39 mnemonic phrase
    /// - Returns: The recovered root key, or nil if recovery fails
    public func recoverRootKey(withMnemonic mnemonic: String) -> SymmetricKey? {
        do {
            // 1. Compute recovery key hash
            let recoveryKeyHash = SHA256.hash(data: mnemonic.data(using: .utf8) ?? Data())

            // 2. Derive recovery wrap key via HKDF
            let ikm = mnemonic.data(using: .utf8)!
            let salt = Data(count: 0)
            let info = "clouddrive_recovery_wrap_key".data(using: .utf8)!
            let recoveryWrapKey = try deriveRecoveryWrapKeyHKDF(ikm: ikm, salt: salt, info: info)

            // 3. Try to unwrap the root key using the recovery wrap key
            if let wrappedData = keychain.retrieveRecoveryWrappedRootKey() {
                let recoveredKey = try unwrapRecoveryRootKey(wrapped: wrappedData, wrapKey: recoveryWrapKey)
                return recoveredKey
            }

            // 4. If no recovery wrapped key exists, we can't recover
            return nil
        } catch {
            print("Recovery failed: \(error)")
            return nil
        }
    }

    /// Changes the KEK and re-wraps the root key.
    /// This is called when the user changes their password.
    /// - Parameter newKEK: The new Key Encryption Key
    /// - Throws: KeychainError if operations fail
    public func changeKEK(to newKEK: SymmetricKey) throws {
        // Get the current unwrapped root key
        let currentRootKey = try unwrappedRootKey()

        // Re-wrap with the new KEK
        let keyData = currentRootKey.withUnsafeBytes { Data($0) }

        let sealedBox = try AES.GCM.seal(keyData, using: newKEK, nonce: AES.GCM.Nonce(), authenticating: "root_key_wrap".data(using: .utf8)!)
        try keychain.storeRootKeyWrapped(sealedBox.combined!)
    }

    /// Rotates the root key, generating a new one and re-wrapping it.
    /// - Returns: The new root key
    /// - Throws: KeychainError if operations fail
    public func rotateRootKey() throws -> SymmetricKey {
        // Generate a new root key
        let newRootKey = SymmetricKey(size: .bits256)

        // Wrap it with the current KEK
        let wrapped = try wrapRootKey(key: newRootKey)

        // Store the wrapped key
        try keychain.storeRootKeyWrapped(wrapped)

        return newRootKey
    }

    // MARK: - Keychain Error Handling

    private enum InternalError: Error {
        case derivationFailed
    }
}

// MARK: - HKDF Helper

private func deriveRecoveryWrapKeyHKDF(ikm: Data, salt: Data, info: Data) throws -> SymmetricKey {
    return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt, info: info, outputByteCount: 32)
}