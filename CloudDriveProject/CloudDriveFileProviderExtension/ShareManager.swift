//
//  ShareManager.swift
//  CloudDriveFileProviderExtension
//
//  Created by Garv R Changrani on 11/08/26.
//

import Foundation
import CryptoKit

final class ShareManager {
    static let shared = ShareManager()

    private init() {}

    // MARK: - Share Generation

    /// Creates a share link with embedded decryption key
    /// - Parameters:
    ///   - itemId: The file identifier to share
    ///   - fileDEK: The file's data encryption key
    ///   - accessType: Access control type ('public', 'password', 'users')
    ///   - expiresAt: Optional expiration date
    ///   - password: Optional password for password-protected shares
    /// - Returns: Share link string
    func generateShareLink(
        itemId: String,
        fileDEK: SymmetricKey,
        accessType: ShareAccessType = .public,
        expiresAt: Date? = nil,
        password: String? = nil
    ) throws -> String {
        // Generate share-specific key
        let shareKey = SymmetricKey(size: .bits256)
        let shareId = UUID().uuidString

        // Wrap file DEK with share key
        let wrappedDEK = wrapDEK(fileDEK, withKey: shareKey, shareId: shareId)

        // Calculate expiration timestamp
        let expiresTimestamp = expiresAt?.timeIntervalSince1970

        // Store share metadata (in real app, this would call backend API)
        let shareMetadata = ShareMetadata(
            shareId: shareId,
            itemId: itemId,
            wrappedDEK: wrappedDEK,
            accessType: accessType,
            passwordHash: password.map { hashPassword($0) },
            expiresAt: expiresAt
        )

        // Encode share key for URL
        let base64Key = shareKey.dataRepresentation.base64EncodedString()

        // Generate share link
        var linkComponents = URLComponents()
        linkComponents.scheme = "https"
        linkComponents.host = "clouddrive.app"
        linkComponents.path = "/share/\(shareId)"
        linkComponents.queryItems = [
            URLQueryItem(name: "key", value: base64Key)
        ]

        guard let url = linkComponents.url else {
            throw ShareError.invalidURL
        }

        return url.absoluteString
    }

    /// Wraps a file DEK with a share-specific key
    /// - Parameters:
    ///   - dek: The file's data encryption key
    ///   - shareKey: The share-specific key
    ///   - shareId: The share identifier for AAD
    /// - Returns: Base64 encoded wrapped DEK
    private func wrapDEK(_ dek: SymmetricKey, withKey shareKey: SymmetricKey, shareId: String) -> String {
        let sealedBox = try! AES.GCM.seal(
            dek.dataRepresentation,
            using: shareKey,
            nonce: AES.GCM.Nonce()
        )
        let combined = sealedBox.nonce + sealedBox.ciphertext + sealedBox.tag
        return combined.base64EncodedString()
    }

    /// Unwraps DEK using share key
    /// - Parameters:
    ///   - wrappedDEK: The wrapped DEK from database
    ///   - shareKey: The share key from URL
    /// - Returns: Unwrapped DEK
    private func unwrapDEK(_ wrappedDEK: String, withKey shareKey: SymmetricKey) throws -> SymmetricKey {
        guard let combinedData = Data(base64Encoded: wrappedDEK) else {
            throw ShareError.decryptionFailed
        }

        guard combinedData.count >= 28 else { // 12 byte nonce + 16 byte tag
            throw ShareError.decryptionFailed
        }

        let nonceData = combinedData.prefix(12)
        let remaining = combinedData.dropFirst(12)
        let tag = remaining.suffix(16)
        let ciphertext = remaining.dropLast(16)

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )

        let dekData = try AES.GCM.open(sealedBox, using: shareKey)
        return SymmetricKey(data: dekData)
    }

    // MARK: - Share Verification

    /// Verifies share access and returns decryption key
    /// - Parameters:
    ///   - shareId: The share identifier
    ///   - shareKey: Base64 encoded share key from URL
    ///   - password: Optional password for password-protected shares
    /// - Returns: Decrypted file DEK
    func verifyShareAccess(
        shareId: String,
        shareKey: String,
        password: String? = nil
    ) async throws -> SymmetricKey {
        // Fetch share metadata from backend (in real app)
        // This is a placeholder implementation
        let shareMetadata = try await fetchShareMetadata(shareId: shareId)

        // Check expiration
        if let expiresAt = shareMetadata.expiresAt, Date() > expiresAt {
            throw ShareError.expired
        }

        // Verify access type
        switch shareMetadata.accessType {
        case .public:
            break // No additional checks

        case .password:
            guard let passwordHash = shareMetadata.passwordHash else {
                throw ShareError.invalidShare
            }
            guard let providedPassword = password else {
                throw ShareError.passwordRequired
            }
            guard verifyPassword(providedPassword, hash: passwordHash) else {
                throw ShareError.invalidPassword
            }

        case .users:
            throw ShareError.unauthorized // User-specific access not implemented in basic version
        }

        // Decode share key
        guard let shareKeyData = Data(base64Encoded: shareKey) else {
            throw ShareError.invalidKeyFormat
        }
        let shareKeyObj = SymmetricKey(data: shareKeyData)

        // Unwrap DEK
        let dek = try unwrapDEK(shareMetadata.wrappedDEK, withKey: shareKeyObj)
        return dek
    }

    /// Fetches share metadata from backend
    /// - Parameter shareId: The share identifier
    /// - Returns: Share metadata
    private func fetchShareMetadata(shareId: String) async throws -> ShareMetadata {
        // This would call the backend API in a real implementation
        // For now, return a placeholder
        // TODO: Implement actual API call
        throw ShareError.shareNotFound
    }

    // MARK: - Share Revocation

    /// Revokes a share, making it inaccessible
    /// - Parameter shareId: The share identifier to revoke
    func revokeShare(shareId: String) async throws {
        // Call backend to delete share
        // TODO: Implement API call to DELETE /shares/{shareId}
        throw ShareError.revokeFailed
    }

    // MARK: - Helper Methods

    private func hashPassword(_ password: String) -> String {
        let data = Data(password.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
    }

    private func verifyPassword(_ password: String, hash: String) -> Bool {
        let hashedInput = hashPassword(password)
        return hashedInput == hash
    }
}

// MARK: - Models

enum ShareAccessType: String, Codable {
    case `public` = "public"
    case password = "password"
    case users = "users"
}

struct ShareMetadata {
    let shareId: String
    let itemId: String
    let wrappedDEK: String
    let accessType: ShareAccessType
    let passwordHash: String?
    let expiresAt: Date?

    init(
        shareId: String,
        itemId: String,
        wrappedDEK: String,
        accessType: ShareAccessType,
        passwordHash: String?,
        expiresAt: Date?
    ) {
        self.shareId = shareId
        self.itemId = itemId
        self.wrappedDEK = wrappedDEK
        self.accessType = accessType
        self.passwordHash = passwordHash
        self.expiresAt = expiresAt
    }
}

// MARK: - Errors

enum ShareError: Error {
    case invalidURL
    case decryptionFailed
    case shareNotFound
    case expired
    case invalidShare
    case passwordRequired
    case invalidPassword
    case unauthorized
    case invalidKeyFormat
    case revokeFailed

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid share URL"
        case .decryptionFailed:
            return "Failed to decrypt share key"
        case .shareNotFound:
            return "Share not found"
        case .expired:
            return "Share link has expired"
        case .invalidShare:
            return "Invalid share configuration"
        case .passwordRequired:
            return "Password required for this share"
        case .invalidPassword:
            return "Invalid password"
        case .unauthorized:
            return "Unauthorized access"
        case .invalidKeyFormat:
            return "Invalid key format"
        case .revokeFailed:
            return "Failed to revoke share"
        }
    }
}
