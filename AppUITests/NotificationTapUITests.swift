import XCTest

/// A reminder is only worth sending if tapping it lands somewhere.
///
/// Everything up to delivery is covered by unit tests against a fake notification
/// centre; what those cannot reach is the part iOS owns — the banner, the tap, and
/// the navigation that follows once the app is woken by it. That has to be driven
/// through SpringBoard on a real notification, which is what this does.
final class NotificationTapUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let networkTimeout: TimeInterval = 40

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTappingAPrepReminderOpensTomorrow() {
        let app = XCUIApplication()
        app.launchArguments = ["-KKBResetState"]
        app.launch()
        completeGuestOnboarding(app)

        // Prep reminders, via the drawer.
        app.buttons["Menu"].tap()
        let reminders = app.buttons["Prep reminders"]
        XCTAssertTrue(reminders.waitForExistence(timeout: 10), "Drawer has no prep-reminder row")
        reminders.tap()

        // Permission first, if it hasn't been given already. `-KKBResetState` clears
        // the app's own storage but notification permission belongs to the
        // simulator, so it survives between runs — this has to cope with both.
        let allowInApp = app.buttons["Allow notifications"]
        if allowInApp.waitForExistence(timeout: networkTimeout) {
            allowInApp.tap()
            let systemAllow = springboard.buttons["Allow"]
            XCTAssertTrue(systemAllow.waitForExistence(timeout: 15), "No system permission prompt")
            systemAllow.tap()
        }

        // Send one now rather than waiting for the evening. The debug button that
        // used to do this is gone; a relaunch under `-KKBSendTestReminder` schedules
        // the same reminder once the session is back up. Permission belongs to the
        // simulator and the guest session to the keychain, so both survive.
        app.terminate()
        app.launchArguments = ["-KKBSendTestReminder"]
        app.launch()
        XCTAssertTrue(
            app.buttons["Today's Menu"].waitForExistence(timeout: networkTimeout),
            "The relaunched app never reached Home, so no reminder was scheduled"
        )
        attach(app, "01-test-reminder-sent")

        // Banners only present over SpringBoard, so get out of the app first.
        XCUIDevice.shared.press(.home)

        let banner = springboard.staticTexts["Prep tonight for tomorrow"]
        XCTAssertTrue(
            banner.waitForExistence(timeout: 40),
            "The reminder was never delivered"
        )
        banner.tap()

        // The tap must reach Tomorrow. A crash would relaunch the app at Home
        // instead, which is exactly what this distinguishes.
        let heading = app.staticTexts["COMING UP"]
        XCTAssertTrue(
            heading.waitForExistence(timeout: networkTimeout),
            "Tapping the reminder did not open Tomorrow — the app may have crashed"
        )
        attach(app, "02-tomorrow-after-tap")
        XCTAssertEqual(app.state, .runningForeground, "The app is not running after the tap")
    }

    /// Shared with the other journeys: a fresh install has to get through guest
    /// onboarding before any of this is reachable.
    private func completeGuestOnboarding(_ app: XCUIApplication) {
        let getStarted = app.buttons["Get Started  →"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 20), "Welcome screen did not appear")
        getStarted.tap()

        XCTAssertTrue(
            app.staticTexts["STEP 1 OF 3"].waitForExistence(timeout: networkTimeout),
            "Guest account creation failed"
        )
        app.buttons["Get started"].tap()

        XCTAssertTrue(app.staticTexts["STEP 2 OF 3"].waitForExistence(timeout: 10))
        let cuisine = app.buttons["Maharashtrian"]
        XCTAssertTrue(cuisine.waitForExistence(timeout: 10))
        cuisine.tap()
        app.buttons["Next: dietary"].tap()

        XCTAssertTrue(app.staticTexts["STEP 3 OF 3"].waitForExistence(timeout: 10))
        app.buttons["Complete setup"].tap()

        XCTAssertTrue(
            app.buttons["Today's Menu"].waitForExistence(timeout: networkTimeout),
            "Did not reach Home"
        )
    }
}
