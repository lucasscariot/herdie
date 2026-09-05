import XCTest

@MainActor
final class HerdieUITests: XCTestCase {
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
