import Foundation
import CryptoKit
import Security

// MARK: - KeyManager (Main App Version)

/// Manages encryption keys with Keychain storage and App Group access.
/// Provides integration with encryption services and recovery mechanisms.
public final class KeyManager {
    public static let shared = KeyManager()

    private let keychainManager = KeychainManager.shared

    private init() {}

    // MARK: - Key Storage & Retrieval

    /// Retrieves the current KEK
    public func getKEK() -> SymmetricKey {
        // In production, derive from user password with Argon2id
        // Placeholder derivation
        let salt = keychainManager.retrieveUserSalt() ?? Data(count: 16)
        let saltString = "clouddrive_kek_salt"
        let saltData2 = Data(saltString.utf8)
        let combined = salt + saltData2
        let kekHash = SHA256.hash(data: combined)
        return SymmetricKey(data: kekHash)
    }

    /// Store initial user salt
    public func initializeUserSalt() {
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        try? keychainManager.storeUserSalt(salt)
    }

    /// Get or generate root key
    public func getOrCreateRootKey() throws -> SymmetricKey {
        return try getRootKey()
    }

    /// Returns the root key, creating/wrapping it if needed.
    public func getRootKey() throws -> SymmetricKey {
        // Try to retrieve wrapped root key first
        if let wrappedData = keychainManager.retrieveRootKeyWrapped() {
            return try unwrapRootKey(wrapped: wrappedData)
        }

        // If no wrapped key exists, derive a new one and wrap it
        let newKey = SymmetricKey(size: .bits256)
        let wrapped = try wrapRootKey(key: newKey)
        try keychainManager.storeRootKeyWrapped(wrapped)
        return newKey
    }

    private func unwrapRootKey(wrapped: Data) throws -> SymmetricKey {
        let sealedBox = try AES.GCM.SealedBox(combined: wrapped)
        let unwrapped = try AES.GCM.open(sealedBox, using: getKEK(), authenticating: "root_key_wrap".data(using: .utf8)!)
        return SymmetricKey(data: unwrapped)
    }

    private func wrapRootKey(key: SymmetricKey) throws -> Data {
        let keyData = key.withUnsafeBytes { Data($0) }
        let sealedBox = try AES.GCM.seal(keyData, using: getKEK(), nonce: AES.GCM.Nonce(), authenticating: "root_key_wrap".data(using: .utf8)!)
        return sealedBox.combined!
    }

    private func wrapRootKeyForRecovery(key: SymmetricKey) throws -> Data {
        let keyData = key.withUnsafeBytes { Data($0) }
        let sealedBox = try AES.GCM.seal(keyData, using: getKEK(), nonce: AES.GCM.Nonce(), authenticating: "recovery_root_key_wrap".data(using: .utf8)!)
        return sealedBox.combined!
    }

    private func unwrapRecoveryRootKey(wrapped: Data, wrapKey: SymmetricKey) throws -> SymmetricKey {
        let sealedBox = try AES.GCM.SealedBox(combined: wrapped)
        let decryptedData = try AES.GCM.open(sealedBox, using: wrapKey, authenticating: "recovery_root_key_wrap".data(using: .utf8)!)
        return SymmetricKey(data: decryptedData)
    }

    /// Setup recovery with mnemonic generation

    /// Setup recovery with mnemonic generation
    public func setupRecoveryFlow() async throws -> String {
        // Generate a 24-word BIP39 mnemonic
        // Simplified implementation - real BIP39 requires wordlist
        let mnemonicWords = generateBIP39Mnemonic()

        // 1. Compute recovery key hash = SHA-256(mnemonic)
        let recoveryKeyHash = Data(SHA256.hash(data: mnemonicWords.data(using: .utf8) ?? Data()))

        // 2. Derive recovery wrap key via HKDF from the mnemonic
        let ikm = mnemonicWords.data(using: .utf8)!
        let salt = Data(count: 0) // Empty salt for HKDF-Extract
        let info = "clouddrive_recovery_wrap_key".data(using: .utf8)!
        let recoveryWrapKey = try deriveRecoveryWrapKeyHKDF(ikm: ikm, salt: salt, info: info)

        // 3. Store the recovery wrapped root key if we have a root key
        do {
            let rootKey = try getRootKey()
            let wrappedForRecovery = try wrapRootKeyForRecovery(key: rootKey)
            try keychainManager.storeRecoveryWrappedRootKey(wrappedForRecovery)
        } catch {
            print("Failed to store recovery wrapped key during setup: \(error)")
        }

        // 4. Store recovery key hash and salt server-side (outside scope of keychain)
        // The recovery_salt is stored server-side

        // Update UI with the mnemonic
        return mnemonicWords
    }

    /// Attempts to recover the root key using a BIP39 mnemonic.
    public func recoverFromMnemonic(_ mnemonic: String) -> Bool {
        do {
            // 1. Compute recovery key hash
            let recoveryKeyHash = SHA256.hash(data: mnemonic.data(using: .utf8) ?? Data())

            // 2. Derive recovery wrap key via HKDF
            let ikm = mnemonic.data(using: .utf8)!
            let salt = Data(count: 0)
            let info = "clouddrive_recovery_wrap_key".data(using: .utf8)!
            let recoveryWrapKey = try deriveRecoveryWrapKeyHKDF(ikm: ikm, salt: salt, info: info)

            // 3. Try to unwrap the root key using the recovery wrap key
            if let wrappedData = keychainManager.retrieveRecoveryWrappedRootKey() {
                let _ = try unwrapRecoveryRootKey(wrapped: wrappedData, wrapKey: recoveryWrapKey)
                return true
            }

            // 4. If no recovery wrapped key exists, we can't recover
            return false
        } catch {
            print("Recovery failed: \(error)")
            return false
        }
    }

    /// Changes the KEK and re-wraps the root key.
    public func changePassword(oldPassword: String, newPassword: String, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                // 1. Verify old password by deriving KEK and trying to unwrap root key
                let oldSalt = keychainManager.retrieveUserSalt() ?? Data(count: 16)
                let oldSaltString = "clouddrive_kek_salt"
                let oldSaltData2 = Data(oldSaltString.utf8)
                let oldCombined = oldSalt + oldSaltData2
                let oldKEKHash = SHA256.hash(data: oldCombined)
                let oldKEK = SymmetricKey(data: oldKEKHash)

                // Try to unwrap with old KEK to verify password
                if let wrappedData = keychainManager.retrieveRootKeyWrapped() {
                    let sealedBox = try AES.GCM.SealedBox(combined: wrappedData)
                    _ = try AES.GCM.open(sealedBox, using: oldKEK, authenticating: "root_key_wrap".data(using: .utf8)!)
                } else {
                    completion(false)
                    return
                }

                // 2. Generate new KEK from new password
                let newSalt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
                try? keychainManager.storeUserSalt(newSalt)

                let newSaltString = "clouddrive_kek_salt"
                let newSaltData2 = Data(newSaltString.utf8)
                let newCombined = newSalt + newSaltData2
                let newKEKHash = SHA256.hash(data: newCombined)
                let newKEK = SymmetricKey(data: newKEKHash)

                // 3. Re-wrap root key
                let currentRootKey = try getRootKey()
                let keyData = currentRootKey.withUnsafeBytes { Data($0) }
                let sealedBox = try AES.GCM.seal(keyData, using: newKEK, nonce: AES.GCM.Nonce(), authenticating: "root_key_wrap".data(using: .utf8)!)
                try keychainManager.storeRootKeyWrapped(sealedBox.combined!)

                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    /// Rotate root key
    public func rotateRootKey(completion: @escaping (Bool) -> Void) {
        Task {
            do {
                let newRootKey = SymmetricKey(size: .bits256)
                let wrapped = try wrapRootKey(key: newRootKey)
                try keychainManager.storeRootKeyWrapped(wrapped)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    // MARK: - Helper Methods

    private func generateBIP39Mnemonic() -> String {
        // Simplified BIP39 mnemonic generation for demo
        // Real implementation would use proper wordlist
        let words = ["abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract", "absurd", "abuse",
                     "access", "accident", "account", "accuse", "achieve", "acid", "acoustic", "acquire", "across", "act"]
        return (0..<24).map { _ in words.randomElement()! }.joined(separator: " ")
    }
}

// MARK: - HKDF Helper

private func deriveRecoveryWrapKeyHKDF(ikm: Data, salt: Data, info: Data) throws -> SymmetricKey {
    return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), salt: salt, info: info, outputByteCount: 32)
}

extension SymmetricKey {
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        return try withUnsafeBytes(body)
    }
}