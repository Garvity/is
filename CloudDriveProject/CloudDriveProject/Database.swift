import Foundation
import SQLite3

public struct CloudDriveItem: Codable, Identifiable {
    public let id: String
    public let userId: String
    public let parentId: String?
    public let name: String
    public let mimeType: String?
    public let size: Int64
    public let r2Key: String?
    public let isDirectory: Bool
    public let createdAt: String
    public let updatedAt: String
}

public class Database {
    public static let shared = Database()
    private var db: OpaquePointer?
    private let appGroupIdentifier = "group.com.example.clouddrive"
    
    private init() {
        do {
            let path = try Self.databasePath(appGroupIdentifier: appGroupIdentifier)
            try openDatabase(at: path)
            try createTables()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    public static func databasePath(appGroupIdentifier: String) throws -> String {
        let fileManager = FileManager.default
        
        // Try to get the App Group container URL first (for sandboxed app/extension)
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let dbURL = containerURL.appendingPathComponent("clouddrive.sqlite")
            if !fileManager.fileExists(atPath: dbURL.path) {
                // Directory will be created when we open the database
            }
            return dbURL.path
        }
        
        // Fallback for non-sandboxed execution (e.g., CLI testing)
        let appGroupURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let containerURL = appGroupURL.appendingPathComponent(appGroupIdentifier)
        
        if !fileManager.fileExists(atPath: containerURL.path) {
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        }
        
        return containerURL.appendingPathComponent("clouddrive.sqlite").path
    }
    
    private func openDatabase(at path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open database"])
        }
    }
    
    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS item (
            id TEXT PRIMARY KEY,
            userId TEXT NOT NULL,
            parentId TEXT,
            name TEXT NOT NULL,
            mimeType TEXT,
            size INTEGER NOT NULL DEFAULT 0,
            r2Key TEXT,
            isDirectory INTEGER NOT NULL DEFAULT 0,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_item_userId ON item(userId);
        CREATE INDEX IF NOT EXISTS idx_item_parentId ON item(parentId);

        CREATE TABLE IF NOT EXISTS conflicts (
            id TEXT PRIMARY KEY,
            itemId TEXT NOT NULL,
            itemName TEXT NOT NULL,
            conflictType TEXT NOT NULL,
            localVersion TEXT NOT NULL,
            serverVersion TEXT NOT NULL,
            localData BLOB,
            serverData BLOB,
            deviceName TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            resolvedAt TEXT,
            resolution TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_conflicts_itemId ON conflicts(itemId);
        CREATE INDEX IF NOT EXISTS idx_conflicts_resolvedAt ON conflicts(resolvedAt);
        """

        var errMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = String(cString: errMsg!)
            sqlite3_free(errMsg)
            throw NSError(domain: "Database", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create tables: \(msg)"])
        }
    }
    
    public func insertOrUpdate(_ items: [CloudDriveItem]) throws {
        let sql = """
        INSERT OR REPLACE INTO item (id, userId, parentId, name, mimeType, size, r2Key, isDirectory, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw NSError(domain: "Database", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare statement"])
        }
        
        for item in items {
            sqlite3_bind_text(stmt, 1, (item.id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (item.userId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (item.parentId as NSString?)?.utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (item.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (item.mimeType as NSString?)?.utf8String, -1, nil)
            sqlite3_bind_int64(stmt, 6, item.size)
            sqlite3_bind_text(stmt, 7, (item.r2Key as NSString?)?.utf8String, -1, nil)
            sqlite3_bind_int(stmt, 8, item.isDirectory ? 1 : 0)
            sqlite3_bind_text(stmt, 9, (item.createdAt as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 10, (item.updatedAt as NSString).utf8String, -1, nil)
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                sqlite3_finalize(stmt)
                throw NSError(domain: "Database", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to insert item"])
            }
            sqlite3_reset(stmt)
        }
        
        sqlite3_finalize(stmt)
    }
    
    public func fetchItems(for userId: String) throws -> [CloudDriveItem] {
        let sql = "SELECT * FROM item WHERE userId = ?"
        var stmt: OpaquePointer?
        var items: [CloudDriveItem] = []
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw NSError(domain: "Database", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare fetch statement"])
        }
        
        sqlite3_bind_text(stmt, 1, (userId as NSString).utf8String, -1, nil)
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let userId = String(cString: sqlite3_column_text(stmt, 1))
            let parentId = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let name = String(cString: sqlite3_column_text(stmt, 3))
            let mimeType = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let size = sqlite3_column_int64(stmt, 5)
            let r2Key = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
            let isDirectory = sqlite3_column_int(stmt, 7) == 1
            let createdAt = String(cString: sqlite3_column_text(stmt, 8))
            let updatedAt = String(cString: sqlite3_column_text(stmt, 9))
            
            items.append(CloudDriveItem(
                id: id,
                userId: userId,
                parentId: parentId,
                name: name,
                mimeType: mimeType,
                size: size,
                r2Key: r2Key,
                isDirectory: isDirectory,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
        
        sqlite3_finalize(stmt)
        return items
    }
    
    public func deleteAll(for userId: String) throws {
        let sql = "DELETE FROM item WHERE userId = ?"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw NSError(domain: "Database", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare delete statement"])
        }
        
        sqlite3_bind_text(stmt, 1, (userId as NSString).utf8String, -1, nil)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            sqlite3_finalize(stmt)
            throw NSError(domain: "Database", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to delete items"])
        }
        
        sqlite3_finalize(stmt)
    }
}
