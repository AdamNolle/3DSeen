import CryptoKit
import Foundation

/// Encrypts transferred files in bounded chunks so scan archives never need to fit in memory.
public enum HandoffResourceCipher {
    private static let magic = Data("3DSeenR3".utf8)
    private static let nonceByteCount = 12
    private static let tagByteCount = 16
    private static let chunkByteCount = 1_048_576
    private static let headerByteCount = 8 + nonceByteCount + 8 + 4
    private static let maximumPlaintextBytes = UInt64(HandoffResourceAdmissionPolicy.maximumResourceBytes - 1_048_576)

    public static func encrypt(_ sourceURL: URL, to destinationURL: URL, secret: Data) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let sizeNumber = attributes[.size] as? NSNumber else {
            throw HandoffResourceCipherError.invalidFile
        }
        let plaintextByteCount = sizeNumber.uint64Value
        guard plaintextByteCount <= maximumPlaintextBytes else {
            throw HandoffResourceCipherError.resourceTooLarge
        }

        let baseNonce = try HandoffAuthenticator.makeNonce().prefix(nonceByteCount)
        var header = magic
        header.append(contentsOf: baseNonce)
        header.append(integerBytes(plaintextByteCount))
        header.append(integerBytes(UInt32(chunkByteCount)))

        try prepareDestination(destinationURL)
        var completed = false
        defer {
            if !completed { try? FileManager.default.removeItem(at: destinationURL) }
        }

        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? input.close()
            try? output.close()
        }
        try output.write(contentsOf: header)

        let key = encryptionKey(secret: secret)
        var bytesRemaining = plaintextByteCount
        var chunkIndex: UInt64 = 0
        while bytesRemaining > 0 {
            let expectedCount = Int(min(UInt64(chunkByteCount), bytesRemaining))
            let plaintext = try readExactly(expectedCount, from: input)
            let nonce = try chunkNonce(baseNonce: Data(baseNonce), index: chunkIndex, key: key)
            let sealed = try ChaChaPoly.seal(
                plaintext,
                using: key,
                nonce: nonce,
                authenticating: associatedData(header: header, index: chunkIndex, byteCount: expectedCount, final: false)
            )
            try output.write(contentsOf: sealed.ciphertext)
            try output.write(contentsOf: sealed.tag)
            bytesRemaining -= UInt64(expectedCount)
            chunkIndex += 1
        }

        let finalNonce = try chunkNonce(baseNonce: Data(baseNonce), index: chunkIndex, key: key)
        let finalTag = try ChaChaPoly.seal(
            Data(),
            using: key,
            nonce: finalNonce,
            authenticating: associatedData(header: header, index: chunkIndex, byteCount: 0, final: true)
        )
        try output.write(contentsOf: finalTag.tag)
        try output.synchronize()
        completed = true
    }

    public static func decrypt(_ sourceURL: URL, to destinationURL: URL, secret: Data) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let sizeNumber = attributes[.size] as? NSNumber,
              !HandoffResourceAdmissionPolicy.exceedsSizeLimit(sizeNumber.int64Value) else {
            throw HandoffResourceCipherError.invalidFile
        }
        try prepareDestination(destinationURL)
        var completed = false
        defer {
            if !completed { try? FileManager.default.removeItem(at: destinationURL) }
        }

        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: destinationURL)
        defer {
            try? input.close()
            try? output.close()
        }

        let header = try readExactly(headerByteCount, from: input)
        guard header.prefix(magic.count) == magic else {
            throw HandoffResourceCipherError.invalidFile
        }
        let baseNonce = Data(header[8..<(8 + nonceByteCount)])
        let plaintextByteCount = integerValue(header[(8 + nonceByteCount)..<(8 + nonceByteCount + 8)])
        let encodedChunkSize = integerValue(header[(8 + nonceByteCount + 8)..<headerByteCount])
        guard plaintextByteCount <= maximumPlaintextBytes,
              encodedChunkSize == UInt64(chunkByteCount) else {
            throw HandoffResourceCipherError.invalidFile
        }

        let key = encryptionKey(secret: secret)
        var bytesRemaining = plaintextByteCount
        var chunkIndex: UInt64 = 0
        while bytesRemaining > 0 {
            let expectedCount = Int(min(UInt64(chunkByteCount), bytesRemaining))
            let encrypted = try readExactly(expectedCount + tagByteCount, from: input)
            let nonce = try chunkNonce(baseNonce: baseNonce, index: chunkIndex, key: key)
            let sealed = try ChaChaPoly.SealedBox(
                nonce: nonce,
                ciphertext: encrypted.prefix(expectedCount),
                tag: encrypted.suffix(tagByteCount)
            )
            let plaintext = try ChaChaPoly.open(
                sealed,
                using: key,
                authenticating: associatedData(header: header, index: chunkIndex, byteCount: expectedCount, final: false)
            )
            try output.write(contentsOf: plaintext)
            bytesRemaining -= UInt64(expectedCount)
            chunkIndex += 1
        }

        let finalTag = try readExactly(tagByteCount, from: input)
        let finalNonce = try chunkNonce(baseNonce: baseNonce, index: chunkIndex, key: key)
        let finalBox = try ChaChaPoly.SealedBox(nonce: finalNonce, ciphertext: Data(), tag: finalTag)
        _ = try ChaChaPoly.open(
            finalBox,
            using: key,
            authenticating: associatedData(header: header, index: chunkIndex, byteCount: 0, final: true)
        )
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else {
            throw HandoffResourceCipherError.invalidFile
        }
        try output.synchronize()
        completed = true
    }

    private static func prepareDestination(_ url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw HandoffResourceCipherError.invalidFile
        }
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw HandoffResourceCipherError.invalidFile
        }
    }

    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            guard let next = try handle.read(upToCount: count - result.count), !next.isEmpty else {
                throw HandoffResourceCipherError.invalidFile
            }
            result.append(next)
        }
        return result
    }

    private static func encryptionKey(secret: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret),
            salt: Data("3DSeen-resource-v3".utf8),
            info: Data("ChaChaPoly chunked file".utf8),
            outputByteCount: 32
        )
    }

    private static func chunkNonce(baseNonce: Data, index: UInt64, key: SymmetricKey) throws -> ChaChaPoly.Nonce {
        var input = baseNonce
        input.append(integerBytes(index))
        let digest = HMAC<SHA256>.authenticationCode(for: input, using: key)
        return try ChaChaPoly.Nonce(data: Data(digest.prefix(nonceByteCount)))
    }

    private static func associatedData(header: Data, index: UInt64, byteCount: Int, final: Bool) -> Data {
        var data = header
        data.append(Data(final ? "final".utf8 : "chunk".utf8))
        data.append(integerBytes(index))
        data.append(integerBytes(UInt64(byteCount)))
        return data
    }

    private static func integerBytes<T: FixedWidthInteger>(_ value: T) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }

    private static func integerValue(_ bytes: Data.SubSequence) -> UInt64 {
        bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}

public enum HandoffResourceCipherError: LocalizedError {
    case invalidFile
    case resourceTooLarge
    case peerNotPaired
    case transferUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidFile:
            "The encrypted handoff resource is invalid or incomplete."
        case .resourceTooLarge:
            "The handoff resource is too large to encrypt safely."
        case .peerNotPaired:
            "Pair with this device before transferring a scan."
        case .transferUnavailable:
            "The secure handoff transfer could not be started."
        }
    }
}
