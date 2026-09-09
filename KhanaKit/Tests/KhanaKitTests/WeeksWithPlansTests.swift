import XCTest
@testable import KhanaKit

final class WeeksWithPlansTests: XCTestCase {

    private func decode(_ json: String) throws -> WeeksWithPlansResponse {
        try JSONDecoder().decode(WeeksWithPlansResponse.self, from: Data(json.utf8))
    }

    func testReadsTheWeekStartDates() throws {
        let decoded = try decode(#"{"weekStartDates":["2026-09-07","2026-09-21"]}"#)
        XCTAssertEqual(decoded.weekStartDates, ["2026-09-07", "2026-09-21"])
    }

    func testAUserWithNoPlansDecodesToAnEmptyListNotAThrow() throws {
        XCTAssertEqual(try decode(#"{"weekStartDates":[]}"#).weekStartDates, [])
        // Defensive: an older deployment that omits the key entirely.
        XCTAssertEqual(try decode("{}").weekStartDates, [])
    }

    func testTheEndpointAsksTheRightQuestion() {
        let forward = Endpoints.weeksWithPlans(from: "2026-09-07")
        XCTAssertEqual(forward.path, "api/meals/weeks")
        XCTAssertEqual(forward.query.first(where: { $0.name == "from" })?.value, "2026-09-07")
        XCTAssertNil(forward.query.first(where: { $0.name == "direction" }))

        let back = Endpoints.weeksWithPlans(from: "2026-09-07", direction: "back")
        XCTAssertEqual(back.query.first(where: { $0.name == "direction" })?.value, "back")
    }
}
