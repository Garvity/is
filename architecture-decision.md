# Architecture Decision: FSKit vs File Provider Extension

## Executive Summary

**Recommendation: Use File Provider Extension (Option B)**

File Provider is the mature, well-supported path for cloud drives on macOS today. FSKit (File System Kit) is brand new in macOS 15.4 (Sequoia), requires users on the very latest OS, and has limited documentation/community knowledge.

---

## Comparison Matrix

| Dimension | File Provider Extension | FSKit (macOS 15.4+) |
|-----------|------------------------|---------------------|
| **macOS Version** | 10.15+ (Catalina) | 15.4+ (Sequoia) |
| **User Base** | ~95%+ of Mac users | ~10-20% (early adopters) |
| **Documentation** | Extensive, 5+ years of examples | Minimal, WWDC 2024 only |
| **Finder Integration** | Native, battle-tested | New, unproven edge cases |
| **Encryption Support** | File-level via NSFileProviderItem | Volume-level via FSKit API |
| **Conflict Handling** | Built-in conflict resolution UI | Manual implementation needed |
| **Background Sync** | Built-in sync engine | You build it |
| **Privileged Helper** | Required for mount (SMJobBless) | Not needed (kernel extension) |
| **App Store** | Fully supported | Unknown/uncertain |
| **Debugging** | Mature tools, console logs | New, limited tooling |
| **Community/StackOverflow** | Hundreds of solutions | Nearly zero |

---

## File Provider Extension: Deep Dive

### How It Works (based on Helumi/Orbit analysis)
```
┌─────────────────────────────────────────────────────────────┐
│                        Your App                               │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────┐  │
│  │  Main App   │───▶│  FileProvider│───▶│  OrbitFS.appex │  │
│  │  (UI/State) │    │  Extension   │    │  (NSFilePro-   │  │
│  └─────────────┘    └──────────────┘    │   viderExt)    │  │
│         │                    │           └───────┬────────┘  │
│         │ XPC/IPC            │                   │           │
│         ▼                    ▼                   ▼           │
│  ┌─────────────┐    ┌──────────────┐    ┌────────────────┐  │
│  │ OrbitMount  │    │  OrbitCore   │    │  Your Backend  │  │
│  │ Helper (XPC)│    │  (API/Logic) │    │  (Workers+R2)  │  │
│  └─────────────┘    └──────────────┘    └────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### What Helumi Already Proves Works
From the reverse-engineering:
- **OrbitMountHelper**: `NSXPCListener` + `NSRunLoop` → privileged mount/unmount
- **OrbitFS.appex**: `NSFileProviderExtension` subclass with full callback suite:
  - `enumerateDirectory` → drives Finder listing
  - `readFromFile` / `writeContents` → streaming I/O
  - `createItemNamed`, `renameItem`, `removeItem` → mutations
  - `activateWithOptions`, `mountWithOptions`, `sync` → lifecycle
- **OrbitCore**: All business logic (API, encryption, upload pipeline, conflict resolution) in a shared framework

### Your Feature Mapping
| Feature | File Provider Approach |
|---------|------------------------|
| Menu bar status | Main app + extension communicate via shared App Group / XPC |
| Finder-visible drive | Native — this is exactly what File Provider *is* |
| Resumable uploads | `uploadContents` with `resumeKey` (Orbit does this at `0x100058024`) |
| Conflict copies | `conflictName` param on `uploadContents` (`0x100059cf0`) + built-in Finder conflict UI |
| Client-side encryption | Encrypt in `OrbitCore` before upload; decrypt in `readFromFile` |

---

## FSKit: Why Not Yet

### What It Is
- New framework in macOS 15.4 (Sequoia) for building *virtual file systems in userspace*
- Runs in-process (no kernel extension, no privileged helper)
- Lower-level: you implement `FSKit.FileSystem`, `FSKit.Volume`, handle VFS ops directly

### Blockers for Your Project
1. **macOS 15.4 minimum** — excludes anyone on 15.3 or older (most users for 6-12 months)
2. **No conflict resolution built in** — you build the "Keep Both" / "Replace" UI
3. **No background sync engine** — you implement the daemon that watches for changes
4. **No Finder integration helpers** — you handle `.DS_Store`, spotlight, Quick Look yourself
5. **App Store review uncertainty** — Apple may reject FSKit apps until the API stabilizes
6. **Zero community knowledge** — you're the beta tester

### When FSKit Makes Sense
- You need *block-level* control (e.g., encrypted volume images, not file-level)
- You're building a developer tool for power users on latest macOS only
- You want to avoid the XPC helper complexity (but gain VFS complexity instead)

---

## Recommended Architecture (File Provider)

### Project Structure
```
YourCloudDrive/
├── YourCloudDrive.xcodeproj
├── YourCloudDrive/              # Main app (menu bar, settings, auth)
│   ├── AppDelegate.swift
│   ├── MenuBarController.swift
│   ├── AuthManager.swift
│   └── Shared/                  # Shared code (App Group accessible)
│       ├── Models.swift
│       ├── APIClient.swift
│       └── Crypto.swift
├── FileProviderExtension/       # NSFileProviderExtension target
│   ├── FileProviderExtension.swift
│   ├── FileProviderEnumerator.swift
│   └── FileProviderItem.swift
├── MountHelper/                 # SMJobBless privileged helper
│   ├── MountHelperProtocol.swift
│   └── MountHelperMain.swift
├── SharedFramework/             # OrbitCore equivalent (shared logic)
│   ├── API/
│   ├── UploadPipeline/
│   ├── ConflictResolver/
│   └── Crypto/
└── Tests/
    ├── APIClientTests.swift
    ├── UploadPipelineTests.swift
    ├── ConflictResolverTests.swift
    └── CryptoTests.swift
```

### Implementation Order (matches your plan)

#### Phase 1: Auth + List/Download
1. **Auth flow**: OAuth2 / custom token exchange → store in Keychain
2. **APIClient**: `GET /items`, `GET /items/content-urls` → `RemoteItem` models
3. **FileProviderEnumerator**: Implement `enumerateItemsForObserver` → yields `FileProviderItem` with `contentURL` for download
4. **MountHelper**: `NSXPCListener` + `SMJobBless` for `mount`/`unmount` (copy from Helumi pattern)
5. **Tests**: Mock server → verify enumerator yields correct items, download works

#### Phase 2: Upload
1. **UploadPipeline**: `uploadNewFile`, `uploadContents` with `NSProgress`, resumable via `resumeKey`
2. **FileProviderExtension**: Implement `writeContentsToFile` → streams to upload pipeline
3. **UploadGovernor/Pacer**: Rate limiting, retry with backoff (copy Orbit patterns)
4. **Tests**: Large file (100MB+), network interruption → verify resume

#### Phase 3: Conflicts
1. **ConflictResolver**: Detect `409 Conflict` / `ETag` mismatch → generate `conflictName`
2. **FileProviderExtension**: Return `NSFileProviderConflict` items for Finder's native UI
3. **User choice handling**: "Keep Both" → rename + upload both; "Replace" → overwrite
4. **Tests**: Simulate concurrent edits → verify both resolution paths

#### Phase 4: Client-Side Encryption
1. **Crypto module**: AES-GCM per-file, keys derived from user password + salt (PBKDF2/Argon2)
2. **Key management**: Wrapped keys stored in Keychain; recovery key for account recovery
3. **Integration**: Encrypt in `writeContentsToFile` *before* upload; decrypt in `readFromFile` *after* download
4. **Metadata**: Store nonce, salt, key ID in file extended attributes or sidecar
5. **Tests**: Round-trip encrypt/decrypt; verify corrupted ciphertext fails auth tag

---

## Key Technical Decisions

| Decision | Recommendation | Rationale |
|----------|----------------|-----------|
| **Backend** | Workers + R2 | Full control, S3-compatible, cheaper than Google Drive API limits |
| **Auth** | Custom JWT + refresh tokens | Simpler than OAuth for single-provider; use `ASWebAuthenticationSession` |
| **Sync engine** | Polling + push (WebSocket) | File Provider expects *you* to signal changes via `NSFileProviderChangeObserver` |
| **Database** | SQLite (GRDB.swift) or CoreData | Local cache of file tree, pending uploads, encryption metadata |
| **Networking** | `URLSession` + async/await | Native Swift concurrency, works in extension |
| **Logging** | OSLog + Sentry (like Helumi) | Production visibility |

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| File Provider extension crashes → Finder shows "drive disconnected" | Extensive unit tests; crash reporting in extension; graceful degradation |
| SMJobBless helper install fails (user denies, codesign issues) | Clear UI guidance; fallback to "manual mount" button; test on clean VMs |
| Large file uploads OOM in extension | Stream in chunks (Orbit uses `InputStream`/`OutputStream`); never load full file in memory |
| Conflict resolution UX confusing | Use Finder's native conflict UI; add menu bar "Resolve Conflicts" entry |
| macOS version breaks File Provider | Pin to tested macOS versions; monitor beta seeds; file radars |

---

## Next Steps

1. **Create Xcode project** with 4 targets: App, FileProviderExtension, MountHelper, SharedFramework
2. **Set up App Groups** for IPC/shared data (`com.yourname.yourapp.group`)
3. **Implement MountHelper first** — it's the hardest to debug (privileged, no UI)
4. **Build API client + auth** against your Workers backend
5. **Wire up FileProviderEnumerator** to return mock items → verify Finder shows drive
6. **Add real backend calls**, then upload, then conflicts, then encryption

---

## References from Helumi Analysis

- **MountHelper pattern**: `main` at `0x100001618` → `NSXPCListener` + delegate + `NSRunLoop`
- **FileProviderExtension pattern**: `OrbitVolume` class with 25+ callbacks (`0x1000085d8`–`0x100012888`)
- **Upload pipeline**: `uploadNewFile` (`0x1000437f4`), `uploadContents` (`0x100058024`), `uploadBlob` (`0x1000ea5e0`)
- **Resumable uploads**: `resumeKey` parameter, `WebUpload` state machine (`0x100152e5c`)
- **Conflict resolution**: `conflictName` parameter on `uploadContents` (`0x100059cf0`)
- **Encryption hints**: `WireSecrets`, `BlobSource`, `fileKey`, `fileNonce` in string tables