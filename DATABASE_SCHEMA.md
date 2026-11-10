# Database Schema

## PostgreSQL (Backend - Source of Truth)

### users
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### folders
```sql
CREATE TABLE folders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES folders(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_folders_user_id ON folders(user_id);
CREATE INDEX idx_folders_parent_id ON folders(parent_id);
```

### files
```sql
CREATE TABLE files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    folder_id UUID REFERENCES folders(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
    size BIGINT NOT NULL DEFAULT 0,
    r2_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_files_user_id ON files(user_id);
CREATE INDEX idx_files_folder_id ON files(folder_id);
```

### _sqlx_migrations (managed by sqlx)
```sql
CREATE TABLE _sqlx_migrations (
    version BIGINT PRIMARY KEY,
    description TEXT NOT NULL,
    installed_on TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    success BOOLEAN NOT NULL,
    checksum BYTEA NOT NULL,
    execution_time BIGINT NOT NULL
);
```

## SQLite3 (Local - Client Cache)

### item
```sql
CREATE TABLE item (
    id TEXT PRIMARY KEY,           -- UUID string from backend
    userId TEXT NOT NULL,          -- UUID string from backend
    parentId TEXT,                 -- UUID string or NULL (root)
    name TEXT NOT NULL,
    mimeType TEXT,                 -- NULL for folders
    size INTEGER NOT NULL DEFAULT 0,
    r2Key TEXT,                    -- Object storage key (future)
    isDirectory INTEGER NOT NULL DEFAULT 0,  -- 1 = folder, 0 = file
    createdAt TEXT NOT NULL,       -- ISO8601 string
    updatedAt TEXT NOT NULL        -- ISO8601 string
);

CREATE INDEX idx_item_userId ON item(userId);
CREATE INDEX idx_item_parentId ON item(parentId);
```

## Migration History (PostgreSQL)

| Version | Description | File |
|---------|-------------|------|
| 1 | Create users table | `0001_create_users.sql` |
| 2 | Create folders table | `0002_create_folders.sql` |
| 3 | Create files table | `0003_create_files.sql` |

Migrations applied via `sqlx migrate run` on backend startup.

## Data Mapping

| Backend (PostgreSQL) | Local (SQLite3) |
|---------------------|-----------------|
| users.id → item.userId | String UUID |
| folders.id → item.id (isDirectory=1) | String UUID |
| folders.parent_id → item.parentId | String UUID or NULL |
| folders.name → item.name | String |
| files.id → item.id (isDirectory=0) | String UUID |
| files.folder_id → item.parentId | String UUID or NULL |
| files.name → item.name | String |
| files.mime_type → item.mimeType | String |
| files.size → item.size | Int64 |
| files.r2_key → item.r2Key | String or NULL |
| folders.created_at → item.createdAt | ISO8601 String |
| folders.updated_at → item.updatedAt | ISO8601 String |

## Key Design Decisions

1. **UUID as TEXT in SQLite**: SQLite doesn't have native UUID type; store as TEXT for compatibility.
2. **Timestamps as TEXT**: ISO8601 strings for cross-platform compatibility; SQLite date functions work with this format.
3. **isDirectory Flag**: Single table for both files and folders (simplifies queries, unified enumeration).
4. **r2Key Reserved**: Placeholder for future object storage integration.
5. **User Isolation**: All queries filtered by `userId` - matches backend authorization model.
