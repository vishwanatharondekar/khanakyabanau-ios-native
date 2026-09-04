import XCTest
@testable import KhanaKit

/// The writer only rebuilds when the week that changed is one the widget is
/// actually showing. Without this every background week fetch — history, the
/// week the user is browsing three weeks out — would rewrite the snapshot and
/// spend a widget reload on data nobody can see.
final class WidgetWindowTests: XCTestCase {

    /// Friday.
    private let today = PlanDate(year: 2026, month: 9, day: 4)

    func testThisWeekIsCovered() {
        XCTAssertTrue(WidgetWindow.covers(weekStartDate: "2026-08-31", today: today))
    }

    /// Only because tomorrow is Saturday, still inside it — see the Sunday case.
    func testNextWeekIsNotCoveredMidWeek() {
        XCTAssertFalse(WidgetWindow.covers(weekStartDate: "2026-09-07", today: today))
    }

    func testLastWeekIsNotCovered() {
        XCTAssertFalse(WidgetWindow.covers(weekStartDate: "2026-08-24", today: today))
    }

    /// On a Sunday tomorrow is Monday, which belongs to next week's document — so
    /// next week genuinely is on screen and a change to it must rebuild.
    func testOnSundayNextWeekIsCovered() {
        let sunday = PlanDate(year: 2026, month: 9, day: 6)
        XCTAssertTrue(WidgetWindow.covers(weekStartDate: "2026-09-07", today: sunday))
        XCTAssertTrue(WidgetWindow.covers(weekStartDate: "2026-08-31", today: sunday))
    }

    func testGarbageIsNotCovered() {
        XCTAssertFalse(WidgetWindow.covers(weekStartDate: "not-a-date", today: today))
        XCTAssertFalse(WidgetWindow.covers(weekStartDate: "", today: today))
    }
}
