import XCTest

final class WizardFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["THREEDSEEN_UI_AUDIT_SCREEN"] = "library"
        app.launch()
    }

    func testWizardRoutesThroughCaptureAndExposesReviewSurface() {
        assertScreen("library")

        app.buttons["New Scan"].firstMatch.tap()
        assertScreen("mode")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Continue with'")).firstMatch.tap()
        assertScreen("briefing")

        app.buttons["Choose Result"].tap()
        assertScreen("quality")

        app.buttons["Start Capture"].tap()
        assertScreen("capture")

        let unavailableAlert = app.alerts["3DSeen needs attention"]
        XCTAssertTrue(unavailableAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(unavailableAlert.staticTexts.element(boundBy: 1).label.contains("physical iPhone or iPad"))
        unavailableAlert.buttons["Back"].tap()
        assertScreen("quality")

        app.terminate()
        app.launchEnvironment["THREEDSEEN_UI_AUDIT_SCREEN"] = "review"
        app.launch()
        assertScreen("review")
        XCTAssertTrue(app.staticTexts["Your scan is saved"].waitForExistence(timeout: 3))
    }

    func testGuidedQualityChoicesAndAdvancedControlsRemainReachable() {
        app.terminate()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launchEnvironment["THREEDSEEN_UI_AUDIT_SCREEN"] = "quality"
        app.launch()
        assertScreen("quality")

        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Quick.'")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Balanced.'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Maximum.'")).firstMatch.exists)
        let advanced = app.buttons["Advanced controls"]
        XCTAssertTrue(advanced.exists)
        // The fixed bottom CTA can overlap the accessibility frame before the long Dynamic Type
        // content scrolls. Move the disclosure into the center before tapping it.
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertTrue(advanced.isHittable)
        advanced.tap()
        let expanded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'Expanded'"),
            object: advanced
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 3), .completed)
        XCTAssertTrue(app.buttons["Start Capture"].exists)
    }

    func testBeginnerCopyAndActionsRemainReachableAtAccessibilitySize() {
        app.terminate()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launchEnvironment["THREEDSEEN_UI_AUDIT_SCREEN"] = "briefing"
        app.launch()
        assertScreen("briefing")
        XCTAssertTrue(app.staticTexts["Get ready to scan"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Choose Result"].exists)

        app.terminate()
        app.launchEnvironment["THREEDSEEN_UI_AUDIT_SCREEN"] = "review"
        app.launch()
        assertScreen("review")
        XCTAssertTrue(app.staticTexts["Your scan is saved"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Retake"].exists)
        XCTAssertTrue(app.buttons["Build Model"].exists)

        app.terminate()
        app.launchEnvironment["THREEDSEEN_UI_AUDIT_SCREEN"] = "compute"
        app.launch()
        assertScreen("compute")
        XCTAssertTrue(app.staticTexts["Build your model"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Use a Mac'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Build on This Device'")).firstMatch.exists)
    }

    func testRegularWizardSurfacesExposeGuidedChoices() {
        app.terminate()
        app.launchEnvironment["THREEDSEEN_UI_AUDIT_SCREEN"] = "mode"
        app.launch()
        assertScreen("mode")
        for name in ["Choose for Me", "Object", "Room", "Outdoor Scene"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.waitForExistence(timeout: 3))
        }

        app.terminate()
        app.launchEnvironment["THREEDSEEN_UI_AUDIT_SCREEN"] = "quality"
        app.launch()
        assertScreen("quality")
        for name in ["Quick", "Balanced", "Maximum"] {
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.waitForExistence(timeout: 3))
        }
        XCTAssertTrue(app.buttons["Advanced controls"].exists)
        XCTAssertTrue(app.buttons["Start Capture"].exists)
    }

    func testAccessibilityDynamicTypeKeepsSettingsAndViewerActionsReachable() {
        app.terminate()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launchEnvironment["THREEDSEEN_UI_AUDIT_SCREEN"] = "settings"
        app.launch()
        assertScreen("settings")
        XCTAssertTrue(app.switches["Thermal protection"].waitForExistence(timeout: 3))
        let trustedSection = app.buttons["Trusted Devices"].firstMatch
        if trustedSection.exists && trustedSection.isHittable {
            trustedSection.tap()
        } else {
            for _ in 0..<5 where !app.switches["Automatically select trusted Mac"].exists { app.swipeUp() }
        }
        XCTAssertTrue(app.switches["Automatically select trusted Mac"].waitForExistence(timeout: 3))
        let storageSection = app.buttons["Storage Maintenance"].firstMatch
        if storageSection.exists && storageSection.isHittable {
            storageSection.tap()
        } else {
            for _ in 0..<5 where !app.buttons["Raw archive retention"].exists { app.swipeUp() }
        }
        XCTAssertTrue(app.buttons["Raw archive retention"].waitForExistence(timeout: 3))

        app.terminate()
        app.launchEnvironment["THREEDSEEN_UI_AUDIT_SCREEN"] = "viewer"
        app.launch()
        assertScreen("viewer")
        XCTAssertTrue(app.buttons["Splat"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Quick Look / AR"].exists)
        XCTAssertTrue(app.buttons["Export"].exists)
    }

    private func assertScreen(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let screen = app.descendants(matching: .any)["studio.screen.\(name)"]
        XCTAssertTrue(screen.waitForExistence(timeout: 3), "Expected Studio screen \(name)", file: file, line: line)
    }
}
