import XCTest

@MainActor
final class HerdieUITests: XCTestCase {
    func testLaunchPerformance() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-storage", "--seed-demo"]
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
        }
    }

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
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Opening a terminal should not load the keyboard until requested")
        XCTAssertGreaterThanOrEqual(agents.frame.width, 44)
        XCTAssertGreaterThanOrEqual(agents.frame.height, 44)
        XCTAssertEqual(agents.frame.midY, app.buttons["Show keyboard"].frame.midY, accuracy: 1)
        let dock = XCTAttachment(screenshot: app.screenshot())
        dock.name = "Compact terminal dock"
        dock.lifetime = .keepAlways
        add(dock)
        app.buttons["Session actions"].tap()
        app.buttons["Read terminal output"].tap()
        XCTAssertTrue(app.navigationBars["Read output"].waitForExistence(timeout: 3))
        app.buttons["Back to live"].tap()
        app.buttons["Write a message"].tap()
        let draft = app.textViews["Message draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 3))
        draft.typeText("Review this change")
        app.buttons["Keep draft"].tap()
        app.buttons["Write a message"].tap()
        XCTAssertEqual(draft.value as? String, "Review this change")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Phone writing sheet"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testTerminalFocusModeRestoresControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-storage", "--seed-demo"]
        app.launch()
        app.staticTexts["Mac Studio"].tap()
        let connected = NSPredicate(format: "enabled == true AND hittable == true")
        expectation(for: connected, evaluatedWith: app.buttons["Running agents"])
        waitForExpectations(timeout: 15)
        app.buttons["Session actions"].tap()
        XCTAssertTrue(app.buttons["Hide controls"].waitForExistence(timeout: 15))
        app.buttons["Hide controls"].tap()
        XCTAssertTrue(app.buttons["Show controls"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Write a message"].exists)
        app.buttons["Show controls"].tap()
        XCTAssertTrue(app.buttons["Write a message"].waitForExistence(timeout: 15))
        app.buttons["Show keyboard"].tap()
        XCTAssertTrue(app.buttons["terminal-hide-keyboard"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Write a message"].exists)
        app.buttons["terminal-hide-keyboard"].tap()
        XCTAssertTrue(app.buttons["Write a message"].waitForExistence(timeout: 15))
    }

    func testFloatingDockCollapsesWhileBrowsingOutput() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-storage", "--seed-demo"]
        app.launch()
        app.staticTexts["Mac Studio"].tap()
        let agents = app.buttons["Running agents"]
        XCTAssertTrue(agents.waitForExistence(timeout: 10))
        let expandedWidth = agents.frame.width
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "Floating dock - expanded"
        expanded.lifetime = .keepAlways
        add(expanded)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertLessThan(agents.frame.width, expandedWidth)
        XCTAssertGreaterThanOrEqual(agents.frame.height, 44)
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.name = "Floating dock - collapsed"
        collapsed.lifetime = .keepAlways
        add(collapsed)
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertEqual(agents.frame.width, expandedWidth, accuracy: 1)
        app.buttons["Write a message"].tap()
        XCTAssertTrue(app.textViews["Message draft"].waitForExistence(timeout: 5))
    }

    func testKeyboardAppearanceInLightAndDarkModes() {
        let app = XCUIApplication()
        for mode in ["Light", "Dark"] {
            app.launchArguments = ["--ui-testing", "--reset-storage", "--seed-demo"]
            app.launch()
            app.buttons["Settings"].tap()
            app.buttons[mode].tap()
            app.buttons["Done"].tap()
            app.staticTexts["Mac Studio"].tap()
            expectation(for: NSPredicate(format: "enabled == true AND hittable == true"), evaluatedWith: app.buttons["Show keyboard"])
            waitForExpectations(timeout: 15)
            app.buttons["Show keyboard"].tap()
            // Fresh simulators can show the system QuickPath introduction.
            if app.buttons["Continue"].waitForExistence(timeout: 2) { app.buttons["Continue"].tap() }
            XCTAssertTrue(app.buttons["terminal-hide-keyboard"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["terminal-key-control"].exists)
            app.buttons["terminal-key-control"].tap()
            XCTAssertEqual(app.buttons["terminal-key-control"].value as? String, "On")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Native keyboard - \(mode)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.buttons["terminal-hide-keyboard"].tap()
            XCTAssertTrue(app.buttons["Write a message"].waitForExistence(timeout: 15))
            app.terminate()
        }
    }

    func testLoadingResolvesIntoAttachedTerminal() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-storage", "--seed-demo", "--slow-connection"]
        app.launch()
        app.staticTexts["Mac Studio"].tap()
        XCTAssertTrue(app.staticTexts["Connecting to Mac Studio…"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Running agents"].waitForExistence(timeout: 5))
        let attached = NSPredicate(format: "enabled == true")
        expectation(for: attached, evaluatedWith: app.buttons["Running agents"])
        waitForExpectations(timeout: 6)
        XCTAssertFalse(app.staticTexts["Connecting to Mac Studio…"].exists)
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
        app.buttons["connection-help"].tap()
        XCTAssertTrue(app.navigationBars["Connection help"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Herdie Settings"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["retry-connection"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Connection recovery"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
