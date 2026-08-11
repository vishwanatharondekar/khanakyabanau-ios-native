import XCTest
@testable import KhanaKit

/// The afternoon toggle inherits from the evening one when the server omits it.
///
/// An older server sends no afternoon field; defaulting it to `true` would show
/// the reminder as on when nothing will ever schedule it.
final class NotificationPreferencesDTOTests: XCTestCase {

    private func settings(from json: String) throws -> PrepReminderSettings {
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(NotificationPreferencesResponse.self, from: data)
        return response.settings
    }

    func testAbsentAfternoonFlagInheritsTruePrepReminders() throws {
        let s = try settings(from: #"{"notificationPreferences":{"prepReminders":true,"hourLocal":21}}"#)
        XCTAssertTrue(s.enabled)
        XCTAssertTrue(s.afternoonEnabled)
    }

    func testAbsentAfternoonFlagInheritsFalsePrepReminders() throws {
        let s = try settings(from: #"{"notificationPreferences":{"prepReminders":false,"hourLocal":21}}"#)
        XCTAssertFalse(s.enabled)
        XCTAssertFalse(s.afternoonEnabled)
    }

    func testExplicitAfternoonFlagWins() throws {
        let s = try settings(from: #"""
        {"notificationPreferences":{"prepReminders":false,"hourLocal":21,"afternoonPrepReminders":true,"afternoonHourLocal":12}}
        """#)
        XCTAssertFalse(s.enabled)
        XCTAssertTrue(s.afternoonEnabled)
        XCTAssertEqual(s.afternoonHour, 12)
    }

    func testAfternoonHourDefaultsToEleven() throws {
        let s = try settings(from: #"{"notificationPreferences":{"prepReminders":true,"hourLocal":21}}"#)
        XCTAssertEqual(s.afternoonHour, 11)
        XCTAssertEqual(PrepReminderSettings.afternoonDefaultHour, 11)
    }
}
