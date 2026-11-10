//
//  ConflictManager.swift
//  CloudDriveFileProviderExtension
//
//  Created by Garv R Changrani on 06/11/26.
//

import Foundation
import SQLite3
import FileProvider

/// Represents a conflict between local and server state
public struct Conflict: Codable {
    public let id: String
    public let itemId: String
    public let itemName: String
    public let conflictType: ConflictType
    public let localVersion: String
    public let serverVersion: String
    public let localData: Data?
    public let serverData: Data?
    public let deviceName: String
    public let createdAt: Date
    public let resolvedAt: Date?
    public let resolution: ConflictResolution?

    public enum ConflictType: String, Codable {
        case modify = "modify"
        case create = "create"
        case delete = "delete"
    }

    public enum ConflictResolution: String, Codable {
        case serverWins = "server_wins"
        case localWins = "local_wins"
        case manual = "manual"
        case createCopy = "create_copy"
    }
}

/// Manages version conflicts between local and server state
public class ConflictManager {
    public static let shared = ConflictManager()

    private let appGroupIdentifier = "group.com.example.clouddrive"
    private var db: OpaquePointer?
    private let deviceName: String
    private let dateFormatter: ISO8601DateFormatter

    private init() {
        // Get device name for conflicted copy naming
        self.deviceName = Host.current().localizedName ?? "Unknown Device"
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        openDatabase()
        createConflictsTable()
    }

    deinit {
        sqlite3_close(db)
    }

    private func openDatabase() {
        let fileManager = FileManager.default
        if let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let dbURL = containerURL.appendingPathComponent("clouddrive.sqlite")
            if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
                print("Failed to open database at \(dbURL.path)")
            }
        }
    }

    private func createConflictsTable() {
        guard let db = db else { return }

        let sql = """
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
            print("Failed to create conflicts table: \(msg)")
        }
    }

    /// Generate a conflicted copy name: "{original} (conflicted copy {deviceName} {date})"
    public func conflictedCopyName(for originalName: String) -> String {
        let timestamp = dateFormatter.string(from: Date())
        let datePart = String(timestamp.prefix(19)).replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "T", with: " ")
        let ext = (originalName as NSString).pathExtension
        let baseName = (originalName as NSString).deletingPathExtension

        if ext.isEmpty {
            return "\(baseName) (conflicted copy \(deviceName) \(datePart))"
        } else {
            return "\(baseName) (conflicted copy \(deviceName) \(datePart)).\(ext)"
        }
    }

    /// Record a conflict in the database
    public func recordConflict(
        itemId: String,
        itemName: String,
        type: Conflict.ConflictType,
        localVersion: String,
        serverVersion: String,
        localData: Data? = nil,
        serverData: Data? = nil
    ) throws -> Conflict {
        guard let db = db else {
            throw NSError(domain: "ConflictManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
        }

        let conflictId = UUID().uuidString
        let now = Date()
        let createdAt = dateFormatter.string(from: now)

        let sql = """
        INSERT INTO conflicts (id, itemId, itemName, conflictType, localVersion, serverVersion, localData, serverData, deviceName, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw NSError(domain: "ConflictManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare statement"])
        }

        sqlite3_bind_text(stmt, 1, (conflictId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (itemId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (itemName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (type.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (localVersion as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (serverVersion as NSString).utf8String, -1, nil)

        if let localData = localData {
            localData.withUnsafeBytes { bytes in
                sqlite3_bind_blob(stmt, 7, bytes.baseAddress, Int32(localData.count), nil)
            }
        } else {
            sqlite3_bind_null(stmt, 7)
        }

        if let serverData = serverData {
            serverData.withUnsafeBytes { bytes in
                sqlite3_bind_blob(stmt, 8, bytes.baseAddress, Int32(serverData.count), nil)
            }
        } else {
            sqlite3_bind_null(stmt, 8)
        }

        sqlite3_bind_text(stmt, 9, (deviceName as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 10, (createdAt as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            sqlite3_finalize(stmt)
            throw NSError(domain: "ConflictManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to insert conflict"])
        }

        sqlite3_finalize(stmt)

        return Conflict(
            id: conflictId,
            itemId: itemId,
            itemName: itemName,
            conflictType: type,
            localVersion: localVersion,
            serverVersion: serverVersion,
            localData: localData,
            serverData: serverData,
            deviceName: deviceName,
            createdAt: now,
            resolvedAt: nil,
            resolution: nil
        )
    }

    /// Resolve a conflict with the given resolution strategy
    public func resolveConflict(conflictId: String, resolution: Conflict.ConflictResolution) throws {
        guard let db = db else {
            throw NSError(domain: "ConflictManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
        }

        let now = Date()
        let resolvedAt = dateFormatter.string(from: now)

        let sql = """
        UPDATE conflicts SET resolvedAt = ?, resolution = ? WHERE id = ?
        """

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw NSError(domain: "ConflictManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare statement"])
        }

        sqlite3_bind_text(stmt, 1, (resolvedAt as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (resolution.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (conflictId as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) != SQLITE_DONE {
            sqlite3_finalize(stmt)
            throw NSError(domain: "ConflictManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to resolve conflict"])
        }

        sqlite3_finalize(stmt)
    }

    /// Get all unresolved conflicts
    public func getUnresolvedConflicts() throws -> [Conflict] {
        guard let db = db else {
            throw NSError(domain: "ConflictManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
        }

        let sql = "SELECT * FROM conflicts WHERE resolvedAt IS NULL ORDER BY createdAt DESC"
        var stmt: OpaquePointer?
        var conflicts: [Conflict] = []

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw NSError(domain: "ConflictManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare statement"])
        }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let itemId = String(cString: sqlite3_column_text(stmt, 1))
            let itemName = String(cString: sqlite3_column_text(stmt, 2))
            let conflictTypeStr = String(cString: sqlite3_column_text(stmt, 3))
            let localVersion = String(cString: sqlite3_column_text(stmt, 4))
            let serverVersion = String(cString: sqlite3_column_text(stmt, 5))

            let localData: Data?
            if sqlite3_column_type(stmt, 6) != SQLITE_NULL {
                let bytes = sqlite3_column_blob(stmt, 6)!
                let length = sqlite3_column_bytes(stmt, 6)
                localData = Data(bytes: bytes, count: Int(length))
            } else {
                localData = nil
            }

            let serverData: Data?
            if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
                let bytes = sqlite3_column_blob(stmt, 7)!
                let length = sqlite3_column_bytes(stmt, 7)
                serverData = Data(bytes: bytes, count: Int(length))
            } else {
                serverData = nil
            }

            let deviceName = String(cString: sqlite3_column_text(stmt, 8))
            let createdAtStr = String(cString: sqlite3_column_text(stmt, 9))
            let resolvedAtStr = sqlite3_column_text(stmt, 10).map { String(cString: $0) }
            let resolutionStr = sqlite3_column_text(stmt, 11).map { String(cString: $0) }

            let conflictType = Conflict.ConflictType(rawValue: conflictTypeStr) ?? .modify
            let createdAt = dateFormatter.date(from: createdAtStr) ?? Date()
            let resolvedAt = resolvedAtStr.flatMap { dateFormatter.date(from: $0) }
            let resolution = resolutionStr.flatMap { Conflict.ConflictResolution(rawValue: $0) }

            conflicts.append(Conflict(
                id: id,
                itemId: itemId,
                itemName: itemName,
                conflictType: conflictType,
                localVersion: localVersion,
                serverVersion: serverVersion,
                localData: localData,
                serverData: serverData,
                deviceName: deviceName,
                createdAt: createdAt,
                resolvedAt: resolvedAt,
                resolution: resolution
            ))
        }

        sqlite3_finalize(stmt)
        return conflicts
    }

    /// Check if a version conflict exists by comparing baseVersion with server version
    public func checkVersionConflict(itemId: String, baseVersion: NSFileProviderItemVersion, serverVersion: String) -> Bool {
        // Extract the content version from the baseVersion
        let baseVersionString = String(data: baseVersion.contentVersion, encoding: .utf8) ?? ""
        return baseVersionString != serverVersion && !baseVersionString.isEmpty && !serverVersion.isEmpty
    }

    /// Create a version out of date error for FileProvider
    public func versionOutOfDateError() -> Error {
        // Use the raw Int value for the error code
        return NSError(domain: NSFileProviderErrorDomain, code: -2015, userInfo: [
            NSLocalizedDescriptionKey: "The item has been modified on another device"
        ])
    }
}