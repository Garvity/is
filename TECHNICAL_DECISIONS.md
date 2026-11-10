# Technical Decisions

## Architecture
- **File Provider**: `NSFileProviderReplicatedExtension` (not FSKit, no MountHelper)
- **Rationale**: Native macOS integration, Finder support, sandboxed, no kernel extensions needed
- **Alternative Considered**: Custom FUSE/mount - rejected (complexity, security, maintenance)

## Backend
- **Language/Framework**: Rust + Axum + Tokio
- **Rationale**: Performance, memory safety, async/await, strong type system
- **Alternative Considered**: Node.js/Express - rejected (runtime overhead, type safety)

## Metadata Storage
- **Backend**: PostgreSQL (via Docker Compose for dev)
- **Rationale**: ACID compliance, UUID support, JSON support, mature ecosystem
- **Local**: SQLite3 (native, not GRDB)
- **Rationale**: Zero dependencies, sandbox-compatible, shared via App Group, minimal overhead

## Object Storage
- **Planned**: S3-compatible (Cloudflare R2, AWS S3, or MinIO)
- **Not Yet Implemented**: Reserved for Milestone 3+

## Authentication & Security
- **Password Hashing**: Argon2id (memory-hard, resistant to GPU attacks)
- **Token Format**: JWT (HS256, 24-hour expiry)
- **Token Storage**: macOS Keychain (`kSecClassGenericPassword`)
- **Key Derivation**: Not yet implemented (future: per-file encryption keys)

## App Group & Sandbox
- **App Group ID**: `group.com.example.clouddrive`
- **Usage**: Shared SQLite database, Keychain access group (future)
- **Path Resolution**: 
  ```swift
  FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.clouddrive")
  ```
  with fallback to `~/Library/Application Support/group.com.example.clouddrive` for non-sandboxed testing

## Project Build System
- **Format**: xcodegen JSON (`project.xcproj`)
- **Rationale**: Declarative, version-controllable, CI-friendly
- **Requirement**: Run `xcodegen generate` to produce standard `project.pbxproj` for Xcode
- **Current Status**: JSON project exists, needs xcodegen or manual Xcode project creation

## Encryption
- **Status**: Not yet implemented (Milestone 5)
- **Planned**: Client-side encryption with per-file keys, key hierarchy, secure sharing

## Synchronization
- **Status**: Basic metadata sync implemented (Milestone 2)
- **Planned**: Background sync, conflict resolution, offline support (Milestone 4)

## Key Technical Risks
1. **App Group Container Access**: Requires valid Apple Developer account and code signing
2. **File Provider Extension Lifecycle**: Complex state management, requires careful testing
3. **Large File Handling**: Streaming/chunked upload/download not yet implemented
4. **Conflict Resolution**: Multi-device sync conflicts need robust strategy
