import Foundation
import RealityKit
import OSLog
import Combine

/// Declares the detail level a compute destination can actually produce. The requested tier is
/// preserved for Mac handoff; on-device RealityKit currently produces Reduced output only.
public enum ComputeDetailCapability {
    public enum Destination: Sendable {
        case onDevice
        case macHandoff
    }

    public static func effectiveTier(for destination: Destination, requestedTier: String) -> String {
        switch destination {
        case .onDevice:
            return "Reduced"
        case .macHandoff:
            let trimmed = requestedTier.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Medium" : trimmed.capitalized
        }
    }
}

public enum ScanLocalComputeError: LocalizedError {
    case missingCaptureArchive(UUID)
    case captureArchiveIsNotDirectory(URL)
    case captureArchiveHasNoImages(URL)
    case outputMissing(URL)

    public var errorDescription: String? {
        switch self {
        case .missingCaptureArchive:
            return "This scan has no captured image archive to reconstruct."
        case .captureArchiveIsNotDirectory(let url):
            return "The capture archive at \(url.lastPathComponent) is not an image directory."
        case .captureArchiveHasNoImages(let url):
            return "The capture archive at \(url.lastPathComponent) contains no usable camera frames."
        case .outputMissing(let url):
            return "Photogrammetry finished without writing \(url.lastPathComponent)."
        }
    }
}

/// A validated photogrammetry request derived from persisted scan state. It deliberately has no
/// sample-asset fallback: scans without a real image archive must not produce a made-up model.
public struct ScanLocalComputeRequest {
    public let inputFolder: URL
    public let outputURL: URL
    public let detailTier: String

    public init(scan: ScanSession, outputDirectory: URL) throws {
        guard let rawArchiveURL = scan.rawArchiveURL else {
            throw ScanLocalComputeError.missingCaptureArchive(scan.id)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rawArchiveURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ScanLocalComputeError.captureArchiveIsNotDirectory(rawArchiveURL)
        }
        guard CaptureArchiveInspector.containsImageFrames(in: rawArchiveURL) else {
            throw ScanLocalComputeError.captureArchiveHasNoImages(rawArchiveURL)
        }

        inputFolder = rawArchiveURL
        outputURL = outputDirectory.appendingPathComponent("model.usdz")
        detailTier = scan.tierRaw
    }

    var effectiveDetailTier: String {
        ComputeDetailCapability.effectiveTier(for: .onDevice, requestedTier: detailTier)
    }

    var photogrammetryDetail: PhotogrammetrySession.Request.Detail {
        // This request is only used by the iOS local-compute service. Keep the actual SDK detail
        // in lockstep with the shared capability policy users see before selecting a destination.
        .reduced
    }
}

/// Runs real on-device photogrammetry for image-based scans and records the resulting asset.
@MainActor
public final class ScanLocalComputeService: ObservableObject {
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var isRunning = false

    private let runner: PhotogrammetryRunner
    private var progressCancellable: AnyCancellable?

    public init() {
        self.runner = PhotogrammetryRunner()
        progressCancellable = runner.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.progress = $0 }
    }

    public init(runner: PhotogrammetryRunner) {
        self.runner = runner
        progressCancellable = runner.$progress
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.progress = $0 }
    }

    @discardableResult
    public func compute(scan: ScanSession, store: ScanAssetStore? = nil) async throws -> URL {
        let destinationStore: ScanAssetStore
        if let store {
            destinationStore = store
        } else {
            destinationStore = try ScanAssetStore()
        }
        let outputDirectory = try destinationStore.directory(for: scan.id)
        destinationStore.repairPersistedURLs(on: scan)
        let request = try ScanLocalComputeRequest(scan: scan, outputDirectory: outputDirectory)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        isRunning = true
        progress = 0
        defer { isRunning = false }

        try await runner.startProcessing(
            inputFolder: request.inputFolder,
            outputURL: request.outputURL,
            detail: request.photogrammetryDetail
        )
        guard FileManager.default.fileExists(atPath: request.outputURL.path) else {
            throw ScanLocalComputeError.outputMissing(request.outputURL)
        }

        // Persist the detail actually produced instead of leaving a Mac-oriented request behind.
        scan.tierRaw = request.effectiveDetailTier
        let previewURL = outputDirectory.appendingPathComponent("geometry-preview.ply")
        let generatedPreview = try? GaussianSplatGenerator.writeModelPreview(
            from: request.outputURL,
            to: previewURL
        )
        scan.triangles = ModelGeometryInspector.inspect(modelURL: request.outputURL)?.formattedTriangleCount ?? "Unavailable"
        scan.markComputed(modelURL: request.outputURL, usdzURL: request.outputURL, previewPLYURL: generatedPreview)
        try destinationStore.writeManifest(try destinationStore.manifest(for: scan))
        return request.outputURL
    }

    public func cancel() {
        runner.cancelSession()
        isRunning = false
    }
}

/// A wrapper around RealityKit's PhotogrammetrySession to handle rendering on both iOS and macOS.
@MainActor
public final class PhotogrammetryRunner: ObservableObject {
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "Compute")

    @Published public var progress: Double = 0.0
    @Published public var isRunning: Bool = false

    private var session: PhotogrammetrySession?

    public init() {}

    /// Starts the photogrammetry process.
    public func startProcessing(inputFolder: URL, outputURL: URL, detail: PhotogrammetrySession.Request.Detail = .reduced) async throws {
        logger.info("Starting photogrammetry session from \(inputFolder.path) to \(outputURL.path)")

        var configuration = PhotogrammetrySession.Configuration()
        configuration.featureSensitivity = .high

        let fileManager = FileManager.default
        let stagingURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".pending-\(UUID().uuidString).\(outputURL.pathExtension)")
        defer { try? fileManager.removeItem(at: stagingURL) }

        let session = try PhotogrammetrySession(input: inputFolder, configuration: configuration)
        self.session = session
        isRunning = true
        progress = 0
        defer {
            isRunning = false
            self.session = nil
        }

        let request = PhotogrammetrySession.Request.modelFile(url: stagingURL, detail: detail)
        try session.process(requests: [request])

        var processingCompleted = false
        for try await output in session.outputs {
            if Task.isCancelled {
                session.cancel()
                throw CancellationError()
            }
            switch output {
            case .processingComplete:
                logger.info("Processing Complete!")
                processingCompleted = true

            case .requestError(let request, let error):
                logger.error("Request Error on \(String(describing: request)): \(error.localizedDescription)")
                throw error

            case .requestComplete(let request, let result):
                logger.info("Request Complete: \(String(describing: request)), Result: \(String(describing: result))")

            case .requestProgress(_, let fractionComplete):
                progress = fractionComplete
                logger.debug("Progress: \(fractionComplete)")

            case .requestProgressInfo(_, let progressInfo):
                if let stage = progressInfo.processingStage {
                    logger.debug("Stage: \(String(describing: stage))")
                }

            case .inputComplete:
                logger.info("Input ingestion complete.")

            case .invalidSample(let id, let reason):
                logger.warning("Invalid sample (id: \(id)): \(reason)")

            case .skippedSample(let id):
                logger.warning("Skipped sample: \(id)")

            case .automaticDownsampling:
                logger.info("Automatic downsampling occurred to preserve memory.")

            case .processingCancelled:
                logger.warning("Processing cancelled.")
                throw CancellationError()

            default:
                logger.warning("Unknown session output.")
            }
        }

        guard processingCompleted, fileManager.fileExists(atPath: stagingURL.path) else {
            throw ScanLocalComputeError.outputMissing(stagingURL)
        }
        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(outputURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: outputURL)
        }
        progress = 1
    }

    /// Pauses or cancels the session (useful for thermal throttling).
    public func cancelSession() {
        logger.warning("Canceling Photogrammetry Session.")
        session?.cancel()
        isRunning = false
    }
}
