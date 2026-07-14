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
    func testAuditLaunchScreenAcceptsKnownStudioRoute() {
        XCTAssertEqual(
            StudioScreen.auditLaunchScreen(environment: ["THREEDSEEN_UI_AUDIT_SCREEN": "quality"]),
            .quality
        )
    }

    func testAuditLaunchScreenRejectsUnknownStudioRoute() {
        XCTAssertNil(
            StudioScreen.auditLaunchScreen(environment: ["THREEDSEEN_UI_AUDIT_SCREEN": "prototype"])
        )
    }

    func testFlowOrder() {
        let flow = StudioModel().flow
        XCTAssertEqual(
            flow,
            [.library, .mode, .briefing, .quality, .capture, .review, .compute, .viewer, .export, .settings]
        )
        XCTAssertEqual(flow.count, StudioScreen.allCases.count)
    }

    @MainActor
    func testWizardNavigationReachesRoutedCaptureStep() {
        let model = StudioModel(initialScreen: .mode)
        model.next()
        XCTAssertEqual(model.screen, .briefing)
        model.next()
        XCTAssertEqual(model.screen, .quality)
        model.next()
        XCTAssertEqual(model.screen, .capture)
        model.next()
        XCTAssertEqual(model.screen, .review)
    }

    @MainActor
    func testCompletedMacResultRoutesSelectedScanToViewer() {
        let model = StudioModel(initialScreen: .library)
        let scanID = UUID()

        model.showCompletedScan(scanID)

        XCTAssertEqual(model.activeScanID, scanID)
        XCTAssertEqual(model.screen, .viewer)
    }

    func testUSDZQuickLookRequiresAnExistingUSDZFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-look-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let usdz = root.appendingPathComponent("model.usdz")
        let obj = root.appendingPathComponent("model.obj")
        try Data("fixture".utf8).write(to: usdz)
        try Data("fixture".utf8).write(to: obj)

        XCTAssertEqual(USDZPresentationPolicy.eligibleURL(usdz), usdz)
        XCTAssertNil(USDZPresentationPolicy.eligibleURL(obj))
        XCTAssertNil(USDZPresentationPolicy.eligibleURL(root.appendingPathComponent("missing.usdz")))
    }

    func testNewStudioModelUsesTheFullDetailDefault() {
        XCTAssertEqual(StudioModel().selectedDetailTier, SettingsStore.QualityTier.full.rawValue)
    }

    func testBeginningANewScanAppliesPersistedCaptureDefaults() {
        let defaults = UserDefaults(suiteName: "StudioModelTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.defaultMode = .landscape
        settings.qualityTier = .reduced

        let model = StudioModel()
        model.beginNewScan(using: settings)

        XCTAssertEqual(model.screen, .mode)
        XCTAssertEqual(model.selectedCaptureModeID, CaptureMode.landscape.rawValue.lowercased())
        XCTAssertEqual(model.selectedDetailTier, SettingsStore.QualityTier.reduced.rawValue)
        XCTAssertNil(model.activeScanID)
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

final class MeasurementFormatterTests: XCTestCase {
    func testMeasurementFormatterRespectsSelectedUnits() {
        XCTAssertEqual(MeasurementFormatter.display(meters: 1.234, units: .centimeters), "123.4 cm")
        XCTAssertEqual(MeasurementFormatter.display(meters: 1.234, units: .inches), "48.6 in")
    }
}

extension StudioScreenTests {
    func testSimulatorDoesNotAdvertiseLiveCaptureAvailability() {
        #if targetEnvironment(simulator)
        let status = CaptureAvailability.status(for: .object)
        XCTAssertFalse(status.isAvailable)
        XCTAssertNotNil(status.message)
        #endif
    }

    func testSimulatorExplainsModeSpecificCaptureRequirement() {
        #if targetEnvironment(simulator)
        let space = CaptureAvailability.status(for: .space)
        let landscape = CaptureAvailability.status(for: .landscape)

        XCTAssertTrue(space.message?.localizedCaseInsensitiveContains("LiDAR") == true)
        XCTAssertTrue(landscape.message?.localizedCaseInsensitiveContains("AR world tracking") == true)
        #endif
    }

    func testStudioModeIDsMapToTheirCaptureEngines() {
        XCTAssertEqual(STUDIO_MODES.first { $0.id == "auto" }?.captureMode, .autoPilot)
        XCTAssertEqual(STUDIO_MODES.first { $0.id == "object" }?.captureMode, .object)
        XCTAssertEqual(STUDIO_MODES.first { $0.id == "space" }?.captureMode, .space)
        XCTAssertEqual(STUDIO_MODES.first { $0.id == "landscape" }?.captureMode, .landscape)
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
