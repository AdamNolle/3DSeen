import Foundation
import Combine
import OSLog

/// The capture modes available in the iOS Hub and Spoke architecture.
public enum CaptureMode: String, CaseIterable, Equatable, Sendable {
    case object = "Object"
    case space = "Space"
    case landscape = "Landscape"
    case autoPilot = "Auto-Pilot"
}

/// The compute options available for processing raw capture data.
public enum ComputeMode: String, Equatable {
    case local = "On-Device Compute"
    case offload = "Desktop Offload"
}

/// The state of the processing pipeline.
public enum AppState: Equatable {
    case idle
    case captureModeSelection
    case capturing(mode: CaptureMode)
    case packagingScan
    case readyForCompute(mode: ComputeMode)
    case computingLocally(progress: Double)
    case computingOffloaded(status: String)
    case completed(assetPath: URL)
    case error(message: String)
    case thermalThrottled(savedStateURL: URL)
}

public struct CaptureCompletion: Equatable, Sendable {
    public let attemptID: UUID
    public let mode: CaptureMode
    public let scanDataURL: URL

    public init(attemptID: UUID, mode: CaptureMode, scanDataURL: URL) {
        self.attemptID = attemptID
        self.mode = mode
        self.scanDataURL = scanDataURL
    }
}

/// Events that trigger state transitions. Capture events carry an attempt identity so late SDK,
/// Vision, writer, or persistence callbacks cannot complete a newer scan.
public enum AppEvent {
    case startCapture(CaptureMode, attemptID: UUID)
    case autoPilotResolved(CaptureMode, attemptID: UUID)
    case finishCapture(scanDataURL: URL, attemptID: UUID)
    case userSelectsComputeMode(ComputeMode)
    case startLocalCompute
    case updateLocalProgress(Double)
    case offloadToMac
    case updateOffloadStatus(String)
    case computeCompleted(URL)
    case thermalCritical(savedStateURL: URL)
    case errorOccurred(String)
    case reset
}

/// The MVVM-C State Machine managing transitions between capturing, queueing, and processing.
@MainActor
public final class ProcessingStateMachine: ObservableObject {
    @Published public private(set) var state: AppState = .idle
    @Published public private(set) var lastScanDataURL: URL?
    @Published public private(set) var lastComputedAssetURL: URL?
    @Published public private(set) var activeCaptureAttemptID: UUID?
    @Published public private(set) var lastCaptureCompletion: CaptureCompletion?
    /// The engine that is actually collecting frames. Auto-Pilot starts as `.autoPilot` and is
    /// updated once Vision has chosen a supported engine.
    @Published public private(set) var activeCaptureMode: CaptureMode?

    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "StateMachine")

    public init() {}

    /// Processes an event to transition to a new state.
    public func send(_ event: AppEvent) {
        logger.debug("Received event: \(String(describing: event))")
        guard let nextState = transition(from: state, with: event) else {
            logger.warning("Invalid transition attempt from \(String(describing: self.state)) with event \(String(describing: event))")
            return
        }
        remember(event)
        logger.debug("Transitioning from \(String(describing: self.state)) to \(String(describing: nextState))")
        state = nextState
    }

    private func remember(_ event: AppEvent) {
        switch event {
        case .startCapture(let mode, let attemptID):
            lastScanDataURL = nil
            lastComputedAssetURL = nil
            lastCaptureCompletion = nil
            activeCaptureMode = mode
            activeCaptureAttemptID = attemptID
        case .autoPilotResolved(let mode, _):
            activeCaptureMode = mode
        case .finishCapture(let scanDataURL, let attemptID):
            lastScanDataURL = scanDataURL
            if let activeCaptureMode {
                lastCaptureCompletion = CaptureCompletion(
                    attemptID: attemptID,
                    mode: activeCaptureMode,
                    scanDataURL: scanDataURL
                )
            }
        case .computeCompleted(let assetURL):
            lastComputedAssetURL = assetURL
        case .reset:
            lastScanDataURL = nil
            lastComputedAssetURL = nil
            lastCaptureCompletion = nil
            activeCaptureMode = nil
            activeCaptureAttemptID = nil
        default:
            break
        }
    }

    private func transition(from currentState: AppState, with event: AppEvent) -> AppState? {
        switch (currentState, event) {

        // From Idle or Completed to Capture Mode
        case (.idle, .startCapture(let mode, _)),
             (.completed, .startCapture(let mode, _)):
            return .capturing(mode: mode)

        // Vision has selected a concrete engine while the Auto-Pilot preview is running.
        case (.capturing(mode: .autoPilot), .autoPilotResolved(let mode, let attemptID))
            where mode != .autoPilot && attemptID == activeCaptureAttemptID:
            return .capturing(mode: mode)

        // From Capturing to Packaging. A terminal callback from an older attempt is ignored.
        case (.capturing, .finishCapture(_, let attemptID)) where attemptID == activeCaptureAttemptID:
            return .packagingScan

        // Persisted scans can re-enter compute after relaunch, cancellation, or a recoverable
        // failure; compute readiness must not depend on an in-memory capture transition.
        case (.packagingScan, .userSelectsComputeMode(let mode)),
             (.idle, .userSelectsComputeMode(let mode)),
             (.completed, .userSelectsComputeMode(let mode)),
             (.error, .userSelectsComputeMode(let mode)),
             (.thermalThrottled, .userSelectsComputeMode(let mode)):
            return .readyForCompute(mode: mode)

        // From Ready to Computing
        case (.readyForCompute(mode: .local), .startLocalCompute):
            return .computingLocally(progress: 0.0)

        case (.readyForCompute(mode: .offload), .offloadToMac):
            return .computingOffloaded(status: "Connecting to Mac...")

        // Progress Updates
        case (.computingLocally, .updateLocalProgress(let progress)):
            return .computingLocally(progress: progress)

        case (.computingOffloaded, .updateOffloadStatus(let status)):
            return .computingOffloaded(status: status)

        // Thermal Throttling
        case (.computingLocally, .thermalCritical(let savedURL)):
            return .thermalThrottled(savedStateURL: savedURL)

        // Completion
        case (.computingLocally, .computeCompleted(let asset)),
             (.computingOffloaded, .computeCompleted(let asset)):
            return .completed(assetPath: asset)

        // Global Error Handling
        case (_, .errorOccurred(let message)):
            return .error(message: message)

        // Global Reset
        case (_, .reset):
            return .idle

        // Invalid transitions do not mutate state or remembered pipeline metadata.
        default:
            return nil
        }
    }
}
