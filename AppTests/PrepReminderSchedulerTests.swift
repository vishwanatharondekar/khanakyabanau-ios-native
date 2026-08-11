import KhanaKit
import UserNotifications
import XCTest
@testable import KhanaKyaBanau

/// Records what the scheduler asks for, so none of this touches the system
/// notification centre — which in a test host means a permission alert with nobody
/// there to tap it, and a run that hangs rather than fails.
@MainActor
final class FakeNotificationCenter: NotificationScheduling {
    var status: UNAuthorizationStatus = .authorized
    private(set) var requests: [UNNotificationRequest] = []

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func pendingIdentifiers() async -> [String] { requests.map(\.identifier) }
    func schedule(_ request: UNNotificationRequest) async { requests.append(request) }

    func removePending(identifiers: [String]) {
        requests.removeAll { identifiers.contains($0.identifier) }
    }

    /// Seed something the scheduler did not create.
    func seed(identifier: String) {
        requests.append(
            UNNotificationRequest(
                identifier: identifier,
                content: UNMutableNotificationContent(),
                trigger: nil
            )
        )
    }
}

/// The wiring between `PrepReminderPlanner` and `UNUserNotificationCenter`.
///
/// The scheduling *rules* are covered exactly in `PrepReminderPlannerTests`, which
/// runs under `swift test`; what is left to prove here is that the right requests
/// reach the centre, and that rescheduling converges rather than piles up.
@MainActor
final class PrepReminderSchedulerTests: XCTestCase {

    private let today = PlanDate(iso: "2026-08-09")!    // a Sunday

    private func soak(_ dish: String, minutes: Int = 480) -> Meal {
        Meal(
            name: dish,
            prep: MealPrep(
                steps: [PrepStep(text: "Soak \(dish.lowercased())",
                                 leadTimeMinutes: minutes, category: .soak)],
                maxLeadTimeMinutes: minutes
            ),
            prepFor: dish
        )
    }

    /// A week of 2026-08-10 with one soaked dish on the Tuesday.
    private func weekWithOnePrepDay() -> [MealPlan] {
        var plan = MealPlan.empty(weekStartDate: "2026-08-10")
        plan.meals["tuesday"] = DayMeals(lunch: soak("Rajma"))
        return [plan]
    }

    private func makeScheduler(
        center: FakeNotificationCenter,
        reminders: PrepReminderSettings = PrepReminderSettings(enabled: true, hour: 21),
        plans: [MealPlan]
    ) -> PrepReminderScheduler {
        PrepReminderScheduler(
            center: center,
            preferences: { (reminders, MealType.allCases) },
            plansForWeeks: { _ in plans }
        )
    }

    func testSchedulesTheEveningBeforeAtTheChosenHour() async throws {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, plans: weekWithOnePrepDay())

        await scheduler.reschedule(now: today, currentHour: 9)

        XCTAssertEqual(center.requests.count, 1)
        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(request.identifier, "kkb.prep.2026-08-11")
        XCTAssertEqual(request.content.title, "Prep tonight for tomorrow")
        XCTAssertEqual(request.content.body, "Rajma: Soak rajma")

        let trigger = request.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.year, 2026)
        XCTAssertEqual(trigger?.dateComponents.month, 8)
        XCTAssertEqual(trigger?.dateComponents.day, 10, "Must fire the evening before")
        XCTAssertEqual(trigger?.dateComponents.hour, 21)
        XCTAssertEqual(trigger?.dateComponents.minute, 0)
        XCTAssertEqual(trigger?.repeats, false)
    }

    /// A tap has to reach Tomorrow whether the notification came from the server or
    /// from this phone, so the payload is the same shape either way.
    func testPayloadMirrorsTheServerPush() async {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, plans: weekWithOnePrepDay())

        await scheduler.reschedule(now: today, currentHour: 9)

        let info = center.requests.first?.content.userInfo
        XCTAssertEqual(info?["type"] as? String, "prep_reminder")
        XCTAssertEqual(info?["targetDate"] as? String, "2026-08-11")
        XCTAssertEqual(info?["lines"] as? [String], ["Soak rajma — Rajma"])
    }

    /// It runs on every foreground, so it has to replace rather than accumulate.
    func testReschedulingReplacesRatherThanAccumulates() async {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, plans: weekWithOnePrepDay())

        await scheduler.reschedule(now: today, currentHour: 9)
        let first = center.requests.map(\.identifier)
        await scheduler.reschedule(now: today, currentHour: 9)
        let second = center.requests.map(\.identifier)

        XCTAssertEqual(first, second, "Rescheduling duplicated reminders")
        XCTAssertEqual(second.count, 1)
    }

    func testCancelAllClearsOurReminders() async {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, plans: weekWithOnePrepDay())

        await scheduler.reschedule(now: today, currentHour: 9)
        XCTAssertFalse(center.requests.isEmpty)

        await scheduler.cancelAll()
        XCTAssertTrue(center.requests.isEmpty)
    }

    /// Sign-out cancels; it must not take somebody else's notification with it.
    func testCancelLeavesForeignRequestsAlone() async {
        let center = FakeNotificationCenter()
        center.seed(identifier: "someone.elses.reminder")
        let scheduler = makeScheduler(center: center, plans: weekWithOnePrepDay())

        await scheduler.reschedule(now: today, currentHour: 9)
        await scheduler.cancelAll()

        XCTAssertEqual(center.requests.map(\.identifier), ["someone.elses.reminder"])
    }

    func testNothingIsScheduledWhenRemindersAreOff() async {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(
            center: center,
            reminders: PrepReminderSettings(
                enabled: false, hour: 21, afternoonEnabled: false, afternoonHour: 11
            ),
            plans: weekWithOnePrepDay()
        )

        await scheduler.reschedule(now: today, currentHour: 9)
        XCTAssertTrue(center.requests.isEmpty)
    }

    /// Without permission nothing would ever be delivered, so nothing is queued —
    /// and the pending list doesn't quietly imply reminders that cannot arrive.
    func testNothingIsScheduledWithoutPermission() async {
        let center = FakeNotificationCenter()
        center.status = .denied
        let scheduler = makeScheduler(center: center, plans: weekWithOnePrepDay())

        await scheduler.reschedule(now: today, currentHour: 9)
        XCTAssertTrue(center.requests.isEmpty)
    }

    /// Permission not yet asked for is not permission — the opt-in prompt handles it.
    func testNothingIsScheduledWhilePermissionIsUndetermined() async {
        let center = FakeNotificationCenter()
        center.status = .notDetermined
        let scheduler = makeScheduler(center: center, plans: weekWithOnePrepDay())

        await scheduler.reschedule(now: today, currentHour: 9)
        XCTAssertTrue(center.requests.isEmpty)
    }

    // MARK: - The debug trigger

    /// The test button has to send the *real* next reminder, or it proves nothing
    /// about the copy that will actually arrive.
    func testTestReminderSendsTheRealNextReminder() async throws {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, plans: weekWithOnePrepDay())

        let outcome = await scheduler.scheduleTestReminder(in: 5)

        let request = try XCTUnwrap(center.requests.first)
        XCTAssertEqual(request.content.body, "Rajma: Soak rajma")
        XCTAssertEqual(request.content.userInfo["type"] as? String, "prep_reminder")
        XCTAssertEqual((request.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 5)
        XCTAssertTrue(outcome.contains("2026-08-11"), "Say which reminder was sent: \(outcome)")
    }

    /// A `reschedule()` on the next foreground must not cancel a test in flight.
    func testTestReminderSurvivesARescheduleSweep() async {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, plans: weekWithOnePrepDay())

        _ = await scheduler.scheduleTestReminder(in: 5)
        await scheduler.reschedule(now: today, currentHour: 9)

        XCTAssertTrue(
            center.requests.contains { $0.identifier == "kkb.debug.prep-test" },
            "Rescheduling swept away the pending test reminder"
        )
    }

    /// With an empty week there is still a delivery path worth testing — but it has
    /// to announce itself as a sample rather than imply prep that isn't planned.
    func testTestReminderFallsBackToALabelledSample() async throws {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(center: center, plans: [])

        let outcome = await scheduler.scheduleTestReminder(in: 5)

        let request = try XCTUnwrap(center.requests.first)
        XCTAssertTrue(request.content.body.hasPrefix("Sample:"), request.content.body)
        XCTAssertTrue(outcome.lowercased().contains("sample"), outcome)
    }

    func testTestReminderRefusesWithoutPermission() async {
        let center = FakeNotificationCenter()
        center.status = .denied
        let scheduler = makeScheduler(center: center, plans: weekWithOnePrepDay())

        let outcome = await scheduler.scheduleTestReminder(in: 5)

        XCTAssertTrue(center.requests.isEmpty)
        XCTAssertTrue(outcome.contains("Allow notifications"), outcome)
    }

    /// Provisional authorization delivers quietly, which is still delivery.
    func testProvisionalAuthorizationStillSchedules() async {
        let center = FakeNotificationCenter()
        center.status = .provisional
        let scheduler = makeScheduler(center: center, plans: weekWithOnePrepDay())

        await scheduler.reschedule(now: today, currentHour: 9)
        XCTAssertEqual(center.requests.count, 1)
    }

    // MARK: - Afternoon reminders

    /// A week of 2026-08-10 with an 8-hour dinner soak every day.
    ///
    /// 8 h before a 20:00 dinner is a 12:00 start: inside the afternoon band and
    /// outside the evening one, so the two reminders can be told apart by content.
    private func weekWithAfternoonPrep() -> [MealPlan] {
        var plan = MealPlan.empty(weekStartDate: "2026-08-10")
        for (day, _) in WeekDates.daysOfWeek(from: PlanDate(iso: "2026-08-10")!) {
            plan.meals[day.key] = DayMeals(dinner: soak("Chole"))
        }
        return [plan]
    }

    func testAfternoonRemindersAreScheduledUnderTheirOwnPrefix() async {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(
            center: center,
            reminders: PrepReminderSettings(
                enabled: true, hour: 21, afternoonEnabled: true, afternoonHour: 11
            ),
            plans: weekWithAfternoonPrep()
        )

        await scheduler.reschedule(now: today, currentHour: 9)

        let identifiers = center.requests.map(\.identifier)
        XCTAssertTrue(
            identifiers.contains { $0.hasPrefix("kkb.prep.pm.") },
            "Expected an afternoon request, got \(identifiers)"
        )
        // cancelAll only sweeps the shared prefix, so every request must carry it.
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix("kkb.prep.") })
    }

    /// The two reminders are gated independently — this is the regression an early
    /// `guard reminders.enabled` in reschedule() would cause.
    func testAfternoonRemindersSurviveTheEveningOneBeingOff() async {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(
            center: center,
            reminders: PrepReminderSettings(
                enabled: false, hour: 21, afternoonEnabled: true, afternoonHour: 11
            ),
            plans: weekWithAfternoonPrep()
        )

        await scheduler.reschedule(now: today, currentHour: 9)

        let identifiers = center.requests.map(\.identifier)
        XCTAssertFalse(identifiers.isEmpty, "The afternoon reminder is independent")
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix("kkb.prep.pm.") })
    }

    func testAfternoonReminderFiresOnTheTargetDayAtTheChosenHour() async throws {
        let center = FakeNotificationCenter()
        let scheduler = makeScheduler(
            center: center,
            reminders: PrepReminderSettings(
                enabled: false, hour: 21, afternoonEnabled: true, afternoonHour: 11
            ),
            plans: weekWithAfternoonPrep()
        )

        await scheduler.reschedule(now: today, currentHour: 9)

        let request = try XCTUnwrap(
            center.requests.first { $0.identifier == "kkb.prep.pm.2026-08-10" }
        )
        XCTAssertEqual(request.content.title, "Prep this afternoon")
        XCTAssertEqual(request.content.body, "Chole: Soak chole")
        XCTAssertEqual(request.content.userInfo["slot"] as? String, "afternoon")

        let trigger = request.trigger as? UNCalendarNotificationTrigger
        // The distinguishing assertion: the target day itself, not the day before.
        XCTAssertEqual(trigger?.dateComponents.day, 10)
        XCTAssertEqual(trigger?.dateComponents.hour, 11)
    }
}
