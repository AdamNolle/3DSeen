import XCTest
@testable import ThreeDSeen

final class CaptureDisplayAwakeTests: XCTestCase {
    func testAwakePolicyAppliesOnlyToTheActiveCaptureAttempt() {
        let activeAttempt = UUID()
        let staleAttempt = UUID()

        XCTAssertTrue(CaptureDisplayAwakePolicy.shouldKeepAwake(
            state: .capturing(mode: .space),
            activeAttemptID: activeAttempt,
            attemptID: activeAttempt,
            isSceneActive: true
        ))
        XCTAssertFalse(CaptureDisplayAwakePolicy.shouldKeepAwake(
            state: .capturing(mode: .space),
            activeAttemptID: activeAttempt,
            attemptID: staleAttempt,
            isSceneActive: true
        ))
        XCTAssertFalse(CaptureDisplayAwakePolicy.shouldKeepAwake(
            state: .packagingScan,
            activeAttemptID: activeAttempt,
            attemptID: activeAttempt,
            isSceneActive: true
        ))
        XCTAssertFalse(CaptureDisplayAwakePolicy.shouldKeepAwake(
            state: .capturing(mode: .space),
            activeAttemptID: activeAttempt,
            attemptID: activeAttempt,
            isSceneActive: false
        ))
    }

    func testIdleTimerLeaseRestoresOriginalValueAfterCapture() {
        var lease = CaptureIdleTimerLease()

        XCTAssertEqual(lease.update(isCapturing: true, currentValue: false), true)
        XCTAssertNil(lease.update(isCapturing: true, currentValue: true))
        XCTAssertEqual(lease.update(isCapturing: false, currentValue: true), false)
        XCTAssertNil(lease.update(isCapturing: false, currentValue: false))
    }

    func testIdleTimerLeasePreservesAnExistingAwakeRequest() {
        var lease = CaptureIdleTimerLease()

        XCTAssertNil(lease.update(isCapturing: true, currentValue: true))
        XCTAssertEqual(lease.restore(), true)
        XCTAssertNil(lease.restore())
    }
}
