# Helumi / Orbit System Specification

## Step 1: OrbitMountHelper Specification
- **Decompilation Status**: Fully decompiled using Hopper via REA.
- **Mechanism**: The helper sets up an `NSXPCListener` bound to a Mach service name (`sub_1001150e0`), assigns a delegate (`*qword_10018f620`), resumes the listener, and enters `[[NSRunLoop mainRunLoop] run]` (Evidence: function at `0x100001618`).
- **MountHelperProtocol**: Confirmed as an XPC service listener delegate interface managing helper actions (mount/unmount requests from the main application).
- **Claims**:
  - Main entrypoint sets up an NSXPCListener for privileged IPC: **Confirmed** (Function: `main` / offset `0x100001618`).
  - Implements MountHelperProtocol to receive commands from Helumi: **Confirmed** (Evidence: XPC listener delegate setup at offset `0x100001618`).

## Step 2: OrbitCore Local Endpoints (`localhost:8787` & `localhost:8969/stream`)
- **Decompilation Status**: Partial/String-referenced; direct listener creation routines for `localhost:8787` and `localhost:8969/stream` are inside compiled Swift async networking libraries or packaged extension targets (`OrbitFS.appex`), yielding no direct standalone decompiler routine with clear symbol mappings for the listen bind call.
- **Claims**:
  - `localhost:8787` is used for local API communication: **Guessed** (Evidence: string constant references in Helumi and OrbitFS binaries, e.g., offset `0x100287870`).
  - `localhost:8969/stream` provides a streaming connection: **Guessed** (Evidence: URL string references in binary).

## Step 3: OrbitCore API Routes & Request/Response Shapes
- **Decompilation Status**: Confirmed via string constants and method signatures in `OrbitCore` module (found in Helumi binary and OrbitFS.appex).
- **API Base URL**: `https://orbit-api.letcontactabhi.workers.dev` (Confirmed via `Info.plist` key `OrbitAPIBaseURL`).
- **Endpoints** (Confirmed via string constants):
  - `POST /auth/native/token` — Authentication/token exchange.
  - `GET /items/content-urls` — Get file content URLs for download.
  - `GET /account/private-files` — Get user's private files/account info.
  - `GET /user/` — Get user profile/info.
  - `GET /account/keys/recovery` — Account key recovery endpoint.
- **Request/Response Shapes** (Guessed via string references and Swift mangled names):
  - Envelope types: `ShareEnvelope`, `ItemEnvelope`, `UserEnvelope`, `ErrorBody`.
  - Models: `RemoteItem`, `BlobSource`, `WireName`, `WireSecrets`, `SaveResult`, `UploadFile`, `FinishedUpload`.
  - Upload methods use `NSProgress` for streaming progress.
- **Confidence**: Endpoints confirmed via string constants; exact JSON schemas **Guessed** (no live decompilation of serialization logic available).

## Step 4: File Provider Behavior (`OrbitFS.appex`)
- **Decompilation Status**: Fully mapped via `OrbitVolume` class implementing `NSFileProviderExtension` callbacks.
- **Enumeration** (`enumerateDirectory:...` at `0x10000e990`):
  - Implemented via `OrbitVolume.enumerateDirectory:startingAtCookie:verifier:providingAttributes:usingPacker:replyHandler:` (`0x10000e990`).
  - Delegates to internal helper `sub_10000e3b0` which performs dynamic cast and fetches children from `Drive` model via `nodeID` (`objc_ivar_offset__TtC7OrbitFS11OrbitFSItem_nodeID`).
- **Fetch/Download** (`fetch` at `0x100056934` / `0x10007a4bc`):
  - `OrbitCore.OrbitAPI.fetch(range:)` (`_$s9OrbitCore0A3APIC5fetch_5range...` at `0x100056934`) retrieves file data ranges via `URLSession` async tasks.
  - `LockedRemote.fetch(range:)` (`0x10007a4bc`) provides encrypted/locked file access.
  - Read callback: `readFromFile:offset:length:intoBuffer:replyHandler:` (`0x10000f3fc`).
- **Upload** (Multiple entrypoints in `OrbitCore`):
  - `DriveRemote.uploadNewFile(from:name:parentId:clientId:modifiedAt:progress:)` (`0x1000437f4`).
  - `OrbitAPI.uploadNewFile(...)` (`0x1000574a4`), `uploadContents(id:from:baseContentVersion:modifiedAt:deviceName:resumeKey:progress:)` (`0x100058024`), `uploadBlob(resumeKey:progress:partDone:)` (`0x1000ea5e0`).
  - Supports resumable uploads via `resumeKey`, multipart/blob streaming via `WebUpload` and `UploadGovernor` (`0x1000edb60`).
  - Write callback: `writeContents:toFile:atOffset:replyHandler:` (`0x10000f98c`).
- **Conflicts**:
  - `ConflictNaming` type referenced in string tables.
  - `uploadContents(..., conflictName:)` parameter (`0x100059cf0`) indicates explicit conflict resolution during save.
- **Additional Volume Operations** (`OrbitVolume` at `0x1000085d8`–`0x100012888`):
  - `activateWithOptions:`, `mountWithOptions:`, `unmountWithReplyHandler:`, `synchronizeWithFlags:`.
  - Item lookup: `lookupItemNamed:inDirectory:replyHandler:` (`0x10000daa8`).
  - Attributes: `getAttributes:ofItem:`, `setAttributes:onItem:`.
  - Mutations: `createItemNamed:type:inDirectory:`, `renameItem:...`, `removeItem:named:fromDirectory:`.
  - Extended attributes: `getXattrNamed:`, `setXattrNamed:toData:`, `listXattrsOfItem:`.

## Unknowns
- Exact JSON serialization schemas for `ItemEnvelope`, `ShareEnvelope`, `UserEnvelope`, `ErrorBody`.
- Complete `MountHelperProtocol` method signatures (Swift mangled names prevent full reconstruction without source).
- Local server implementation for `localhost:8787` / `8969` (likely in separate compiled Swift Concurrency runtime not fully exposed to static decompiler).
- CoreData/SQLite schema for local persistence.