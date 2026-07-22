import XCTest
@testable import ThreeDSeen

@MainActor
final class StateMachineTests: XCTestCase {
    private let dummyURL = URL(fileURLWithPath: "/tmp/scan")
    private let attemptID = UUID()

    func testHappyPathLocalCompute() {
        let sm = ProcessingStateMachine()
        XCTAssertEqual(sm.state, .idle)

        sm.send(.startCapture(.object, attemptID: attemptID))
        XCTAssertEqual(sm.state, .capturing(mode: .object))

        sm.send(.finishCapture(scanDataURL: dummyURL, attemptID: attemptID))
        XCTAssertEqual(sm.state, .packagingScan)

        sm.send(.userSelectsComputeMode(.local))
        XCTAssertEqual(sm.state, .readyForCompute(mode: .local))

        sm.send(.startLocalCompute)
        XCTAssertEqual(sm.state, .computingLocally(progress: 0))

        sm.send(.updateLocalProgress(0.42))
        XCTAssertEqual(sm.state, .computingLocally(progress: 0.42))

        let out = URL(fileURLWithPath: "/tmp/out.usdz")
        sm.send(.computeCompleted(out))
        XCTAssertEqual(sm.state, .completed(assetPath: out))

        sm.send(.reset)
        XCTAssertEqual(sm.state, .idle)
    }

    func testRemembersCaptureAndComputedURLs() {
        let sm = ProcessingStateMachine()
        let captureURL = URL(fileURLWithPath: "/tmp/capture-package")
        let assetURL = URL(fileURLWithPath: "/tmp/model.usdz")

        sm.send(.startCapture(.object, attemptID: attemptID))
        sm.send(.finishCapture(scanDataURL: captureURL, attemptID: attemptID))
        XCTAssertEqual(sm.lastScanDataURL, captureURL)

        sm.send(.userSelectsComputeMode(.local))
        sm.send(.startLocalCompute)
        sm.send(.computeCompleted(assetURL))
        XCTAssertEqual(sm.lastComputedAssetURL, assetURL)

        sm.send(.reset)
        XCTAssertNil(sm.lastScanDataURL)
        XCTAssertNil(sm.lastComputedAssetURL)
    }

    func testPersistedScanCanEnterComputeFromIdleAfterRelaunch() {
        let sm = ProcessingStateMachine()

        sm.send(.userSelectsComputeMode(.local))
        XCTAssertEqual(sm.state, .readyForCompute(mode: .local))
        sm.send(.startLocalCompute)
        XCTAssertEqual(sm.state, .computingLocally(progress: 0))
    }

    func testOffloadPath() {
        let sm = ProcessingStateMachine()
        sm.send(.startCapture(.space, attemptID: attemptID))
        sm.send(.finishCapture(scanDataURL: dummyURL, attemptID: attemptID))
        sm.send(.userSelectsComputeMode(.offload))
        XCTAssertEqual(sm.state, .readyForCompute(mode: .offload))
        sm.send(.offloadToMac)
        guard case .computingOffloaded = sm.state else { return XCTFail("expected offloaded") }
    }

    func testAutoPilotResolutionTransitionsToTheSelectedCaptureMode() {
        let sm = ProcessingStateMachine()

        sm.send(.startCapture(.autoPilot, attemptID: attemptID))
        sm.send(.autoPilotResolved(.landscape, attemptID: attemptID))

        XCTAssertEqual(sm.state, .capturing(mode: .landscape))
        XCTAssertEqual(sm.activeCaptureMode, .landscape)
    }

    func testInvalidTransitionDoesNotMutatePipelineMetadata() {
        let sm = ProcessingStateMachine()
        sm.send(.finishCapture(scanDataURL: dummyURL, attemptID: attemptID)) // invalid from .idle
        XCTAssertEqual(sm.state, .idle)
        XCTAssertNil(sm.lastScanDataURL)
        XCTAssertNil(sm.lastComputedAssetURL)
        XCTAssertNil(sm.activeCaptureMode)

        sm.send(.startCapture(.object, attemptID: attemptID))
        sm.send(.finishCapture(scanDataURL: dummyURL, attemptID: attemptID))
        sm.send(.userSelectsComputeMode(.local))
        sm.send(.startLocalCompute)
        let output = URL(fileURLWithPath: "/tmp/computed.usdz")
        sm.send(.computeCompleted(output))

        sm.send(.finishCapture(scanDataURL: URL(fileURLWithPath: "/tmp/stale"), attemptID: attemptID))
        XCTAssertEqual(sm.lastScanDataURL, dummyURL)
        XCTAssertEqual(sm.lastComputedAssetURL, output)
        XCTAssertEqual(sm.activeCaptureMode, .object)
    }

    func testStaleCaptureAttemptCannotCompleteANewerScan() {
        let sm = ProcessingStateMachine()
        let staleAttempt = UUID()
        let currentAttempt = UUID()

        sm.send(.startCapture(.object, attemptID: staleAttempt))
        sm.send(.reset)
        sm.send(.startCapture(.object, attemptID: currentAttempt))
        sm.send(.finishCapture(scanDataURL: dummyURL, attemptID: staleAttempt))

        XCTAssertEqual(sm.state, .capturing(mode: .object))
        XCTAssertNil(sm.lastCaptureCompletion)
        sm.send(.finishCapture(scanDataURL: dummyURL, attemptID: currentAttempt))
        XCTAssertEqual(sm.lastCaptureCompletion?.attemptID, currentAttempt)
        XCTAssertEqual(sm.state, .packagingScan)
    }

    func testThermalSafetyPolicyIsConservativeAndUserControllable() {
        XCTAssertFalse(LocalComputeSafetyPolicy.shouldInterrupt(thermalState: .nominal, protectionEnabled: true))
        XCTAssertFalse(LocalComputeSafetyPolicy.shouldInterrupt(thermalState: .fair, protectionEnabled: true))
        XCTAssertTrue(LocalComputeSafetyPolicy.shouldInterrupt(thermalState: .serious, protectionEnabled: true))
        XCTAssertTrue(LocalComputeSafetyPolicy.shouldInterrupt(thermalState: .critical, protectionEnabled: true))
        XCTAssertFalse(LocalComputeSafetyPolicy.shouldInterrupt(thermalState: .critical, protectionEnabled: false))
    }

    func testThermalThrottleFromLocalCompute() {
        let sm = ProcessingStateMachine()
        sm.send(.startCapture(.object, attemptID: attemptID))
        sm.send(.finishCapture(scanDataURL: dummyURL, attemptID: attemptID))
        sm.send(.userSelectsComputeMode(.local))
        sm.send(.startLocalCompute)
        let saved = URL(fileURLWithPath: "/tmp/saved")
        sm.send(.thermalCritical(savedStateURL: saved))
        XCTAssertEqual(sm.state, .thermalThrottled(savedStateURL: saved))
    }

    func testErrorIsGlobal() {
        let sm = ProcessingStateMachine()
        sm.send(.startCapture(.landscape, attemptID: attemptID))
        sm.send(.errorOccurred("boom"))
        XCTAssertEqual(sm.state, .error(message: "boom"))
    }
}
