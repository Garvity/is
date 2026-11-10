import Foundation
import SQLite3

class CacheManager {
    static let shared = CacheManager()

    private let appGroupIdentifier = "group.com.example.clouddrive"
    private var db: OpaquePointer?
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 1 * 1024 * 1024 * 1024 // 1GB

    private init() {
        let fileManager = FileManager.default
        let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)!
        self.cacheDirectory = containerURL.appendingPathComponent("Library/Caches/com.example.clouddrive", isDirectory: true)

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let dbURL = containerURL.appendingPathComponent("clouddrive.sqlite")
        if sqlite3_open(dbURL.path, &db) == SQLITE_OK {
            setupCacheTable()
        }
    }

    deinit {
        sqlite3_close(db)
    }

    private func setupCacheTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS cache_metadata (
            id TEXT PRIMARY KEY,
            last_accessed INTEGER NOT NULL,
            is_hydrated INTEGER NOT NULL DEFAULT 0,
            cache_path TEXT
        );
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func getCachedURL(for id: String) -> URL? {
        guard let db = db else { return nil }

        let sql = "SELECT cache_path, is_hydrated FROM cache_metadata WHERE id = ?"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) == SQLITE_ROW {
                let isHydrated = sqlite3_column_int(stmt, 1) == 1
                if isHydrated, let path = sqlite3_column_text(stmt, 0) {
                    let url = URL(fileURLWithPath: String(cString: path))
                    if FileManager.default.fileExists(atPath: url.path) {
                        updateAccessTime(for: id)
                        sqlite3_finalize(stmt)
                        return url
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        return nil
    }

    func markHydrated(id: String, localURL: URL) {
        guard let db = db else { return }

        let sql = "INSERT OR REPLACE INTO cache_metadata (id, last_accessed, is_hydrated, cache_path) VALUES (?, ?, 1, ?)"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 2, Int64(Date().timeIntervalSince1970))
            sqlite3_bind_text(stmt, 3, (localURL.path as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        evictIfNeeded()
    }

    private func updateAccessTime(for id: String) {
        guard let db = db else { return }

        let sql = "UPDATE cache_metadata SET last_accessed = ? WHERE id = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970))
            sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    private func evictIfNeeded() {
        guard let db = db else { return }

        // Simple LRU eviction
        var totalSize: Int64 = 0
        let fileManager = FileManager.default
        let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])

        for file in files ?? [] {
            let attributes = try? fileManager.attributesOfItem(atPath: file.path)
            totalSize += (attributes?[.size] as? Int64) ?? 0
        }

        if totalSize > maxCacheSize {
            let sql = "SELECT id, cache_path FROM cache_metadata WHERE is_hydrated = 1 ORDER BY last_accessed ASC LIMIT 1"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(stmt, 0))
                    let path = String(cString: sqlite3_column_text(stmt, 1))
                    try? fileManager.removeItem(atPath: path)

                    let deleteSql = "UPDATE cache_metadata SET is_hydrated = 0, cache_path = NULL WHERE id = ?"
                    var delStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, deleteSql, -1, &delStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(delStmt, 1, (id as NSString).utf8String, -1, nil)
                        sqlite3_step(delStmt)
                    }
                    sqlite3_finalize(delStmt)
                }
            }
            sqlite3_finalize(stmt)
        }
    }
}
