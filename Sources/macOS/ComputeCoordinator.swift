import Foundation
import Combine
import MultipeerConnectivity
import ZIPFoundation
import RealityKit
import OSLog

/// A completed model retained by the Mac app. The record is reconstructed from the durable
/// scan manifest at launch, rather than from design-time sample data.
public struct MacComputedScan: Identifiable, Equatable {
    public let manifest: ScanAssetManifest
    public let modelURL: URL
    public let byteCount: Int64
    public let creationDate: Date

    public var id: UUID { manifest.scanID }
    public var name: String {
        manifest.displayName ?? "\(manifest.captureMode.rawValue)-\(manifest.scanID.uuidString.prefix(8))"
    }
    public var sizeMB: Int { max(0, Int((Double(byteCount) / 1_000_000).rounded(.up))) }
    public var isRenderable: Bool { FileManager.default.fileExists(atPath: modelURL.path) }
}

/// Derived display facts for the desktop library. Counts and storage always originate from
/// actual persisted scan records, so an empty library stays empty.
public struct MacLibrarySummary: Equatable {
    public let scanCount: Int
    public let objectCount: Int
    public let spaceCount: Int
    public let landscapeCount: Int
    public let totalByteCount: Int64

    public init(scans: [MacComputedScan]) {
        scanCount = scans.count
        objectCount = scans.filter { $0.manifest.captureMode == .object }.count
        spaceCount = scans.filter { $0.manifest.captureMode == .space }.count
        landscapeCount = scans.filter { $0.manifest.captureMode == .landscape }.count
        totalByteCount = scans.reduce(0) { $0 + max(0, $1.byteCount) }
    }

    public var storageText: String {
        if totalByteCount < 1_000_000 { return "\(totalByteCount / 1_000) KB" }
        if totalByteCount < 1_000_000_000 { return String(format: "%.1f MB", Double(totalByteCount) / 1_000_000) }
        return String(format: "%.2f GB", Double(totalByteCount) / 1_000_000_000)
    }
}

/// Drives the macOS "Studio" compute dashboard: receives a scan archive over MultipeerConnectivity,
/// unzips it, runs RealityKit PhotogrammetrySession on Apple Silicon, and publishes pipeline state.
@MainActor
public final class ComputeCoordinator: ObservableObject {
    public enum SplatOutput: String, CaseIterable, Identifiable {
        case geometryPreview
        case trainedSplat

        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .geometryPreview: return "Geometry preview"
            case .trainedSplat: return "Trained splat"
            }
        }
    }

    private struct PendingHandoff {
        let archive: URL
        let replyPeer: MCPeerID
        let peerInstallationID: HandoffInstallationID
        let metadata: ScanHandoffMetadata
    }

    private struct PendingOffer {
        let peerID: HandoffInstallationID
        let scanID: UUID
        let offer: HandoffJobOffer
    }

    private struct CompletionInput {
        let output: URL
        let scanID: UUID
        let rawArchiveURL: URL
        let captureMode: CaptureMode
        let detailTier: String
        let frameCount: Int
        let captureQualityReport: CaptureQualityReport?
        let replyPeer: MCPeerID?
        let replyPeerID: HandoffInstallationID?
        let jobID: UUID?
    }

    public enum Stage: Int, CaseIterable {
        case waiting, ingest, sparse, dense, mesh, texture, optimize, done
        public var label: String {
            switch self {
            case .waiting: return "Waiting for hand-off"
            case .ingest: return "Frame ingest"
            case .sparse: return "Sparse cloud"
            case .dense: return "Dense reconstruction"
            case .mesh: return "Meshing"
            case .texture: return "Texturing"
            case .optimize: return "Optimize & export"
            case .done: return "Complete"
            }
        }

        /// Pure mapping from photogrammetry progress to an active pipeline stage (unit-testable).
        public static func forProgress(_ p: Double) -> Stage {
            switch p {
            case ..<0.1:  return .ingest
            case ..<0.3:  return .sparse
            case ..<0.65: return .dense
            case ..<0.82: return .mesh
            case ..<0.97: return .texture
            default:      return .optimize
            }
        }
    }

    @Published public private(set) var stage: Stage = .waiting
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var receivedFrames = 0
    @Published public private(set) var outputURL: URL?
    @Published public private(set) var outputManifest: ScanAssetManifest?
    @Published public private(set) var libraryScans: [MacComputedScan] = []
    @Published public var selectedScanID: UUID?
    @Published public private(set) var log: [(time: String, message: String)] = []
    @Published public var peerName: String = "—"
    @Published public var selectedSplatOutput: SplatOutput = .geometryPreview
    @Published public private(set) var splatTrainerStage: NerfstudioSplatTrainer.Stage = .idle
    @Published public private(set) var pendingPairingRequests: [HandoffPairingRequest] = []
    @Published public private(set) var authenticatedPeerIDs: Set<HandoffInstallationID> = []
    @Published public private(set) var trustedPeerIDs: Set<HandoffInstallationID> = []
    @Published public private(set) var activeRemoteJobID: UUID?
    @Published public private(set) var queuedRemoteJobCount = 0

    public let network: NetworkHandoffManager
    public let pairing: HandoffPairingCoordinator
    public let runner = PhotogrammetryRunner()
    public let splatTrainer: NerfstudioSplatTrainer
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen", category: "Compute")
    private let assetStore: ScanAssetStore?
    private let remoteJobJournal: MacHandoffJobJournal
    private var pendingHandoffs: [PendingHandoff] = []
    private var pendingOffers: [UUID: PendingOffer] = [:]
    private var activeRemoteJob: (jobID: UUID, scanID: UUID, peerID: HandoffInstallationID)?
    private var cancelledRemoteJobIDs: Set<UUID> = []
    private var isDrainingHandoffs = false
    private var isExecutingProcess = false

    public init(
        splatTrainer: NerfstudioSplatTrainer? = nil,
        network: NetworkHandoffManager? = nil,
        credentialStore: (any PairingCredentialStore)? = nil,
        assetStore: ScanAssetStore? = try? ScanAssetStore(),
        remoteJobJournalURL: URL? = nil
    ) {
        let selectedNetwork = network ?? NetworkHandoffManager()
        self.network = selectedNetwork
        self.pairing = HandoffPairingCoordinator(
            transport: selectedNetwork,
            credentialStore: credentialStore
        )
        self.assetStore = assetStore
        let journalURL = remoteJobJournalURL
            ?? assetStore?.rootDirectory.deletingLastPathComponent()
                .appendingPathComponent("Handoff/mac-jobs.json")
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("3dseen-mac-jobs.json")
        self.remoteJobJournal = MacHandoffJobJournal(fileURL: journalURL)
        self.splatTrainer = splatTrainer ?? NerfstudioSplatTrainer()
        selectedNetwork.onReceiveScan = { [weak self] url, peer, metadata in
            Task { await self?.receiveHandoff(archive: url, peer: peer, metadata: metadata) }
        }
        selectedNetwork.$connectedPeers
            .receive(on: RunLoop.main)
            .sink { [weak self] peers in self?.peerName = peers.first?.displayName ?? "—" }
            .store(in: &cancellables)
        selectedNetwork.controlEventsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.handleControlEvent($0) }
            .store(in: &cancellables)
        pairing.$pendingRequests
            .sink { [weak self] in self?.pendingPairingRequests = $0 }
            .store(in: &cancellables)
        pairing.$authenticatedPeerIDs
            .sink { [weak self] in self?.authenticatedPeerIDs = $0 }
            .store(in: &cancellables)
        pairing.$trustedPeerIDs
            .sink { [weak self] in self?.trustedPeerIDs = $0 }
            .store(in: &cancellables)
        pairing.$lastError
            .compactMap { $0 }
            .sink { [weak self] in self?.addLog("Authentication: \($0)") }
            .store(in: &cancellables)
        // Map raw photogrammetry progress onto pipeline stages.
        runner.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                self?.mapProgress(progress)
                self?.sendActiveProgress(progress)
            }
            .store(in: &cancellables)
        self.splatTrainer.$stage
            .receive(on: RunLoop.main)
            .sink { [weak self] stage in self?.splatTrainerStage = stage }
            .store(in: &cancellables)
        do {
            try remoteJobJournal.recoverInterruptedWork(
                completedJobIDs: completedRemoteJobIDs(in: assetStore)
            )
        } catch {
            addLog("Remote job history could not be recovered: \(error.localizedDescription)")
        }
        reloadLibrary()
    }

    /// Reloads result manifests saved by this Mac app. Invalid or partially written folders are
    /// intentionally ignored so they never appear as completed scans in the library.
    public func reloadLibrary() {
        guard let assetStore else { return }
        let fm = FileManager.default
        let directories = (try? fm.contentsOfDirectory(
            at: assetStore.rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        libraryScans = directories.compactMap { directory in
            guard let scanID = UUID(uuidString: directory.lastPathComponent),
                  let manifest = try? assetStore.loadManifest(for: scanID) else {
                return nil
            }
            let candidateURLs = [manifest.usdzFileURL, manifest.sourceModelURL, manifest.previewPLYURL].compactMap { $0 }
            guard let modelURL = candidateURLs.first(where: { fm.fileExists(atPath: $0.path) }) else { return nil }
            let attributes = try? fm.attributesOfItem(atPath: modelURL.path)
            let byteCount = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let created = (try? directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return MacComputedScan(manifest: manifest, modelURL: modelURL, byteCount: byteCount, creationDate: created)
        }
        .sorted { $0.creationDate > $1.creationDate }

        if let selectedScanID, libraryScans.contains(where: { $0.id == selectedScanID }) {
            return
        }
        selectedScanID = libraryScans.first?.id
    }

    private func mapProgress(_ p: Double) {
        guard stage != .waiting && stage != .done else { return }
        progress = p
        stage = Stage.forProgress(p)
    }

    private func addLog(_ message: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        log.append((f.string(from: Date()), message))
        logger.info("\(message)")
    }

    private func handleControlEvent(_ event: HandoffControlEvent) {
        guard pairing.isAuthenticated(event.peerID) else { return }
        switch event.message.payload {
        case .jobOffer(let offer):
            guard let jobID = event.message.jobID, let scanID = event.message.scanID else {
                send(.failed(HandoffFailure(code: .corruptArchive, detail: "Job identity is missing.")), event: event)
                return
            }
            pendingOffers[jobID] = PendingOffer(peerID: event.peerID, scanID: scanID, offer: offer)
            recordRemoteJob(jobID: jobID, scanID: scanID, peerID: event.peerID, state: .accepted, progress: 0)
            updateQueueProjection()
            send(.jobAccepted, event: event)
            addLog("Accepted typed job offer \(jobID.uuidString.prefix(8))")
        case .cancel:
            guard let jobID = event.message.jobID else { return }
            cancelRemoteJob(jobID, event: event)
        case .statusRequest:
            let status: HandoffJobStatus
            let durableRecord = event.message.jobID.flatMap { remoteJobJournal.records[$0] }
            if activeRemoteJob?.jobID == event.message.jobID {
                status = HandoffJobStatus(state: .processing, progress: progress)
            } else if pendingOffers[event.message.jobID ?? UUID()] != nil {
                status = HandoffJobStatus(state: .accepted, progress: 0)
            } else if let durableRecord,
                      durableRecord.peerID == event.peerID,
                      durableRecord.scanID == event.message.scanID {
                status = HandoffJobStatus(state: durableRecord.state, progress: durableRecord.progress)
            } else {
                status = HandoffJobStatus(state: .failed, progress: 0)
            }
            send(.statusResponse(status), event: event)
            if let durableRecord, durableRecord.state == .completed {
                resendCompletedResult(durableRecord)
            }
        default:
            break
        }
    }

    private func receiveHandoff(archive: URL, peer: MCPeerID, metadata: ScanHandoffMetadata) async {
        guard let peerID = network.installationID(for: peer), pairing.isAuthenticated(peerID) else {
            network.removeReceivedResource(archive)
            addLog("Rejected unauthenticated scan resource from \(peer.displayName)")
            return
        }
        if let jobID = metadata.jobID {
            guard let offer = pendingOffers[jobID],
                  offer.peerID == peerID,
                  offer.scanID == metadata.scanID,
                  (try? HandoffResourceDescriptor.inspect(archive)) == offer.offer.resource else {
                network.removeReceivedResource(archive)
                if let scanID = metadata.scanID {
                    recordRemoteJob(jobID: jobID, scanID: scanID, peerID: peerID, state: .failed, progress: 0)
                }
                send(
                    .failed(HandoffFailure(code: .corruptArchive, detail: "The offered resource digest did not match.")),
                    jobID: jobID,
                    scanID: metadata.scanID,
                    to: peerID
                )
                addLog("Rejected uncorrelated or corrupt job resource")
                return
            }
            pendingOffers.removeValue(forKey: jobID)
            updateQueueProjection()
        }
        await enqueueHandoff(archive: archive, peer: peer, peerID: peerID, metadata: metadata)
    }

    private func enqueueHandoff(
        archive: URL,
        peer: MCPeerID,
        peerID: HandoffInstallationID,
        metadata: ScanHandoffMetadata
    ) async {
        pendingHandoffs.append(.init(
            archive: archive,
            replyPeer: peer,
            peerInstallationID: peerID,
            metadata: metadata
        ))
        updateQueueProjection()
        addLog("Queued hand-off from \(peer.displayName) (\(pendingHandoffs.count) waiting)")
        guard !isDrainingHandoffs else { return }
        isDrainingHandoffs = true
        defer { isDrainingHandoffs = false }
        while !pendingHandoffs.isEmpty {
            let handoff = pendingHandoffs.removeFirst()
            updateQueueProjection()
            await process(
                archive: handoff.archive,
                replyPeer: handoff.replyPeer,
                captureMode: handoff.metadata.captureMode,
                detailTier: handoff.metadata.detailTier,
                sourceScanID: handoff.metadata.scanID,
                replyPeerID: handoff.peerInstallationID,
                jobID: handoff.metadata.jobID
            )
        }
    }

    /// Retain an incoming capture, pass image archives to PhotogrammetrySession, or preserve an
    /// already-computed RoomPlan USDZ without pretending it needs image reconstruction.
    public func process(
        archive: URL,
        replyPeer: MCPeerID? = nil,
        captureMode: CaptureMode? = nil,
        detailTier: String? = nil,
        sourceScanID: UUID? = nil,
        replyPeerID: HandoffInstallationID? = nil,
        jobID: UUID? = nil
    ) async {
        defer { network.removeReceivedResource(archive) }
        guard !isExecutingProcess else {
            addLog("Rejected overlapping compute request; network hand-offs remain serialized")
            return
        }
        isExecutingProcess = true
        let remoteJob = jobID.flatMap { jobID in
            sourceScanID.flatMap { scanID in
                replyPeerID.map { (jobID: jobID, scanID: scanID, peerID: $0) }
            }
        }
        activeRemoteJob = remoteJob
        if let remoteJob {
            recordRemoteJob(
                jobID: remoteJob.jobID,
                scanID: remoteJob.scanID,
                peerID: remoteJob.peerID,
                state: .processing,
                progress: 0
            )
        }
        updateQueueProjection()
        var completed = false
        defer {
            isExecutingProcess = false
            if let remoteJob, !completed, cancelledRemoteJobIDs.remove(remoteJob.jobID) == nil {
                recordRemoteJob(
                    jobID: remoteJob.jobID,
                    scanID: remoteJob.scanID,
                    peerID: remoteJob.peerID,
                    state: .failed,
                    progress: progress
                )
                send(
                    .failed(HandoffFailure(
                        code: .reconstructionFailed,
                        detail: "Mac reconstruction did not complete."
                    )),
                    jobID: remoteJob.jobID,
                    scanID: remoteJob.scanID,
                    to: remoteJob.peerID
                )
            }
            if activeRemoteJob?.jobID == remoteJob?.jobID { activeRemoteJob = nil }
            updateQueueProjection()
        }
        stage = .ingest; progress = 0; outputURL = nil; outputManifest = nil
        addLog("Received \(archive.lastPathComponent)")

        guard let assetStore else {
            addLog("Persistent scan storage is unavailable")
            stage = .waiting
            return
        }

        let scanID = sourceScanID ?? UUID()
        let stagingDirectory = assetStore.rootDirectory
            .appendingPathComponent(".staging-\(scanID.uuidString)-\(UUID().uuidString)", isDirectory: true)
        let rawExtension = archive.pathExtension.isEmpty ? "data" : archive.pathExtension
        let rawArchiveURL = stagingDirectory.appendingPathComponent("raw-capture.\(rawExtension)")
        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: archive, to: rawArchiveURL)
        } catch {
            addLog("Could not stage hand-off: \(error.localizedDescription)")
            stage = .waiting
            return
        }
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        let out = stagingDirectory.appendingPathComponent("model.usdz")
        let mode = captureMode ?? .object

        // RoomPlan already produces an honest USDZ. Copy it into this Mac's durable scan store
        // and return it instead of attempting photogrammetry on an empty image folder.
        if archive.pathExtension.lowercased() == "usdz" {
            do {
                guard Self.isValidModel(at: rawArchiveURL) else {
                    throw ScanLocalComputeError.outputMissing(rawArchiveURL)
                }
                try ModelExporter().export(sourceModel: rawArchiveURL, to: .usdz, outputURL: out)
                guard Self.isValidModel(at: out) else {
                    throw ScanLocalComputeError.outputMissing(out)
                }
                try complete(.init(output: out, scanID: scanID, rawArchiveURL: rawArchiveURL,
                                   captureMode: mode, detailTier: "RoomPlan", frameCount: 0,
                                   captureQualityReport: nil, replyPeer: replyPeer,
                                   replyPeerID: replyPeerID, jobID: jobID))
                completed = true
            } catch {
                addLog("Could not retain RoomPlan model: \(error.localizedDescription)")
                stage = .waiting
            }
            return
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("compute-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let images = work.appendingPathComponent("images", isDirectory: true)
        var captureQualityReport: CaptureQualityReport?
        do {
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            guard rawArchiveURL.pathExtension.lowercased() == "zip" else {
                throw ScanLocalComputeError.captureArchiveHasNoImages(rawArchiveURL)
            }
            try FileManager.default.unzipItem(at: rawArchiveURL, to: images)
            captureQualityReport = ScanHandoffArchive.captureQualityReport(in: images)
            receivedFrames = CaptureArchiveInspector.decodableImageFrameCount(in: images)
            guard receivedFrames > 0 else {
                throw ScanLocalComputeError.captureArchiveHasNoImages(images)
            }
            addLog("Unpacked \(receivedFrames) image frames")
        } catch {
            addLog("Capture archive is unusable: \(error.localizedDescription)")
            stage = .waiting
            return
        }

        addLog("Photogrammetry started (RealityKit)")
        do {
            let requestedTier = detailTier ?? "Medium"
            try await runner.startProcessing(inputFolder: images, outputURL: out, detail: Self.photogrammetryDetail(for: requestedTier))
            let input = CompletionInput(output: out, scanID: scanID, rawArchiveURL: rawArchiveURL,
                                        captureMode: mode, detailTier: requestedTier, frameCount: receivedFrames,
                                        captureQualityReport: captureQualityReport, replyPeer: replyPeer,
                                        replyPeerID: replyPeerID, jobID: jobID)
            let trainedPreview = await trainSplatIfRequested(images: images, scanDirectory: stagingDirectory, scanID: scanID)
            try complete(input, previewOverride: trainedPreview?.url, previewKind: trainedPreview?.kind)
            completed = true
        } catch {
            addLog("Photogrammetry error: \(error.localizedDescription)")
            stage = .waiting
        }
    }

    private func trainSplatIfRequested(images: URL, scanDirectory: URL, scanID: UUID) async -> (url: URL, kind: SplatPreviewKind)? {
        guard selectedSplatOutput == .trainedSplat else { return nil }
        guard splatTrainer.isAvailable else {
            addLog("Trained splat is unavailable; saving a geometry preview")
            return nil
        }
        let work = scanDirectory.appendingPathComponent("splat-training", isDirectory: true)
        let job = NerfstudioSplatTrainer.Job(inputImagesURL: images, workingDirectory: work, scanID: scanID)
        defer { try? FileManager.default.removeItem(at: work) }
        addLog("Trained splat requested (7,000 MPS iterations)")
        splatTrainerStage = .preprocessing
        do {
            let preview = try await splatTrainer.train(job: job)
            let retainedPreview = scanDirectory.appendingPathComponent("trained-splat.ply")
            try FileManager.default.copyItem(at: preview, to: retainedPreview)
            splatTrainerStage = splatTrainer.stage
            addLog("Trained splat exported → \(retainedPreview.lastPathComponent)")
            return (retainedPreview, .trainedSplat)
        } catch {
            splatTrainerStage = splatTrainer.stage
            addLog("Trained splat failed; saving geometry preview: \(error.localizedDescription)")
            return nil
        }
    }

    private func complete(_ input: CompletionInput, previewOverride: URL? = nil,
                          previewKind: SplatPreviewKind? = nil) throws {
        guard FileManager.default.fileExists(atPath: input.output.path), let assetStore else {
            throw ScanLocalComputeError.outputMissing(input.output)
        }
        let stagingDirectory = input.output.deletingLastPathComponent()
        let finalDirectory = assetStore.rootDirectory.appendingPathComponent(input.scanID.uuidString, isDirectory: true)
        let finalOutput = finalDirectory.appendingPathComponent(input.output.lastPathComponent)
        let finalRawArchive = finalDirectory.appendingPathComponent(input.rawArchiveURL.lastPathComponent)
        let geometryPreviewURL = stagingDirectory.appendingPathComponent("geometry-preview.ply")
        let generatedPreview = previewOverride ?? (try? GaussianSplatGenerator.writeModelPreview(
            from: input.output,
            to: geometryPreviewURL
        ))
        let finalPreviewKind = previewKind ?? .geometryPreview
        if generatedPreview == nil {
            addLog("Could not generate geometry-derived splat preview")
        }
        let finalPreviewURL = generatedPreview.map {
            finalDirectory.appendingPathComponent($0.lastPathComponent)
        }
        let manifest = ScanAssetManifest(
            scanID: input.scanID,
            captureMode: input.captureMode,
            detailTier: input.detailTier,
            rawArchiveURL: finalRawArchive,
            sourceModelURL: finalOutput,
            usdzFileURL: finalOutput,
            previewPLYURL: finalPreviewURL,
            previewPLYKind: finalPreviewKind,
            frameCount: input.frameCount,
            coveragePercent: 0,
            weakSpotCount: 0,
            captureQualityReport: input.captureQualityReport,
            handoffJobID: input.jobID
        )
        try assetStore.writeManifest(manifest, to: stagingDirectory)
        try Self.commitScanDirectory(stagingDirectory, to: finalDirectory)

        stage = .done
        progress = 1
        outputURL = finalOutput
        outputManifest = manifest
        reloadLibrary()
        selectScan(input.scanID)
        if let jobID = input.jobID, let peerID = input.replyPeerID {
            recordRemoteJob(
                jobID: jobID,
                scanID: input.scanID,
                peerID: peerID,
                state: .completed,
                progress: 1
            )
        }
        addLog("Render complete → \(finalOutput.lastPathComponent)")
        if let replyPeer = input.replyPeer {
            do {
                try sendResultPackage(
                    output: finalOutput,
                    manifest: manifest,
                    to: replyPeer,
                    peerID: input.replyPeerID,
                    jobID: input.jobID
                )
            } catch {
                addLog("Could not package result for return: \(error.localizedDescription)")
            }
        }
    }

    static func commitScanDirectory(_ stagingDirectory: URL, to finalDirectory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: finalDirectory.path) {
            let backupName = ".backup-\(UUID().uuidString)"
            _ = try fileManager.replaceItemAt(
                finalDirectory,
                withItemAt: stagingDirectory,
                backupItemName: backupName,
                options: []
            )
            try? fileManager.removeItem(at: finalDirectory.deletingLastPathComponent().appendingPathComponent(backupName))
        } else {
            try fileManager.moveItem(at: stagingDirectory, to: finalDirectory)
        }
    }

    private static func isValidModel(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? 0) > 0 else { return false }
        return ModelGeometryInspector.inspect(modelURL: url) != nil
    }

    private static func photogrammetryDetail(for tier: String) -> PhotogrammetrySession.Request.Detail {
        switch tier.lowercased() {
        case "preview": return .preview
        case "reduced": return .reduced
        case "full": return .full
        case "raw": return .raw
        default: return .medium
        }
    }

    /// Active flag for the dashboard.
    public var isProcessing: Bool { stage != .waiting && stage != .done }
}

extension ComputeCoordinator {
    private func cancelRemoteJob(_ jobID: UUID, event: HandoffControlEvent) {
        pendingOffers.removeValue(forKey: jobID)
        let removed = pendingHandoffs.filter { $0.metadata.jobID == jobID }
        pendingHandoffs.removeAll { $0.metadata.jobID == jobID }
        for handoff in removed { network.removeReceivedResource(handoff.archive) }
        cancelledRemoteJobIDs.insert(jobID)
        if activeRemoteJob?.jobID == jobID {
            runner.cancelSession()
            splatTrainer.cancel()
        }
        if let scanID = event.message.scanID {
            recordRemoteJob(jobID: jobID, scanID: scanID, peerID: event.peerID, state: .cancelled, progress: 0)
        }
        send(.cancelled, event: event)
        updateQueueProjection()
        addLog("Cancelled remote job \(jobID.uuidString.prefix(8))")
    }

    public func cancelActiveRemoteJob() {
        guard let job = activeRemoteJob else { return }
        cancelledRemoteJobIDs.insert(job.jobID)
        runner.cancelSession()
        splatTrainer.cancel()
        recordRemoteJob(
            jobID: job.jobID,
            scanID: job.scanID,
            peerID: job.peerID,
            state: .cancelled,
            progress: progress
        )
        send(.cancelled, jobID: job.jobID, scanID: job.scanID, to: job.peerID)
        addLog("Cancelled active remote job \(job.jobID.uuidString.prefix(8))")
    }

    public func cancelQueuedRemoteJobs() {
        for (jobID, offer) in pendingOffers {
            recordRemoteJob(jobID: jobID, scanID: offer.scanID, peerID: offer.peerID, state: .cancelled, progress: 0)
            send(.cancelled, jobID: jobID, scanID: offer.scanID, to: offer.peerID)
        }
        for handoff in pendingHandoffs {
            if let jobID = handoff.metadata.jobID, let scanID = handoff.metadata.scanID {
                recordRemoteJob(
                    jobID: jobID,
                    scanID: scanID,
                    peerID: handoff.peerInstallationID,
                    state: .cancelled,
                    progress: 0
                )
                send(.cancelled, jobID: jobID, scanID: scanID, to: handoff.peerInstallationID)
            }
            network.removeReceivedResource(handoff.archive)
        }
        pendingOffers.removeAll()
        pendingHandoffs.removeAll()
        updateQueueProjection()
        addLog("Cancelled queued remote jobs")
    }

    private func updateQueueProjection() {
        queuedRemoteJobCount = pendingOffers.count + pendingHandoffs.count
        activeRemoteJobID = activeRemoteJob?.jobID
    }

    private func sendActiveProgress(_ progress: Double) {
        guard let job = activeRemoteJob else { return }
        send(.progress(progress), jobID: job.jobID, scanID: job.scanID, to: job.peerID)
    }

    private func send(_ payload: HandoffMessagePayload, event: HandoffControlEvent) {
        send(payload, jobID: event.message.jobID, scanID: event.message.scanID, to: event.peerID)
    }

    private func send(
        _ payload: HandoffMessagePayload,
        jobID: UUID?,
        scanID: UUID?,
        to peerID: HandoffInstallationID
    ) {
        _ = network.send(
            HandoffMessageEnvelope(
                jobID: jobID,
                scanID: scanID,
                senderInstallationID: network.localInstallationID,
                payload: payload
            ),
            to: peerID
        )
    }

    private func sendResultPackage(
        output: URL,
        manifest: ScanAssetManifest?,
        to peer: MCPeerID,
        peerID: HandoffInstallationID?,
        jobID: UUID?
    ) throws {
        guard let manifest else { return }
        let zipURL = try ScanResultPackage().write(output: output, manifest: manifest)
        if let peerID, let jobID {
            let descriptor = try HandoffResourceDescriptor.inspect(zipURL)
            send(.resultReady(descriptor), jobID: jobID, scanID: manifest.scanID, to: peerID)
        }
        let resourceName = NetworkHandoffManager.handoffResourceName(
            for: zipURL,
            metadata: ScanHandoffMetadata(
                jobID: jobID,
                scanID: manifest.scanID,
                captureMode: manifest.captureMode,
                detailTier: manifest.detailTier
            )
        )
        addLog("Sending result package → \(peer.displayName)")
        network.sendResource(fileURL: zipURL, named: resourceName, to: peer) { [weak self] error in
            try? FileManager.default.removeItem(at: zipURL)
            if let error {
                self?.addLog("Result return failed: \(error.localizedDescription)")
            } else {
                self?.addLog("Returned result package → \(peer.displayName)")
            }
        }
    }

    private func recordRemoteJob(
        jobID: UUID,
        scanID: UUID,
        peerID: HandoffInstallationID,
        state: HandoffJobState,
        progress: Double
    ) {
        do {
            try remoteJobJournal.upsert(MacRemoteJobRecord(
                jobID: jobID,
                scanID: scanID,
                peerID: peerID,
                state: state,
                progress: min(max(progress, 0), 1),
                updatedAt: Date()
            ))
        } catch {
            addLog("Remote job history could not be saved: \(error.localizedDescription)")
        }
    }

    private func resendCompletedResult(_ record: MacRemoteJobRecord) {
        guard let assetStore,
              let peer = network.peerID(for: record.peerID),
              let manifest = try? assetStore.loadManifest(for: record.scanID) else { return }
        let output = [manifest.usdzFileURL, manifest.sourceModelURL, manifest.previewPLYURL]
            .compactMap { $0 }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let output else { return }
        do {
            try sendResultPackage(
                output: output,
                manifest: manifest,
                to: peer,
                peerID: record.peerID,
                jobID: record.jobID
            )
            addLog("Resent durable result for job \(record.jobID.uuidString.prefix(8))")
        } catch {
            addLog("Durable result resend failed: \(error.localizedDescription)")
        }
    }

    public var selectedScan: MacComputedScan? {
        guard let selectedScanID else { return nil }
        return libraryScans.first { $0.id == selectedScanID }
    }

    public var librarySummary: MacLibrarySummary { MacLibrarySummary(scans: libraryScans) }
    public var trainedSplatAvailable: Bool { splatTrainer.isAvailable }

    public func confirmPairing(_ request: HandoffPairingRequest) {
        pairing.confirm(request)
    }

    public func rejectPairing(_ request: HandoffPairingRequest) {
        pairing.reject(request)
    }

    public func forgetPeer(_ peerID: HandoffInstallationID) {
        pairing.forget(peerID)
    }

    @discardableResult
    public func refreshSplatRuntime() -> Bool {
        let available = splatTrainer.refreshRuntime()
        addLog(available ? "Trained-splat runtime is ready" : "Trained-splat runtime is unavailable")
        return available
    }

    public func selectScan(_ id: UUID?) {
        selectedScanID = id
        if let scan = selectedScan {
            outputURL = scan.modelURL
            outputManifest = scan.manifest
        }
    }

    public func addMeasurement(_ measurement: ScanMeasurement, to scanID: UUID) throws {
        guard let assetStore else { throw CocoaError(.fileNoSuchFile) }
        var manifest = try assetStore.loadManifest(for: scanID)
        var measurements = manifest.measurements ?? []
        measurements.append(measurement)
        manifest.measurements = measurements
        try assetStore.writeManifest(manifest)
        reloadLibrary()
        selectScan(scanID)
    }

    public func removeMeasurement(_ measurementID: UUID, from scanID: UUID) throws {
        guard let assetStore else { throw CocoaError(.fileNoSuchFile) }
        var manifest = try assetStore.loadManifest(for: scanID)
        manifest.measurements = (manifest.measurements ?? []).filter { $0.id != measurementID }
        try assetStore.writeManifest(manifest)
        reloadLibrary()
        selectScan(scanID)
    }

    @discardableResult
    public func exportMeasurements(for scanID: UUID, to directory: URL) throws -> URL {
        guard let scan = libraryScans.first(where: { $0.id == scanID }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try MeasurementExporter().exportCSV(
            scan.manifest.measurements ?? [],
            named: scan.name,
            to: directory
        )
    }
}
