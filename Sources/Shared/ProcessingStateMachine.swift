import Foundation
import Combine
import OSLog

/// The capture modes available in the iOS Hub and Spoke architecture.
public enum CaptureMode: String, CaseIterable, Equatable {
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

/// Events that trigger state transitions.
public enum AppEvent {
    case startCapture(CaptureMode)
    case finishCapture(scanDataURL: URL)
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

    private let logger = Logger(subsystem: "com.adamnolle.3DSeen.Shared", category: "StateMachine")

    public init() {}

    /// Processes an event to transition to a new state.
    public func send(_ event: AppEvent) {
        logger.debug("Received event: \(String(describing: event))")
        let nextState = transition(from: state, with: event)
        logger.debug("Transitioning from \(String(describing: self.state)) to \(String(describing: nextState))")
        state = nextState
    }

    private func transition(from currentState: AppState, with event: AppEvent) -> AppState {
        switch (currentState, event) {

        // From Idle or Completed to Capture Mode
        case (.idle, .startCapture(let mode)),
             (.completed, .startCapture(let mode)):
            return .capturing(mode: mode)

        // From Capturing to Packaging
        case (.capturing, .finishCapture):
            return .packagingScan

        // From Packaging to Ready for Compute
        case (.packagingScan, .userSelectsComputeMode(let mode)):
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

        // Invalid transitions
        default:
            logger.warning("Invalid transition attempt from \(String(describing: currentState)) with event \(String(describing: event))")
            return currentState
        }
    }
}
