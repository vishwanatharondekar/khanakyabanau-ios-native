import XCTest
@testable import KhanaKit

/// Round-tripped rather than asserted one way, because the widget builds these
/// URLs and the app parses them — a drift between the two is a tap that opens
/// the wrong screen.
final class WidgetDeepLinkTests: XCTestCase {

    func testTodayRoundTrips() {
        XCTAssertEqual(WidgetDeepLink.parse(WidgetDeepLink.url(target: "today")), .today)
    }

    func testTomorrowRoundTrips() {
        XCTAssertEqual(WidgetDeepLink.parse(WidgetDeepLink.url(target: "tomorrow")), .tomorrow)
    }

    func testAMealRoundTrips() {
        let url = WidgetDeepLink.url(day: .friday, mealType: .dinner)
        XCTAssertEqual(WidgetDeepLink.parse(url), .meal(day: .friday, type: .dinner))
    }

    func testEveryDayAndTypeRoundTrips() {
        for day in DayOfWeek.allCases {
            for type in MealType.allCases {
                let url = WidgetDeepLink.url(day: day, mealType: type)
                XCTAssertEqual(
                    WidgetDeepLink.parse(url), .meal(day: day, type: type),
                    "round trip failed for \(day.key)/\(type.key)"
                )
            }
        }
    }

    func testAForeignSchemeIsRejected() {
        XCTAssertNil(WidgetDeepLink.parse(URL(string: "https://khanakyabanau.in/today")!))
    }

    func testAnUnknownHostIsRejected() {
        XCTAssertNil(WidgetDeepLink.parse(URL(string: "khanakyabanau://elsewhere")!))
    }

    func testAMealLinkMissingPartsIsRejected() {
        XCTAssertNil(WidgetDeepLink.parse(URL(string: "khanakyabanau://meal/friday")!))
        XCTAssertNil(WidgetDeepLink.parse(URL(string: "khanakyabanau://meal/notaday/dinner")!))
        XCTAssertNil(WidgetDeepLink.parse(URL(string: "khanakyabanau://meal/friday/brunch")!))
    }
}
