import FileProvider
import Foundation
import os.log

final class CloudDriveFileProvider: NSObject, NSFileProviderReplicatedExtension {
    private let logger = OSLog(subsystem: "com.example.clouddrive", category: "FileProvider")

    func itemForIdentifier(_ itemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        os_log("itemForIdentifier called", log: logger, type: .debug)
        let item = CloudDriveItem(identifier: itemIdentifier, parentIdentifier: .rootContainerIdentifier, filename: "Demo", type: .directory)
        completionHandler(item, nil)
        return Progress(totalUnitCount: 0)
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        os_log("fetchContents called for %{public}@", log: logger, type: .debug, itemIdentifier.rawValue)
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: Data(), attributes: nil)
        let item = CloudDriveItem(identifier: itemIdentifier, parentIdentifier: .rootContainerIdentifier, filename: "file.txt", type: .file)
        completionHandler(tempURL, item, nil)
        return Progress(totalUnitCount: 0)
    }

    func createItem(basedOn templateItem: NSFileProviderItem, fields fieldSet: NSFileProviderItemFields, contents contentsURL: URL?, options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        os_log("createItem called", log: logger, type: .debug)
        let newIdentifier = NSFileProviderItemIdentifier(UUID().uuidString)
        let item = CloudDriveItem(identifier: newIdentifier, parentIdentifier: templateItem.parentItemIdentifier, filename: templateItem.displayName ?? "new", type: .directory)
        completionHandler(item, fieldSet, false, nil)
        return Progress(totalUnitCount: 0)
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields fieldSet: NSFileProviderItemFields, contents newContentsURL: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        os_log("modifyItem called", log: logger, type: .debug)
        completionHandler(item, .init(), false, nil)
        return Progress(totalUnitCount: 0)
    }

    func deleteItem(withIdentifier itemIdentifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        os_log("deleteItem called", log: logger, type: .debug)
        completionHandler(nil)
        return Progress(totalUnitCount: 0)
    }

    func fetchPartialContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion, request: NSFileProviderRequest, minimalRange range: NSRange, aligningTo alignment: Int, options: NSFileProviderFetchContentsOptions, completionHandler: @escaping (URL?, NSFileProviderItem?, NSRange, NSFileProviderMaterializationFlags, Error?) -> Void) -> Progress {
        os_log("fetchPartialContents called", log: logger, type: .debug)
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempURL.path, contents: Data(), attributes: nil)
        let item = CloudDriveItem(identifier: itemIdentifier, parentIdentifier: .rootContainerIdentifier, filename: "partial", type: .file)
        completionHandler(tempURL, item, range, [], nil)
        return Progress(totalUnitCount: 0)
    }
}

enum ItemType { case file, directory }

class CloudDriveItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let type: ItemType

    init(identifier: NSFileProviderItemIdentifier, parentIdentifier: NSFileProviderItemIdentifier, filename: String, type: ItemType) {
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parentIdentifier
        self.filename = filename
        self.type = type
    }

    var displayName: String { filename }
    var itemCapabilities: NSFileProviderItemCapabilities { .allowsReading }
    var parentItemIdentifierValue: NSFileProviderItemIdentifier { parentItemIdentifier }
}
