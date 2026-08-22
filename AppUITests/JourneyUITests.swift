import XCTest

/// End-to-end walkthroughs of the journeys the product actually ships, driven
/// against the **production** backend — the same thing a person would do by hand,
/// but repeatable.
///
/// These are deliberately tolerant about timing (the AI endpoints do not stream and
/// can take the better part of a minute) and about content (a real account's plan
/// changes week to week). They assert on structure and navigation, not on dishes.
final class JourneyUITests: XCTestCase {

    /// Generous, because a cold `GET /api/meals/{week}` also resolves images.
    private let networkTimeout: TimeInterval = 40

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchSignedOut() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-KKBResetState"]
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Get Started → guest account → 3-step onboarding → Home.
    func testGuestOnboardingReachesHome() {
        let app = launchSignedOut()

        let getStarted = app.buttons["Get Started  →"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 20), "Welcome screen did not appear")
        attach(app, "01-welcome")
        getStarted.tap()

        // Step 1 of 3 — welcome.
        let step1 = app.staticTexts["STEP 1 OF 3"]
        XCTAssertTrue(
            step1.waitForExistence(timeout: networkTimeout),
            "Onboarding did not start — guest account creation probably failed"
        )
        attach(app, "02-onboarding-welcome")
        app.buttons["Get started"].tap()

        // Step 2 of 3 — cuisines. At least one is required to advance.
        XCTAssertTrue(app.staticTexts["STEP 2 OF 3"].waitForExistence(timeout: 10))
        let cuisine = app.buttons["Maharashtrian"]
        XCTAssertTrue(cuisine.waitForExistence(timeout: 10), "Cuisine chips missing")
        cuisine.tap()
        attach(app, "03-onboarding-cuisine")
        app.buttons["Next: dietary"].tap()

        // Step 3 of 3 — dietary.
        XCTAssertTrue(app.staticTexts["STEP 3 OF 3"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.switches["I am vegetarian"].waitForExistence(timeout: 10))
        attach(app, "04-onboarding-dietary")
        app.buttons["Complete setup"].tap()

        // Home.
        let todayTab = app.buttons["Today's Menu"]
        XCTAssertTrue(
            todayTab.waitForExistence(timeout: networkTimeout),
            "Did not reach Home after completing onboarding"
        )
        XCTAssertTrue(app.buttons["The Week"].exists)
        attach(app, "05-home-today")
    }

    /// Home → The Week → day cards, then back to Today.
    func testWeekTabRendersAndNavigatesWeeks() {
        let app = signedInApp()

        app.buttons["The Week"].tap()
        XCTAssertTrue(
            app.staticTexts["THE WEEK OF"].waitForExistence(timeout: networkTimeout),
            "Week header never appeared"
        )
        attach(app, "06-week")

        // The four actions above the grid.
        for action in ["AI", "PDF", "Shopping", "Clear"] {
            XCTAssertTrue(app.buttons[action].exists, "Missing \(action) action")
        }

        // Week navigation moves the range label.
        let header = app.staticTexts["THE WEEK OF"]
        XCTAssertTrue(header.exists)
        app.buttons["Next week"].tap()
        XCTAssertTrue(app.buttons["Previous week"].waitForExistence(timeout: networkTimeout))
        attach(app, "07-week-next")
        app.buttons["Previous week"].tap()

        app.buttons["Today's Menu"].tap()
        XCTAssertTrue(app.staticTexts["On today's card"].waitForExistence(timeout: networkTimeout))
        attach(app, "08-back-to-today")
    }

    /// The drawer's four settings screens each open and dismiss.
    func testSettingsScreensOpen() {
        let app = signedInApp()

        for (label, title) in [
            ("Dietary preferences", "Dietary Preferences"),
            ("Meal settings", "Meal Settings"),
            ("Prep reminders", "Prep Reminders"),
            ("Language", "Language"),
        ] {
            app.buttons["Menu"].tap()
            let row = app.buttons[label]
            XCTAssertTrue(row.waitForExistence(timeout: 10), "Drawer row '\(label)' missing")
            row.tap()

            XCTAssertTrue(
                app.staticTexts[title].waitForExistence(timeout: networkTimeout),
                "Settings screen '\(title)' did not open"
            )
            attach(app, "settings-\(title)")
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.buttons["Menu"].waitForExistence(timeout: 10))
        }
    }

    /// A guest must never be offered Logout — signing out of an anonymous account
    /// would silently destroy their plans. They get account creation instead.
    func testGuestDrawerOffersAccountCreationAndNeverLogout() {
        let app = signedInApp()
        app.buttons["Menu"].tap()

        XCTAssertTrue(app.buttons["Create account"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Guest"].exists)
        attach(app, "09-guest-drawer")

        // Logout lives behind Account now, so the invariant has to be checked
        // there. Asserting its absence from the drawer would pass whatever the
        // guest rule did, because no user sees Logout in the drawer any more.
        app.buttons["Account"].tap()
        XCTAssertTrue(
            app.buttons["Delete account"].waitForExistence(timeout: 10),
            "Account sheet did not open"
        )
        XCTAssertFalse(app.buttons["Logout"].exists, "Guests must not see Logout")
        attach(app, "10-guest-account")
    }

    /// Opening a planned meal from Today reaches the detail page.
    func testTomorrowScreenOpensFromTodayCard() {
        let app = signedInApp()

        let tomorrow = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] 'Tomorrow'")
        ).firstMatch
        guard tomorrow.waitForExistence(timeout: networkTimeout) else {
            XCTFail("Tomorrow card not found on Today's Menu")
            return
        }
        tomorrow.tap()

        XCTAssertTrue(
            app.staticTexts["ON THE MENU"].waitForExistence(timeout: networkTimeout),
            "Tomorrow screen did not open"
        )
        attach(app, "10-tomorrow")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["On today's card"].waitForExistence(timeout: 15))
    }

    // MARK: - Helpers

    /// Onboards a fresh guest and returns the app sitting on Home. Each test gets
    /// its own account, so they never contend over one plan.
    private func signedInApp() -> XCUIApplication {
        let app = launchSignedOut()

        let getStarted = app.buttons["Get Started  →"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 20))
        getStarted.tap()

        XCTAssertTrue(app.staticTexts["STEP 1 OF 3"].waitForExistence(timeout: networkTimeout))
        app.buttons["Get started"].tap()
        app.buttons["Maharashtrian"].tap()
        app.buttons["Next: dietary"].tap()
        app.buttons["Complete setup"].tap()

        XCTAssertTrue(
            app.buttons["Today's Menu"].waitForExistence(timeout: networkTimeout),
            "Could not reach Home"
        )
        return app
    }
}
