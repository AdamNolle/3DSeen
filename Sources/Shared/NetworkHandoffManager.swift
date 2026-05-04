import Foundation
import MultipeerConnectivity
import OSLog

/// Manages sending raw scan ZIPs from iOS to macOS using MultipeerConnectivity.
public final class NetworkHandoffManager: NSObject, ObservableObject {
    private let serviceType = "3dseen"
    private let myPeerId = MCPeerID(displayName: Host.current().localizedName ?? "3DSeen Device")
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "Network")
    
    @Published public var connectedPeers: [MCPeerID] = []
    
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
    }
    
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        logger.debug("Finished receiving \(resourceName)")
    }
}

extension NetworkHandoffManager: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

extension NetworkHandoffManager: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        logger.debug("Found peer: \(peerID.displayName)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.debug("Lost peer: \(peerID.displayName)")
    }
}
