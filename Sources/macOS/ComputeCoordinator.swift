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
        "\(manifest.captureMode.rawValue)-\(manifest.scanID.uuidString.prefix(8))"
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
        let metadata: ScanHandoffMetadata
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

    public let network = NetworkHandoffManager()
    public let runner = PhotogrammetryRunner()
    public let splatTrainer: NerfstudioSplatTrainer
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen", category: "Compute")
    private let assetStore: ScanAssetStore?
    private var pendingHandoffs: [PendingHandoff] = []
    private var isDrainingHandoffs = false
    private var isExecutingProcess = false

    public init(splatTrainer: NerfstudioSplatTrainer? = nil) {
        assetStore = try? ScanAssetStore()
        self.splatTrainer = splatTrainer ?? NerfstudioSplatTrainer()
        network.onReceiveScan = { [weak self] url, peer, metadata in
            Task { await self?.enqueueHandoff(archive: url, peer: peer, metadata: metadata) }
        }
        network.$connectedPeers
            .receive(on: RunLoop.main)
            .sink { [weak self] peers in self?.peerName = peers.first?.displayName ?? "—" }
            .store(in: &cancellables)
        // Map raw photogrammetry progress onto pipeline stages.
        runner.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] p in self?.mapProgress(p) }
            .store(in: &cancellables)
        self.splatTrainer.$stage
            .receive(on: RunLoop.main)
            .sink { [weak self] stage in self?.splatTrainerStage = stage }
            .store(in: &cancellables)
        reloadLibrary()
    }

    public var selectedScan: MacComputedScan? {
        guard let selectedScanID else { return nil }
        return libraryScans.first { $0.id == selectedScanID }
    }

    public var librarySummary: MacLibrarySummary { MacLibrarySummary(scans: libraryScans) }
    public var trainedSplatAvailable: Bool { splatTrainer.isAvailable }

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

    private func sendResultPackage(output: URL, manifest: ScanAssetManifest?, to peer: MCPeerID) throws {
        guard let manifest else { return }
        let zipURL = try ScanResultPackage().write(output: output, manifest: manifest)
        addLog("Sending result package → \(peer.displayName)")
        network.sendResource(fileURL: zipURL, named: zipURL.lastPathComponent, to: peer) { [weak self] error in
            try? FileManager.default.removeItem(at: zipURL)
            if let error {
                self?.addLog("Result return failed: \(error.localizedDescription)")
            } else {
                self?.addLog("Returned result package → \(peer.displayName)")
            }
        }
    }

    private func enqueueHandoff(archive: URL, peer: MCPeerID, metadata: ScanHandoffMetadata) async {
        pendingHandoffs.append(.init(archive: archive, replyPeer: peer, metadata: metadata))
        addLog("Queued hand-off from \(peer.displayName) (\(pendingHandoffs.count) waiting)")
        guard !isDrainingHandoffs else { return }
        isDrainingHandoffs = true
        defer { isDrainingHandoffs = false }
        while !pendingHandoffs.isEmpty {
            let handoff = pendingHandoffs.removeFirst()
            await process(
                archive: handoff.archive,
                replyPeer: handoff.replyPeer,
                captureMode: handoff.metadata.captureMode,
                detailTier: handoff.metadata.detailTier,
                sourceScanID: handoff.metadata.scanID
            )
        }
    }

    /// Retain an incoming capture, pass image archives to PhotogrammetrySession, or preserve an
    /// already-computed RoomPlan USDZ without pretending it needs image reconstruction.
    public func process(archive: URL, replyPeer: MCPeerID? = nil, captureMode: CaptureMode? = nil,
                        detailTier: String? = nil, sourceScanID: UUID? = nil) async {
        defer { network.removeReceivedResource(archive) }
        guard !isExecutingProcess else {
            addLog("Rejected overlapping compute request; network hand-offs remain serialized")
            return
        }
        isExecutingProcess = true
        defer { isExecutingProcess = false }
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
                                   captureQualityReport: nil, replyPeer: replyPeer))
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
                                        captureQualityReport: captureQualityReport, replyPeer: replyPeer)
            let trainedPreview = await trainSplatIfRequested(images: images, scanDirectory: stagingDirectory, scanID: scanID)
            try complete(input, previewOverride: trainedPreview?.url, previewKind: trainedPreview?.kind)
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
            captureQualityReport: input.captureQualityReport
        )
        try assetStore.writeManifest(manifest, to: stagingDirectory)
        try Self.commitScanDirectory(stagingDirectory, to: finalDirectory)

        stage = .done
        progress = 1
        outputURL = finalOutput
        outputManifest = manifest
        reloadLibrary()
        selectScan(input.scanID)
        addLog("Render complete → \(finalOutput.lastPathComponent)")
        if let replyPeer = input.replyPeer {
            do {
                try sendResultPackage(output: finalOutput, manifest: manifest, to: replyPeer)
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
