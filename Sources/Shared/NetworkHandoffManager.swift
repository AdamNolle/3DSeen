import Combine
import Foundation
import MultipeerConnectivity
import OSLog
import ZIPFoundation
#if os(iOS)
import UIKit
#endif

/// Capture facts preserved alongside a raw handoff archive. Resource transfer has no separate
/// metadata channel, so the sender embeds these stable values in the resource name.
public struct ScanHandoffMetadata: Equatable, Sendable {
    public let jobID: UUID?
    public let scanID: UUID?
    public let captureMode: CaptureMode?
    public let detailTier: String?

    public init(
        jobID: UUID? = nil,
        scanID: UUID? = nil,
        captureMode: CaptureMode? = nil,
        detailTier: String? = nil
    ) {
        self.jobID = jobID
        self.scanID = scanID
        self.captureMode = captureMode
        self.detailTier = detailTier
    }
}

private struct ScanHandoffResourceEnvelope: Codable {
    let jobID: UUID?
    let scanID: UUID?
    let captureModeRaw: String
    let detailTier: String?
    let originalName: String
}

/// Creates a file resource suitable for `MCSession.sendResource`. Image captures are directories
/// on iOS, but Multipeer handoff and macOS reconstruction both operate on a ZIP archive.
public enum ScanHandoffArchive {
    private static let captureQualityReportFileName = "3dseen-capture-quality.json"

    public enum ArchiveError: LocalizedError {
        case missingCapture(URL)

        public var errorDescription: String? {
            switch self {
            case .missingCapture(let url):
                return "The capture archive at \(url.lastPathComponent) is no longer available."
            }
        }
    }

    public static func package(_ captureURL: URL, captureQualityReport: CaptureQualityReport? = nil) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: captureURL.path, isDirectory: &isDirectory) else {
            throw ArchiveError.missingCapture(captureURL)
        }
        guard isDirectory.boolValue else { return captureURL }

        let packageURL = captureURL.deletingLastPathComponent()
            .appendingPathComponent("\(captureURL.lastPathComponent).zip")
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        try fileManager.zipItem(at: captureURL, to: packageURL, shouldKeepParent: false)
        if let captureQualityReport {
            try append(captureQualityReport, to: packageURL)
        }
        return packageURL
    }

    /// Reads the optional image-quality sidecar from an extracted capture package. Older packages
    /// and RoomPlan USDZ handoffs intentionally return `nil`.
    public static func captureQualityReport(in extractedArchive: URL) -> CaptureQualityReport? {
        let url = extractedArchive.appendingPathComponent(captureQualityReportFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CaptureQualityReport.self, from: data)
    }

    private static func append(_ report: CaptureQualityReport, to packageURL: URL) throws {
        let data = try JSONEncoder().encode(report)
        let archive = try Archive(url: packageURL, accessMode: .update)
        try archive.addEntry(
            with: captureQualityReportFileName,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate
        ) { position, size in
            let start = Int(position)
            let end = min(start + size, data.count)
            return start < end ? data.subdata(in: start..<end) : Data()
        }
    }
}

/// Manages sending raw scan archives from iOS to macOS using MultipeerConnectivity.
public final class NetworkHandoffManager: NSObject, ObservableObject {
    private struct PendingInvitationRecord {
        let invitation: HandoffInvitation
        let handler: (Bool, MCSession?) -> Void
    }

    private let serviceType = "3dseen"
    public let localInstallationID: HandoffInstallationID
    private let myPeerId: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "Network")

    @Published public var connectedPeers: [MCPeerID] = []
    @Published public private(set) var discoveredPeers: [HandoffPeer] = []
    @Published public private(set) var connectedHandoffPeers: [HandoffPeer] = []
    @Published public private(set) var pendingInvitations: [HandoffInvitation] = []
    /// Most recent scan archive received from a peer (macOS receiving side).
    @Published public var lastReceivedScan: URL?
    /// Live transfer progress (0…1) for the in-flight resource.
    @Published public var transferProgress: Double = 0
    /// Called on the main queue when a scan archive finishes arriving. The optional mode is
    /// carried in the resource name so a Mac can preserve RoomPlan versus image-scan behavior.
    public var onReceiveScan: ((URL, MCPeerID, ScanHandoffMetadata) -> Void)?
    public var onReceiveResultPackage: ((URL, MCPeerID, ScanHandoffMetadata) -> Void)?
    public var onSendError: ((Error) -> Void)?
    private let progressLock = NSLock()
    private var activeProgress: [UUID: Progress] = [:]
    private var progressObservations: [UUID: NSKeyValueObservation] = [:]
    private var incomingTransferIDs: [String: [UUID]] = [:]
    private var peerIDsByInstallationID: [HandoffInstallationID: MCPeerID] = [:]
    private var invitationRecords: [UUID: PendingInvitationRecord] = [:]
    private let controlEvents = PassthroughSubject<HandoffControlEvent, Never>()
    private var seenMessageIDs: Set<UUID> = []
    private var seenMessageOrder: [UUID] = []

    public override init() {
        localInstallationID = HandoffInstallationIdentityStore().loadOrCreate()
        #if os(iOS)
        myPeerId = MCPeerID(displayName: UIDevice.current.name)
        #else
        myPeerId = MCPeerID(displayName: Host.current().localizedName ?? "3DSeen Device")
        #endif
        super.init()

        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self

        #if os(iOS)
        // iOS advertises its scans
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerId,
            discoveryInfo: Self.discoveryInfo(for: localPeer),
            serviceType: serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        #elseif os(macOS)
        // macOS browses for incoming scans
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        #endif
    }

    deinit {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
    }

    private var localPeer: HandoffPeer {
        #if os(iOS)
        let platform = HandoffPeerPlatform.iOS
        let capabilities: Set<HandoffCapability> = [.captureSender]
        #else
        let platform = HandoffPeerPlatform.macOS
        let capabilities: Set<HandoffCapability> = [.photogrammetry, .trainedSplat, .blenderExport]
        #endif
        return HandoffPeer(
            installationID: localInstallationID,
            displayName: myPeerId.displayName,
            platform: platform,
            capabilities: capabilities,
            connectionState: .discovered
        )
    }

    public func installationID(for peerID: MCPeerID) -> HandoffInstallationID? {
        peerIDsByInstallationID.first { $0.value == peerID }?.key
    }

    public func peerID(for installationID: HandoffInstallationID) -> MCPeerID? {
        peerIDsByInstallationID[installationID]
    }

    public func invite(peerID: HandoffInstallationID) {
        guard let peerIDValue = peerIDsByInstallationID[peerID],
              let peer = discoveredPeers.first(where: { $0.installationID == peerID }) else { return }
        updatePeer(peer, state: .inviting)
        let context = try? JSONEncoder().encode(localPeer)
        browser?.invitePeer(peerIDValue, to: session, withContext: context, timeout: 30)
    }

    public func respond(to invitationID: UUID, accept: Bool) {
        guard let record = invitationRecords.removeValue(forKey: invitationID) else { return }
        pendingInvitations.removeAll { $0.id == invitationID }
        record.handler(accept, accept ? session : nil)
    }

    @discardableResult
    public func send(_ message: HandoffMessageEnvelope, to peerID: HandoffInstallationID) -> Bool {
        guard message.senderInstallationID == localInstallationID,
              let destination = peerIDsByInstallationID[peerID],
              session.connectedPeers.contains(destination) else { return false }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: [destination], with: .reliable)
            return true
        } catch {
            logger.error("Control message send failed: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { self.onSendError?(error) }
            return false
        }
    }

    public func sendResource(fileURL: URL, named resourceName: String? = nil, to peer: MCPeerID,
                             completion: ((Error?) -> Void)? = nil) {
        let name = resourceName ?? fileURL.lastPathComponent
        let transferID = UUID()
        logger.debug("Sending resource \(name, privacy: .public) to \(peer.displayName, privacy: .public)")
        let maybeProgress = session.sendResource(at: fileURL, withName: name, toPeer: peer) { [weak self] error in
            self?.finishProgress(id: transferID, succeeded: error == nil)
            if let error {
                self?.logger.error("Resource send failed: \(error.localizedDescription, privacy: .public)")
            } else {
                self?.logger.info("Resource sent: \(name, privacy: .public)")
            }
            DispatchQueue.main.async {
                if let error { self?.onSendError?(error) }
                completion?(error)
            }
        }
        guard let progress = maybeProgress else {
            DispatchQueue.main.async { self.transferProgress = 0 }
            return
        }
        observe(progress, id: transferID)
    }

    /// Deletes a resource only when it is inside this manager's UUID-scoped inbox. Callers can
    /// safely invoke this after importing a handoff without risking arbitrary user-selected files.
    public func removeReceivedResource(_ url: URL) {
        let fileManager = FileManager.default
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let inbox = base.appendingPathComponent("3DSeen/Inbox", isDirectory: true).standardizedFileURL.path + "/"
        let resourcePath = url.standardizedFileURL.path
        guard resourcePath.hasPrefix(inbox) else { return }
        try? fileManager.removeItem(at: url.deletingLastPathComponent())
    }

    public func sendScan(fileURL: URL, to peer: MCPeerID, metadata: ScanHandoffMetadata = .init()) {
        logger.debug("Sending scan to \(peer.displayName)...")
        let resourceName = metadata.captureMode == nil
            ? fileURL.lastPathComponent
            : Self.handoffResourceName(for: fileURL, metadata: metadata)
        sendResource(fileURL: fileURL, named: resourceName, to: peer)
    }

    @discardableResult
    public func sendScan(
        _ fileURL: URL,
        to peerID: HandoffInstallationID,
        metadata: ScanHandoffMetadata = .init()
    ) -> Bool {
        guard let peer = peerIDsByInstallationID[peerID], session.connectedPeers.contains(peer) else {
            logger.warning("The selected handoff peer is not connected.")
            return false
        }
        sendScan(fileURL: fileURL, to: peer, metadata: metadata)
        return true
    }

    /// Legacy convenience retained while the macOS result path migrates to stable peer IDs.
    @discardableResult
    public func sendScanToFirstPeer(_ fileURL: URL, metadata: ScanHandoffMetadata = .init()) -> Bool {
        guard let peer = session.connectedPeers.first else {
            logger.warning("No connected peer to hand off to.")
            return false
        }
        sendScan(fileURL: fileURL, to: peer, metadata: metadata)
        return true
    }
}

@MainActor
extension NetworkHandoffManager: ScanHandoffTransport {
    public var discoveredPeersPublisher: AnyPublisher<[HandoffPeer], Never> {
        $discoveredPeers.eraseToAnyPublisher()
    }

    public var connectedHandoffPeersPublisher: AnyPublisher<[HandoffPeer], Never> {
        $connectedHandoffPeers.eraseToAnyPublisher()
    }

    public var pendingInvitationsPublisher: AnyPublisher<[HandoffInvitation], Never> {
        $pendingInvitations.eraseToAnyPublisher()
    }

    public var controlEventsPublisher: AnyPublisher<HandoffControlEvent, Never> {
        controlEvents.eraseToAnyPublisher()
    }

    public var transferProgressPublisher: AnyPublisher<Double, Never> {
        $transferProgress.eraseToAnyPublisher()
    }
}

extension NetworkHandoffManager: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            guard let installationID = self.peerIDsByInstallationID.first(where: { $0.value == peerID })?.key,
                  let peer = self.discoveredPeers.first(where: { $0.installationID == installationID }) else { return }
            switch state {
            case .connected:
                self.updatePeer(peer, state: .connected)
                let hello = HandoffMessageEnvelope(
                    senderInstallationID: self.localInstallationID,
                    payload: .hello(self.localPeer)
                )
                _ = self.send(hello, to: installationID)
            case .connecting:
                self.updatePeer(peer, state: .inviting)
            case .notConnected:
                self.updatePeer(peer, state: .discovered)
            @unknown default:
                self.updatePeer(peer, state: .discovered)
            }
        }
        logger.debug("Peer \(peerID.displayName) state changed to \(state.rawValue)")
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(HandoffMessageEnvelope.self, from: data) else {
            logger.warning("Ignoring malformed handoff control data.")
            return
        }
        DispatchQueue.main.async {
            guard let peerIDValue = self.peerIDsByInstallationID.first(where: { $0.value == peerID })?.key,
                  peerIDValue == message.senderInstallationID,
                  self.recordMessageIfNew(message.id) else {
                self.logger.warning("Ignoring uncorrelated or duplicate handoff control message.")
                return
            }
            do {
                try message.validateVersion()
                self.controlEvents.send(.init(message: message, peerID: peerIDValue))
            } catch {
                let rejection = HandoffMessageEnvelope(
                    senderInstallationID: self.localInstallationID,
                    payload: .protocolRejected(
                        minimum: HandoffProtocolVersion.minimumSupported,
                        maximum: HandoffProtocolVersion.current
                    )
                )
                _ = self.send(rejection, to: peerIDValue)
            }
        }
    }
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        logger.debug("Started receiving \(resourceName) from \(peerID.displayName)")
        let transferID = UUID()
        let key = incomingTransferKey(resourceName: resourceName, peerID: peerID)
        progressLock.lock()
        incomingTransferIDs[key, default: []].append(transferID)
        progressLock.unlock()
        observe(progress, id: transferID)
    }

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        let transferID = popIncomingTransferID(resourceName: resourceName, peerID: peerID)
        if let transferID { finishProgress(id: transferID, succeeded: error == nil) }
        if let error = error {
            logger.error("Failed to receive \(resourceName): \(error.localizedDescription)")
            return
        }
        guard let localURL else { return }
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let transferDirectory = base
            .appendingPathComponent("3DSeen", isDirectory: true)
            .appendingPathComponent("Inbox", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let metadata = Self.handoffMetadata(from: resourceName)
        let destinationName = URL(fileURLWithPath: Self.handoffOriginalResourceName(from: resourceName)).lastPathComponent
        let destination = transferDirectory.appendingPathComponent(destinationName)
        do {
            try fileManager.createDirectory(at: transferDirectory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: localURL, to: destination)
            logger.info("Received \(resourceName) → \(destination.path)")
            DispatchQueue.main.async {
                self.transferProgress = 1
                self.lastReceivedScan = destination
                if destinationName.hasSuffix(ScanResultPackage.fileSuffix) {
                    self.onReceiveResultPackage?(destination, peerID, metadata)
                } else {
                    self.onReceiveScan?(destination, peerID, metadata)
                }
            }
        } catch {
            logger.error("Could not move received resource: \(error.localizedDescription)")
        }
    }
}

extension NetworkHandoffManager {
    private static let handoffPrefix = "3dseen-handoff-v1-"
    private static let discoveryInstallationKey = "installationID"
    private static let discoveryProtocolKey = "protocol"
    private static let discoveryPlatformKey = "platform"
    private static let discoveryCapabilitiesKey = "capabilities"

    private static func discoveryInfo(for peer: HandoffPeer) -> [String: String] {
        [
            discoveryInstallationKey: peer.installationID.rawValue.uuidString,
            discoveryProtocolKey: String(peer.protocolVersion),
            discoveryPlatformKey: peer.platform.rawValue,
            discoveryCapabilitiesKey: peer.capabilities.map(\.rawValue).sorted().joined(separator: ","),
        ]
    }

    private static func handoffPeer(displayName: String, discoveryInfo: [String: String]?) -> HandoffPeer? {
        guard let discoveryInfo,
              let rawID = discoveryInfo[discoveryInstallationKey],
              let uuid = UUID(uuidString: rawID),
              let rawVersion = discoveryInfo[discoveryProtocolKey],
              let version = Int(rawVersion),
              let rawPlatform = discoveryInfo[discoveryPlatformKey],
              let platform = HandoffPeerPlatform(rawValue: rawPlatform) else { return nil }
        let capabilities = Set(
            (discoveryInfo[discoveryCapabilitiesKey] ?? "")
                .split(separator: ",")
                .compactMap { HandoffCapability(rawValue: String($0)) }
        )
        return HandoffPeer(
            installationID: HandoffInstallationID(rawValue: uuid),
            displayName: displayName,
            platform: platform,
            protocolVersion: version,
            capabilities: capabilities
        )
    }

    private func register(_ peer: HandoffPeer, peerID: MCPeerID) {
        peerIDsByInstallationID[peer.installationID] = peerID
        if let index = discoveredPeers.firstIndex(where: { $0.installationID == peer.installationID }) {
            discoveredPeers[index] = peer
        } else {
            discoveredPeers.append(peer)
        }
        discoveredPeers.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        refreshConnectedHandoffPeers()
    }

    private func updatePeer(_ peer: HandoffPeer, state: HandoffPeerConnectionState) {
        var updated = peer
        updated.connectionState = state
        if let index = discoveredPeers.firstIndex(where: { $0.installationID == updated.installationID }) {
            discoveredPeers[index] = updated
        } else {
            discoveredPeers.append(updated)
        }
        refreshConnectedHandoffPeers()
    }

    private func refreshConnectedHandoffPeers() {
        let connectedIDs = Set(session.connectedPeers.compactMap { connectedPeer in
            peerIDsByInstallationID.first(where: { $0.value == connectedPeer })?.key
        })
        connectedHandoffPeers = discoveredPeers.filter { connectedIDs.contains($0.installationID) }
    }

    private func expireInvitation(_ invitationID: UUID) {
        guard let record = invitationRecords.removeValue(forKey: invitationID) else { return }
        pendingInvitations.removeAll { $0.id == invitationID }
        record.handler(false, nil)
    }

    private func recordMessageIfNew(_ messageID: UUID) -> Bool {
        guard seenMessageIDs.insert(messageID).inserted else { return false }
        seenMessageOrder.append(messageID)
        if seenMessageOrder.count > 512 {
            let removalCount = seenMessageOrder.count - 512
            let expired = Array(seenMessageOrder.prefix(removalCount))
            seenMessageOrder.removeFirst(removalCount)
            seenMessageIDs.subtract(expired)
        }
        return true
    }

    static func handoffResourceName(for fileURL: URL, metadata: ScanHandoffMetadata) -> String {
        guard let captureMode = metadata.captureMode else { return fileURL.lastPathComponent }
        let envelope = ScanHandoffResourceEnvelope(
            jobID: metadata.jobID,
            scanID: metadata.scanID,
            captureModeRaw: captureMode.rawValue,
            detailTier: metadata.detailTier,
            originalName: fileURL.lastPathComponent
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return fileURL.lastPathComponent }
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return handoffPrefix + encoded
    }

    static func handoffMetadata(from resourceName: String) -> ScanHandoffMetadata {
        guard let envelope = handoffEnvelope(from: resourceName) else {
            return legacyHandoffParts(from: resourceName)?.metadata ?? .init()
        }
        return .init(
            jobID: envelope.jobID,
            scanID: envelope.scanID,
            captureMode: CaptureMode(rawValue: envelope.captureModeRaw),
            detailTier: envelope.detailTier
        )
    }

    static func handoffOriginalResourceName(from resourceName: String) -> String {
        handoffEnvelope(from: resourceName)?.originalName
            ?? legacyHandoffParts(from: resourceName)?.originalName
            ?? resourceName
    }

    private static func handoffEnvelope(from resourceName: String) -> ScanHandoffResourceEnvelope? {
        guard resourceName.hasPrefix(handoffPrefix) else { return nil }
        var encoded = String(resourceName.dropFirst(handoffPrefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - encoded.count % 4) % 4
        encoded += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return try? JSONDecoder().decode(ScanHandoffResourceEnvelope.self, from: data)
    }

    private static func legacyHandoffParts(from resourceName: String)
        -> (metadata: ScanHandoffMetadata, originalName: String)? {
        let prefix = "3dseen-handoff-"
        guard resourceName.hasPrefix(prefix) else { return nil }
        let remaining = String(resourceName.dropFirst(prefix.count))
        let modes = CaptureMode.allCases.sorted { $0.rawValue.count > $1.rawValue.count }
        guard let mode = modes.first(where: {
            remaining.hasPrefix($0.rawValue.lowercased() + "-")
        }) else { return nil }
        let afterMode = remaining.dropFirst(mode.rawValue.count + 1)
        guard let separator = afterMode.firstIndex(of: "-") else {
            return (.init(captureMode: mode), String(afterMode))
        }
        let tierValue = String(afterMode[..<separator]).replacingOccurrences(of: "_", with: " ")
        let originalName = String(afterMode[afterMode.index(after: separator)...])
        let tier = tierValue == "default" ? nil : tierValue.capitalized
        return (.init(captureMode: mode, detailTier: tier), originalName)
    }

    private func incomingTransferKey(resourceName: String, peerID: MCPeerID) -> String {
        "\(peerID.displayName)|\(resourceName)"
    }

    private func popIncomingTransferID(resourceName: String, peerID: MCPeerID) -> UUID? {
        let key = incomingTransferKey(resourceName: resourceName, peerID: peerID)
        progressLock.lock()
        defer { progressLock.unlock() }
        guard var ids = incomingTransferIDs[key], !ids.isEmpty else { return nil }
        let id = ids.removeFirst()
        if ids.isEmpty { incomingTransferIDs.removeValue(forKey: key) } else { incomingTransferIDs[key] = ids }
        return id
    }

    private func observe(_ progress: Progress, id: UUID) {
        let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] _, _ in
            self?.publishAggregateProgress()
        }
        progressLock.lock()
        activeProgress[id] = progress
        progressObservations[id] = observation
        progressLock.unlock()
        publishAggregateProgress()
    }

    private func finishProgress(id: UUID, succeeded: Bool) {
        progressLock.lock()
        activeProgress.removeValue(forKey: id)
        progressObservations.removeValue(forKey: id)
        let remaining = activeProgress.values.map(\.fractionCompleted)
        progressLock.unlock()
        let value = remaining.isEmpty
            ? (succeeded ? 1 : 0)
            : remaining.reduce(0, +) / Double(remaining.count)
        DispatchQueue.main.async { self.transferProgress = value }
    }

    private func publishAggregateProgress() {
        progressLock.lock()
        let fractions = activeProgress.values.map(\.fractionCompleted)
        progressLock.unlock()
        let value = fractions.isEmpty ? 0 : fractions.reduce(0, +) / Double(fractions.count)
        DispatchQueue.main.async { self.transferProgress = value }
    }
}

extension NetworkHandoffManager: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                           didReceiveInvitationFromPeer peerID: MCPeerID,
                           withContext context: Data?,
                           invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        guard let context,
              let peer = try? JSONDecoder().decode(HandoffPeer.self, from: context),
              (try? HandoffProtocolVersion.validate(peer.protocolVersion)) != nil else {
            invitationHandler(false, nil)
            return
        }
        DispatchQueue.main.async {
            self.register(peer, peerID: peerID)
            let invitation = HandoffInvitation(peer: peer, expiresAt: Date().addingTimeInterval(30))
            self.invitationRecords[invitation.id] = PendingInvitationRecord(
                invitation: invitation,
                handler: invitationHandler
            )
            self.pendingInvitations.append(invitation)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.expireInvitation(invitation.id)
            }
        }
    }
}

extension NetworkHandoffManager: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        logger.debug("Found peer: \(peerID.displayName)")
        guard let peer = Self.handoffPeer(displayName: peerID.displayName, discoveryInfo: info),
              (try? HandoffProtocolVersion.validate(peer.protocolVersion)) != nil else {
            logger.warning("Ignoring peer with missing or unsupported discovery identity.")
            return
        }
        DispatchQueue.main.async { self.register(peer, peerID: peerID) }
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.debug("Lost peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            guard !self.session.connectedPeers.contains(peerID),
                  let entry = self.peerIDsByInstallationID.first(where: { $0.value == peerID }) else { return }
            self.peerIDsByInstallationID.removeValue(forKey: entry.key)
            self.discoveredPeers.removeAll { $0.installationID == entry.key }
            self.refreshConnectedHandoffPeers()
        }
    }
}
