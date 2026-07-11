import XCTest
@testable import ThreeDSeen

final class ComputeDetailCapabilityTests: XCTestCase {
    func testOnDeviceComputeDeclaresReducedOutputForAnyRequestedTier() {
        XCTAssertEqual(
            ComputeDetailCapability.effectiveTier(for: .onDevice, requestedTier: "Full"),
            "Reduced"
        )
    }

    func testMacHandoffPreservesTheRequestedTier() {
        XCTAssertEqual(
            ComputeDetailCapability.effectiveTier(for: .macHandoff, requestedTier: "Raw"),
            "Raw"
        )
    }
}
