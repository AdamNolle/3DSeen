import XCTest
@testable import ThreeDSeen

final class AutoPilotTests: XCTestCase {

    func testStrongLandscapeSignal() {
        let s = AutoPilotVisionManager.suggestion(forClassifications: [
            ("outdoor mountain vista", 0.82), ("sky", 0.61), ("vase", 0.1)
        ])
        XCTAssertEqual(s.mode, .landscape)
        XCTAssertGreaterThan(s.confidence, 0.5)
    }

    func testStrongSpaceSignal() {
        let s = AutoPilotVisionManager.suggestion(forClassifications: [
            ("indoor room", 0.7), ("furniture", 0.6)
        ])
        XCTAssertEqual(s.mode, .space)
    }

    func testFallsBackToObject() {
        let s = AutoPilotVisionManager.suggestion(forClassifications: [
            ("ceramic vase", 0.92), ("pottery", 0.4)
        ])
        XCTAssertEqual(s.mode, .object)
        XCTAssertGreaterThanOrEqual(s.confidence, 0.6)
    }

    func testEmptyDefaultsToObject() {
        let s = AutoPilotVisionManager.suggestion(forClassifications: [])
        XCTAssertEqual(s.mode, .object)
    }

    func testSpaceBeatsWeakLandscape() {
        let s = AutoPilotVisionManager.suggestion(forClassifications: [
            ("indoor kitchen", 0.9), ("window", 0.4), ("tree", 0.1)
        ])
        XCTAssertEqual(s.mode, .space)
    }

    func testResolutionKeepsACompatibleSuggestedMode() {
        let suggestion = AutoPilotVisionManager.Suggestion(mode: .landscape, confidence: 0.9, label: "mountain")

        XCTAssertEqual(
            AutoPilotVisionManager.resolvedMode(for: suggestion, supportedModes: [.object, .landscape]),
            .landscape
        )
    }

    func testResolutionFallsBackToObjectWhenSuggestedModeIsUnavailable() {
        let suggestion = AutoPilotVisionManager.Suggestion(mode: .space, confidence: 0.9, label: "room")

        XCTAssertEqual(
            AutoPilotVisionManager.resolvedMode(for: suggestion, supportedModes: [.object]),
            .object
        )
    }
}
