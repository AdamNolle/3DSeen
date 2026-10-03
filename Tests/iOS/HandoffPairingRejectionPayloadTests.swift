import XCTest
@testable import ThreeDSeen

final class HandoffPairingRejectionPayloadTests: XCTestCase {
    func testPairingRejectionProofRoundTrips() throws {
        let sender = HandoffInstallationID()
        let envelope = HandoffMessageEnvelope(
            senderInstallationID: sender,
            payload: .pairingRejected(Data("decline-proof".utf8))
        )

        let decoded = try JSONDecoder().decode(
            HandoffMessageEnvelope.self,
            from: JSONEncoder().encode(envelope)
        )

        XCTAssertEqual(decoded, envelope)
    }
}
