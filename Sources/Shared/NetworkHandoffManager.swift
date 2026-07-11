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
    public let scanID: UUID?
    public let captureMode: CaptureMode?
    public let detailTier: String?

    public init(scanID: UUID? = nil, captureMode: CaptureMode? = nil, detailTier: String? = nil) {
        self.scanID = scanID
        self.captureMode = captureMode
        self.detailTier = detailTier
    }
}

private struct ScanHandoffResourceEnvelope: Codable {
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
    /// Called on the main queue when a scan archive finishes arriving. The optional mode is
    /// carried in the resource name so a Mac can preserve RoomPlan versus image-scan behavior.
    public var onReceiveScan: ((URL, MCPeerID, ScanHandoffMetadata) -> Void)?
    public var onReceiveResultPackage: ((URL, MCPeerID) -> Void)?
    public var onSendError: ((Error) -> Void)?
    private let progressLock = NSLock()
    private var activeProgress: [UUID: Progress] = [:]
    private var progressObservations: [UUID: NSKeyValueObservation] = [:]
    private var incomingTransferIDs: [String: [UUID]] = [:]

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

    /// Convenience for iOS: hand the scan to the first connected Mac.
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
                if resourceName.hasSuffix(ScanResultPackage.fileSuffix) {
                    self.onReceiveResultPackage?(destination, peerID)
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

    static func handoffResourceName(for fileURL: URL, metadata: ScanHandoffMetadata) -> String {
        guard let captureMode = metadata.captureMode else { return fileURL.lastPathComponent }
        let envelope = ScanHandoffResourceEnvelope(
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
