import XCTest

@MainActor
final class HerdieUITests: XCTestCase {
    func testHomeMakerLinkIsAvailableOnFirstLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-storage"]
        app.launch()
        let link = app.buttons["home-maker-link"]
        XCTAssertTrue(link.waitForExistence(timeout: 3))
        link.tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(link.exists)
    }

    func testMakerCardAppearsOnThirdLaunchAndCanBeDismissed() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-storage"]
        app.launch()
        XCTAssertFalse(app.buttons["Dismiss maker card"].exists)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertFalse(app.buttons["Dismiss maker card"].exists)
        app.terminate()
        app.launch()
        let dismiss = app.buttons["Dismiss maker card"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
        dismiss.tap()
        XCTAssertFalse(dismiss.exists)
        app.terminate()
        app.launch()
        XCTAssertFalse(dismiss.exists)
    }

    func testPhoneDockOpensReaderAndPreservesWritingDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-storage", "--seed-demo"]
        app.launch()
        app.staticTexts["Mac Studio"].tap()
        let agents = app.buttons["Running agents"]
        XCTAssertTrue(agents.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(agents.frame.width, 44)
        XCTAssertEqual(agents.frame.height, 44, accuracy: 1)
        XCTAssertEqual(agents.frame.midY, app.buttons["Show keyboard"].frame.midY, accuracy: 1)
        let dock = XCTAttachment(screenshot: app.screenshot())
        dock.name = "Compact terminal dock"
        dock.lifetime = .keepAlways
        add(dock)
        app.buttons["Read terminal output"].tap()
        XCTAssertTrue(app.navigationBars["Read output"].waitForExistence(timeout: 3))
        app.buttons["Back to live"].tap()
        app.buttons["Write a message"].tap()
        let draft = app.textViews["Message draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 3))
        draft.tap()
        draft.typeText("Review this change")
        app.buttons["Keep draft"].tap()
        app.buttons["Write a message"].tap()
        XCTAssertEqual(draft.value as? String, "Review this change")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Phone writing sheet"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testConnectionCreationFlowIsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-storage"]
        app.launch()

        app.buttons["Add connection"].tap()

        XCTAssertTrue(app.navigationBars["New Connection"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["Connection name"].exists)
        XCTAssertTrue(app.buttons["Connect"].exists)
    }

    func testConnectionEditorAcceptsTypingAcrossSSHFields() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-storage"]
        app.launch()
        app.buttons["Add connection"].tap()

        let started = ContinuousClock.now
        app.textFields["connection-name"].tap()
        app.textFields["connection-name"].typeText("Mac Studio")
        app.textFields["connection-host"].tap()
        app.textFields["connection-host"].typeText("studio.local")
        app.textFields["connection-username"].tap()
        app.textFields["connection-username"].typeText("lucas")
        app.buttons["Password"].tap()
        app.secureTextFields["connection-password"].tap()
        app.secureTextFields["connection-password"].typeText("secret")
        let elapsed = started.duration(to: .now)

        XCTAssertEqual(app.textFields["connection-name"].value as? String, "Mac Studio")
        XCTAssertEqual(app.textFields["connection-host"].value as? String, "studio.local")
        XCTAssertEqual(app.textFields["connection-username"].value as? String, "lucas")
        XCTAssertLessThan(elapsed, .seconds(10), "SSH form input took \(elapsed)")
    }

    func testSettingsExposeToolbarAndComposerControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-storage"]
        app.launch()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 2))
        app.buttons["Composer"].tap()

        XCTAssertTrue(app.navigationBars["Composer"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.switches["Composer mode"].exists)
    }

    func testSavedConnectionsExposeReorderingAndDeletion() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-storage", "--seed-demo"]
        app.launch()

        app.buttons["Manage"].tap()

        XCTAssertTrue(app.navigationBars["Manage Connections"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Mac Studio"].exists)
        XCTAssertTrue(app.buttons["Delete Mac Studio"].exists)
    }

    func testConnectionFailureStaysVisibleAndCanBeRetried() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--reset-storage",
            "--seed-demo",
            "--simulate-connection-failure"
        ]
        app.launch()

        app.staticTexts["Mac Studio"].tap()

        XCTAssertTrue(app.staticTexts["Couldn’t connect"].waitForExistence(timeout: 2))
        let resolutionMessage = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "The host name could not be resolved.")
        ).firstMatch
        XCTAssertTrue(resolutionMessage.exists)
        XCTAssertTrue(app.buttons["retry-connection"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Connection recovery"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
