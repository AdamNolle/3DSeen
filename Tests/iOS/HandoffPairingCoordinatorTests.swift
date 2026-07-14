import Combine
import MultipeerConnectivity
import XCTest
@testable import ThreeDSeen

@MainActor
final class HandoffPairingCoordinatorTests: XCTestCase {
    func testFirstPairingRequiresBothMatchingCodeConfirmations() async throws {
        let phone = PairingFakeTransport(name: "Phone", platform: .iOS)
        let mac = PairingFakeTransport(name: "Mac", platform: .macOS)
        let phoneStore = InMemoryPairingCredentialStore()
        let macStore = InMemoryPairingCredentialStore()
        let phonePairing = HandoffPairingCoordinator(transport: phone, credentialStore: phoneStore)
        let macPairing = HandoffPairingCoordinator(transport: mac, credentialStore: macStore)

        phone.connect(to: mac.localPeer)
        mac.connect(to: phone.localPeer)
        try await settle()
        relayPayload(.authenticationChallenge, from: phone, to: mac)
        relayPayload(.authenticationChallenge, from: mac, to: phone)
        try await settle()

        let phoneRequest = try XCTUnwrap(phonePairing.pendingRequests.first)
        let macRequest = try XCTUnwrap(macPairing.pendingRequests.first)
        XCTAssertEqual(phoneRequest.code, macRequest.code)
        XCTAssertFalse(phonePairing.isAuthenticated(mac.localInstallationID))
        XCTAssertFalse(macPairing.isAuthenticated(phone.localInstallationID))

        phonePairing.confirm(phoneRequest)
        relayPayload(.authenticationResponse, from: phone, to: mac)
        try await settle()
        XCTAssertFalse(phonePairing.isAuthenticated(mac.localInstallationID))
        XCTAssertFalse(macPairing.isAuthenticated(phone.localInstallationID))
        XCTAssertTrue(try phoneStore.trustedPeerIDs().isEmpty)
        XCTAssertTrue(try macStore.trustedPeerIDs().isEmpty)

        macPairing.confirm(macRequest)
        try await settle()
        XCTAssertTrue(macPairing.isAuthenticated(phone.localInstallationID))
        relayPayload(.authenticationResponse, from: mac, to: phone)
        try await settle()

        XCTAssertTrue(phonePairing.isAuthenticated(mac.localInstallationID))
        XCTAssertEqual(try phoneStore.secret(for: mac.localInstallationID), try macStore.secret(for: phone.localInstallationID))
    }

    func testStoredTrustReconnectsWithFreshChallengesWithoutSAS() async throws {
        let phoneID = HandoffInstallationID()
        let macID = HandoffInstallationID()
        let secret = Data(repeating: 7, count: 32)
        let phoneStore = InMemoryPairingCredentialStore()
        let macStore = InMemoryPairingCredentialStore()
        try phoneStore.store(secret: secret, for: macID)
        try macStore.store(secret: secret, for: phoneID)
        let phone = PairingFakeTransport(id: phoneID, name: "Phone", platform: .iOS)
        let mac = PairingFakeTransport(id: macID, name: "Mac", platform: .macOS)
        let phonePairing = HandoffPairingCoordinator(transport: phone, credentialStore: phoneStore)
        let macPairing = HandoffPairingCoordinator(transport: mac, credentialStore: macStore)

        phone.connect(to: mac.localPeer)
        mac.connect(to: phone.localPeer)
        try await settle()
        relayPayload(.authenticationChallenge, from: phone, to: mac)
        relayPayload(.authenticationChallenge, from: mac, to: phone)
        try await settle()
        XCTAssertTrue(phonePairing.pendingRequests.isEmpty)
        XCTAssertTrue(macPairing.pendingRequests.isEmpty)

        relayPayload(.authenticationResponse, from: phone, to: mac)
        relayPayload(.authenticationResponse, from: mac, to: phone)
        try await settle()

        XCTAssertTrue(phonePairing.isAuthenticated(macID))
        XCTAssertTrue(macPairing.isAuthenticated(phoneID))
    }

    func testRejectDoesNotPersistHalfEstablishedTrust() async throws {
        let phone = PairingFakeTransport(name: "Phone", platform: .iOS)
        let mac = PairingFakeTransport(name: "Mac", platform: .macOS)
        let phoneStore = InMemoryPairingCredentialStore()
        let phonePairing = HandoffPairingCoordinator(transport: phone, credentialStore: phoneStore)
        let macPairing = HandoffPairingCoordinator(
            transport: mac,
            credentialStore: InMemoryPairingCredentialStore()
        )

        phone.connect(to: mac.localPeer)
        mac.connect(to: phone.localPeer)
        try await settle()
        relayPayload(.authenticationChallenge, from: phone, to: mac)
        relayPayload(.authenticationChallenge, from: mac, to: phone)
        try await settle()

        phonePairing.reject(try XCTUnwrap(phonePairing.pendingRequests.first))
        XCTAssertTrue(try phoneStore.trustedPeerIDs().isEmpty)
        XCTAssertFalse(phonePairing.isAuthenticated(mac.localInstallationID))
        withExtendedLifetime(macPairing) {}
    }

    private func relayPayload(
        _ expectedPayload: PairingPayloadKind,
        from source: PairingFakeTransport,
        to destination: PairingFakeTransport
    ) {
        guard let index = source.sent.firstIndex(where: { expectedPayload.matches($0.payload) }) else {
            return XCTFail("Missing \(expectedPayload) message")
        }
        let message = source.sent.remove(at: index)
        destination.deliver(message, from: source.localInstallationID)
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(30))
    }
}

private enum PairingPayloadKind: CustomStringConvertible {
    case authenticationChallenge
    case authenticationResponse

    var description: String {
        switch self {
        case .authenticationChallenge: "authentication challenge"
        case .authenticationResponse: "authentication response"
        }
    }

    func matches(_ payload: HandoffMessagePayload) -> Bool {
        switch (self, payload) {
        case (.authenticationChallenge, .authenticationChallenge),
             (.authenticationResponse, .authenticationResponse):
            true
        default:
            false
        }
    }
}

@MainActor
private final class PairingFakeTransport: ScanHandoffTransport {
    let localInstallationID: HandoffInstallationID
    let localPeer: HandoffPeer
    @Published private(set) var connectedHandoffPeers: [HandoffPeer] = []
    var discoveredPeers: [HandoffPeer] = []
    var pendingInvitations: [HandoffInvitation] = []
    var transferProgress = 0.0
    var discoveredPeersPublisher: AnyPublisher<[HandoffPeer], Never> { Empty().eraseToAnyPublisher() }
    var connectedHandoffPeersPublisher: AnyPublisher<[HandoffPeer], Never> {
        $connectedHandoffPeers.eraseToAnyPublisher()
    }
    var pendingInvitationsPublisher: AnyPublisher<[HandoffInvitation], Never> { Empty().eraseToAnyPublisher() }
    var controlEventsPublisher: AnyPublisher<HandoffControlEvent, Never> { controls.eraseToAnyPublisher() }
    var transferProgressPublisher: AnyPublisher<Double, Never> { Empty().eraseToAnyPublisher() }
    var onReceiveResultPackage: ((URL, MCPeerID, ScanHandoffMetadata) -> Void)?
    var onSendError: ((Error) -> Void)?
    var sent: [HandoffMessageEnvelope] = []
    private let controls = PassthroughSubject<HandoffControlEvent, Never>()

    init(
        id: HandoffInstallationID = HandoffInstallationID(),
        name: String,
        platform: HandoffPeerPlatform
    ) {
        localInstallationID = id
        localPeer = HandoffPeer(
            installationID: id,
            displayName: name,
            platform: platform,
            capabilities: [.photogrammetry]
        )
    }

    func connect(to peer: HandoffPeer) {
        connectedHandoffPeers = [peer]
    }

    func deliver(_ message: HandoffMessageEnvelope, from peerID: HandoffInstallationID) {
        controls.send(HandoffControlEvent(message: message, peerID: peerID))
    }

    func send(_ message: HandoffMessageEnvelope, to peerID: HandoffInstallationID) -> Bool {
        guard connectedHandoffPeers.contains(where: { $0.installationID == peerID }) else { return false }
        sent.append(message)
        return true
    }

    func installationID(for _: MCPeerID) -> HandoffInstallationID? { nil }

    func invite(peerID _: HandoffInstallationID) {}

    func respond(to _: UUID, accept _: Bool) {}

    func sendScan(
        _ fileURL: URL,
        to peerID: HandoffInstallationID,
        metadata: ScanHandoffMetadata
    ) -> Bool {
        _ = fileURL
        _ = metadata
        return connectedHandoffPeers.contains { $0.installationID == peerID }
    }

    func removeReceivedResource(_ url: URL) {
        _ = url
    }
}
