import XCTest
@testable import KhanaKit

/// Mirrors the worked examples in the web app's `lib/prep-tonight.ts` and Android's
/// `PrepTonightTest`. A disagreement here means the app and the push notification
/// tell the user different things.
final class PrepTonightTests: XCTestCase {

    private func meal(
        _ name: String,
        steps: [PrepStep],
        prepFor: String? = nil
    ) -> Meal {
        Meal(
            name: name,
            prep: MealPrep(
                steps: steps,
                maxLeadTimeMinutes: steps.map(\.leadTimeMinutes).max() ?? 0
            ),
            prepFor: prepFor ?? name
        )
    }

    /// Soaking rajma 8 h before a 13:00 lunch means starting at 05:00 — before the
    /// 07:00 cutoff, so it is a tonight job.
    func testLongSoakForLunchIsATonightJob() {
        let day = DayMeals(lunch: meal(
            "Rajma", steps: [PrepStep(text: "Soak rajma", leadTimeMinutes: 480, category: .soak)]
        ))
        let items = PrepTonight.itemsForTomorrow(day)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.startByMinutes, 13 * 60 - 480)
        XCTAssertEqual(items.first?.dish, "Rajma")
        XCTAssertEqual(items.first?.mealType, .lunch)
    }

    /// A 4 h marinade for a 20:00 dinner starts at 16:00 — comfortably a same-day job.
    func testShortMarinadeForDinnerIsNotATonightJob() {
        let day = DayMeals(dinner: meal(
            "Tikka", steps: [PrepStep(text: "Marinate", leadTimeMinutes: 240, category: .marinate)]
        ))
        XCTAssertTrue(PrepTonight.itemsForTomorrow(day).isEmpty)
    }

    /// The cutoff is strict: a step that can start exactly at 07:00 is a morning job.
    func testExactlySevenAMIsExcluded() {
        let day = DayMeals(breakfast: meal(
            "Idli", steps: [PrepStep(text: "Steam", leadTimeMinutes: 60, category: .boil)]
        ))
        XCTAssertTrue(PrepTonight.itemsForTomorrow(day).isEmpty)
    }

    func testOneMinuteBeforeTheCutoffIsIncluded() {
        let day = DayMeals(breakfast: meal(
            "Idli", steps: [PrepStep(text: "Steam", leadTimeMinutes: 61, category: .boil)]
        ))
        XCTAssertEqual(PrepTonight.itemsForTomorrow(day).count, 1)
    }

    /// A 24 h ferment for tomorrow's lunch has to start at 13:00 *today*, which is
    /// a negative offset from tomorrow's midnight.
    func testOvernightFermentProducesANegativeStartTime() {
        let day = DayMeals(lunch: meal(
            "Idli", steps: [PrepStep(text: "Ferment batter", leadTimeMinutes: 1440, category: .ferment)]
        ))
        XCTAssertEqual(PrepTonight.itemsForTomorrow(day).first?.startByMinutes, -660)
    }

    /// Prep whose `prepFor` no longer matches the dish is stale — telling someone to
    /// soak chana for a dish they swapped out is worse than saying nothing.
    func testStalePrepIsIgnored() {
        let day = DayMeals(lunch: meal(
            "Chole",
            steps: [PrepStep(text: "Soak", leadTimeMinutes: 480, category: .soak)],
            prepFor: "Rajma"
        ))
        XCTAssertTrue(PrepTonight.itemsForTomorrow(day).isEmpty)
    }

    /// Absent prep and empty prep both yield nothing, for different reasons: one has
    /// never been generated, the other genuinely needs no advance work.
    func testAbsentAndEmptyPrepBothYieldNothing() {
        let noPrep = DayMeals(lunch: Meal(name: "Poha"))
        XCTAssertTrue(PrepTonight.itemsForTomorrow(noPrep).isEmpty)

        let emptyPrep = DayMeals(lunch: meal("Poha", steps: []))
        XCTAssertTrue(PrepTonight.itemsForTomorrow(emptyPrep).isEmpty)
    }

    func testDisabledCoursesAreSkipped() {
        let day = DayMeals(lunch: meal(
            "Rajma", steps: [PrepStep(text: "Soak", leadTimeMinutes: 480, category: .soak)]
        ))
        XCTAssertTrue(PrepTonight.itemsForTomorrow(day, enabledTypes: [.breakfast]).isEmpty)
        XCTAssertEqual(PrepTonight.itemsForTomorrow(day, enabledTypes: [.lunch]).count, 1)
    }

    func testItemsAreOrderedMostUrgentFirst() {
        let day = DayMeals(
            breakfast: meal(
                "Upma", steps: [PrepStep(text: "Soak", leadTimeMinutes: 120, category: .soak)]
            ),
            lunch: meal(
                "Idli", steps: [PrepStep(text: "Ferment", leadTimeMinutes: 1440, category: .ferment)]
            )
        )
        XCTAssertEqual(PrepTonight.itemsForTomorrow(day).map(\.startByMinutes), [-660, 360])
    }

    func testEveryQualifyingStepOfADishIsListed() {
        let day = DayMeals(lunch: meal("Biryani", steps: [
            PrepStep(text: "Soak rice", leadTimeMinutes: 480, category: .soak),
            PrepStep(text: "Marinate meat", leadTimeMinutes: 720, category: .marinate),
            PrepStep(text: "Chop onions", leadTimeMinutes: 30, category: .chop),
        ]))
        let items = PrepTonight.itemsForTomorrow(day)
        XCTAssertEqual(items.count, 2, "The 30-minute chop is a same-day job")
        XCTAssertEqual(items.map(\.step.category), [.marinate, .soak])
    }

    // MARK: - Lead-time wording

    func testLeadTimeWordingMatchesTheOtherClients() {
        XCTAssertEqual(formatLeadTime(0), "Just before cooking")
        XCTAssertEqual(formatLeadTime(-10), "Just before cooking")
        XCTAssertEqual(formatLeadTime(30), "30 min ahead")
        XCTAssertEqual(formatLeadTime(59), "59 min ahead")
        XCTAssertEqual(formatLeadTime(60), "1 hour ahead")
        XCTAssertEqual(formatLeadTime(90), "2 hours ahead", "Rounds to the nearest hour")
        XCTAssertEqual(formatLeadTime(480), "8 hours ahead")
        XCTAssertEqual(formatLeadTime(1440), "1 day ahead")
        XCTAssertEqual(formatLeadTime(2880), "2 days ahead")
    }

    func testNominalMealTimesCoverEveryCourse() {
        for type in MealType.allCases {
            XCTAssertNotNil(PrepTonight.nominalMealTimes[type], "\(type.key) has no nominal time")
        }
        XCTAssertEqual(PrepTonight.nominalMealTimes[.breakfast], 8 * 60)
        XCTAssertEqual(PrepTonight.nominalMealTimes[.dinner], 20 * 60)
        XCTAssertEqual(PrepTonight.morningCutoffMinutes, 7 * 60)
    }
}
