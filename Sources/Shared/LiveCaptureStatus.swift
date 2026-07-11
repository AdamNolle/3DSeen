import Foundation

/// Truthful, presentation-ready state shared by the platform capture engines. It deliberately
/// carries only facts directly reported by an engine; unavailable measurements are omitted.
public struct LiveCaptureStatus: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case ready
        case detecting
        case capturing
        case finalizing
        case processing
    }

    public let mode: CaptureMode
    public let phase: Phase
    public let frameCount: Int?
    public let trackingStatus: String?

    public init(mode: CaptureMode, phase: Phase, frameCount: Int? = nil, trackingStatus: String? = nil) {
        self.mode = mode
        self.phase = phase
        self.frameCount = frameCount.map { max(0, $0) }
        self.trackingStatus = trackingStatus?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var title: String {
        switch mode {
        case .object: return "Object capture"
        case .space: return "Space capture"
        case .landscape: return "Landscape capture"
        case .autoPilot: return "Auto-Pilot"
        }
    }

    public var phaseLabel: String {
        switch phase {
        case .ready: return "Ready"
        case .detecting: return "Detecting object"
        case .capturing: return "Capturing"
        case .finalizing: return "Saving capture"
        case .processing: return "Building room model"
        }
    }

    public var primaryFacts: [String] {
        var facts: [String] = []
        if let frameCount { facts.append("\(frameCount) frames") }
        if let trackingStatus, !trackingStatus.isEmpty { facts.append(trackingStatus.capitalized) }
        return facts
    }

    public var guidance: String {
        switch (mode, phase) {
        case (.object, .ready):
            return "Frame the object, then begin automatic detection."
        case (.object, .detecting):
            return "Move around the object slowly to establish its capture bounds."
        case (.object, .capturing):
            return "Keep the object in view while you move around it."
        case (.object, .finalizing):
            return "Waiting for Object Capture to finish writing image frames."
        case (.object, .processing):
            return "Object Capture is processing the captured object."
        case (.space, .processing):
            return "RoomPlan is processing the captured space into a USDZ model."
        case (.space, _):
            return "Pan across walls, openings, and furniture before finishing the scan."
        case (.landscape, .capturing):
            return "Walk a smooth arc while frames are captured automatically."
        case (.landscape, .finalizing):
            return "Waiting for the final landscape frames to be written."
        case (.landscape, _):
            return "Wait for world tracking before moving through the scene."
        case (.autoPilot, _):
            return "Analyzing the live camera feed to choose a compatible capture mode."
        }
    }

    public var primaryActionTitle: String? {
        switch (mode, phase) {
        case (.object, .ready): return "Start auto-detection"
        case (.object, .detecting): return "Start capturing"
        default: return nil
        }
    }

    public var finishActionTitle: String? {
        switch (mode, phase) {
        case (.object, .capturing): return "Finish object scan"
        case (.landscape, .capturing): return "Finish landscape scan"
        case (.space, .ready), (.space, .detecting), (.space, .capturing): return "Finish space scan"
        default: return nil
        }
    }
}
