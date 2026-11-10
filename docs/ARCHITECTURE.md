# CloudDrive Architecture

## Key Hierarchy
```
User Password + Server Salt
    ↓
Argon2id (Planned for full implementation)
    ↓
Master Key (256-bit)
    ↓
HKDF-SHA256 (context-specific info strings)
    │
    ├── HKDF("auth") → auth_key (for server authentication)
    ├── HKDF("kek") → kek (Key Encryption Key, wraps root key)
    └── HKDF("name_hmac_key") → name_hmac_key (for filename HMAC)
    ↓
Root Key (random 256-bit, wrapped by kek, stored in keychain)
    ↓
Per-file DEKs (random 256-bit, wrapped by root key)
    ↓
Stored in item metadata as encrypted_dek
```

## Encryption Design
- **File Content:** Chunked AES-GCM (64KB chunks).
- **Integrity:** Per-chunk AES-GCM authentication tags (with AAD including header hash and chunk index).
- **Filenames:** AES-GCM encrypted + HMAC authenticated.
- **Key Storage:** Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
