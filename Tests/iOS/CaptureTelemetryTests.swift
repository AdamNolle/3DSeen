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

    func testSpaceCaptureShowsMeasuredSurfaceCount() {
        let status = LiveCaptureStatus(
            mode: .space,
            phase: .capturing,
            frameCount: 3,
            surfaceTriangleCount: 400,
            surfaceSampleCount: 1_250,
 trackedObjectCount: 3
        )
        XCTAssertEqual(status.primaryFacts, ["3 frames", "400 faces", "1,250 surface dots", "3 tracked objects"])
    }

    func testSpaceCaptureGuidesDotsAndHapticCoverage() {
        let status = LiveCaptureStatus(mode: .space, phase: .capturing)

        XCTAssertEqual(
            status.guidance,
            "Move slowly around furniture and keep each object in view as you circle it. " +
                "Bright dots mark Vision-segmented objects in LiDAR space; a light tap confirms new object detail. " +
                "Blue dots continue to mark room surfaces. " +
                "The live mesh is a responsive preview; the saved model uses all captured geometry and camera textures. " +
                "Only visible, well-tracked surfaces can be captured."
        )
    }

    func testSpaceProcessingStatusExplainsThatTheModelIsBeingBuilt() {
        let status = LiveCaptureStatus(mode: .space, phase: .processing)

        XCTAssertEqual(status.title, "Space capture")
        XCTAssertEqual(status.phaseLabel, "Building room model")
        XCTAssertEqual(status.guidance, "Building the measured LiDAR surface and embedding captured camera textures in your model.")
        XCTAssertNil(status.finishActionTitle)
    }
}
