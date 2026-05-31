import Foundation
import MultipeerConnectivity
import OSLog
#if os(iOS)
import UIKit
#endif

/// Manages sending raw scan ZIPs from iOS to macOS using MultipeerConnectivity.
public final class NetworkHandoffManager: NSObject, ObservableObject {
    private let serviceType = "3dseen"
    #if os(iOS)
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    #else
    private let myPeerId = MCPeerID(displayName: Host.current().localizedName ?? "3DSeen Device")
    #endif
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "Network")

    @Published public var connectedPeers: [MCPeerID] = []
    /// Most recent scan archive received from a peer (macOS receiving side).
    @Published public var lastReceivedScan: URL?
    /// Live transfer progress (0…1) for the in-flight resource.
    @Published public var transferProgress: Double = 0
    /// Called on the main queue when a scan archive finishes arriving.
    public var onReceiveScan: ((URL) -> Void)?
    private var progressObservation: NSKeyValueObservation?

    public override init() {
        super.init()

        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        #if os(iOS)
        // iOS advertises its scans
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        #elseif os(macOS)
        // macOS browses for incoming scans
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        #endif
    }

    public func sendScan(fileURL: URL, to peer: MCPeerID) {
        logger.debug("Sending scan to \(peer.displayName)...")
        session.sendResource(at: fileURL, withName: fileURL.lastPathComponent, toPeer: peer) { error in
            if let error = error {
                self.logger.error("Failed to send resource: \(error)")
            } else {
                self.logger.debug("Scan sent successfully.")
            }
        }
    }

    /// Convenience for iOS: hand the scan to the first connected Mac.
    public func sendScanToFirstPeer(_ fileURL: URL) {
        guard let peer = session.connectedPeers.first else {
            logger.warning("No connected peer to hand off to.")
            return
        }
        sendScan(fileURL: fileURL, to: peer)
    }
}

extension NetworkHandoffManager: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }
        logger.debug("Peer \(peerID.displayName) state changed to \(state.rawValue)")
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        logger.debug("Started receiving \(resourceName) from \(peerID.displayName)")
        progressObservation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] prog, _ in
            DispatchQueue.main.async { self?.transferProgress = prog.fractionCompleted }
        }
    }

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        progressObservation = nil
        if let error = error {
            logger.error("Failed to receive \(resourceName): \(error.localizedDescription)")
            return
        }
        guard let localURL else { return }
        // Move the temp resource into a stable inbox the compute coordinator can read.
        let inbox = FileManager.default.temporaryDirectory.appendingPathComponent("3dseen-inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let dest = inbox.appendingPathComponent(resourceName)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: localURL, to: dest)
            logger.info("Received \(resourceName) → \(dest.path)")
            DispatchQueue.main.async {
                self.transferProgress = 1
                self.lastReceivedScan = dest
                self.onReceiveScan?(dest)
            }
        } catch {
            logger.error("Could not move received resource: \(error.localizedDescription)")
        }
    }
}

extension NetworkHandoffManager: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                           didReceiveInvitationFromPeer peerID: MCPeerID,
                           withContext context: Data?,
                           invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

extension NetworkHandoffManager: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        logger.debug("Found peer: \(peerID.displayName)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.debug("Lost peer: \(peerID.displayName)")
    }
}
