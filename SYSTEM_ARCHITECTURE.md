# System Architecture

## Overview
A production-quality macOS cloud drive built with native Apple File Provider framework, inspired by Helumi.

## Components

### 1. Main App (CloudDriveProject)
- **Technology**: Swift 5.9+, SwiftUI, AppKit (where needed)
- **Responsibilities**:
  - User authentication UI (login/register)
  - Session management (JWT token storage in Keychain)
  - File Provider domain registration via `NSFileProviderManager`
  - Local metadata persistence via SQLite3
  - Backend API communication
  - Settings and account management

### 2. File Provider Extension (CloudDriveFileProviderExtension)
- **Technology**: `NSFileProviderReplicatedExtension` (non-UI extension)
- **Responsibilities**:
  - Finder integration (virtual filesystem)
  - Item enumeration (`NSFileProviderEnumerator`)
  - File materialization (on-demand download)
  - File upload (modifications, new files)
  - Deletion, rename, move operations
  - Sync anchor management
- **Extension Point**: `com.apple.fileprovider-replicated`
- **App Group**: `group.com.example.clouddrive`

### 3. Local Storage (SQLite3)
- **Technology**: Native SQLite3 (not GRDB)
- **Location**: App Group container (`group.com.example.clouddrive`)
- **Schema**: `item` table with columns for id, userId, parentId, name, mimeType, size, r2Key, isDirectory, createdAt, updatedAt
- **Indexes**: `idx_item_userId`, `idx_item_parentId`
- **Access**: Shared between main app and File Provider extension via App Group

### 4. Secure Credential Storage
- **Technology**: macOS Keychain (`kSecClassGenericPassword`)
- **Service**: `com.example.clouddrive.auth`
- **Account**: `jwt_token`
- **Accessibility**: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

### 5. Backend API
- **Technology**: Rust + Axum + Tokio
- **Database**: PostgreSQL (Docker Compose)
- **Authentication**: Argon2id password hashing, JWT (HS256, 24hr expiry)
- **Endpoints**:
  - `POST /auth/register` - User registration
  - `POST /auth/login` - User login
  - `GET /auth/me` - Current user info
  - `GET /items` - List folders and files
  - `POST /items` - Create folder/file
  - `GET /items/:id` - Get item
  - `PATCH /items/:id` - Update item
  - `DELETE /items/:id` - Delete item
- **User Isolation**: All item queries filtered by authenticated user ID

### 6. PostgreSQL Schema
- **users**: id (UUID PK), email (UNIQUE), password_hash, created_at
- **folders**: id (UUID PK), user_id (FK), parent_id (FK), name, created_at, updated_at
- **files**: id (UUID PK), user_id (FK), folder_id (FK), name, mime_type, size, r2_key, created_at, updated_at

## Data Flow

```
Finder Request
      ↓
File Provider Extension (NSFileProviderReplicatedExtension)
      ↓
Local SQLite3 (App Group container)
      ↓
Main App (background sync) ←→ Backend API (Rust/Axum)
      ↓
PostgreSQL (source of truth) + Object Storage (future)
```

## Project Structure
```
CloudDriveProject/
├── CloudDriveProject.xcodeproj/          # xcodegen JSON project
│   ├── project.xcproj                    # xcodegen project definition
│   └── project.xcworkspace/              # Xcode workspace
├── CloudDriveProject/                    # Main app target
│   ├── CloudDriveProjectApp.swift
│   ├── ContentView.swift                 # SwiftUI auth + metadata UI
│   ├── AuthViewModel.swift               # Auth + sync coordination
│   ├── KeychainService.swift             # JWT Keychain storage
│   ├── Database.swift                    # SQLite3 (native)
│   ├── APIClient.swift                   # Backend communication
│   ├── APIModels.swift                   # DTOs
│   └── CloudDriveProject.entitlements
├── CloudDriveFileProviderExtension/      # Extension target
│   ├── FileProviderExtension.swift       # NSFileProviderReplicatedExtension
│   ├── FileProviderEnumerator.swift      # NSFileProviderEnumerator
│   ├── FileProviderItem.swift            # NSFileProviderItem
│   ├── Info.plist                        # Extension configuration
│   └── CloudDriveFileProviderExtension.entitlements
├── CloudDriveCore/                       # Unused duplicate (legacy)
└── backend/                              # Rust backend
    ├── Cargo.toml
    ├── docker-compose.yml
    ├── .env
    ├── migrations/
    └── src/
