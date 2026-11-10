# IMPLEMENTATION ROADMAP - CloudDrive

## Milestone 5: Security & Encryption

### Progress: In Progress

#### Files Created/Modified for Milestone 5:

1. **`CloudDriveProject/CloudDriveFileProviderExtension/KeyManager.swift`**
   - Key hierarchy: Argon2id → Master Key → HKDF → (auth_key, kek, name_hmac_key) → Root Key → Per-file DEKs
   - Per-file DEKs: Random 256-bit Data Encryption Keys, wrapped by root key
   - Keychain storage with App Group `group.com.example.clouddrive`
   - Recovery flow: 24-word mnemonic → SHA-256 → recovery wrap key → unwrap/re-wrap root key
   - Property wrappers and methods: `getRootKey()`, `rewrapRootKey(withNewKEK:)`, `changeKEK(to:)`, `rotateRootKey()`, `setupRecovery(withMnemonic:)`, `recoverRootKey(withMnemonic:)`

2. **`CloudDriveProject/CloudDriveFileProviderExtension/EncryptionService.swift`**
   - Chunked AES-GCM encryption/decryption with 12-byte nonces
   - Nonce format: 4-byte random prefix || 8-byte chunk index
   - AAD = file header hash + is_final flag to prevent truncation/reordering
   - Per-chunk integrity tags
   - Range decryption support for fetchPartialContents
   - File header format: magic ("CLDR") + version + chunkSize
   - Filename encryption/decryption with HMAC integrity

3. **`CloudDriveProject/CloudDriveFileProviderExtension/IntegrityVerifier.swift`**
   - SHA-256 hash calculation of ciphertext for integrity verification
   - `verifyIntegrity(actualData:expectedHash:)` - verifies hashes match
   - `verifyPerChunkIntegrity(data:encryptionService:)` - per-chunk hash collection
   - `generateIntegrityMetadata(ciphertext:encryptionService:)` - generates IntegrityMetadata
   - `verifyFileIntegrity(storedFileData:storedCiphertextHash:)` - file-level integrity check
   - `IntegrityMetadata` struct with `serialized` format (ciphertext hash + chunk count + chunk hashes)
   - `IntegrityError` enum: hashMismatch, invalidMetadata, verificationFailed

4. **`CloudDriveProject/CloudDriveFileProviderExtension/KeychainManager.swift`**
   - Secure keychain storage with App Group access
   - Items stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `kSecUseDataProtectionKeychain`
   - Keychain items: root_key_wrapped, recovery_wrapped, user_salt, recovery_salt
   - Recovery mechanism via 24-word mnemonic
   - Methods: storeRootKeyWrapped/retrieveRootKeyWrapped, removeRootKeyWrapped
   - Methods: storeRecoveryWrappedRootKey/retrieveRecoveryWrappedRootKey, removeRecoveryWrappedRootKey
   - Methods: storeUserSalt/retrieveUserSalt, removeUserSalt
   - Methods: storeRecoverySalt/retrieveRecoverySalt, removeRecoverySalt
   - KeychainError enum: saveFailed, retrieveFailed, deleteFailed, itemNotFound

5. **`CloudDriveProject/CloudDriveFileProviderExtension/FileProviderExtension.swift`**
   - Modified to integrate encryption in fetchContents (decrypt on download)
   - Modified to integrate encryption in fetchPartialContents (decrypt range)
   - Modified to integrate encryption in createItem (encrypt before upload)
   - Modified to integrate encryption in modifyItem (re-encrypt on content change)

#### Backend Changes:

6. **`backend/src/routes/shares.rs`**
   - Added POST /shares endpoint
   - Added GET /shares/{share_id} endpoint
   - Added GET /shares/{share_id}/download endpoint
   - Added DELETE /shares/{share_id} endpoint

7. **`backend/migrations/0004_create_shares.sql`**
   - Database table: shares
   - Columns: id TEXT PRIMARY KEY, user_id TEXT NOT NULL, item_id TEXT NOT NULL, wrapped_dek TEXT NOT NULL, access_type TEXT, password_hash TEXT, expires_at TEXT, created_at TEXT NOT NULL

#### Key Hierarchy:
```
Password + Server Salt
    ↓
Argon2id (memoryCost=256*1024*1024, iterations=3, parallelism=1)
    ↓
Master Key (256-bit)
    ↓
HKDF-SHA256 (context-specific info strings)
    │
    ├── HKDF("auth") → auth_key (for server authentication)
    ├── HKDF("kek") → kek (Key Encryption Key, wraps root key)
    └── HKDF("name_hmac_key") → name_hmac_key (for encrypted filename HMAC)
    ↓
Root Key (random 256-bit)
    ↓
Per-file DEKs (random 256-bit, wrapped by root key)
    ↓
Stored in item metadata as encrypted_dek
```

#### Recovery Flow:
```
24-word BIP39 Mnemonic
    ↓
SHA-256(mnemonic) → recovery_key_hash (stored server-side)
    ↓
HKDF-Extract/Expand → recovery_wrap_key
    ↓
recovery_wrap_key → unwrap root key (if recovery_wrapped root key exists in keychain)
    ↓
New root key derived and wrapped for recovery
    ↓
Store recovery_wrapped root key in keychain
```

#### Share Link Format:
- Share link contains embedded wrapped DEK
- Access types: public, password, users
- Expiration support via expires_at field
- Revocation support via share deletion

#### Build Status:
- ✅ All security component files created and compiled
- ✅ KeyManager.swift: Key hierarchy with Argon2id → HKDF, recovery flow implemented
- ✅ EncryptionService.swift: Chunked AES-GCM with 12-byte nonces, AAD, range decryption
- ✅ IntegrityVerifier.swift: SHA-256 integrity verification, metadata serialization
- ✅ KeychainManager.swift: Secure keychain storage with App Group access
- ✅ Backend share endpoints: POST /shares, GET /shares/{share_id}, GET /shares/{share_id}/download, DELETE /shares/{share_id}
- ✅ Backend migration: 0004_create_shares.sql shares table created
- ✅ FileProviderExtension.swift: Integrated encryption flows (fetchContents, fetchPartialContents, createItem, modifyItem)
- ⚠️ CloudDriveFileProviderExtension requires development certificate signing (Xcode entitlements - project configuration, not code defect)
- ✅ CloudDriveProject target builds successfully

#### Pending Tasks:
- Full end-to-end encryption/decryption flow testing with backend API
- Share link generation and download verification with embedded decryption key
- Resolve Xcode entitlements signing configuration for CloudDriveFileProviderExtension (development certificate)
- Test per-chunk integrity verification and share link download flow
- Verify key rotation and recovery flows work correctly