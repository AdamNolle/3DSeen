import Foundation
import RealityKit
import OSLog
import Combine

/// A wrapper around RealityKit's PhotogrammetrySession to handle rendering on both iOS and macOS.
@MainActor
public final class PhotogrammetryRunner: ObservableObject {
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "Compute")

    @Published public var progress: Double = 0.0
    @Published public var isRunning: Bool = false

    private var session: PhotogrammetrySession?
    private var cancellable: AnyCancellable?

    public init() {}

    /// Starts the photogrammetry process.
    public func startProcessing(inputFolder: URL, outputURL: URL, detail: PhotogrammetrySession.Request.Detail = .reduced) async throws {
        logger.info("Starting photogrammetry session from \(inputFolder.path) to \(outputURL.path)")

        var configuration = PhotogrammetrySession.Configuration()
        configuration.featureSensitivity = .high

        let session = try PhotogrammetrySession(input: inputFolder, configuration: configuration)
        self.session = session
        self.isRunning = true

        let request = PhotogrammetrySession.Request.modelFile(url: outputURL, detail: detail)

        // Start processing
        try session.process(requests: [request])

        // Monitor outputs
        for try await output in session.outputs {
            switch output {
            case .processingComplete:
                self.logger.info("Processing Complete!")
                self.progress = 1.0
                self.isRunning = false

            case .requestError(let request, let error):
                self.logger.error("Request Error on \(String(describing: request)): \(error.localizedDescription)")
                self.isRunning = false
                throw error

            case .requestComplete(let request, let result):
                self.logger.info("Request Complete: \(String(describing: request)), Result: \(String(describing: result))")

            case .requestProgress(_, let fractionComplete):
                self.progress = fractionComplete
                self.logger.debug("Progress: \(fractionComplete)")

            case .inputComplete:
                self.logger.info("Input ingestion complete.")

            case .invalidSample(let id, let reason):
                self.logger.warning("Invalid sample (id: \(id)): \(reason)")

            case .skippedSample(let id):
                self.logger.warning("Skipped sample: \(id)")

            case .automaticDownsampling:
                self.logger.info("Automatic downsampling occurred to preserve memory.")

            case .processingCancelled:
                self.logger.warning("Processing cancelled.")
                self.isRunning = false

            @unknown default:
                self.logger.warning("Unknown session output.")
            }
        }
    }

    /// Pauses or cancels the session (useful for thermal throttling).
    public func cancelSession() {
        logger.warning("Canceling Photogrammetry Session.")
        session?.cancel()
        isRunning = false
    }
}
