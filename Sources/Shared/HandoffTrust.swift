import CryptoKit
import Foundation
import Security

public protocol PairingCredentialStore: AnyObject {
    func secret(for peerID: HandoffInstallationID) throws -> Data?
    func store(secret: Data, for peerID: HandoffInstallationID) throws
    func removeSecret(for peerID: HandoffInstallationID) throws
    func trustedPeerIDs() throws -> Set<HandoffInstallationID>
}

public enum PairingCredentialError: LocalizedError, Equatable {
    case keychain(OSStatus)
    case invalidSecret
    case invalidChallenge

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
        case .invalidSecret:
            return "A pairing secret must contain at least 32 bytes."
        case .invalidChallenge:
            return "The peer sent an invalid key-agreement challenge."
        }
    }
}

public final class KeychainPairingCredentialStore: PairingCredentialStore {
    private let service: String
    private let legacyService: String?

    public init(service: String = "com.adamnolle.3DSeen.handoff-pairing.v3") {
        self.service = service
        legacyService = service == "com.adamnolle.3DSeen.handoff-pairing.v3"
            ? "com.adamnolle.3DSeen.handoff-pairing"
            : nil
    }

    public func secret(for peerID: HandoffInstallationID) throws -> Data? {
        var query = baseQuery(peerID: peerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PairingCredentialError.keychain(status) }
        return result as? Data
    }

    public func store(secret: Data, for peerID: HandoffInstallationID) throws {
        guard secret.count >= 32 else { throw PairingCredentialError.invalidSecret }
        let query = baseQuery(peerID: peerID)
        let attributes: [String: Any] = [kSecValueData as String: secret]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            try deleteLegacyCredentials(for: peerID)
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw PairingCredentialError.keychain(updateStatus)
        }
        var item = query
        item[kSecValueData as String] = secret
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw PairingCredentialError.keychain(addStatus) }
        try deleteLegacyCredentials(for: peerID)
    }

    public func removeSecret(for peerID: HandoffInstallationID) throws {
        let status = SecItemDelete(baseQuery(peerID: peerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PairingCredentialError.keychain(status)
        }
        try deleteLegacyCredentials(for: peerID)
    }

    public func trustedPeerIDs() throws -> Set<HandoffInstallationID> {
        try deleteLegacyCredentials()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw PairingCredentialError.keychain(status) }
        let rows = result as? [[String: Any]] ?? []
        return Set(rows.compactMap { row in
            guard let account = row[kSecAttrAccount as String] as? String,
                  let uuid = UUID(uuidString: account) else { return nil }
            return HandoffInstallationID(rawValue: uuid)
        })
    }

    private func baseQuery(peerID: HandoffInstallationID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: peerID.rawValue.uuidString,
        ]
    }

    private func deleteLegacyCredentials(for peerID: HandoffInstallationID? = nil) throws {
        guard let legacyService else { return }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
        ]
        if let peerID {
            query[kSecAttrAccount as String] = peerID.rawValue.uuidString
        }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PairingCredentialError.keychain(status)
        }
    }
}

public final class InMemoryPairingCredentialStore: PairingCredentialStore {
    private let lock = NSLock()
    private var values: [HandoffInstallationID: Data] = [:]

    public init() {}

    public func secret(for peerID: HandoffInstallationID) throws -> Data? {
        lock.withLock { values[peerID] }
    }

    public func store(secret: Data, for peerID: HandoffInstallationID) throws {
        guard secret.count >= 32 else { throw PairingCredentialError.invalidSecret }
        lock.withLock { values[peerID] = secret }
    }

    public func removeSecret(for peerID: HandoffInstallationID) throws {
        _ = lock.withLock { values.removeValue(forKey: peerID) }
    }

    public func trustedPeerIDs() throws -> Set<HandoffInstallationID> {
        lock.withLock { Set(values.keys) }
    }
}

public enum HandoffAuthenticator {
    public static let nonceByteCount = 32
    public static let publicKeyByteCount = 32

    public static func makeNonce() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: nonceByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw PairingCredentialError.keychain(status) }
        return Data(bytes)
    }

    public static func makeKeyAgreementPrivateKey() -> Curve25519.KeyAgreement.PrivateKey {
        Curve25519.KeyAgreement.PrivateKey()
    }

    public static func deriveSharedSecret(
        localID: HandoffInstallationID,
        remoteID: HandoffInstallationID,
        localChallenge: HandoffAuthenticationChallenge,
        remoteChallenge: HandoffAuthenticationChallenge,
        localPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
        guard localChallenge.nonce.count == nonceByteCount,
              remoteChallenge.nonce.count == nonceByteCount,
              localID != remoteID,
              localChallenge.keyAgreementPublicKey.count == publicKeyByteCount,
              remoteChallenge.keyAgreementPublicKey.count == publicKeyByteCount,
              localChallenge.keyAgreementPublicKey == localPrivateKey.publicKey.rawRepresentation else {
            throw PairingCredentialError.invalidChallenge
        }

        let publicKey: Curve25519.KeyAgreement.PublicKey
        do {
            publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteChallenge.keyAgreementPublicKey)
        } catch {
            throw PairingCredentialError.invalidChallenge
        }

        let participants = [
            (localID, localChallenge.nonce, localChallenge.keyAgreementPublicKey),
            (remoteID, remoteChallenge.nonce, remoteChallenge.keyAgreementPublicKey),
        ].sorted { $0.0.rawValue.uuidString < $1.0.rawValue.uuidString }
        var transcript = Data("3DSeen-pairing-v3|".utf8)
        for (id, nonce, key) in participants {
            transcript.append(Data(id.rawValue.uuidString.lowercased().utf8))
            transcript.append(0)
            transcript.append(nonce)
            transcript.append(0)
            transcript.append(key)
            transcript.append(0)
        }

        let sharedSecret = try localPrivateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let key = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: transcript,
            sharedInfo: Data("3DSeen-pairing-credential-v3".utf8),
            outputByteCount: 32
        )
        return key.withUnsafeBytes { Data($0) }
    }

    public static func sharedAuthenticationCode(secret: Data) -> String {
        let digest = HMAC<SHA256>.authenticationCode(
            for: Data("3DSeen-pairing-confirm-v3".utf8),
            using: SymmetricKey(data: secret)
        )
        let value = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } % 1_000_000
        return String(format: "%06llu", value)
    }

    public static func authenticationResponse(
        secret: Data,
        challenge: Data,
        responderID: HandoffInstallationID
    ) -> Data {
        let key = SymmetricKey(data: secret)
        return Data(HMAC<SHA256>.authenticationCode(
            for: responseMaterial(challenge: challenge, responderID: responderID),
            using: key
        ))
    }

    public static func verifyAuthenticationResponse(
        _ response: Data,
        secret: Data,
        challenge: Data,
        responderID: HandoffInstallationID
    ) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            response,
            authenticating: responseMaterial(challenge: challenge, responderID: responderID),
            using: SymmetricKey(data: secret)
        )
    }

    private static func responseMaterial(challenge: Data, responderID: HandoffInstallationID) -> Data {
        var data = Data("3DSeen-auth-v3|".utf8)
        data.append(Data(responderID.rawValue.uuidString.lowercased().utf8))
        data.append(0)
        data.append(challenge)
        return data
    }
}
