import Foundation
import Combine
import ZIPFoundation
import RealityKit
import OSLog

/// Drives the macOS "Studio" compute dashboard: receives a scan archive over MultipeerConnectivity,
/// unzips it, runs RealityKit PhotogrammetrySession on Apple Silicon, and publishes pipeline state.
@MainActor
public final class ComputeCoordinator: ObservableObject {
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
    @Published public private(set) var log: [(time: String, message: String)] = []
    @Published public var peerName: String = "—"

    public let network = NetworkHandoffManager()
    public let runner = PhotogrammetryRunner()
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen", category: "Compute")

    public init() {
        network.onReceiveScan = { [weak self] url in
            Task { await self?.process(archive: url) }
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

    /// Unzip the received archive and run photogrammetry to a USDZ.
    public func process(archive: URL) async {
        stage = .ingest; progress = 0; outputURL = nil
        addLog("Received \(archive.lastPathComponent)")

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("compute-\(UUID().uuidString)", isDirectory: true)
        let images = work.appendingPathComponent("images", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
            if archive.pathExtension.lowercased() == "zip" {
                try FileManager.default.unzipItem(at: archive, to: images)
            }
            receivedFrames = (try? FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil))?.count ?? 0
            addLog("Unpacked \(receivedFrames) frames")
        } catch {
            addLog("Unpack failed: \(error.localizedDescription)")
            stage = .waiting
            return
        }

        let out = work.appendingPathComponent("model.usdz")
        addLog("Photogrammetry started (RealityKit)")
        do {
            try await runner.startProcessing(inputFolder: images, outputURL: out, detail: .medium)
            stage = .done; progress = 1; outputURL = out
            addLog("Render complete → \(out.lastPathComponent)")
        } catch {
            addLog("Photogrammetry error: \(error.localizedDescription)")
            stage = .waiting
        }
    }

    /// Active flag for the dashboard.
    public var isProcessing: Bool { stage != .waiting && stage != .done }

    // MARK: - Demo (no physical iPhone present)

    private var simCancellable: AnyCancellable?

    /// Animates the pipeline for demos when no real hand-off is available.
    public func simulate() {
        simCancellable?.cancel()
        stage = .ingest; progress = 0; receivedFrames = 334; outputURL = nil
        addLog("Simulated hand-off · 334 frames")
        simCancellable = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let np = self.progress + 0.012
                if np >= 1 {
                    self.simCancellable?.cancel()
                    self.progress = 1; self.stage = .done
                    self.addLog("Render complete (simulated)")
                } else {
                    self.mapProgress(np)
                }
            }
    }
}
