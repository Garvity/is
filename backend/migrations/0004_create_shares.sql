CREATE TABLE IF NOT EXISTS shares (
    id TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL,
    item_id TEXT NOT NULL,
    wrapped_dek TEXT NOT NULL,
    access_type TEXT NOT NULL,
    password_hash TEXT,
    expires_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);