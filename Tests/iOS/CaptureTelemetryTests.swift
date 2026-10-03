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

    func testCaptureGuidanceOverrideIsTrimmedAndTakesPrecedence() {
        let status = LiveCaptureStatus(
            mode: .space,
            phase: .capturing,
            guidanceOverride: "  Finish this section to save its scan data.  "
        )

        XCTAssertEqual(status.guidance, "Finish this section to save its scan data.")
    }

    func testSpaceCaptureShowsMeasuredSurfaceCount() {
        let status = LiveCaptureStatus(
            mode: .space,
            phase: .capturing,
            frameCount: 3,
            surfaceTriangleCount: 400,
            surfaceSampleCount: 1_250,
            trackedObjectCount: 3,
            objectSurfaceSampleCount: 240
        )
        XCTAssertEqual(status.primaryFacts, [
            "3 frames", "400 faces", "1,250 surface dots", "3 tracked objects", "240 object dots"
        ])
    }

    func testSpaceCaptureGuidesDotsAndHapticCoverage() {
        let status = LiveCaptureStatus(mode: .space, phase: .capturing)

        XCTAssertEqual(
            status.guidance,
            "Move slowly around furniture and keep each object in view as you circle it. " +
            "Bright dots mark measured LiDAR points on detected objects; a short haptic marks a newly detected object and light taps mark new surface detail. " +
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

    func testCaptureHapticsPulseOnObjectDiscoveryAndCoalesceCoverageMilestones() {
        var scheduler = CaptureHapticScheduler(minimumInterval: 1.1)

        XCTAssertEqual(
            scheduler.nextPulse(at: 1, coverageMilestone: 0, objectWasDiscovered: true),
            .objectDiscovery
        )
        XCTAssertNil(scheduler.nextPulse(at: 1.4, coverageMilestone: 1))
        XCTAssertEqual(scheduler.nextPulse(at: 2.2, coverageMilestone: 1), .surfaceCoverage)
        XCTAssertNil(scheduler.nextPulse(at: 3.1, coverageMilestone: 1))
        XCTAssertEqual(scheduler.nextPulse(at: 3.31, coverageMilestone: 2), .surfaceCoverage)
    }
}
