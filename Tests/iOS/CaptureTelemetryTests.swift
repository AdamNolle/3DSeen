import XCTest
@testable import ThreeDSeen

final class CaptureTelemetryTests: XCTestCase {
    func testLandscapeCaptureShowsOnlyMeasuredFrameAndTrackingFacts() {
        let status = LiveCaptureStatus(
            mode: .landscape,
            phase: .capturing,
            frameCount: 12,
            trackingStatus: "tracking"
        )

        XCTAssertEqual(status.title, "Landscape capture")
        XCTAssertEqual(status.primaryFacts, ["12 frames", "Tracking"])
        XCTAssertEqual(status.guidance, "Walk a smooth arc while frames are captured automatically.")
        XCTAssertEqual(status.finishActionTitle, "Finish landscape scan")
    }

    func testObjectReadyStatusDoesNotInventCaptureMetrics() {
        let status = LiveCaptureStatus(mode: .object, phase: .ready)

        XCTAssertEqual(status.title, "Object capture")
        XCTAssertTrue(status.primaryFacts.isEmpty)
        XCTAssertEqual(status.guidance, "Frame the object, then begin automatic detection.")
        XCTAssertEqual(status.primaryActionTitle, "Start auto-detection")
    }

    func testSpaceProcessingStatusExplainsThatTheModelIsBeingBuilt() {
        let status = LiveCaptureStatus(mode: .space, phase: .processing)

        XCTAssertEqual(status.title, "Space capture")
        XCTAssertEqual(status.phaseLabel, "Building room model")
        XCTAssertEqual(status.guidance, "RoomPlan is processing the captured space into a USDZ model.")
        XCTAssertNil(status.finishActionTitle)
    }
}
