import Security
import CryptoKit
import XCTest
@testable import ThreeDSeen

final class HandoffTrustTests: XCTestCase {
    func testMemoryCredentialStoreSupportsTrustAndRevocation() throws {
        let store = InMemoryPairingCredentialStore()
        let peer = HandoffInstallationID()
        let secret = Data(repeating: 7, count: 32)

        XCTAssertNil(try store.secret(for: peer))
        XCTAssertThrowsError(try store.store(secret: Data(repeating: 1, count: 16), for: peer))
        try store.store(secret: secret, for: peer)
        XCTAssertEqual(try store.secret(for: peer), secret)
        XCTAssertEqual(try store.trustedPeerIDs(), [peer])
        try store.removeSecret(for: peer)
        XCTAssertNil(try store.secret(for: peer))
        XCTAssertTrue(try store.trustedPeerIDs().isEmpty)
    }

    func testKeychainCredentialStoreRoundTripsAndRevokes() throws {
        let store = KeychainPairingCredentialStore(service: "HandoffTrustTests-\(UUID())")
        let peer = HandoffInstallationID()
        let secret = Data(repeating: 9, count: 32)
        defer { try? store.removeSecret(for: peer) }

        do {
            try store.store(secret: secret, for: peer)
            XCTAssertEqual(try store.secret(for: peer), secret)
            XCTAssertTrue(try store.trustedPeerIDs().contains(peer))
            try store.removeSecret(for: peer)
            XCTAssertNil(try store.secret(for: peer))
        } catch PairingCredentialError.keychain(errSecMissingEntitlement) {
            throw XCTSkip("Unsigned Simulator tests do not receive a Keychain application identifier.")
        }
    }

    func testEphemeralKeyAgreementDerivesSymmetricSecretAndRejectsRelayKey() throws {
        let first = HandoffInstallationID(
            rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        )
        let second = HandoffInstallationID(
            rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        )
        let firstNonce = Data((0..<32).map(UInt8.init))
        let secondNonce = Data((32..<64).map(UInt8.init))
        let firstKey = HandoffAuthenticator.makeKeyAgreementPrivateKey()
        let secondKey = HandoffAuthenticator.makeKeyAgreementPrivateKey()
        let firstChallenge = HandoffAuthenticationChallenge(
            nonce: firstNonce,
            keyAgreementPublicKey: firstKey.publicKey.rawRepresentation
        )
        let secondChallenge = HandoffAuthenticationChallenge(
            nonce: secondNonce,
            keyAgreementPublicKey: secondKey.publicKey.rawRepresentation
        )

        let firstSecret = try HandoffAuthenticator.deriveSharedSecret(
            localID: first,
            remoteID: second,
            localChallenge: firstChallenge,
            remoteChallenge: secondChallenge,
            localPrivateKey: firstKey
        )
        let secondSecret = try HandoffAuthenticator.deriveSharedSecret(
            localID: second,
            remoteID: first,
            localChallenge: secondChallenge,
            remoteChallenge: firstChallenge,
            localPrivateKey: secondKey
        )

        XCTAssertEqual(firstSecret, secondSecret)
        XCTAssertEqual(
            HandoffAuthenticator.sharedAuthenticationCode(secret: firstSecret),
            HandoffAuthenticator.sharedAuthenticationCode(secret: secondSecret)
        )

        let relayKey = HandoffAuthenticator.makeKeyAgreementPrivateKey()
        let relayChallenge = HandoffAuthenticationChallenge(
            nonce: firstNonce,
            keyAgreementPublicKey: relayKey.publicKey.rawRepresentation
        )
        let relaySecret = try HandoffAuthenticator.deriveSharedSecret(
            localID: first,
            remoteID: second,
            localChallenge: relayChallenge,
            remoteChallenge: secondChallenge,
            localPrivateKey: relayKey
        )
        XCTAssertNotEqual(firstSecret, relaySecret)
        XCTAssertNotEqual(
            HandoffAuthenticator.sharedAuthenticationCode(secret: firstSecret),
            HandoffAuthenticator.sharedAuthenticationCode(secret: relaySecret)
        )
        XCTAssertThrowsError(try HandoffAuthenticator.deriveSharedSecret(
            localID: first,
            remoteID: second,
            localChallenge: firstChallenge,
            remoteChallenge: HandoffAuthenticationChallenge(
                nonce: secondNonce,
                keyAgreementPublicKey: Data(repeating: 0, count: HandoffAuthenticator.publicKeyByteCount - 1)
            ),
            localPrivateKey: firstKey
        ))
    }

    func testHMACChallengeResponseRejectsTampering() {
        let peer = HandoffInstallationID()
        let secret = Data(repeating: 4, count: 32)
        let challenge = Data("challenge".utf8)
        let response = HandoffAuthenticator.authenticationResponse(
            secret: secret,
            challenge: challenge,
            responderID: peer
        )

        XCTAssertTrue(HandoffAuthenticator.verifyAuthenticationResponse(
            response,
            secret: secret,
            challenge: challenge,
            responderID: peer
        ))
        XCTAssertFalse(HandoffAuthenticator.verifyAuthenticationResponse(
            response,
            secret: secret,
            challenge: Data("tampered".utf8),
            responderID: peer
        ))
        XCTAssertFalse(HandoffAuthenticator.verifyAuthenticationResponse(
            response,
            secret: secret,
            challenge: challenge,
            responderID: HandoffInstallationID()
        ))
    }

    func testNonceUsesExpectedCryptographicLength() throws {
        XCTAssertEqual(try HandoffAuthenticator.makeNonce().count, HandoffAuthenticator.nonceByteCount)
        XCTAssertNotEqual(try HandoffAuthenticator.makeNonce(), try HandoffAuthenticator.makeNonce())
    }
}
