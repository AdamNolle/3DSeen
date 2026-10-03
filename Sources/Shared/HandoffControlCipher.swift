import CryptoKit
import Foundation

private struct AuthenticatedHandoffControlFrame: Codable {
    let version: Int
    let senderInstallationID: HandoffInstallationID
    let sealedMessage: Data
}

public enum HandoffControlCipher {
    public static func requiresAuthentication(_ payload: HandoffMessagePayload) -> Bool {
        switch payload {
        case .hello, .authenticationChallenge, .authenticationResponse, .pairingRejected, .protocolRejected:
            false
        default:
            true
        }
    }

    public static func seal(_ message: HandoffMessageEnvelope, using secret: Data) throws -> Data {
        guard requiresAuthentication(message.payload) else {
            return try JSONEncoder().encode(message)
        }
        let key = SymmetricKey(data: secret)
        let aad = associatedData(senderID: message.senderInstallationID)
        let plaintext = try JSONEncoder().encode(message)
        let sealed = try ChaChaPoly.seal(plaintext, using: key, authenticating: aad)
        let frame = AuthenticatedHandoffControlFrame(
            version: HandoffProtocolVersion.current,
            senderInstallationID: message.senderInstallationID,
            sealedMessage: sealed.combined
        )
        return try JSONEncoder().encode(frame)
    }

    public static func open(
        _ data: Data,
        expectedSenderID: HandoffInstallationID,
        using secret: Data
    ) throws -> HandoffMessageEnvelope {
        let frame = try JSONDecoder().decode(AuthenticatedHandoffControlFrame.self, from: data)
        guard frame.version == HandoffProtocolVersion.current,
              frame.senderInstallationID == expectedSenderID else {
            throw HandoffControlCipherError.invalidFrame
        }
        let sealed = try ChaChaPoly.SealedBox(combined: frame.sealedMessage)
        let plaintext = try ChaChaPoly.open(
            sealed,
            using: SymmetricKey(data: secret),
            authenticating: associatedData(senderID: expectedSenderID)
        )
        let message = try JSONDecoder().decode(HandoffMessageEnvelope.self, from: plaintext)
        guard message.senderInstallationID == expectedSenderID,
              requiresAuthentication(message.payload) else {
            throw HandoffControlCipherError.invalidFrame
        }
        try message.validateVersion()
        return message
    }

    public static func decodeUnauthenticatedHandshake(_ data: Data) throws -> HandoffMessageEnvelope {
        let message = try JSONDecoder().decode(HandoffMessageEnvelope.self, from: data)
        guard !requiresAuthentication(message.payload) else {
            throw HandoffControlCipherError.authenticationRequired
        }
        // The receiver validates the protocol version after decoding so it can
        // send a protocolRejected response to a peer that needs to re-pair.
        return message
    }

    private static func associatedData(senderID: HandoffInstallationID) -> Data {
        Data("3DSeen-control-v3|\(senderID.rawValue.uuidString.lowercased())".utf8)
    }
}

public enum HandoffControlCipherError: Error {
    case invalidFrame
    case authenticationRequired
}
