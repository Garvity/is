# CloudDrive Implementation Roadmap

## Milestone 5: Security & Encryption
### Status: In Progress

#### Completed:
- Key hierarchy structure (KeyManager.swift)
- Basic Keychain storage (KeychainManager.swift)
- Initial Encryption/Decryption service (EncryptionService.swift)
- Backend share endpoints (shares.rs, 0004_create_shares.sql)

#### Pending:
- Redesign of `EncryptionService` (Chunked AES-GCM + AAD).
- Proper Argon2id KDF implementation in `KeyManager`.
- Xcode entitlement configuration for File Provider extension.
- Full end-to-end encryption/decryption flow testing.
- Share link generation and verification.
