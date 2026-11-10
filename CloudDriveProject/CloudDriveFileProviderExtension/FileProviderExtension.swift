//
//  FileProviderExtension.swift
//  CloudDriveFileProviderExtension
//
//  Created by Garv R Changrani on 06/11/26.
//

import FileProvider
import SQLite3
import UniformTypeIdentifiers

// Import other classes in the same module
import Foundation
import CryptoKit

class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private let appGroupIdentifier = "group.com.example.clouddrive"
    private var db: OpaquePointer?
    private let syncManager = SyncStateManager.shared
    private let offlineQueue = OfflineQueue.shared
    private let conflictManager = ConflictManager.shared

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
        openDatabase()
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
        sqlite3_close(db)
        db = nil
    }

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        guard let db = db else {
            completionHandler(nil, NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not available"]))
            return Progress()
        }

        let sql = "SELECT * FROM item WHERE id = ?"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            completionHandler(nil, NSError(domain: "Database", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare statement"]))
            return Progress()
        }

        sqlite3_bind_text(stmt, 1, (identifier.rawValue as NSString).utf8String, -1, nil)

        var item: FileProviderItem?
        if sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 3))
            let mimeType = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let size = sqlite3_column_int64(stmt, 5)
            let r2Key = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
            let isDirectory = sqlite3_column_int(stmt, 7) == 1
            let createdAt = String(cString: sqlite3_column_text(stmt, 8))
            let updatedAt = String(cString: sqlite3_column_text(stmt, 9))

            // Determine parent
            let parentId = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let parentIdentifier = parentId.map { NSFileProviderItemIdentifier($0) } ?? .rootContainer

            item = FileProviderItem(
                identifier: identifier,
                parentIdentifier: parentIdentifier,
                filename: name,
                isDirectory: isDirectory,
                size: size,
                mimeType: mimeType,
                r2Key: r2Key,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }

        sqlite3_finalize(stmt)
        completionHandler(item, nil)
        return Progress()
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                guard let db = db else {
                    throw NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
                }

                let sql = "SELECT r2Key, mimeType, name, size, isDirectory FROM item WHERE id = ?"
                var stmt: OpaquePointer?

                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                    throw NSError(domain: "Database", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare statement"])
                }

                sqlite3_bind_text(stmt, 1, (itemIdentifier.rawValue as NSString).utf8String, -1, nil)

                var r2Key: String?
                var mimeType: String?
                var name: String = ""
                var size: Int64 = 0
                var isDirectory: Bool = false

                if sqlite3_step(stmt) == SQLITE_ROW {
                    r2Key = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
                    mimeType = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                    name = String(cString: sqlite3_column_text(stmt, 2))
                    size = sqlite3_column_int64(stmt, 3)
                    isDirectory = sqlite3_column_int(stmt, 4) == 1
                }

                sqlite3_finalize(stmt)

                guard !isDirectory, let r2Key = r2Key else {
                    let item = try await fetchItem(identifier: itemIdentifier)
                    completionHandler(nil, item, nil)
                    return
                }

                let itemId = itemIdentifier.rawValue
                if let cachedURL = CacheManager.shared.getCachedURL(for: itemId) {
                    let item = try await fetchItem(identifier: itemIdentifier)
                    completionHandler(cachedURL, item, nil)
                    return
                }

                let localURL = try await downloadFromR2(r2Key: r2Key, filename: name, itemId: itemId)

                let item = try await fetchItem(identifier: itemIdentifier)
                completionHandler(localURL, item, nil)
            } catch {
                completionHandler(nil, nil, error)
            }
        }

        return progress
    }

    private func downloadFromR2(r2Key: String, filename: String, itemId: String) async throws -> URL {
        let fileManager = FileManager.default
        let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)!
        let cacheDir = containerURL.appendingPathComponent("Library/Caches/com.example.clouddrive", isDirectory: true)
        let localURL = cacheDir.appendingPathComponent("\(itemId)-\(filename)")

        if fileManager.fileExists(atPath: localURL.path) {
            CacheManager.shared.markHydrated(id: itemId, localURL: localURL)
            return localURL
        }

        guard let token = KeychainService.shared.getToken() else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "No auth token"])
        }

        let baseURL = URL(string: "http://localhost:3000")!
        let url = baseURL.appendingPathComponent("/files/\(r2Key)/download")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (tempURL, response) = try await URLSession.shared.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "Download", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to download file"])
        }

        // Download encrypted file data
        let encryptedData = try Data(contentsOf: tempURL)

        // Decrypt file content
        let decryptedData = try EncryptionService.shared.decrypt(data: encryptedData)

        // Write decrypted data to cache
        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }
        try decryptedData.write(to: localURL)

        CacheManager.shared.markHydrated(id: itemId, localURL: localURL)
        return localURL
    }

    func fetchPartialContents(for itemIdentifier: NSFileProviderItemIdentifier, requestedRange: Range<Int64>, originalBaseVersion version: NSFileProviderItemVersion, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                guard let db = db else {
                    throw NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
                }

                let sql = "SELECT r2Key, mimeType, name, size, isDirectory FROM item WHERE id = ?"
                var stmt: OpaquePointer?

                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                    throw NSError(domain: "Database", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare statement"])
                }

                sqlite3_bind_text(stmt, 1, (itemIdentifier.rawValue as NSString).utf8String, -1, nil)

                var r2Key: String?
                var name: String = ""
                var isDirectory: Bool = false

                if sqlite3_step(stmt) == SQLITE_ROW {
                    r2Key = sqlite3_column_text(stmt, 0).map { String(cString: $0) }
                    name = String(cString: sqlite3_column_text(stmt, 2))
                    isDirectory = sqlite3_column_int(stmt, 4) == 1
                }

                sqlite3_finalize(stmt)

                guard !isDirectory, let r2Key = r2Key else {
                    let item = try await fetchItem(identifier: itemIdentifier)
                    completionHandler(nil, item, nil)
                    return
                }

                let itemId = itemIdentifier.rawValue
                if let cachedURL = CacheManager.shared.getCachedURL(for: itemId) {
                    let item = try await fetchItem(identifier: itemIdentifier)
                    completionHandler(cachedURL, item, nil)
                    return
                }

                let localURL = try await downloadPartialFromR2(r2Key: r2Key, filename: name, itemId: itemId, range: requestedRange)
                let item = try await fetchItem(identifier: itemIdentifier)
                completionHandler(localURL, item, nil)
            } catch {
                completionHandler(nil, nil, error)
            }
        }

        return progress
    }

    private func downloadPartialFromR2(r2Key: String, filename: String, itemId: String, range: Range<Int64>) async throws -> URL {
        let fileManager = FileManager.default
        let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)!
        let cacheDir = containerURL.appendingPathComponent("Library/Caches/com.example.clouddrive", isDirectory: true)
        let localURL = cacheDir.appendingPathComponent("\(itemId)-\(filename)")

        if fileManager.fileExists(atPath: localURL.path) {
            CacheManager.shared.markHydrated(id: itemId, localURL: localURL)
            return localURL
        }

        guard let token = KeychainService.shared.getToken() else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "No auth token"])
        }

        let baseURL = URL(string: "http://localhost:3000")!
        let url = baseURL.appendingPathComponent("/files/\(r2Key)/download")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (httpResponse.statusCode == 200 || httpResponse.statusCode == 206) else {
            throw NSError(domain: "Download", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to download partial file"])
        }

        // Decrypt partial range
        let decryptedData = try EncryptionService.shared.decryptRange(encryptedData: data, range: range)

        try decryptedData.write(to: localURL)
        CacheManager.shared.markHydrated(id: itemId, localURL: localURL)
        return localURL
    }

    private func fetchItem(identifier: NSFileProviderItemIdentifier) async throws -> NSFileProviderItem {
        return try await withCheckedThrowingContinuation { continuation in
            _ = item(for: identifier, request: NSFileProviderRequest()) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let item = item {
                    continuation.resume(returning: item)
                } else {
                    continuation.resume(throwing: NSError(domain: "Item", code: 1, userInfo: [NSLocalizedDescriptionKey: "Item not found"]))
                }
            }
        }
    }

    /// Fetch server version for an item
    private func fetchServerVersion(itemId: String, token: String) async throws -> String {
        let baseURL = URL(string: "http://localhost:3000")!
        let url = baseURL.appendingPathComponent("/items/\(itemId)")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "FetchVersion", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch server version"])
        }

        // Parse the response to get the updatedAt field as version
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let updatedAt = json["updatedAt"] as? String {
            return updatedAt
        }

        throw NSError(domain: "FetchVersion", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
    }

    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                guard let db = db else {
                    throw NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
                }

                // Get auth token
                guard let token = KeychainService.shared.getToken() else {
                    throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "No auth token"])
                }

                // Get parent ID
                let parentId = itemTemplate.parentItemIdentifier == .rootContainer ? nil : itemTemplate.parentItemIdentifier.rawValue

                // Create item via API
                let baseURL = URL(string: "http://localhost:3000")!
                var request = URLRequest(url: baseURL.appendingPathComponent("/items"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                let isDirectory = itemTemplate.contentType == .folder
                let body: [String: Any] = [
                    "name": itemTemplate.filename,
                    "isDirectory": isDirectory,
                    "parentId": parentId as Any
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "Create", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }

                // Handle conflict: item already exists on server (409 Conflict)
                if httpResponse.statusCode == 409 {
                    // Conflict detected - item was created on another device
                    // Record conflict and create conflicted copy
                    let conflict = try conflictManager.recordConflict(
                        itemId: UUID().uuidString, // temporary ID
                        itemName: itemTemplate.filename,
                        type: .create,
                        localVersion: "",
                        serverVersion: "",
                        localData: try? JSONSerialization.data(withJSONObject: body),
                        serverData: data
                    )

                    let conflictedName = conflictManager.conflictedCopyName(for: itemTemplate.filename)

                    // Retry with conflicted name
                    var retryBody = body
                    retryBody["name"] = conflictedName
                    request.httpBody = try JSONSerialization.data(withJSONObject: retryBody)

                    let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                    guard let retryHttpResponse = retryResponse as? HTTPURLResponse, retryHttpResponse.statusCode == 201 else {
                        throw NSError(domain: "Create", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create conflicted copy"])
                    }

                    // Parse created item from retry response
                    guard let json = try JSONSerialization.jsonObject(with: retryData) as? [String: Any],
                          let id = json["id"] as? String,
                          let createdAt = json["createdAt"] as? String,
                          let updatedAt = json["updatedAt"] as? String else {
                        throw NSError(domain: "Create", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
                    }

                    let createdItem = FileProviderItem(
                        identifier: NSFileProviderItemIdentifier(id),
                        parentIdentifier: itemTemplate.parentItemIdentifier,
                        filename: conflictedName,
                        isDirectory: isDirectory,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    )

                    // If contents provided, encrypt and upload them
                    if let contentsURL = url, !isDirectory {
                        let r2Key = json["r2Key"] as? String ?? id
                        try await uploadEncryptedFile(contentsURL: contentsURL, r2Key: r2Key, token: token)
                    }

                    // Mark conflict as resolved with create_copy strategy
                    try conflictManager.resolveConflict(conflictId: conflict.id, resolution: .createCopy)

                    completionHandler(createdItem, fields, false, nil)
                    return
                }

                guard httpResponse.statusCode == 201 else {
                    throw NSError(domain: "Create", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create item"])
                }

                // Parse response to get the created item
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = json["id"] as? String,
                      let createdAt = json["createdAt"] as? String,
                      let updatedAt = json["updatedAt"] as? String else {
                    throw NSError(domain: "Create", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
                }

                let createdItem = FileProviderItem(
                    identifier: NSFileProviderItemIdentifier(id),
                    parentIdentifier: itemTemplate.parentItemIdentifier,
                    filename: itemTemplate.filename,
                    isDirectory: isDirectory,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )

                // If contents provided, encrypt and upload them
                if let contentsURL = url, !isDirectory {
                    let r2Key = json["r2Key"] as? String ?? id
                    try await uploadEncryptedFile(contentsURL: contentsURL, r2Key: r2Key, token: token)
                }

                completionHandler(createdItem, fields, false, nil)
            } catch {
                completionHandler(nil, [], false, error)
            }
        }

        return progress
    }

    private func uploadEncryptedFile(contentsURL: URL, r2Key: String, token: String) async throws {
        let fileManager = FileManager.default
        let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)!
        let cacheDir = containerURL.appendingPathComponent("Library/Caches/com.example.clouddrive", isDirectory: true)
        let localCache = cacheDir.appendingPathComponent("upload-cache-\(UUID().uuidString)")

        // Read original file data
        let originalData = try Data(contentsOf: contentsURL)
        let filename = contentsURL.lastPathComponent

        // Encrypt with header
        let header = EncryptionService.FileHeader()
        let fileHeaderHash = SHA256.hash(data: header.serialize())
        let encryptedData = try EncryptionService.shared.encrypt(
            data: originalData,
            fileHeaderHash: fileHeaderHash,
            isFinalChunk: true
        )

        // Encrypt filename
        let filenameResult = try EncryptionService.shared.encryptFilename(filename)

        // Write to temp cache
        if fileManager.fileExists(atPath: localCache.path) {
            try fileManager.removeItem(at: localCache)
        }
        try encryptedData.write(to: localCache)

        // Upload
        let baseURL = URL(string: "http://localhost:3000")!
        let url = baseURL.appendingPathComponent("/files/\(r2Key)/upload")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = encryptedData

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            try? fileManager.removeItem(at: localCache)
            throw NSError(domain: "Upload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to upload encrypted file"])
        }

        try? fileManager.removeItem(at: localCache)
    }

    private func uploadFile(contentsURL: URL, r2Key: String, token: String) async throws {
        let baseURL = URL(string: "http://localhost:3000")!
        let url = baseURL.appendingPathComponent("/files/\(r2Key)/upload")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Data(contentsOf: contentsURL)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "Upload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to upload file"])
        }
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                guard let db = db else {
                    throw NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
                }

                guard let token = KeychainService.shared.getToken() else {
                    throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "No auth token"])
                }

                let identifier = item.itemIdentifier.rawValue

                // Fetch current server version for conflict detection
                let serverVersion: String
                do {
                    serverVersion = try await fetchServerVersion(itemId: identifier, token: token)
                } catch {
                    // If we can't fetch server version, proceed but log warning
                    print("Warning: Could not fetch server version for conflict detection: \(error)")
                    serverVersion = ""
                }

                // Check for version conflict
                let baseVersionString = String(data: version.contentVersion, encoding: .utf8) ?? ""
                if conflictManager.checkVersionConflict(itemId: identifier, baseVersion: version, serverVersion: serverVersion) {
                    // Version conflict detected - item was modified on another device
                    print("Conflict detected for item \(identifier): base=\(baseVersionString), server=\(serverVersion)")

                    // Record conflict
                    let conflict = try conflictManager.recordConflict(
                        itemId: identifier,
                        itemName: item.filename,
                        type: .modify,
                        localVersion: baseVersionString,
                        serverVersion: serverVersion,
                        localData: try? JSONSerialization.data(withJSONObject: changedFields),
                        serverData: nil // Would need to fetch full server item
                    )

                    // Create conflicted copy automatically
                    let conflictedName = conflictManager.conflictedCopyName(for: item.filename)

                    // Create a new item with the conflicted name containing local changes
                    let baseURL = URL(string: "http://localhost:3000")!
                    var createRequest = URLRequest(url: baseURL.appendingPathComponent("/items"))
                    createRequest.httpMethod = "POST"
                    createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    createRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                    let isDirectory = item.contentType == .folder
                    let parentId = item.parentItemIdentifier == .rootContainer ? nil : item.parentItemIdentifier.rawValue

                    var createBody: [String: Any] = [
                        "name": conflictedName,
                        "isDirectory": isDirectory,
                        "parentId": parentId as Any
                    ]

                    // Include the changed fields
                    if changedFields.contains(.filename) {
                        createBody["name"] = conflictedName // Use conflicted name
                    }

                    createRequest.httpBody = try JSONSerialization.data(withJSONObject: createBody)

                    let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
                    guard let createHttpResponse = createResponse as? HTTPURLResponse, createHttpResponse.statusCode == 201 else {
                        throw NSError(domain: "ConflictCopy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create conflicted copy"])
                    }

                    guard let json = try JSONSerialization.jsonObject(with: createData) as? [String: Any],
                          let newId = json["id"] as? String,
                          let createdAt = json["createdAt"] as? String,
                          let updatedAt = json["updatedAt"] as? String else {
                        throw NSError(domain: "ConflictCopy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
                    }

                    let conflictedItem = FileProviderItem(
                        identifier: NSFileProviderItemIdentifier(newId),
                        parentIdentifier: item.parentItemIdentifier,
                        filename: conflictedName,
                        isDirectory: isDirectory,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    )

                    // If contents changed, encrypt and upload to the new item
                    if let contentsURL = newContents {
                        let r2Key = json["r2Key"] as? String ?? newId
                        try await uploadEncryptedFile(contentsURL: contentsURL, r2Key: r2Key, token: token)
                    }

                    // Mark conflict as resolved with create_copy strategy
                    try conflictManager.resolveConflict(conflictId: conflict.id, resolution: .createCopy)

                    completionHandler(conflictedItem, changedFields, false, nil)
                    return
                }

                var updatedFields: [String: Any] = [:]
                var updatedFileProviderItem: FileProviderItem?

                // Handle name change
                if changedFields.contains(.filename) {
                    updatedFields["name"] = item.filename
                }

                // Handle parent change (move)
                if changedFields.contains(.parentItemIdentifier) {
                    let newParentId = item.parentItemIdentifier == .rootContainer ? nil : item.parentItemIdentifier.rawValue
                    updatedFields["parentId"] = newParentId as Any
                }

                // Update via API with expected version for CAS (Compare-And-Swap)
                if !updatedFields.isEmpty {
                    let baseURL = URL(string: "http://localhost:3000")!
                    var request = URLRequest(url: baseURL.appendingPathComponent("/items/\(identifier)"))
                    request.httpMethod = "PATCH"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                    // Include expected version for CAS
                    if !baseVersionString.isEmpty {
                        updatedFields["expectedVersion"] = baseVersionString
                    }

                    request.httpBody = try JSONSerialization.data(withJSONObject: updatedFields)

                    let (_, response) = try await URLSession.shared.data(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NSError(domain: "Modify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                    }

                    // Handle conflict on update (409 Conflict)
                    if httpResponse.statusCode == 409 {
                        // Version mismatch - conflict detected
                        let serverVer = try await fetchServerVersion(itemId: identifier, token: token)
                        let conflict = try conflictManager.recordConflict(
                            itemId: identifier,
                            itemName: item.filename,
                            type: .modify,
                            localVersion: baseVersionString,
                            serverVersion: serverVer,
                            localData: try? JSONSerialization.data(withJSONObject: updatedFields),
                            serverData: nil
                        )

                        // Create conflicted copy
                        let conflictedName = conflictManager.conflictedCopyName(for: item.filename)

                        var createRequest = URLRequest(url: baseURL.appendingPathComponent("/items"))
                        createRequest.httpMethod = "POST"
                        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        createRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                        let isDirectory = item.contentType == .folder
                        let parentId = item.parentItemIdentifier == .rootContainer ? nil : item.parentItemIdentifier.rawValue

                        var createBody: [String: Any] = [
                            "name": conflictedName,
                            "isDirectory": isDirectory,
                            "parentId": parentId as Any
                        ]
                        createBody["name"] = conflictedName

                        createRequest.httpBody = try JSONSerialization.data(withJSONObject: createBody)

                        let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
                        guard let createHttpResponse = createResponse as? HTTPURLResponse, createHttpResponse.statusCode == 201 else {
                            throw NSError(domain: "ConflictCopy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create conflicted copy"])
                        }

                        guard let json = try JSONSerialization.jsonObject(with: createData) as? [String: Any],
                              let newId = json["id"] as? String,
                              let createdAt = json["createdAt"] as? String,
                              let updatedAt = json["updatedAt"] as? String else {
                            throw NSError(domain: "ConflictCopy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
                        }

                        let conflictedItem = FileProviderItem(
                            identifier: NSFileProviderItemIdentifier(newId),
                            parentIdentifier: item.parentItemIdentifier,
                            filename: conflictedName,
                            isDirectory: isDirectory,
                            createdAt: createdAt,
                            updatedAt: updatedAt
                        )

                        if let contentsURL = newContents {
                            let r2Key = json["r2Key"] as? String ?? newId
                            try await uploadEncryptedFile(contentsURL: contentsURL, r2Key: r2Key, token: token)
                        }

                        try conflictManager.resolveConflict(conflictId: conflict.id, resolution: .createCopy)
                        completionHandler(conflictedItem, changedFields, false, nil)
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw NSError(domain: "Modify", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to modify item"])
                    }
                }

                // Handle content changes
                if let contentsURL = newContents {
                    try await uploadEncryptedFile(contentsURL: contentsURL, r2Key: identifier, token: token)
                }

                // Return updated item
                if let updatedItem = try await fetchItem(identifier: item.itemIdentifier) as? FileProviderItem {
                    updatedFileProviderItem = updatedItem
                }
                completionHandler(updatedFileProviderItem, changedFields, false, nil)
            } catch {
                completionHandler(nil, [], false, error)
            }
        }

        return progress
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                guard let token = KeychainService.shared.getToken() else {
                    throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "No auth token"])
                }

                let itemId = identifier.rawValue

                // Fetch item name for conflict tracking
                var itemName = itemId
                if let db = db {
                    let sql = "SELECT name FROM item WHERE id = ?"
                    var stmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(stmt, 1, (itemId as NSString).utf8String, -1, nil)
                        if sqlite3_step(stmt) == SQLITE_ROW {
                            itemName = String(cString: sqlite3_column_text(stmt, 0))
                        }
                        sqlite3_finalize(stmt)
                    }
                }

                // Fetch server version for conflict detection
                let serverVersion: String
                do {
                    serverVersion = try await fetchServerVersion(itemId: itemId, token: token)
                } catch {
                    print("Warning: Could not fetch server version for delete conflict detection: \(error)")
                    serverVersion = ""
                }

                // Check for version conflict
                let baseVersionString = String(data: version.contentVersion, encoding: .utf8) ?? ""
                if conflictManager.checkVersionConflict(itemId: itemId, baseVersion: version, serverVersion: serverVersion) {
                    // Version conflict detected - item was modified on another device
                    print("Delete conflict detected for item \(itemId): base=\(baseVersionString), server=\(serverVersion)")

                    // Record conflict
                    let conflict = try conflictManager.recordConflict(
                        itemId: itemId,
                        itemName: itemName,
                        type: .delete,
                        localVersion: baseVersionString,
                        serverVersion: serverVersion,
                        localData: nil,
                        serverData: nil
                    )

                    // For delete conflicts, return versionOutOfDate to let Finder handle it
                    completionHandler(conflictManager.versionOutOfDateError())
                    return
                }

                let baseURL = URL(string: "http://localhost:3000")!
                var request = URLRequest(url: baseURL.appendingPathComponent("/items/\(itemId)"))
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                // Include expected version for CAS
                if !baseVersionString.isEmpty {
                    var body: [String: Any] = ["expectedVersion": baseVersionString]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                }

                let (_, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "Delete", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }

                // Handle conflict on delete (409 Conflict)
                if httpResponse.statusCode == 409 {
                    let serverVer = try await fetchServerVersion(itemId: itemId, token: token)
                    let conflict = try conflictManager.recordConflict(
                        itemId: itemId,
                        itemName: itemName,
                        type: .delete,
                        localVersion: baseVersionString,
                        serverVersion: serverVer,
                        localData: nil,
                        serverData: nil
                    )

                    // Return versionOutOfDate for delete conflicts
                    completionHandler(conflictManager.versionOutOfDateError())
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    throw NSError(domain: "Delete", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to delete item"])
                }

                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }

        return progress
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        return FileProviderEnumerator(enumeratedItemIdentifier: containerItemIdentifier)
    }
}