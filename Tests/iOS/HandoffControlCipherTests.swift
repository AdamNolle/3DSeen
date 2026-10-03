import XCTest
@testable import ThreeDSeen

final class HandoffControlCipherTests: XCTestCase {
    func testAuthenticatedControlRoundTripsAndRejectsWrongKeyAndTampering() throws {
        let sender = HandoffInstallationID()
        let secret = Data(repeating: 0x41, count: 32)
        let message = HandoffMessageEnvelope(
            senderInstallationID: sender,
            payload: .jobAccepted
        )

        let sealed = try HandoffControlCipher.seal(message, using: secret)
        XCTAssertNotEqual(sealed, try JSONEncoder().encode(message))
        XCTAssertEqual(try HandoffControlCipher.open(sealed, expectedSenderID: sender, using: secret), message)
        XCTAssertThrowsError(try HandoffControlCipher.open(
            sealed,
            expectedSenderID: sender,
            using: Data(repeating: 0x42, count: 32)
        ))

        var tampered = sealed
        tampered[tampered.index(before: tampered.endIndex)] ^= 1
        XCTAssertThrowsError(try HandoffControlCipher.open(tampered, expectedSenderID: sender, using: secret))
    }

    func testUnpairedHandshakeIsAllowedButJobControlRequiresCredential() throws {
        let sender = HandoffInstallationID()
        let hello = HandoffMessageEnvelope(
            senderInstallationID: sender,
            payload: .hello(HandoffPeer(
                installationID: sender,
                displayName: "Phone",
                platform: .iOS,
                capabilities: [.captureSender]
            ))
        )
        let encodedHello = try HandoffControlCipher.seal(hello, using: Data())
        XCTAssertEqual(try HandoffControlCipher.decodeUnauthenticatedHandshake(encodedHello), hello)

        let oldHello = HandoffMessageEnvelope(
            protocolVersion: HandoffProtocolVersion.current - 1,
            senderInstallationID: sender,
            payload: hello.payload
        )
        let decodedOldHello = try HandoffControlCipher.decodeUnauthenticatedHandshake(
            JSONEncoder().encode(oldHello)
        )
        XCTAssertEqual(decodedOldHello, oldHello)
        XCTAssertThrowsError(try decodedOldHello.validateVersion())

        let jobControl = HandoffMessageEnvelope(senderInstallationID: sender, payload: .jobAccepted)
        let encodedJob = try JSONEncoder().encode(jobControl)
        XCTAssertThrowsError(try HandoffControlCipher.decodeUnauthenticatedHandshake(encodedJob))
    }
}
