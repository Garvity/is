//
//  FileProviderEnumerator.swift
//  CloudDriveFileProviderExtension
//
//  Created by Garv R Changrani on 06/11/26.
//

import FileProvider
import SQLite3

class FileProviderEnumerator: NSObject, NSFileProviderEnumerator {

    private let enumeratedItemIdentifier: NSFileProviderItemIdentifier
    private let appGroupIdentifier = "group.com.example.clouddrive"
    private var db: OpaquePointer?
    private let anchor = NSFileProviderSyncAnchor("anchor".data(using: .utf8)!)

    init(enumeratedItemIdentifier: NSFileProviderItemIdentifier) {
        self.enumeratedItemIdentifier = enumeratedItemIdentifier
        super.init()
        openDatabase()
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

    func invalidate() {
        // cleanup any resources if needed
    }

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        guard let db = db else {
            observer.finishEnumerating(upTo: nil)
            return
        }

        let parentId: String?
        if enumeratedItemIdentifier == .rootContainer {
            parentId = nil
        } else {
            parentId = enumeratedItemIdentifier.rawValue
        }

        let sql: String
        if parentId == nil {
            sql = "SELECT * FROM item WHERE parentId IS NULL"
        } else {
            sql = "SELECT * FROM item WHERE parentId = ?"
        }

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            observer.finishEnumerating(upTo: nil)
            return
        }

        if let parentId = parentId {
            sqlite3_bind_text(stmt, 1, (parentId as NSString).utf8String, -1, nil)
        }

        var items: [FileProviderItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 3))
            let mimeType = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let size = sqlite3_column_int64(stmt, 5)
            let r2Key = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
            let isDirectory = sqlite3_column_int(stmt, 7) == 1
            let createdAt = String(cString: sqlite3_column_text(stmt, 8))
            let updatedAt = String(cString: sqlite3_column_text(stmt, 9))

            let item = FileProviderItem(
                identifier: NSFileProviderItemIdentifier(id),
                parentIdentifier: enumeratedItemIdentifier,
                filename: name,
                isDirectory: isDirectory,
                size: size,
                mimeType: mimeType,
                r2Key: r2Key,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
            items.append(item)
        }

        sqlite3_finalize(stmt)

        observer.didEnumerate(items)
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        let sequence = Int64(String(data: anchor.rawValue, encoding: .utf8) ?? "0") ?? 0
        let engine = SyncEngine()

        engine.fetchAndApplyChanges(since: sequence) { newSequence in
            let newAnchor = NSFileProviderSyncAnchor("\(newSequence)".data(using: .utf8)!)
            observer.finishEnumeratingChanges(upTo: newAnchor, moreComing: false)
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(anchor)
    }
}