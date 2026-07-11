import Foundation
import Vision
import CoreML
import OSLog

/// Reads the live camera feed and recommends the optimal capture mode.
/// Uses Apple's built-in Vision scene classifier (`VNClassifyImageRequest`) — no custom model
/// to bundle or train — and maps its taxonomy to 3DSeen's capture modes with confidence.
public final class AutoPilotVisionManager {
    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "Vision")

    public struct Suggestion: Equatable {
        public let mode: CaptureMode
        public let confidence: Float
        public let label: String
    }

    // Keyword → mode mapping over the Vision classification taxonomy.
    private static let landscapeHints = ["outdoor", "sky", "mountain", "landscape", "tree", "plant",
                                         "field", "beach", "water", "snow", "foliage", "nature", "cityscape", "valley"]
    private static let spaceHints = ["indoor", "room", "interior", "furniture", "wall", "floor",
                                     "kitchen", "bedroom", "office", "ceiling", "door", "window", "staircase"]

    public init() {}

    /// Analyzes a frame and returns the suggested mode + confidence.
    public func suggestion(for pixelBuffer: CVPixelBuffer) -> Suggestion {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logger.error("Vision classify failed: \(error.localizedDescription)")
            return Suggestion(mode: .object, confidence: 0, label: "object")
        }
        let observations = (request.results ?? [])
            .filter { $0.hasMinimumRecall(0.1, forPrecision: 0.5) || $0.confidence > 0.2 }
            .prefix(20)
            .map { (identifier: $0.identifier, confidence: $0.confidence) }
        return Self.suggestion(forClassifications: Array(observations))
    }

    /// Pure mapping from a list of Vision classifications to a capture-mode suggestion.
    /// Extracted so the decision logic is unit-testable without a live camera frame.
    static func suggestion(forClassifications classifications: [(identifier: String, confidence: Float)]) -> Suggestion {
        var landscapeScore: Float = 0
        var spaceScore: Float = 0
        var topLabel = "object"
        var topConf: Float = 0

        for c in classifications {
            let id = c.identifier.lowercased()
            if c.confidence > topConf { topConf = c.confidence; topLabel = c.identifier }
            if landscapeHints.contains(where: id.contains) { landscapeScore += c.confidence }
            if spaceHints.contains(where: id.contains) { spaceScore += c.confidence }
        }

        // A strong landscape/space signal wins; otherwise it's a discrete object.
        if landscapeScore > 0.5 && landscapeScore >= spaceScore {
            return Suggestion(mode: .landscape, confidence: min(1, landscapeScore), label: topLabel)
        } else if spaceScore > 0.5 && spaceScore > landscapeScore {
            return Suggestion(mode: .space, confidence: min(1, spaceScore), label: topLabel)
        } else {
            return Suggestion(mode: .object, confidence: max(0.6, topConf), label: topLabel)
        }
    }

    /// Keeps a Vision recommendation only when the target device can actually run that capture
    /// engine. Object capture is the portable fallback for unsupported RoomPlan/ARKit modes.
    public static func resolvedMode(for suggestion: Suggestion, supportedModes: Set<CaptureMode>) -> CaptureMode {
        guard suggestion.mode != .autoPilot, supportedModes.contains(suggestion.mode) else {
            return .object
        }
        return suggestion.mode
    }

    /// Async convenience used by the live capture coordinator.
    public func analyzeFrame(pixelBuffer: CVPixelBuffer) async -> CaptureMode {
        suggestion(for: pixelBuffer).mode
    }
}
