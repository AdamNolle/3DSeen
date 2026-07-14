import CryptoKit
import Foundation

public enum HandoffProtocolVersion {
    public static let current = 2
    public static let minimumSupported = 1

    public static func validate(_ version: Int) throws {
        guard (minimumSupported...current).contains(version) else {
            throw HandoffProtocolError.unsupportedVersion(version)
        }
    }
}

public enum HandoffProtocolError: LocalizedError, Equatable {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Handoff protocol version \(version) is not supported."
        }
    }
}

public struct HandoffInstallationID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.rawValue = UUID()
    }
}

public struct HandoffInstallationIdentityStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "handoff.installationID") {
        self.defaults = defaults
        self.key = key
    }

    public func loadOrCreate() -> HandoffInstallationID {
        if let raw = defaults.string(forKey: key), let id = UUID(uuidString: raw) {
            return HandoffInstallationID(rawValue: id)
        }
        let id = HandoffInstallationID()
        defaults.set(id.rawValue.uuidString, forKey: key)
        return id
    }
}

public enum HandoffPeerPlatform: String, Codable, Sendable {
    case iOS
    case macOS
}

public enum HandoffCapability: String, Codable, CaseIterable, Sendable {
    case captureSender
    case photogrammetry
    case trainedSplat
    case blenderExport
}

public enum HandoffPeerConnectionState: String, Codable, Sendable {
    case discovered
    case inviting
    case connected
    case pairing
    case authenticated
}

public struct HandoffPeer: Codable, Equatable, Identifiable, Sendable {
    public var id: HandoffInstallationID { installationID }
    public let installationID: HandoffInstallationID
    public var displayName: String
    public var platform: HandoffPeerPlatform
    public var protocolVersion: Int
    public var capabilities: Set<HandoffCapability>
    public var connectionState: HandoffPeerConnectionState

    public init(
        installationID: HandoffInstallationID,
        displayName: String,
        platform: HandoffPeerPlatform,
        protocolVersion: Int = HandoffProtocolVersion.current,
        capabilities: Set<HandoffCapability> = [],
        connectionState: HandoffPeerConnectionState = .discovered
    ) {
        self.installationID = installationID
        self.displayName = displayName
        self.platform = platform
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.connectionState = connectionState
    }
}

public struct HandoffInvitation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let peer: HandoffPeer
    public let expiresAt: Date

    public init(id: UUID = UUID(), peer: HandoffPeer, expiresAt: Date) {
        self.id = id
        self.peer = peer
        self.expiresAt = expiresAt
    }
}

public enum HandoffFailureCode: String, Codable, Sendable {
    case unsupportedProtocol
    case untrustedPeer
    case missingArchive
    case corruptArchive
    case reconstructionFailed
    case resultPackagingFailed
    case transferFailed
    case cancelled
    case timedOut
}

public struct HandoffFailure: Codable, Equatable, Sendable {
    public let code: HandoffFailureCode
    public let detail: String

    public init(code: HandoffFailureCode, detail: String) {
        self.code = code
        self.detail = detail
    }
}

public struct HandoffResourceDescriptor: Codable, Equatable, Sendable {
    public let byteCount: Int64
    public let sha256: String

    public init(byteCount: Int64, sha256: String) {
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    public static func inspect(_ url: URL) throws -> HandoffResourceDescriptor {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return HandoffResourceDescriptor(
            byteCount: Int64(values.fileSize ?? 0),
            sha256: digest.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }
}

public struct HandoffJobOffer: Codable, Equatable, Sendable {
    public let captureModeRaw: String
    public let detailTier: String
    public let resource: HandoffResourceDescriptor

    public init(captureMode: CaptureMode, detailTier: String, resource: HandoffResourceDescriptor) {
        self.captureModeRaw = captureMode.rawValue
        self.detailTier = detailTier
        self.resource = resource
    }

    public var captureMode: CaptureMode {
        CaptureMode(rawValue: captureModeRaw) ?? .object
    }
}

public struct HandoffJobStatus: Codable, Equatable, Sendable {
    public let state: HandoffJobState
    public let progress: Double

    public init(state: HandoffJobState, progress: Double) {
        self.state = state
        self.progress = min(max(progress, 0), 1)
    }
}

public enum HandoffMessagePayload: Codable, Equatable, Sendable {
    case hello(HandoffPeer)
    case authenticationChallenge(Data)
    case authenticationResponse(Data)
    case jobOffer(HandoffJobOffer)
    case jobAccepted
    case progress(Double)
    case resultReady(HandoffResourceDescriptor)
    case failed(HandoffFailure)
    case cancel
    case cancelled
    case statusRequest
    case statusResponse(HandoffJobStatus)
    case protocolRejected(minimum: Int, maximum: Int)
}

public struct HandoffMessageEnvelope: Codable, Equatable, Identifiable, Sendable {
    public let protocolVersion: Int
    public let id: UUID
    public let jobID: UUID?
    public let scanID: UUID?
    public let senderInstallationID: HandoffInstallationID
    public let sentAt: Date
    public let payload: HandoffMessagePayload

    public init(
        protocolVersion: Int = HandoffProtocolVersion.current,
        id: UUID = UUID(),
        jobID: UUID? = nil,
        scanID: UUID? = nil,
        senderInstallationID: HandoffInstallationID,
        sentAt: Date = Date(),
        payload: HandoffMessagePayload
    ) {
        self.protocolVersion = protocolVersion
        self.id = id
        self.jobID = jobID
        self.scanID = scanID
        self.senderInstallationID = senderInstallationID
        self.sentAt = sentAt
        self.payload = payload
    }

    public func validateVersion() throws {
        try HandoffProtocolVersion.validate(protocolVersion)
    }
}

public enum HandoffPeerSelectionPolicy {
    public static func preferredPeer(
        connectedPeers: [HandoffPeer],
        authenticatedPeerIDs: Set<HandoffInstallationID>,
        autoSelect: Bool
    ) -> HandoffInstallationID? {
        guard autoSelect else { return nil }
        let authenticated = connectedPeers.filter {
            authenticatedPeerIDs.contains($0.installationID)
        }
        guard authenticated.count == 1 else { return nil }
        return authenticated[0].installationID
    }
}

public struct HandoffControlEvent: Equatable, Sendable {
    public let message: HandoffMessageEnvelope
    public let peerID: HandoffInstallationID

    public init(message: HandoffMessageEnvelope, peerID: HandoffInstallationID) {
        self.message = message
        self.peerID = peerID
    }
}

public enum HandoffJobState: String, Codable, CaseIterable, Sendable {
    case queued
    case awaitingPeer
    case pairing
    case offered
    case accepted
    case sending
    case processing
    case returning
    case completed
    case failed
    case cancelled
    case interrupted

    public var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }

    public func canTransition(to next: HandoffJobState) -> Bool {
        guard self != next else { return true }
        switch (self, next) {
        case (.queued, .awaitingPeer),
             (.queued, .sending),
             (.awaitingPeer, .pairing),
             (.awaitingPeer, .offered),
             (.pairing, .offered),
             (.offered, .accepted),
             (.accepted, .sending),
             (.awaitingPeer, .sending),
             (.sending, .processing),
             (.processing, .returning),
             (.returning, .completed),
             (.interrupted, .awaitingPeer),
             (.interrupted, .sending),
             (.failed, .queued):
            return true
        case (_, .failed), (_, .cancelled),
             (.offered, .interrupted), (.accepted, .interrupted),
             (.sending, .interrupted), (.processing, .interrupted), (.returning, .interrupted):
            return !isTerminal
        default:
            return false
        }
    }
}

public struct HandoffJobRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let scanID: UUID
    public var peerName: String?
    public var peerInstallationID: HandoffInstallationID?
    public var captureModeRaw: String
    public var detailTier: String
    public var state: HandoffJobState
    public var createdAt: Date
    public var updatedAt: Date
    public var attemptCount: Int
    public var progress: Double
    public var lastError: String?
    public var responseDeadline: Date?

    public init(
        id: UUID = UUID(),
        scanID: UUID,
        peerName: String? = nil,
        peerInstallationID: HandoffInstallationID? = nil,
        captureMode: CaptureMode,
        detailTier: String,
        state: HandoffJobState = .queued,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        attemptCount: Int = 0,
        progress: Double = 0,
        lastError: String? = nil,
        responseDeadline: Date? = nil
    ) {
        self.id = id
        self.scanID = scanID
        self.peerName = peerName
        self.peerInstallationID = peerInstallationID
        self.captureModeRaw = captureMode.rawValue
        self.detailTier = detailTier
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attemptCount = attemptCount
        self.progress = min(max(progress, 0), 1)
        self.lastError = lastError
        self.responseDeadline = responseDeadline
    }

    public var captureMode: CaptureMode {
        CaptureMode(rawValue: captureModeRaw) ?? .object
    }

    public mutating func transition(to next: HandoffJobState, error: String? = nil, now: Date = Date()) throws {
        guard state.canTransition(to: next) else {
            throw HandoffJobError.invalidTransition(from: state, to: next)
        }
        state = next
        updatedAt = now
        lastError = error
        if next == .sending { attemptCount += 1 }
        if next == .completed { progress = 1 }
        if next.isTerminal { responseDeadline = nil }
    }
}

public enum HandoffJobError: LocalizedError, Equatable {
    case invalidTransition(from: HandoffJobState, to: HandoffJobState)

    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let from, let to):
            return "A handoff job cannot move from \(from.rawValue) to \(to.rawValue)."
        }
    }
}

/// Atomic JSON journal used as the durable authority for cross-launch handoff state.
public actor HandoffJobJournal {
    private let fileURL: URL
    private var records: [HandoffJobRecord]?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func all() throws -> [HandoffJobRecord] {
        if let records { return records }
        let loaded: [HandoffJobRecord]
        if FileManager.default.fileExists(atPath: fileURL.path) {
            loaded = try JSONDecoder().decode([HandoffJobRecord].self, from: Data(contentsOf: fileURL))
        } else {
            loaded = []
        }
        records = loaded
        return loaded
    }

    public func upsert(_ record: HandoffJobRecord) throws {
        var values = try all()
        if let index = values.firstIndex(where: { $0.id == record.id }) {
            values[index] = record
        } else {
            values.append(record)
        }
        try persist(values)
    }

    public func remove(_ id: UUID) throws {
        let values = try all().filter { $0.id != id }
        try persist(values)
    }

    public func markInterruptedWork(now: Date = Date()) throws -> [HandoffJobRecord] {
        var values = try all()
        for index in values.indices where [
            .offered, .accepted, .sending, .processing, .returning,
        ].contains(values[index].state) {
            values[index].state = .interrupted
            values[index].updatedAt = now
            values[index].lastError = "The app closed before this handoff finished. Retry when the peer reconnects."
        }
        try persist(values)
        return values
    }

    private func persist(_ values: [HandoffJobRecord]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(values)
        try data.write(to: fileURL, options: .atomic)
        records = values
    }
}
