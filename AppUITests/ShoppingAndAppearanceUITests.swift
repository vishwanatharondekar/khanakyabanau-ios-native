import XCTest

/// Shopping-list generation (a real AI call) and appearance checks.
///
/// Deliberately one shopping-list generation per run: it consumes one of a guest's
/// three lifetime allowances on the production backend.
final class ShoppingAndAppearanceUITests: XCTestCase {

    private let networkTimeout: TimeInterval = 45
    /// The shopping-list route calls an LLM and does not stream.
    private let aiTimeout: TimeInterval = 120

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

    private func onboardedWeek(_ app: XCUIApplication) {
        app.launch()
        XCTAssertTrue(app.buttons["Get Started  →"].waitForExistence(timeout: 20))
        app.buttons["Get Started  →"].tap()
        XCTAssertTrue(app.staticTexts["STEP 1 OF 3"].waitForExistence(timeout: networkTimeout))
        app.buttons["Get started"].tap()
        app.buttons["Maharashtrian"].tap()
        app.buttons["Next: dietary"].tap()
        app.buttons["Complete setup"].tap()
        XCTAssertTrue(app.buttons["The Week"].waitForExistence(timeout: networkTimeout))
        app.buttons["The Week"].tap()
        XCTAssertTrue(app.staticTexts["THE WEEK OF"].waitForExistence(timeout: networkTimeout))
    }

    private func writeDish(_ app: XCUIApplication, course: String, dish: String) {
        let add = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH[c] 'Add a \(course)'"))
            .firstMatch
        guard add.waitForExistence(timeout: networkTimeout) else {
            XCTFail("No empty \(course) slot")
            return
        }
        add.tap()
        let field = app.textFields["write your own…"]
        XCTAssertTrue(field.waitForExistence(timeout: 20))
        field.tap()
        field.typeText(dish)
        app.buttons["Save this dish"].tap()
        XCTAssertTrue(app.staticTexts[dish].waitForExistence(timeout: networkTimeout))
    }

    /// Plan a couple of dishes, generate the list, and check the scoping controls,
    /// the tick-off behaviour and the export actions are all live.
    func testShoppingListGeneratesAndScopes() {
        let app = XCUIApplication()
        app.launchArguments = ["-KKBResetState"]
        onboardedWeek(app)

        writeDish(app, course: "breakfast", dish: "Poha")
        writeDish(app, course: "lunch", dish: "Rajma Chawal")

        app.buttons["Shopping"].tap()

        // The blocking loader while the AI works.
        XCTAssertTrue(
            app.staticTexts["Shopping list"].waitForExistence(timeout: aiTimeout),
            "Shopping list never arrived — the AI call failed or timed out"
        )
        attach(app, "30-shopping-list")

        // Day chips exist when the server returned a per-day breakdown. "All week"
        // sits past the right edge of the scrolling row, so only assert existence.
        XCTAssertTrue(app.buttons["All week"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Mon"].exists)

        // The three export actions.
        for action in ["Share", "Copy", "PDF"] {
            XCTAssertTrue(app.buttons[action].exists, "Missing \(action) action")
        }

        // Ticking an ingredient flips it to "already have".
        let toBuy = app.buttons.matching(NSPredicate(format: "value == 'To buy'")).firstMatch
        if toBuy.waitForExistence(timeout: 10) {
            toBuy.tap()
            attach(app, "31-shopping-ticked")
        }

        // Widening the scope re-aggregates without erroring. Today is whatever day
        // the test runs on, so add a day that is definitely not already selected.
        let monday = app.buttons["Mon"]
        if monday.isHittable {
            monday.tap()
            XCTAssertTrue(
                app.staticTexts["Shopping list"].waitForExistence(timeout: 15),
                "Changing the day scope tore the sheet down"
            )
            attach(app, "32-shopping-rescoped")
        }
    }

    /// Walks the primary surfaces with the dark appearance requested.
    ///
    /// This is a *smoke* test, not proof of dark mode: `XCUIDevice.appearance` is
    /// recorded but not always applied by SpringBoard, so a pass here only says the
    /// screens render and stay navigable. The palette itself — surfaces darkening,
    /// text lightening, contrast holding — is asserted directly against trait
    /// collections in `DesignSystemTests`, which is where that claim actually lives.
    func testPrimarySurfacesRenderWithDarkAppearanceRequested() {
        let app = XCUIApplication()
        app.launchArguments = ["-KKBResetState"]
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }

        onboardedWeek(app)
        attach(app, "40-dark-week")

        app.buttons["Today's Menu"].tap()
        XCTAssertTrue(app.staticTexts["On today's card"].waitForExistence(timeout: networkTimeout))
        attach(app, "41-dark-today")

        app.buttons["Menu"].tap()
        XCTAssertTrue(app.buttons["Dietary preferences"].waitForExistence(timeout: 10))
        attach(app, "42-dark-drawer")
    }
}
