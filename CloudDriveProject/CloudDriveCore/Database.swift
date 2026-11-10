import Foundation
import GRDB

public struct CloudDriveItem: Codable, FetchableRecord, PersistableRecord, Identifiable {
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
    public var dbQueue: DatabaseQueue
    
    private init() {
        do {
            let path = try Self.databasePath()
            dbQueue = try DatabaseQueue(path: path)
            try migrator.migrate(dbQueue)
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
    
    public static func databasePath() throws -> String {
        let fileManager = FileManager.default
        let appGroupURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let containerURL = appGroupURL.appendingPathComponent("group.com.example.clouddrive")
        
        if !fileManager.fileExists(atPath: containerURL.path) {
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        }
        
        return containerURL.appendingPathComponent("clouddrive.sqlite").path
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createItems") { db in
            try db.create(table: "item") { t in
                t.column("id", .text).primaryKey()
                t.column("userId", .text).notNull()
                t.column("parentId", .text)
                t.column("name", .text).notNull()
                t.column("mimeType", .text)
                t.column("size", .integer).notNull().defaults(to: 0)
                t.column("r2Key", .text)
                t.column("isDirectory", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .text).notNull()
                t.column("updatedAt", .text).notNull()
            }
            try db.create(index: "idx_item_userId", on: "item", columns: ["userId"])
            try db.create(index: "idx_item_parentId", on: "item", columns: ["parentId"])
        }

        migrator.registerMigration("createConflicts") { db in
            try db.create(table: "conflicts") { t in
                t.column("id", .text).primaryKey()
                t.column("itemId", .text).notNull()
                t.column("itemName", .text).notNull()
                t.column("conflictType", .text).notNull()
                t.column("localVersion", .text).notNull()
                t.column("serverVersion", .text).notNull()
                t.column("localData", .blob)
                t.column("serverData", .blob)
                t.column("deviceName", .text).notNull()
                t.column("createdAt", .text).notNull()
                t.column("resolvedAt", .text)
                t.column("resolution", .text)
            }
            try db.create(index: "idx_conflicts_itemId", on: "conflicts", columns: ["itemId"])
            try db.create(index: "idx_conflicts_resolvedAt", on: "conflicts", columns: ["resolvedAt"])
        }

        return migrator
    }
    
    public func insertOrUpdate(_ items: [CloudDriveItem]) throws {
        try dbQueue.write { db in
            for item in items {
                try item.insert(db, onConflict: .replace)
            }
        }
    }
    
    public func fetchItems(for userId: String) throws -> [CloudDriveItem] {
        try dbQueue.read { db in
            try CloudDriveItem
                .filter(Column("userId") == userId)
                .fetchAll(db)
        }
    }
    
    public func deleteAll(for userId: String) throws {
        try dbQueue.write { db in
            _ = try CloudDriveItem
                .filter(Column("userId") == userId)
                .deleteAll(db)
        }
    }
}
