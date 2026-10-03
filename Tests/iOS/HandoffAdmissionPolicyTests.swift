import XCTest
@testable import ThreeDSeen

final class HandoffAdmissionPolicyTests: XCTestCase {
    func testInvitationAdmissionBoundsPendingInvitationsAndRateLimitsPeers() {
        var gate = HandoffInvitationAdmissionGate()
        let firstPeers = (0..<4).map { _ in HandoffInstallationID() }
        for peer in firstPeers {
            XCTAssertTrue(gate.admit(peer, at: 100))
        }
        XCTAssertFalse(gate.admit(HandoffInstallationID(), at: 100))

        let nextPeers = (0..<4).map { _ in HandoffInstallationID() }
        for peer in nextPeers {
            XCTAssertTrue(gate.admit(peer, at: 101.1))
        }
        XCTAssertFalse(gate.admit(HandoffInstallationID(), at: 101.1))
        XCTAssertFalse(gate.admit(HandoffInstallationID(), at: 102.2))
    }

    func testInvitationAdmissionKeepsPeerCooldownAfterRelease() {
        var gate = HandoffInvitationAdmissionGate()
        let peer = HandoffInstallationID()

        XCTAssertTrue(gate.admit(peer, at: 10))
        gate.release(peer)
        XCTAssertFalse(gate.admit(peer, at: 39.9))
        XCTAssertTrue(gate.admit(peer, at: 40))
    }

    func testQueuedHandoffAdmissionBoundsCountBytesAndOverflow() {
        let limit = HandoffResourceAdmissionPolicy.maximumResourceBytes
        let aggregateLimit = HandoffResourceAdmissionPolicy.maximumAggregateQueuedBytes

        XCTAssertFalse(HandoffResourceAdmissionPolicy.admits(
            isAuthenticated: true,
            hasRegisteredReceiver: true,
            activeResourceCount: 0,
            advertisedByteCount: 0
        ))
        XCTAssertFalse(HandoffResourceAdmissionPolicy.admits(
            isAuthenticated: true,
            hasRegisteredReceiver: true,
            activeResourceCount: 0,
            advertisedByteCount: -1
        ))

        XCTAssertTrue(HandoffResourceAdmissionPolicy.admitsQueuedResource(
            queuedResourceCount: 0,
            queuedByteCount: 0,
            activeByteCount: limit,
            incomingByteCount: limit
        ))
        XCTAssertFalse(HandoffResourceAdmissionPolicy.admitsQueuedResource(
            queuedResourceCount: 1,
            queuedByteCount: aggregateLimit,
            activeByteCount: 0,
            incomingByteCount: 1
        ))
        XCTAssertFalse(HandoffResourceAdmissionPolicy.admitsQueuedResource(
            queuedResourceCount: 2,
            queuedByteCount: 0,
            activeByteCount: 0,
            incomingByteCount: 1
        ))
        XCTAssertFalse(HandoffResourceAdmissionPolicy.admitsQueuedResource(
            queuedResourceCount: 0,
            queuedByteCount: Int64.max,
            activeByteCount: aggregateLimit,
            incomingByteCount: 1
        ))
        XCTAssertFalse(HandoffResourceAdmissionPolicy.admitsQueuedResource(
            queuedResourceCount: 0,
            queuedByteCount: 0,
            activeByteCount: 0,
            incomingByteCount: 0
        ))
    }
}
