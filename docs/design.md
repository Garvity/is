# CloudDrive Design Document (Revised + Cited)

**App Name:** CloudDrive (placeholder — to be decided)
**Bundle IDs:** `com.example.clouddrive`, `com.example.clouddrive.fileprovider`
**App Group:** `group.com.example.clouddrive`
**Framework:** `CloudDriveCore`

**Sources recorded in `/Users/garv/Projects/helumi/docs/references.md`**

---

## 1. API DESIGN & PROTOCOLS

### 1.1 Base URL & Versioning
- Base URL: `https://api.example.com/v1` (Cloudflare Worker)
- Versioning: URL path `/v1/`
- Content-Type: `application/json`

### 1.2 Authentication & Zero-Knowledge Derivation

**Argon2id single-run → HKDF split (RFC 9106 test vectors):**
- Client performs one Argon2id invocation with parameters `memory=256 MiB, iterations=3, parallelism=1`. Salt = `user_salt` from D1.
- HKDF-SHA256 (RFC 5869) derives `auth_key` and `kek` from Argon2id output.
- `auth_value = HKDF(auth_key, "auth")` — static value derived from auth_key, no nonce/HMAC.
- Server stores a peppered fast hash of `auth_value` (not scrypt/bcrypt). The pepper is a Worker secret.
- Fake-salt response for unknown emails to prevent enumeration.

**Recovery flow:**
- User has a recovery key (24-word mnemonic) generated at setup. Stored offline by user.
- `recovery_salt` stored in D1, `recovery_key_hash` = SHA-256(high-entropy mnemonic) — fast hash, no Argon2.
- Recovery flow:
  1. Client derives `recovery_auth_key` and `recovery_wrap_key` from mnemonic via HKDF.
  2. Server verifies `recovery_key_hash` (fast hash, peppered).
  3. Server returns `recovery_wrapped_root_key`; client unwraps, re-wraps with new password-derived KEK via `POST /auth/set-new-password` and updates `root_key_wraps`, revokes old auth credential.

**Sessions:**
- `sessions(id, user_id, refresh_token_hash, created_at, last_used_at, revoked BOOLEAN)`.
- Refresh tokens rotated on use.
- JWT algorithm: RS256 only (HS256 removed). Public key for verification.

**Rate limiting:** Cloudflare Workers Rate Limiting binding (https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/) — `env.RATE_LIMITER.limit({key: userId || ip})`. Fallback strict limit via Durable Object per user.

### 1.3 Items

All queries include `user_id` in WHERE clause.

Atomic CAS: `UPDATE items SET version=version+1 WHERE id=? AND user_id=? AND version=?`

`GET /items/{id}/download` returns pre-signed R2 GET URL.

`POST /items` includes `encrypted_key_blob`, status set to `pending`.

`POST /uploads/{uploadId}/complete` requires `expectedVersion`.

### 1.4 Upload Sessions & R2 Multipart

Part size limits (Cloudflare R2):
- 5 MiB – 5 GiB per part, all non-trailing parts must be the same size. Source: developers.cloudflare.com/r2/objects/upload-objects/ (Multipart upload details).
Error code 10048 enforces same-size parts.

Resume: `GET /uploads/{uploadId}` lists uploaded parts via R2 `ListParts`. Client re-uploads missing parts.

---

## 2. D1 DATABASE SCHEMA

```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  user_salt TEXT NOT NULL,
  auth_value_hash TEXT NOT NULL,
  recovery_salt TEXT NOT NULL,
  recovery_key_hash TEXT NOT NULL
);

CREATE TABLE items (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  parent_id TEXT NOT NULL,
  name_ciphertext TEXT NOT NULL,
  name_hmac TEXT NOT NULL,
  name_nfc TEXT NOT NULL,
  type TEXT NOT NULL,
  size INTEGER NOT NULL,
  version INTEGER NOT NULL,
  change_seq INTEGER NOT NULL,
  modified_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('pending','active')),
  deleted INTEGER NOT NULL DEFAULT 0,
  ciphertext_hash TEXT,
  encrypted_key_blob TEXT NOT NULL,
  r2_key TEXT
);
CREATE UNIQUE INDEX idx_items_parent_hmac ON items(user_id, parent_id, name_hmac) WHERE deleted=0;
CREATE INDEX idx_items_change_seq ON items(user_id, change_seq);

CREATE TABLE root_key_wraps (
  user_id TEXT PRIMARY KEY,
  kek_wrapped_root_key BLOB NOT NULL,
  recovery_wrapped_root_key BLOB NOT NULL
);

CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  refresh_token_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_used_at TEXT NOT NULL,
  revoked INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE user_sync_state (
  user_id TEXT PRIMARY KEY,
  last_sync_seq INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE upload_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  item_id TEXT NOT NULL,
  r2_upload_id TEXT NOT NULL,
  r2_key TEXT NOT NULL,
  base_version INTEGER NOT NULL,
  part_count INTEGER NOT NULL,
  expires_at TEXT NOT NULL
);
```

Change_seq allocation via D1 `batch()` in same transaction as item write.

Plaintext size derived client-side before encryption.

Name normalization: NFC via `String.precomposedStringWithCanonicalMapping` before HMAC.

---

## 3. NSFileProviderReplicatedExtension SYNC

**Actual protocol signatures (Apple Developer Documentation):**

- `createItem(basedOn:fields:contents:options:request:completionHandler:)` — https://developer.apple.com/documentation/fileprovider/nsfileproviderreplicatedextension/createitem(basedon:fields:contents:options:request:completionhandler:)
- `deleteItem(identifier:baseVersion:options:request:completionHandler:)` — https://developer.apple.com/documentation/fileprovider/nsfileproviderreplicatedextension/deleteitem(identifier:baseversion:options:request:completionhandler:)
- `modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?, options: NSFileProviderModifyItemOptions, request: NSFileProviderRequest, completionHandler: (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void)`
- `fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: (URL?, NSFileProviderItem?, Error?) -> Void)`
- `fetchPartialContents(for:version:request:minimalRange:aligningTo:options:completionHandler:)` — https://developer.apple.com/documentation/fileprovider/nsfileproviderpartialcontentfetching/fetchpartialcontents(for:version:request:minimalrange:aligningto:options:completionhandler:)
- `item(forIdentifier:request:completionHandler:)` — fetch metadata
- `enumerator(forContainerItemIdentifier:request:completionHandler:)`
- Working-set enumerator uses `enumerator(forContainerItemIdentifier:)` which returns `NSFileProviderEnumerator` with `enumerateChanges`, `currentSyncAnchor`.

Domain registration via `NSFileProviderManager.add(_:completionHandler:)` — https://developer.apple.com/documentation/fileprovider/nsfileprovidermanager/add(_:completionhandler:)

**Menu bar sync trigger:** App calls `NSFileProviderManager(for: domain).signalEnumerator(for: .rootContainer)` per Apple sample. Signal enumerator per Apple sample.

**Version mapping:** `NSFileProviderItemVersion` ↔ `items.version`.

---

## 4. ENCRYPTION

- `root_key` random 256-bit, wrapped by KEK and recovery key.
- `name_hmac_key` derived from root key.
- Password change rewraps root key.
- Chunked AES-GCM with 4-byte random prefix || 8-byte chunk index nonce (12 bytes). AAD includes header hash + is_final.
- Range reads: YES, replicated extension supports `fetchPartialContents`. Encryption rationale remains valid.

---

## 5. MACOS ENTITLEMENTS

App entitlements:
- `com.apple.security.app-sandbox`
- `com.apple.security.network.client`
- `com.apple.security.application-groups`
- `keychain-access-groups` = `[TEAMID.com.example.clouddrive]`

Extension entitlements:
- `com.apple.developer.fileprovider`
- `com.apple.security.app-sandbox`
- `com.apple.security.network.client`
- `com.apple.security.application-groups`
- `keychain-access-groups` = `[TEAMID.com.example.clouddrive]`

Root key access: Keychain cache with `kSecAttrAccessGroup = TEAMID.com.example.clouddrive`, `kSecUseDataProtectionKeychain = true`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. TN3137 notes data protection keychain uses access groups entitlement.

---

## 6. CONFLICT RULES

Extension throws `NSFileProviderError(.versionOutOfDate)` on version mismatch. Apple docs state `NSFileProviderError.Code.localVersionConflictingWithServer` is for conflicts; exact behavior of who creates the copy is UNVERIFIED per Apple docs. Spike test required.

Copy naming: `"{original} (conflicted copy {deviceName} {date})"`.

Conflict table:
```sql
CREATE TABLE conflicts (
  id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL,
  server_version INTEGER NOT NULL,
  local_version INTEGER NOT NULL,
  resolution TEXT NOT NULL
);
```

Delete-vs-edit and rename-vs-edit tracked via conflicts table.

---

## 7. THREAT MODEL

Server sees: file sizes, folder hierarchy, encrypted filenames, encrypted chunks. Never sees plaintext content or unencrypted filenames.

---

## 8. PHASE BREAKDOWN

Phase 1: Auth + List + Download
Phase 2: Upload with resume
Phase 3: Conflicts
Phase 4: Encryption

Each phase has tests.

---

*End of Revised Design Document.*