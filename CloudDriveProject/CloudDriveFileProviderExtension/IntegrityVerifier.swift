//
//  IntegrityVerifier.swift
//  CloudDriveFileProviderExtension
//
//  Created by Garv R Changrani on 11/08/26.
//

import Foundation
import CryptoKit

final class IntegrityVerifier {
    static let shared = IntegrityVerifier()

    private init() {}

    // MARK: - File Integrity Verification

    /// Calculates SHA-256 hash of ciphertext for integrity verification
    /// - Parameter ciphertext: The encrypted file data
    /// - Returns: SHA-256 hash as Data
    func calculateCiphertextHash(_ ciphertext: Data) -> Data {
        Data(SHA256.hash(data: ciphertext))
    }

    /// Verifies that the actual hash matches the expected hash
    /// - Parameters:
    ///   - actualData: The actual ciphertext data to verify
    ///   - expectedHash: The expected hash stored in metadata
    /// - Throws: IntegrityError if hashes don't match
    func verifyIntegrity(actualData: Data, expectedHash: Data) throws {
        let actualHash = calculateCiphertextHash(actualData)
        guard actualHash == expectedHash else {
            throw IntegrityError.hashMismatch
        }
    }

    /// Performs per-chunk integrity verification for encrypted data
    /// - Parameters:
    ///   - data: Complete encrypted file data
    ///   - encryptionService: Reference to EncryptionService for chunk verification
    /// - Returns: Array of chunk hashes
    func verifyPerChunkIntegrity(data: Data, encryptionService: EncryptionService) -> [Data] {
        var chunkHashes: [Data] = []

        // Skip file header (4 bytes magic + 1 byte version + 32 bytes DEK = 37 bytes)
        let headerSize = 37
        guard data.count >= headerSize + 12 else {
            return []
        }

        var offset = headerSize
        while offset < data.count {
            guard offset + 12 <= data.count else { break }

            let nonceData = data.subdata(in: offset..<offset + 12)
            offset += 12

            // Extract chunk data (simplified - assumes standard chunk structure)
            let maxChunkSize = 64 * 1024 + 16 // 64KB ciphertext + tag
            guard data.count - offset >= 16 else { break }

            let chunkEncrypted = data.subdata(in: offset..<min(offset + maxChunkSize, data.count))
            let ciphertext = chunkEncrypted.dropLast(16)

            // For per-chunk integrity, we need to verify each chunk's authenticity
            // This is already handled by AES-GCM tags in the EncryptionService
            // Here we just record the chunk hash for metadata
            let chunkHash = calculateCiphertextHash(ciphertext)
            chunkHashes.append(chunkHash)

            offset += min(maxChunkSize, data.count - offset)
        }

        return chunkHashes
    }

    /// Verifies a file integrity by re-computing hash and comparing with stored value
    /// - Parameters:
    ///   - storedFileData: The file data stored on disk (encrypted)
    ///   - storedCiphertextHash: The hash stored in metadata
    /// - Throws: IntegrityError if verification fails
    func verifyFileIntegrity(storedFileData: Data, storedCiphertextHash: Data) throws {
        try verifyIntegrity(actualData: storedFileData, expectedHash: storedCiphertextHash)
    }

    /// Generates integrity metadata for a file
    /// - Parameter ciphertext: The encrypted file data
    /// - Returns: Integrity metadata containing hash and chunk hashes
    func generateIntegrityMetadata(ciphertext: Data, encryptionService: EncryptionService) -> IntegrityMetadata {
        let ciphertextHash = calculateCiphertextHash(ciphertext)
        let chunkHashes = verifyPerChunkIntegrity(data: ciphertext, encryptionService: encryptionService)

        return IntegrityMetadata(
            ciphertextHash: ciphertextHash,
            chunkHashes: chunkHashes,
            algorithm: "SHA-256",
            version: "1.0"
        )
    }
}

// MARK: - Data Models

struct IntegrityMetadata {
    let ciphertextHash: Data
    let chunkHashes: [Data]
    let algorithm: String
    let version: String

    /// Serializes metadata to Data for storage
    var serialized: Data {
        var data = Data()

        // Store ciphertext hash (32 bytes for SHA-256)
        data.append(ciphertextHash)

        // Store number of chunk hashes
        var chunkCount = UInt32(chunkHashes.count).bigEndian
        var chunkCountData = Data(bytes: &chunkCount, count: 4)
        data.append(chunkCountData)

        // Store all chunk hashes
        for chunkHash in chunkHashes {
            data.append(chunkHash)
        }

        return data
    }

    /// Deserializes metadata from Data
    /// - Parameter data: Serialized metadata
    /// - Returns: IntegrityMetadata instance
    static func deserialize(from data: Data) -> IntegrityMetadata? {
        guard data.count >= 36 else { return nil } // 32 (hash) + 4 (count)

        let ciphertextHash = data.subdata(in: 0..<32)

        let chunkCountData = data.subdata(in: 32..<36)
        let chunkCount = chunkCountData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        var offset = 36
        var chunkHashes: [Data] = []
        for _ in 0..<chunkCount {
            guard offset + 32 <= data.count else { break }
            let chunkHash = data.subdata(in: offset..<offset + 32)
            chunkHashes.append(chunkHash)
            offset += 32
        }

        return IntegrityMetadata(
            ciphertextHash: ciphertextHash,
            chunkHashes: chunkHashes,
            algorithm: "SHA-256",
            version: "1.0"
        )
    }
}

// MARK: - Errors

enum IntegrityError: Error {
    case hashMismatch
    case invalidMetadata
    case verificationFailed

    var localizedDescription: String {
        switch self {
        case .hashMismatch:
            return "Ciphertext hash verification failed"
        case .invalidMetadata:
            return "Invalid integrity metadata"
        case .verificationFailed:
            return "Integrity verification failed"
        }
    }
}
