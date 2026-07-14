import Combine
import Foundation
import MultipeerConnectivity

/// Injectable seam around MultipeerConnectivity. Application coordinators own one transport for
/// their entire lifetime; views never own sessions or result callbacks. Stable installation IDs
/// are the application boundary; MCPeerID remains only on legacy receive callbacks during v1
/// resource migration.
@MainActor
public protocol ScanHandoffTransport: AnyObject {
    var localInstallationID: HandoffInstallationID { get }
    var discoveredPeers: [HandoffPeer] { get }
    var connectedHandoffPeers: [HandoffPeer] { get }
    var pendingInvitations: [HandoffInvitation] { get }
    var transferProgress: Double { get }
    var discoveredPeersPublisher: AnyPublisher<[HandoffPeer], Never> { get }
    var connectedHandoffPeersPublisher: AnyPublisher<[HandoffPeer], Never> { get }
    var pendingInvitationsPublisher: AnyPublisher<[HandoffInvitation], Never> { get }
    var controlEventsPublisher: AnyPublisher<HandoffControlEvent, Never> { get }
    var transferProgressPublisher: AnyPublisher<Double, Never> { get }
    var onReceiveResultPackage: ((URL, MCPeerID, ScanHandoffMetadata) -> Void)? { get set }
    var onSendError: ((Error) -> Void)? { get set }

    func installationID(for peerID: MCPeerID) -> HandoffInstallationID?
    func invite(peerID: HandoffInstallationID)
    func respond(to invitationID: UUID, accept: Bool)

    @discardableResult
    func send(_ message: HandoffMessageEnvelope, to peerID: HandoffInstallationID) -> Bool

    @discardableResult
    func sendScan(
        _ fileURL: URL,
        to peerID: HandoffInstallationID,
        metadata: ScanHandoffMetadata
    ) -> Bool

    func removeReceivedResource(_ url: URL)
}
