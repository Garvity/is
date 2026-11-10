import Foundation
import SQLite3

class OfflineQueue {
    static let shared = OfflineQueue()
    private let appGroupIdentifier = "group.com.example.clouddrive"
    private var db: OpaquePointer?

    private init() {
        openDatabase()
        createTable()
    }

    private func openDatabase() {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let dbURL = containerURL.appendingPathComponent("clouddrive.sqlite")
            if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
                print("Failed to open database at \\(dbURL.path)")
            }
        }
    }

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS pending_sync (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            data TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            attempts INTEGER DEFAULT 0
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func enqueue(itemId: String, operation: String, data: String? = nil) {
        let sql = "INSERT INTO pending_sync (item_id, operation, data) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_text(stmt, 1, (itemId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (operation as NSString).utf8String, -1, nil)
        if let data = data {
            sqlite3_bind_text(stmt, 3, (data as NSString).utf8String, -1, nil)
        }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    func getPendingItems() -> [(id: Int, itemId: String, operation: String, data: String?)] {
        let sql = "SELECT id, item_id, operation, data FROM pending_sync ORDER BY created_at"
        var stmt: OpaquePointer?
        var items: [(id: Int, itemId: String, operation: String, data: String?)] = []
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(stmt, 0))
            let itemId = String(cString: sqlite3_column_text(stmt, 1))
            let operation = String(cString: sqlite3_column_text(stmt, 2))
            let data = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            items.append((id, itemId, operation, data))
        }
        sqlite3_finalize(stmt)
        return items
    }

    func remove(itemId: Int) {
        let sql = "DELETE FROM pending_sync WHERE id = ?"
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        sqlite3_bind_int(stmt, 1, Int32(itemId))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }
}
