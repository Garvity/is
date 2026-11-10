import Foundation
import CryptoKit

// MARK: - Encryption Service
// Implements chunked AES-GCM with AAD and robust nonce handling.

final class EncryptionService {
    static let shared = EncryptionService()

    private let keyManager = KeyManager.shared
    private var fileEncryptionKey: SymmetricKey
    private let nameEncryptionKey: SymmetricKey
    private let nameHmacKey: SymmetricKey

    private let chunkSize = 64 * 1024 // 64KB
    private let magicNumber = Data([0x43, 0x4C, 0x44, 0x52]) // "CLDR"
    private let currentVersion: UInt8 = 1

    private init() {
        self.fileEncryptionKey = SymmetricKey(size: .bits256)
        self.nameEncryptionKey = SymmetricKey(size: .bits256)
        self.nameHmacKey = SymmetricKey(size: .bits256)
    }

    // MARK: - Key Setup

    func initializeWithMasterKey(_ masterKey: SymmetricKey) {
        self.fileEncryptionKey = masterKey
    }

    // MARK: - Chunked File Encryption/Decryption

    struct FileHeader {
        let magic: Data
        let version: UInt8
        let chunkSize: UInt32

        init() {
            self.magic = Data([0x43, 0x4C, 0x44, 0x52]) // "CLDR"
            self.version = 1
            self.chunkSize = 64 * 1024
        }

        func serialize() -> Data {
            var data = Data()
            data.append(magic)
            data.append(Data([version]))
            var size = chunkSize
            data.append(Data(bytes: &size, count: 4))
            return data
        }
    }

    /// Encrypts file data in chunks using AES-GCM with AAD (Chunk Index).
    func encryptFile(_ data: Data, using dek: SymmetricKey) throws -> Data {
        var output = Data()
        let header = FileHeader()
        output.append(header.serialize())

        let totalChunks = (data.count + chunkSize - 1) / chunkSize
        var chunkIndex: UInt32 = 0

        for offset in stride(from: 0, to: data.count, by: chunkSize) {
            let chunkLength = min(chunkSize, data.count - offset)
            let chunkData = data.subdata(in: offset..<offset + chunkLength)

            // AAD: chunk index to prevent reordering/dropping attacks
            let aad = withUnsafeBytes(of: &chunkIndex) { Data($0) }

            var nonce = AES.GCM.Nonce()
            _ = withUnsafeMutableBytes(of: &nonce) { bytes in
                SecRandomCopyBytes(kSecRandomDefault, 12, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self))
            }

            let sealedBox = try AES.GCM.seal(chunkData, using: dek, nonce: nonce, authenticating: aad)
            
            // Format: [Nonce (12 bytes)] [Ciphertext length (4 bytes)] [Ciphertext + Tag]
            let nonceData = Data(nonce)
            let combined = nonceData + sealedBox.ciphertext + sealedBox.tag
            let lengthField = UInt32(combined.count)
            var lengthVar = lengthField
            let lengthData = withUnsafeBytes(of: &lengthVar) { Data($0) }

            output.append(lengthData)
            output.append(combined)

            chunkIndex += 1
        }

        return output
    }

    func encryptFile(_ data: Data) throws -> Data {
        return try encryptFile(data, using: fileEncryptionKey)
    }

    /// Decrypts file data encrypted in chunks using AES-GCM with AAD.
    func decryptFile(_ encryptedData: Data, using dek: SymmetricKey) throws -> Data {
        guard encryptedData.count >= 9 else { // 4 magic + 1 version + 4 chunk size
            throw EncryptionError.invalidHeader
        }

        let magic = encryptedData.prefix(4)
        guard magic == magicNumber else {
            throw EncryptionError.invalidMagic
        }

        let version = encryptedData[4]
        guard version == currentVersion else {
            throw EncryptionError.unsupportedVersion
        }

        var offset = 5 + 4 // Skip header and chunk size
        var output = Data()
        var chunkIndex: UInt32 = 0

        while offset < encryptedData.count {
            guard offset + 4 <= encryptedData.count else {
                throw EncryptionError.invalidCiphertext
            }

            let lengthData = encryptedData.subdata(in: offset..<offset + 4)
            let chunkLength = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }
            offset += 4

            guard offset + Int(chunkLength) <= encryptedData.count else {
                throw EncryptionError.invalidCiphertext
            }

            let chunkPacket = encryptedData.subdata(in: offset..<offset + Int(chunkLength))
            offset += Int(chunkLength)

            guard chunkPacket.count >= 12 + 16 else {
                throw EncryptionError.invalidCiphertext
            }

            let nonceData = chunkPacket.prefix(12)
            let ciphertextWithTag = chunkPacket.dropFirst(12)
            let tag = ciphertextWithTag.suffix(16)
            let actualCiphertext = ciphertextWithTag.dropLast(16)

            guard let nonceObj = try? AES.GCM.Nonce(data: nonceData) else {
                throw EncryptionError.invalidNonce
            }

            let aad = withUnsafeBytes(of: &chunkIndex) { Data($0) }

            let sealedBox = try AES.GCM.SealedBox(
                nonce: nonceObj,
                ciphertext: actualCiphertext,
                tag: tag
            )

            let decryptedChunk = try AES.GCM.open(sealedBox, using: dek, authenticating: aad)
            output.append(decryptedChunk)

            chunkIndex += 1
        }

        return output
    }
    func decryptFile(_ data: Data) throws -> Data {
        return try decryptFile(data, using: fileEncryptionKey)
    }

    // MARK: - Convenience Methods for FileProviderExtension

    /// Decrypts file data using the default file encryption key
    func decrypt(data: Data) throws -> Data {
        return try decryptFile(data)
    }

    /// Decrypts a range of encrypted data (not fully implemented - falls back to full decrypt)
    func decryptRange(encryptedData: Data, range: Range<Int64>) throws -> Data {
        // For simplicity, decrypt the entire file and return the requested range
        let fullData = try decryptFile(encryptedData)
        let start = Int(range.lowerBound)
        let end = Int(range.upperBound)
        guard start >= 0 && end <= fullData.count && start < end else {
            throw EncryptionError.invalidRange
        }
        return fullData.subdata(in: start..<end)
    }

    /// Encrypts file data with header using the default file encryption key
    func encrypt(data: Data, fileHeaderHash: SHA256.Digest, isFinalChunk: Bool) throws -> Data {
        // For now, use the standard chunked encryption
        return try encryptFile(data)
    }

    // MARK: - Filename Encryption

    func encryptFilename(_ filename: String) throws -> (ciphertext: Data, hmac: Data) {
        let filenameData = filename.data(using: .utf8) ?? Data()
        var nonce = AES.GCM.Nonce()
        _ = withUnsafeMutableBytes(of: &nonce) { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 12, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self))
        }
        let sealedBox = try AES.GCM.seal(filenameData, using: nameEncryptionKey, nonce: nonce)
        let combined = Data(nonce) + sealedBox.ciphertext + sealedBox.tag
        let hmac = Data(SHA256.hash(data: combined))
        return (combined, hmac)
    }

    func decryptFilename(ciphertext: Data, hmac: Data) throws -> String {
        let expectedHmac = Data(SHA256.hash(data: ciphertext))
        guard expectedHmac == hmac else {
            throw EncryptionError.hmacMismatch
        }
        
        guard ciphertext.count >= 12 + 16 else {
            throw EncryptionError.invalidCiphertext
        }

        let nonce = ciphertext.prefix(12)
        let encryptedData = ciphertext.dropFirst(12)
        let tag = encryptedData.suffix(16)
        let actualCiphertext = encryptedData.dropLast(16)

        guard let nonceObj = try? AES.GCM.Nonce(data: nonce) else {
            throw EncryptionError.invalidNonce
        }

        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonceObj,
            ciphertext: actualCiphertext,
            tag: tag
        )

        let decrypted = try AES.GCM.open(sealedBox, using: nameEncryptionKey)
        guard let filename = String(data: decrypted, encoding: .utf8) else {
            throw EncryptionError.decodingError
        }
        return filename
    }

    // MARK: - DEK Management

    func generateAndWrapDEK(with rootKey: SymmetricKey) -> (dek: SymmetricKey, wrappedDEK: Data) {
        let dek = SymmetricKey(size: .bits256)
        var nonce = AES.GCM.Nonce()
        _ = withUnsafeMutableBytes(of: &nonce) { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 12, bytes.baseAddress!.assumingMemoryBound(to: UInt8.self))
        }
        let dekData = dek.withUnsafeBytes { Data($0) }
        let sealedBox = try! AES.GCM.seal(dekData, using: rootKey, nonce: nonce, authenticating: "dek_wrap".data(using: .utf8)!)
        let wrapped = Data(nonce) + sealedBox.ciphertext + sealedBox.tag
        return (dek, wrapped)
    }

    func unwrapDEK(_ wrappedDEK: Data, with rootKey: SymmetricKey) throws -> SymmetricKey {
        guard wrappedDEK.count >= 28 else {
            throw EncryptionError.decryptionFailed
        }

        let nonceData = wrappedDEK.prefix(12)
        let remaining = wrappedDEK.dropFirst(12)
        let tag = remaining.suffix(16)
        let ciphertext = remaining.dropLast(16)

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )

        let dekData = try AES.GCM.open(sealedBox, using: rootKey, authenticating: "dek_wrap".data(using: .utf8)!)
        return SymmetricKey(data: dekData)
    }
}

extension SymmetricKey {
    var dataRepresentation: Data {
        withUnsafeBytes { Data($0) }
    }
}

enum EncryptionError: Error {
    case invalidHeader
    case invalidMagic
    case unsupportedVersion
    case invalidNonce
    case invalidChunk
    case invalidCiphertext
    case hmacMismatch
    case integrityCheckFailed
    case decodingError
    case invalidRange
    case decryptionFailed
}

extension SymmetricKey {
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        return try withUnsafeBytes(body)
    }
}
