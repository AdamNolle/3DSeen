import XCTest
@testable import ThreeDSeen

@MainActor
final class StateMachineTests: XCTestCase {
    private let dummyURL = URL(fileURLWithPath: "/tmp/scan")

    func testHappyPathLocalCompute() {
        let sm = ProcessingStateMachine()
        XCTAssertEqual(sm.state, .idle)

        sm.send(.startCapture(.object))
        XCTAssertEqual(sm.state, .capturing(mode: .object))

        sm.send(.finishCapture(scanDataURL: dummyURL))
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

    func testOffloadPath() {
        let sm = ProcessingStateMachine()
        sm.send(.startCapture(.space))
        sm.send(.finishCapture(scanDataURL: dummyURL))
        sm.send(.userSelectsComputeMode(.offload))
        XCTAssertEqual(sm.state, .readyForCompute(mode: .offload))
        sm.send(.offloadToMac)
        guard case .computingOffloaded = sm.state else { return XCTFail("expected offloaded") }
    }

    func testInvalidTransitionIsIgnored() {
        let sm = ProcessingStateMachine()
        sm.send(.finishCapture(scanDataURL: dummyURL)) // invalid from .idle
        XCTAssertEqual(sm.state, .idle)
    }

    func testThermalThrottleFromLocalCompute() {
        let sm = ProcessingStateMachine()
        sm.send(.startCapture(.object))
        sm.send(.finishCapture(scanDataURL: dummyURL))
        sm.send(.userSelectsComputeMode(.local))
        sm.send(.startLocalCompute)
        let saved = URL(fileURLWithPath: "/tmp/saved")
        sm.send(.thermalCritical(savedStateURL: saved))
        XCTAssertEqual(sm.state, .thermalThrottled(savedStateURL: saved))
    }

    func testErrorIsGlobal() {
        let sm = ProcessingStateMachine()
        sm.send(.startCapture(.landscape))
        sm.send(.errorOccurred("boom"))
        XCTAssertEqual(sm.state, .error(message: "boom"))
    }
}
