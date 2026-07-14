import Combine
import Foundation

public struct HandoffPairingRequest: Identifiable, Equatable, Sendable {
    public var id: HandoffInstallationID { peer.installationID }
    public let peer: HandoffPeer
    public let code: String

    public init(peer: HandoffPeer, code: String) {
        self.peer = peer
        self.code = code
    }
}

/// Application-layer authentication over an encrypted Multipeer session. First pairing requires
/// both users to confirm the same SAS before either side proves possession of the derived secret.
/// Later connections authenticate silently with fresh HMAC challenges.
@MainActor
public final class HandoffPairingCoordinator: ObservableObject {
    private struct SessionState {
        var peer: HandoffPeer
        var localNonce: Data
        var remoteNonce: Data?
        var pendingResponse: Data?
        var provisionalSecret: Data?
    }

    @Published public private(set) var pendingRequests: [HandoffPairingRequest] = []
    @Published public private(set) var authenticatedPeerIDs: Set<HandoffInstallationID> = []
    @Published public private(set) var trustedPeerIDs: Set<HandoffInstallationID> = []
    @Published public private(set) var lastError: String?

    private let transport: any ScanHandoffTransport
    private let credentialStore: any PairingCredentialStore
    private var sessions: [HandoffInstallationID: SessionState] = [:]
    private var cancellables = Set<AnyCancellable>()

    public init(
        transport: any ScanHandoffTransport,
        credentialStore: (any PairingCredentialStore)? = nil
    ) {
        self.transport = transport
        self.credentialStore = credentialStore ?? KeychainPairingCredentialStore()

        transport.connectedHandoffPeersPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.reconcileConnectedPeers($0) }
            .store(in: &cancellables)
        transport.controlEventsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.handle($0) }
            .store(in: &cancellables)

        do {
            trustedPeerIDs = try self.credentialStore.trustedPeerIDs()
        } catch PairingCredentialError.keychain(-34_018) {
            // Unsigned Simulator builds have no Keychain application identifier.
        } catch {
            lastError = "Pairing credentials could not be read: \(error.localizedDescription)"
        }
        reconcileConnectedPeers(transport.connectedHandoffPeers)
    }

    public func isAuthenticated(_ peerID: HandoffInstallationID) -> Bool {
        authenticatedPeerIDs.contains(peerID)
    }

    public func confirm(_ request: HandoffPairingRequest) {
        let peerID = request.peer.installationID
        guard var state = sessions[peerID],
              let remoteNonce = state.remoteNonce,
              pairingCode(for: state, remoteNonce: remoteNonce) == request.code else { return }
        let secret = HandoffAuthenticator.deriveSharedSecret(
            localID: transport.localInstallationID,
            remoteID: peerID,
            localNonce: state.localNonce,
            remoteNonce: remoteNonce
        )
        state.provisionalSecret = secret
        sessions[peerID] = state
        pendingRequests.removeAll { $0.id == peerID }
        sendResponse(secret: secret, challenge: remoteNonce, to: peerID)
        if let pendingResponse = state.pendingResponse {
            verify(response: pendingResponse, for: peerID, state: state, secret: secret)
        }
    }

    public func reject(_ request: HandoffPairingRequest) {
        let peerID = request.peer.installationID
        pendingRequests.removeAll { $0.id == peerID }
        sessions.removeValue(forKey: peerID)
        send(
            .failed(HandoffFailure(code: .untrustedPeer, detail: "The authentication code was not approved.")),
            to: peerID
        )
    }

    public func forget(_ peerID: HandoffInstallationID) {
        do {
            try credentialStore.removeSecret(for: peerID)
            authenticatedPeerIDs.remove(peerID)
            trustedPeerIDs.remove(peerID)
            sessions.removeValue(forKey: peerID)
            pendingRequests.removeAll { $0.id == peerID }
        } catch {
            lastError = "The trusted peer could not be forgotten: \(error.localizedDescription)"
        }
    }

    private func reconcileConnectedPeers(_ peers: [HandoffPeer]) {
        let connectedIDs = Set(peers.map(\.installationID))
        authenticatedPeerIDs = authenticatedPeerIDs.intersection(connectedIDs)
        pendingRequests.removeAll { !connectedIDs.contains($0.id) }
        sessions = sessions.filter { connectedIDs.contains($0.key) }
        for peer in peers where sessions[peer.installationID] == nil {
            beginAuthentication(with: peer)
        }
    }

    private func beginAuthentication(with peer: HandoffPeer) {
        do {
            let localNonce = try HandoffAuthenticator.makeNonce()
            sessions[peer.installationID] = SessionState(
                peer: peer,
                localNonce: localNonce
            )
            send(.authenticationChallenge(localNonce), to: peer.installationID)
        } catch {
            lastError = "Authentication could not start: \(error.localizedDescription)"
        }
    }

    private func handle(_ event: HandoffControlEvent) {
        switch event.message.payload {
        case .hello(let peer):
            guard peer.installationID == event.peerID else { return }
            if sessions[event.peerID] == nil { beginAuthentication(with: peer) }
        case .authenticationChallenge(let challenge):
            receive(challenge: challenge, from: event.peerID)
        case .authenticationResponse(let response):
            receive(response: response, from: event.peerID)
        case .failed(let failure) where failure.code == .untrustedPeer:
            lastError = failure.detail
            authenticatedPeerIDs.remove(event.peerID)
        case .protocolRejected(let minimum, let maximum):
            lastError = "Peer supports handoff protocol versions \(minimum) through \(maximum)."
        default:
            break
        }
    }

    private func receive(challenge: Data, from peerID: HandoffInstallationID) {
        guard var state = sessions[peerID], challenge.count == HandoffAuthenticator.nonceByteCount else { return }
        state.remoteNonce = challenge
        sessions[peerID] = state
        do {
            if let secret = try credentialStore.secret(for: peerID) {
                sendResponse(secret: secret, challenge: challenge, to: peerID)
            } else {
                let request = HandoffPairingRequest(
                    peer: state.peer,
                    code: pairingCode(for: state, remoteNonce: challenge)
                )
                if let index = pendingRequests.firstIndex(where: { $0.id == peerID }) {
                    pendingRequests[index] = request
                } else {
                    pendingRequests.append(request)
                }
            }
        } catch {
            lastError = "Pairing credentials could not be read: \(error.localizedDescription)"
        }
    }

    private func receive(response: Data, from peerID: HandoffInstallationID) {
        guard var state = sessions[peerID] else { return }
        do {
            guard let secret = try credentialStore.secret(for: peerID) ?? state.provisionalSecret else {
                state.pendingResponse = response
                sessions[peerID] = state
                return
            }
            verify(response: response, for: peerID, state: state, secret: secret)
        } catch {
            lastError = "Pairing credentials could not be read: \(error.localizedDescription)"
        }
    }

    private func verify(
        response: Data,
        for peerID: HandoffInstallationID,
        state: SessionState,
        secret: Data
    ) {
        guard HandoffAuthenticator.verifyAuthenticationResponse(
            response,
            secret: secret,
            challenge: state.localNonce,
            responderID: peerID
        ) else {
            authenticatedPeerIDs.remove(peerID)
            lastError = "The peer failed authentication. Forget it and pair again."
            return
        }
        if let provisionalSecret = state.provisionalSecret {
            do {
                try credentialStore.store(secret: provisionalSecret, for: peerID)
                trustedPeerIDs.insert(peerID)
            } catch {
                lastError = "Pairing could not be saved: \(error.localizedDescription)"
                return
            }
        }
        authenticatedPeerIDs.insert(peerID)
        pendingRequests.removeAll { $0.id == peerID }
        lastError = nil
    }

    private func sendResponse(secret: Data, challenge: Data, to peerID: HandoffInstallationID) {
        let response = HandoffAuthenticator.authenticationResponse(
            secret: secret,
            challenge: challenge,
            responderID: transport.localInstallationID
        )
        send(.authenticationResponse(response), to: peerID)
    }

    private func pairingCode(for state: SessionState, remoteNonce: Data) -> String {
        HandoffAuthenticator.sharedAuthenticationCode(
            localID: transport.localInstallationID,
            remoteID: state.peer.installationID,
            localNonce: state.localNonce,
            remoteNonce: remoteNonce
        )
    }

    private func send(_ payload: HandoffMessagePayload, to peerID: HandoffInstallationID) {
        let message = HandoffMessageEnvelope(
            senderInstallationID: transport.localInstallationID,
            payload: payload
        )
        if !transport.send(message, to: peerID) {
            lastError = "The authentication message could not be sent to \(peerID.rawValue.uuidString)."
        }
    }
}
