import XCTest
import simd
@testable import ThreeDSeen

final class ThemeTests: XCTestCase {
    func testModes() {
        XCTAssertEqual(Theme.light.mode, .light)
        XCTAssertEqual(Theme.dark.mode, .dark)
        XCTAssertEqual(Theme.of(.dark).mode, .dark)
        XCTAssertEqual(Theme.of(.light).mode, .light)
    }
}

final class StudioScreenTests: XCTestCase {
    func testFlowOrder() {
        let flow = StudioModel().flow
        XCTAssertEqual(flow.first, .library)
        XCTAssertEqual(flow.last, .settings)
        XCTAssertEqual(flow.count, StudioScreen.allCases.count)
    }

    @MainActor
    func testNavigationNextPrev() {
        let m = StudioModel()
        XCTAssertEqual(m.screen, .library)
        m.next()
        XCTAssertEqual(m.screen, .mode)
        m.prev()
        XCTAssertEqual(m.screen, .library)
        m.prev() // clamp at start
        XCTAssertEqual(m.screen, .library)
    }
}

final class SplatMatrixTests: XCTestCase {
    func testPerspectiveHasPositiveScales() {
        let m = GaussianSplatMetalView.Coordinator.perspective(fovyRadians: 0.9, aspect: 1.5, near: 0.05, far: 100)
        XCTAssertGreaterThan(m.columns.0.x, 0)
        XCTAssertGreaterThan(m.columns.1.y, 0)
        XCTAssertEqual(m.columns.2.w, -1, accuracy: 0.0001) // perspective divide term
    }

    func testOrbitViewIsOrthonormal() {
        let v = GaussianSplatMetalView.Coordinator.orbitView(yaw: 0.5, pitch: -0.2, distance: 3)
        let c0 = SIMD3(v.columns.0.x, v.columns.0.y, v.columns.0.z)
        XCTAssertEqual(simd_length(c0), 1, accuracy: 0.001)
    }
}
