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
