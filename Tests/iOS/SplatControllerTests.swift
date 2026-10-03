import XCTest
import Combine
import MetalKit
@testable import ThreeDSeen

@MainActor
final class SplatControllerTests: XCTestCase {
    func testSelectingTheSameFileAgainCreatesANewLoadAttempt() {
        let controller = SplatController()
        let url = URL(fileURLWithPath: "/tmp/repaired.splat")
        controller.load(url)
        let firstAttempt = controller.loadAttemptID
        controller.status = "Could not open splat file"

        controller.load(url)

        XCTAssertEqual(controller.url, url)
        XCTAssertNotEqual(controller.loadAttemptID, firstAttempt)
        XCTAssertTrue(controller.status.hasPrefix("Loading"))
    }

    func testMissingMetalDeviceReportsUnavailableWithoutCrashingOrStayingLoading() async {
        let controller = SplatController()
        let coordinator = GaussianSplatMetalView.Coordinator(controller: controller)
        let view = MTKView(frame: .zero, device: nil)
        view.device = nil
        coordinator.configure(view: view)
        controller.load(URL(fileURLWithPath: "/tmp/scene.splat"))
        let unavailable = expectation(description: "Unsupported rendering hardware is surfaced")
        let subscription = controller.$status
            .first(where: { $0.contains("unavailable") })
            .sink { _ in unavailable.fulfill() }

        coordinator.loadIfNeeded(in: view)

        await fulfillment(of: [unavailable], timeout: 3)
        withExtendedLifetime(subscription) {}
        XCTAssertFalse(controller.status.hasPrefix("Loading"))
    }
}
