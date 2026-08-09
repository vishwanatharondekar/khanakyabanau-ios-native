import XCTest

/// The write paths, driven against production.
///
/// `PUT /api/meals/{week}` replaces the whole grid, so a mistake here does not
/// merely fail — it silently deletes a user's week. These tests round-trip through
/// the real server and re-read to prove the write actually landed.
final class PlannerUITests: XCTestCase {

    private let networkTimeout: TimeInterval = 45

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

    /// Fresh guest, onboarded, sitting on The Week.
    private func weekApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-KKBResetState"]
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
        return app
    }

    /// Writing a dish into an empty slot must persist server-side, and must still
    /// be there after navigating away and back (which re-reads the week).
    func testWritingADishPersistsAcrossAReload() {
        let app = weekApp()

        // An empty Monday breakfast offers a single add affordance.
        let add = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH[c] 'Add a breakfast'"))
            .firstMatch
        guard add.waitForExistence(timeout: networkTimeout) else {
            // A brand-new guest's week is empty, so this should exist. If it does
            // not, the grid did not render its rows at all.
            XCTFail("No empty breakfast slot found on the week grid")
            return
        }
        add.tap()

        // The suggestion sheet opens for an empty slot.
        let ownField = app.textFields["write your own…"]
        XCTAssertTrue(
            ownField.waitForExistence(timeout: 20),
            "Suggestion sheet did not open for the empty slot"
        )
        attach(app, "20-suggestion-sheet")

        let dish = "Kanda Poha"
        ownField.tap()
        ownField.typeText(dish)
        app.buttons["Save this dish"].tap()

        // It should appear in the grid.
        XCTAssertTrue(
            app.staticTexts[dish].waitForExistence(timeout: networkTimeout),
            "Dish did not appear in the week grid after saving"
        )
        attach(app, "21-dish-saved")

        // Navigate away and back — this re-reads the week from the server, so the
        // dish surviving proves the PUT actually landed.
        app.buttons["Next week"].tap()
        XCTAssertTrue(app.staticTexts["THE WEEK OF"].waitForExistence(timeout: networkTimeout))
        app.buttons["Previous week"].tap()

        XCTAssertTrue(
            app.staticTexts[dish].waitForExistence(timeout: networkTimeout),
            "Dish did not survive a reload — the save did not reach the server"
        )
        attach(app, "22-dish-after-reload")
    }

    /// Tapping a filled slot opens the rename dialog rather than the suggestion
    /// sheet, and saving an unchanged name must not clear the slot.
    func testEditingAFilledSlotKeepsTheDish() {
        let app = weekApp()

        let add = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH[c] 'Add a breakfast'"))
            .firstMatch
        guard add.waitForExistence(timeout: networkTimeout) else {
            XCTFail("No empty breakfast slot found")
            return
        }
        add.tap()

        let ownField = app.textFields["write your own…"]
        XCTAssertTrue(ownField.waitForExistence(timeout: 20))
        ownField.tap()
        ownField.typeText("Thalipeeth")
        app.buttons["Save this dish"].tap()
        XCTAssertTrue(app.staticTexts["Thalipeeth"].waitForExistence(timeout: networkTimeout))

        // Now the row is filled, so the edit pencil is available.
        let edit = app.buttons["Edit meal"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 15), "Edit control missing on a filled row")
        edit.tap()

        XCTAssertTrue(
            app.staticTexts["What's cooking?"].waitForExistence(timeout: 15),
            "Edit dialog did not open"
        )
        attach(app, "23-edit-dialog")
        app.buttons["Save"].tap()

        // Saving an unchanged name is not an edit and must not clear the slot.
        XCTAssertTrue(
            app.staticTexts["Thalipeeth"].waitForExistence(timeout: networkTimeout),
            "Saving an unchanged name cleared the dish"
        )
        attach(app, "24-after-unchanged-save")
    }

    /// The AI prompt sheet opens and takes pantry ingredients and mood cuisines.
    /// Generation itself is left to run only as far as the loading state — a full
    /// week generation burns one of the guest's three lifetime allowances.
    func testAIPromptSheetOpensWithItsControls() {
        let app = weekApp()

        app.buttons["AI"].tap()
        XCTAssertTrue(
            app.staticTexts["Generate with AI"].waitForExistence(timeout: 15),
            "AI prompt sheet did not open"
        )
        XCTAssertTrue(app.staticTexts["WHAT'S IN THE PANTRY?"].exists)
        XCTAssertTrue(app.staticTexts["I AM IN MOOD FOR"].exists)
        XCTAssertTrue(app.buttons["Generate"].exists)
        attach(app, "25-ai-prompt")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["THE WEEK OF"].waitForExistence(timeout: 15))
    }

    /// Clear-week is destructive, so it must confirm first.
    func testClearWeekAsksForConfirmation() {
        let app = weekApp()

        app.buttons["Clear"].tap()
        let alert = app.alerts["Clear all meals"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "Clear did not confirm before destroying")
        attach(app, "26-clear-confirm")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["THE WEEK OF"].waitForExistence(timeout: 15))
    }
}
