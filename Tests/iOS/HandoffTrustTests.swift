import Security
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

    func testSASAndSecretDerivationHaveStableSymmetricVectors() throws {
        let first = HandoffInstallationID(
            rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        )
        let second = HandoffInstallationID(
            rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        )
        let firstNonce = Data((0..<32).map(UInt8.init))
        let secondNonce = Data((32..<64).map(UInt8.init))

        let firstCode = HandoffAuthenticator.sharedAuthenticationCode(
            localID: first,
            remoteID: second,
            localNonce: firstNonce,
            remoteNonce: secondNonce
        )
        let secondCode = HandoffAuthenticator.sharedAuthenticationCode(
            localID: second,
            remoteID: first,
            localNonce: secondNonce,
            remoteNonce: firstNonce
        )
        let firstSecret = HandoffAuthenticator.deriveSharedSecret(
            localID: first,
            remoteID: second,
            localNonce: firstNonce,
            remoteNonce: secondNonce
        )
        let secondSecret = HandoffAuthenticator.deriveSharedSecret(
            localID: second,
            remoteID: first,
            localNonce: secondNonce,
            remoteNonce: firstNonce
        )

        XCTAssertEqual(firstCode, "981121")
        XCTAssertEqual(secondCode, firstCode)
        XCTAssertEqual(firstSecret, secondSecret)
        XCTAssertEqual(firstSecret.map { String(format: "%02x", $0) }.joined(),
                       "59a3c067eb6c8d2de49109a9c6b7bd0a2eebcba069eb2db13ee06eda6da08b04")
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
