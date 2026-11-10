import Foundation

public struct AuthResponse: Codable {
    public let token: String
}

public struct UserProfile: Codable {
    public let id: String
    public let email: String
}

public struct ItemListResponse: Codable {
    public let folders: [FolderDTO]
    public let files: [FileDTO]
}

public struct FolderDTO: Codable, Identifiable {
    public let id: String
    public let userId: String
    public let parentId: String?
    public let name: String
    public let createdAt: String
    public let updatedAt: String
}

public struct FileDTO: Codable, Identifiable {
    public let id: String
    public let userId: String
    public let folderId: String?
    public let name: String
    public let mimeType: String
    public let size: Int64
    public let r2Key: String?
    public let createdAt: String
    public let updatedAt: String
}
