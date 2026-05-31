import XCTest
@testable import ThreeDSeenMac

final class ComputeStageTests: XCTestCase {

    func testProgressMapsToStages() {
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.00), .ingest)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.05), .ingest)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.20), .sparse)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.50), .dense)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.75), .mesh)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.90), .texture)
        XCTAssertEqual(ComputeCoordinator.Stage.forProgress(0.99), .optimize)
    }

    func testStageOrderingMonotonic() {
        let order = ComputeCoordinator.Stage.allCases
        XCTAssertEqual(order.first, .waiting)
        XCTAssertEqual(order.last, .done)
        // forProgress never returns waiting/done (those are set explicitly by the coordinator)
        for p in stride(from: 0.0, through: 1.0, by: 0.05) {
            let s = ComputeCoordinator.Stage.forProgress(p)
            XCTAssertNotEqual(s, .waiting)
            XCTAssertNotEqual(s, .done)
        }
    }

    func testLabels() {
        XCTAssertEqual(ComputeCoordinator.Stage.done.label, "Complete")
        XCTAssertEqual(ComputeCoordinator.Stage.dense.label, "Dense reconstruction")
    }
}

@MainActor
final class MacStateMachineTests: XCTestCase {
    func testSharedStateMachineWorksOnMac() {
        let sm = ProcessingStateMachine()
        sm.send(.startCapture(.object))
        XCTAssertEqual(sm.state, .capturing(mode: .object))
    }
}
