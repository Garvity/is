# CloudDrive Project Status this is the project status

**Decisions Made:**
-   **App Type:** macOS menu bar app (SwiftUI)
-   **Drive Implementation:** `NSFileProviderReplicatedExtension`
-   **Shared Code:** `CloudDriveCore` framework
-   **Local Cache:** SQLite (GRDB.swift) in App Group container
-   **Networking:** `URLSession` with async/await
-   **Backend:** Cloudflare Workers + R2 + D1
-   **Auth/Crypto:** Zero-knowledge (Argon2id → HKDF), wrapped random `root_key`, chunked AES-GCM.
-   **No Mount Helper, No BGAppRefreshTask, No Background Modes.**
-   **Out of Scope (Current Phases):** Passkey support, push notifications, sharing/collaboration.

**Done:**
-   `docs/design.md`: Comprehensive design, API, D1 schema, sync, conflicts, encryption, entitlements.
-   `docs/references.md`: Cited sources for design claims.
-   `CloudDriveProject/CloudDriveApp/CloudDriveApp.swift`: Main app scaffold.
-   `CloudDriveProject/CloudDriveApp/ContentView.swift`: Host app UI with domain registration logic.
-   `CloudDriveProject/CloudDriveFileProviderExtension/FileProviderExtension.swift`: File Provider extension scaffold (hardcoded items, placeholder logic).
-   **NOTE: No code has been compiled or tested yet.**

**Not Done / Next Steps (Phase 1 Spike):**
-   Create Xcode project (App + File Provider Extension targets).
-   Configure entitlements via Xcode capabilities.
-   Run `xcodebuild` and report raw compiler errors.
-   Fix signatures from compiler errors.
-   Verify 3 hardcoded items are visible in Finder.

**Open Questions:**
-   App Name & Bundle ID prefix (current placeholder: `com.example.clouddrive`).
-   Exact behavior of conflict copy creation after `versionOutOfDate` error.

**Known Docs/design.md Bugs (Unfixed):**
-   `CloudDriveItem` type handling (e.g. `itemIsDirectory` helper, `itemCapabilities`). These will be resolved during the spike compilation.

**Setup Facts:**
-   **Team ID:** `TEAMID` (placeholder - needs to be replaced).
-   **Bundle Prefix:** `TEAMID.com.example.clouddrive` (derived).
-   **Xcode:** Assumed installed for project creation and build.
-   **Environment:** User will run in throwaway account/VM.
