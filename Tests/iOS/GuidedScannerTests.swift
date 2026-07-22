import XCTest
import simd
@testable import ThreeDSeen

final class GuidedScannerTests: XCTestCase {
    func testSubjectSelectorPrefersCenteredForegroundInstance() {
        let labels: [UInt8] = [
            1, 1, 0, 2, 2,
            1, 1, 2, 2, 2,
            0, 0, 2, 2, 2,
            3, 3, 3, 0, 0
        ]

        let result = SubjectMaskSelector.select(labels: labels, width: 5, height: 4)

        XCTAssertEqual(result?.label, 2)
        XCTAssertEqual(result?.normalizedBounds, CGRect(x: 0.4, y: 0, width: 0.6, height: 0.75))
    }

    func testSubjectSelectorFallsBackToLargestInstanceAndRejectsNoise() {
        let labels: [UInt8] = [
            1, 1, 0, 2,
            1, 1, 0, 2,
            0, 0, 0, 0,
            3, 0, 0, 0
        ]
        XCTAssertEqual(
            SubjectMaskSelector.select(labels: labels, width: 4, height: 4)?.label,
            1
        )
        XCTAssertNil(SubjectMaskSelector.select(
            labels: [0, 0, 0, 1],
            width: 4,
            height: 1,
            minimumAreaFraction: 0.3
        ))
    }

    func testSelectedMaskRejectsBackgroundInsideBoundingBox() {
        let mask = SubjectInstanceMask(
            labels: [1, 0, 1, 1],
            width: 2,
            height: 2,
            selectedLabel: 1
        )

        XCTAssertTrue(mask.contains(normalizedPoint: CGPoint(x: 0.1, y: 0.1)))
        XCTAssertFalse(mask.contains(normalizedPoint: CGPoint(x: 0.75, y: 0.1)))
        XCTAssertFalse(mask.contains(normalizedPoint: CGPoint(x: 1, y: 0.5)))
    }

    func testSubjectLockRequiresConfirmationAndResistsSingleFrameSwitch() {
        var tracker = SubjectLockTracker()
        let first = subject(bounds: CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4), timestamp: 1)
        let matching = subject(bounds: CGRect(x: 0.12, y: 0.11, width: 0.4, height: 0.4), timestamp: 2)
        let different = subject(bounds: CGRect(x: 0.65, y: 0.55, width: 0.3, height: 0.3), timestamp: 3)

        XCTAssertNil(tracker.update(with: first))
        XCTAssertEqual(tracker.update(with: matching)?.timestamp, 2)
        XCTAssertEqual(tracker.update(with: different)?.timestamp, 2)
        XCTAssertEqual(tracker.update(with: different)?.timestamp, 3)
        XCTAssertNotNil(tracker.update(with: nil))
        XCTAssertNotNil(tracker.update(with: nil))
        XCTAssertNil(tracker.update(with: nil))
    }

    func testCaptureTemporaryCleanupRemovesOnlyKnownEngineSources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("guided-cleanup-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sources = [
            root.appendingPathComponent("guided-object-123", isDirectory: true),
            root.appendingPathComponent("landscape-123", isDirectory: true),
            root.appendingPathComponent("space-123.usdz"),
        ]
        let unrelated = root.appendingPathComponent("user-export.usdz")
        for source in sources { try Data("capture".utf8).write(to: source) }
        try Data("keep".utf8).write(to: unrelated)

        for source in sources {
            try GuidedCaptureTemporarySource.discardIfOwned(source, temporaryDirectory: root)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        }
        try GuidedCaptureTemporarySource.discardIfOwned(unrelated, temporaryDirectory: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testProjectionInvertsAspectFillTransformBeforeMaskLookup() {
        let mask = SubjectInstanceMask(labels: [0, 1, 0, 0], width: 2, height: 2, selectedLabel: 1)
        let subject = DetectedSubject(
            normalizedBounds: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            timestamp: 1,
            instanceLabel: 1,
            mask: mask
        )
        let transform = CGAffineTransform(a: 0.8, b: 0, c: 0, d: 0.7, tx: 0.1, ty: 0.2)
        let projection = SubjectImageProjection(
            subject: subject,
            imageToViewTransform: transform,
            viewportSize: CGSize(width: 400, height: 800),
            orientation: .portrait
        )
        let rawSubjectPoint = CGPoint(x: 0.25, y: 0.25)
        let viewPoint = rawSubjectPoint.applying(transform)
        let screenPoint = CGPoint(x: viewPoint.x * 400, y: viewPoint.y * 800)

        XCTAssertTrue(projection.contains(screenPoint: screenPoint))
        XCTAssertFalse(projection.contains(screenPoint: CGPoint(x: 40, y: 160)))
    }

    func testScannerOrientationPointMappingRoundTrips() {
        let point = CGPoint(x: 0.23, y: 0.71)
        for orientation in [UIInterfaceOrientation.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight] {
            let oriented = ScannerOrientation.orientedPoint(fromRaw: point, orientation: orientation)
            let roundTrip = ScannerOrientation.rawPoint(fromOriented: oriented, orientation: orientation)
            XCTAssertEqual(roundTrip.x, point.x, accuracy: 0.000_001)
            XCTAssertEqual(roundTrip.y, point.y, accuracy: 0.000_001)
        }
    }

    func testCaptureGateRequiresTrackingSubjectAndPoseNovelty() {
        let gate = GuidedCaptureGate()
        let first = CapturePose(transform: transform(x: 0), timestamp: 1)
        XCTAssertEqual(gate.evaluate(
            current: first,
            previous: nil,
            trackingIsNormal: false,
            subjectIsFresh: true,
            writerBacklog: 0
        ), .reject("tracking"))
        XCTAssertEqual(gate.evaluate(
            current: first,
            previous: nil,
            trackingIsNormal: true,
            subjectIsFresh: false,
            writerBacklog: 0
        ), .reject("subject"))
        XCTAssertEqual(gate.evaluate(
            current: first,
            previous: nil,
            trackingIsNormal: true,
            subjectIsFresh: true,
            writerBacklog: 0
        ), .accept)

        let still = CapturePose(transform: transform(x: 0.01), timestamp: 2)
        XCTAssertEqual(gate.evaluate(
            current: still,
            previous: first,
            trackingIsNormal: true,
            subjectIsFresh: true,
            writerBacklog: 0
        ), .reject("move farther"))
        let moved = CapturePose(transform: transform(x: 0.08), timestamp: 2)
        XCTAssertEqual(gate.evaluate(
            current: moved,
            previous: first,
            trackingIsNormal: true,
            subjectIsFresh: true,
            writerBacklog: 0
        ), .accept)
    }

    func testCaptureGateRejectsPoorImageQualityAndFastMotion() {
        let gate = GuidedCaptureGate()
        let pose = CapturePose(transform: transform(x: 0), timestamp: 1)
        XCTAssertEqual(gate.evaluate(
            current: pose,
            previous: nil,
            trackingIsNormal: true,
            subjectIsFresh: true,
            imageQualityIsAcceptable: false,
            motionIsAcceptable: true,
            writerBacklog: 0
        ), .reject("image quality"))
        XCTAssertEqual(gate.evaluate(
            current: pose,
            previous: nil,
            trackingIsNormal: true,
            subjectIsFresh: true,
            imageQualityIsAcceptable: true,
            motionIsAcceptable: false,
            writerBacklog: 0
        ), .reject("move slower"))
    }

    func testCaptureGateBoundsWriterBacklogAndAllowsManualSubjectFallback() {
        let gate = GuidedCaptureGate()
        let pose = CapturePose(transform: transform(x: 0), timestamp: 1)
        XCTAssertEqual(gate.evaluate(
            current: pose,
            previous: nil,
            trackingIsNormal: true,
            subjectIsFresh: true,
            writerBacklog: 2
        ), .reject("writer busy"))
        XCTAssertEqual(gate.evaluate(
            current: pose,
            previous: nil,
            trackingIsNormal: true,
            subjectIsFresh: false,
            writerBacklog: 0,
            manual: true
        ), .accept)
    }

    private func subject(bounds: CGRect, timestamp: TimeInterval) -> DetectedSubject {
        DetectedSubject(
            normalizedBounds: bounds,
            timestamp: timestamp,
            instanceLabel: 1,
            mask: SubjectInstanceMask(labels: [1], width: 1, height: 1, selectedLabel: 1)
        )
    }

    private func transform(x: Float) -> simd_float4x4 {
        var value = matrix_identity_float4x4
        value.columns.3.x = x
        return value
    }
}
