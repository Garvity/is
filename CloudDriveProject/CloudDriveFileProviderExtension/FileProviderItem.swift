//
//  FileProviderItem.swift
//  CloudDriveFileProviderExtension
//
//  Created by Garv R Changrani on 06/11/26.
//

import FileProvider
import UniformTypeIdentifiers

class FileProviderItem: NSObject, NSFileProviderItem {

    private let _itemIdentifier: NSFileProviderItemIdentifier
    private let _parentItemIdentifier: NSFileProviderItemIdentifier
    private let _filename: String
    private let _isDirectory: Bool
    private let _size: Int64
    private let _mimeType: String?
    private let _r2Key: String?
    private let _createdAt: String
    private let _updatedAt: String
    private let _contentType: UTType
    private let _itemVersion: NSFileProviderItemVersion

    init(
        identifier: NSFileProviderItemIdentifier,
        parentIdentifier: NSFileProviderItemIdentifier,
        filename: String,
        isDirectory: Bool,
        size: Int64 = 0,
        mimeType: String? = nil,
        r2Key: String? = nil,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self._itemIdentifier = identifier
        self._parentItemIdentifier = parentIdentifier
        self._filename = filename
        self._isDirectory = isDirectory
        self._size = size
        self._mimeType = mimeType
        self._r2Key = r2Key
        self._createdAt = createdAt
        self._updatedAt = updatedAt

        // Determine content type
        if isDirectory {
            self._contentType = .folder
        } else if let mimeType = mimeType, let utType = UTType(mimeType: mimeType) {
            self._contentType = utType
        } else {
            self._contentType = .data
        }

        // Create version from updatedAt
        let versionData = updatedAt.data(using: .utf8) ?? Data()
        self._itemVersion = NSFileProviderItemVersion(contentVersion: versionData, metadataVersion: versionData)

        super.init()
    }

    // Convenience initializer for placeholder items
    convenience init(identifier: NSFileProviderItemIdentifier) {
        self.init(
            identifier: identifier,
            parentIdentifier: .rootContainer,
            filename: identifier.rawValue,
            isDirectory: identifier == .rootContainer
        )
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        return _itemIdentifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        return _parentItemIdentifier
    }

    var capabilities: NSFileProviderItemCapabilities {
        var caps: NSFileProviderItemCapabilities = [.allowsReading, .allowsRenaming, .allowsTrashing, .allowsDeleting]
        if !_isDirectory {
            caps.insert(.allowsReading)
            caps.insert(.allowsWriting)
        }
        caps.insert(.allowsReparenting)
        return caps
    }

    var itemVersion: NSFileProviderItemVersion {
        return _itemVersion
    }

    var filename: String {
        return _filename
    }

    var contentType: UTType {
        return _contentType
    }

    var isDirectory: Bool {
        return _isDirectory
    }

    // Additional properties for our internal use
    var size: Int64 {
        return _size
    }

    var mimeType: String? {
        return _mimeType
    }

    var r2Key: String? {
        return _r2Key
    }

    var createdAt: String {
        return _createdAt
    }

    var updatedAt: String {
        return _updatedAt
    }
}