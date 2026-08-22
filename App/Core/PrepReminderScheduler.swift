import Foundation
import KhanaKit
import UserNotifications

/// The slice of `UNUserNotificationCenter` the scheduler actually uses.
///
/// Exists so tests can drive the scheduler without touching the system centre —
/// which in a test host means a permission alert that nothing is there to tap.
@MainActor
protocol NotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus
    func pendingIdentifiers() async -> [String]
    func schedule(_ request: UNNotificationRequest) async
    func removePending(identifiers: [String])
}

extension UNUserNotificationCenter: NotificationScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    func pendingIdentifiers() async -> [String] {
        await pendingNotificationRequests().map(\.identifier)
    }

    func schedule(_ request: UNNotificationRequest) async {
        try? await add(request)
    }

    func removePending(identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Schedules prep reminders **locally**, on the phone.
///
/// The server's version is a push: the `prep-reminders` cron works out what needs
/// soaking tonight and sends it via FCM. That path needs an APNs token, which needs
/// the `aps-environment` entitlement, which a free Apple Developer account cannot
/// provision — so on a personally-signed build there is no push at all.
///
/// This feature does not actually need the server, though. `PrepTonight` already
/// computes the whole thing on-device from the meal plan — that logic was ported so
/// the Tomorrow card could show the user what they were about to be reminded of.
/// Given the plan and the user's chosen hour, the phone can schedule the same
/// reminder itself, with no entitlement and no Firebase.
///
/// The trade-off, and it is a real one: a local notification can only be scheduled
/// from data the app has already fetched. Reminders are laid down for the next
/// `PrepReminderPlanner.horizonDays` days each time the app runs, so
///   - opening the app at least once a week keeps them flowing;
///   - a plan edited on the web or on Android is not reflected until this phone
///     next opens the app.
/// The server push has neither limitation, which is why it stays the primary path
/// when a paid membership and a real Firebase config are present.
///
/// What to schedule is decided by `PrepReminderPlanner`; this only does the wiring.
@MainActor
final class PrepReminderScheduler {
    /// Prefix for our requests, so rescheduling only ever clears our own.
    static let identifierPrefix = "kkb.prep."
    /// Afternoon requests. Still under `identifierPrefix`, so `cancelAll` sweeps
    /// both without knowing about this one.
    static let afternoonIdentifierPrefix = identifierPrefix + "pm."

    private let center: any NotificationScheduling
    /// Read afresh on every reschedule, so a settings change needs no re-wiring.
    private let preferences: () -> (reminders: PrepReminderSettings, enabledTypes: [MealType])
    /// The weeks to consider, keyed by `yyyy-MM-dd` Monday. A closure so tests can
    /// supply plans without a network round trip.
    private let plansForWeeks: ([String]) async -> [MealPlan]

    init(
        meals: MealRepository,
        settings: SettingsRepository,
        center: any NotificationScheduling = UNUserNotificationCenter.current()
    ) {
        self.center = center
        self.preferences = { (settings.prepReminders, settings.enabledTypes) }
        self.plansForWeeks = { keys in
            var plans: [MealPlan] = []
            for key in keys {
                if let plan = try? await meals.week(key) { plans.append(plan) }
            }
            return plans
        }
    }

    /// Seam for tests: no repositories, no network, no system notification centre.
    init(
        center: any NotificationScheduling,
        preferences: @escaping () -> (reminders: PrepReminderSettings, enabledTypes: [MealType]),
        plansForWeeks: @escaping ([String]) async -> [MealPlan]
    ) {
        self.center = center
        self.preferences = preferences
        self.plansForWeeks = plansForWeeks
    }

    /// Recomputes and re-lays the whole schedule.
    ///
    /// Safe to call often — it replaces its own pending requests wholesale rather
    /// than adding to them, so plan edits and settings changes converge.
    func reschedule(now: PlanDate = WeekDates.today(), currentHour: Int? = nil) async {
        await cancelAll()

        let (reminders, enabledTypes) = preferences()

        let status = await center.authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let resolvedHour = currentHour ?? Calendar.current.component(.hour, from: Date())

        if reminders.enabled {
            let planned = await plannedReminders(
                now: now,
                hour: reminders.hour,
                currentHour: resolvedHour,
                enabledTypes: enabledTypes
            )
            for reminder in planned {
                await add(reminder, at: reminders.hour, identifierPrefix: Self.identifierPrefix)
            }
        }

        if reminders.afternoonEnabled {
            let plans = await plansForWeeks(
                PrepReminderPlanner.weekKeys(from: now, startOffset: 0)
            )
            let planned = PrepReminderPlanner.afternoonReminders(
                plans: plans,
                from: now,
                hour: reminders.afternoonHour,
                currentHour: resolvedHour,
                enabledTypes: enabledTypes
            )
            for reminder in planned {
                await add(
                    reminder,
                    at: reminders.afternoonHour,
                    identifierPrefix: Self.afternoonIdentifierPrefix
                )
            }
        }
    }

    /// Drops every reminder this class owns. Used on sign-out, and before relaying.
    func cancelAll() async {
        let ours = await center.pendingIdentifiers()
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePending(identifiers: ours)
    }

    // MARK: - Internals

    private func plannedReminders(
        now: PlanDate,
        hour: Int,
        currentHour: Int,
        enabledTypes: [MealType]
    ) async -> [PrepReminder] {
        let plans = await plansForWeeks(PrepReminderPlanner.weekKeys(from: now))
        return PrepReminderPlanner.reminders(
            plans: plans,
            from: now,
            hour: hour,
            currentHour: currentHour,
            enabledTypes: enabledTypes
        )
    }

#if DEBUG
    /// UI tests pass `-KKBSendTestReminder` to have a real reminder delivered a few
    /// seconds after launch, the way `-KKBResetState` clears stored state.
    ///
    /// This replaced a "Send a test reminder now" button in the prep-reminder
    /// settings sheet. The button existed only to drive
    /// `testTappingAPrepReminderOpensTomorrow`, and a debug control sitting in the
    /// app's own settings screen is a worse home for that than a launch argument
    /// no user can reach.
    static var isTestReminderRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-KKBSendTestReminder")
    }

    /// Delivers the next real reminder a few seconds from now.
    ///
    /// The whole point of the feature is that it arrives hours later, which makes it
    /// miserable to check: waiting until 11pm to find out the copy is wrong, or that
    /// a tap doesn't open Tomorrow, is not a workable loop. This fires the *actual*
    /// next reminder — same wording, same payload, same tap handling — so everything
    /// except the clock is exercised.
    ///
    /// Debug builds only. A shipped app has no business faking its own reminders,
    /// and `#if DEBUG` keeps the code out of the Release binary entirely.
    ///
    /// Carries its own identifier so a `reschedule()` on the next foreground cannot
    /// quietly cancel the test before it lands.
    ///
    /// - Returns: what was scheduled, or why it wasn't, to show back to whoever
    ///   pressed the button.
    func scheduleTestReminder(in seconds: TimeInterval = 8) async -> String {
        let status = await center.authorizationStatus()
        guard status == .authorized || status == .provisional else {
            return "Allow notifications first — nothing can be delivered yet."
        }

        let (reminders, enabledTypes) = preferences()
        // `currentHour: 0` so tonight's reminder is still offered after its hour has
        // gone by. What is being tested here is delivery, not the schedule.
        let planned = await plannedReminders(
            now: WeekDates.today(), hour: reminders.hour, currentHour: 0,
            enabledTypes: enabledTypes
        )

        let content = UNMutableNotificationContent()
        content.sound = .default
        let outcome: String

        if let next = planned.first {
            content.title = next.title
            content.body = next.body
            content.userInfo = [
                "type": "prep_reminder",
                "targetDate": next.targetDate.isoString,
                "lines": next.lines,
            ]
            outcome = "Sending the \(next.targetDate.isoString) reminder in \(Int(seconds))s."
        } else {
            // Stopping at "nothing to send" would leave delivery itself untested, so
            // send something — but label it, or it reads as a plan that isn't there.
            content.title = "Prep tonight for tomorrow"
            content.body = "Sample: Rajma: Soak rajma"
            content.userInfo = [
                "type": "prep_reminder",
                "targetDate": WeekDates.today().adding(days: 1).isoString,
                "lines": ["Soak rajma — Rajma"],
            ]
            outcome = "No prep in the next 7 days — sending a sample in \(Int(seconds))s."
        }

        await center.schedule(
            UNNotificationRequest(
                identifier: "kkb.debug.prep-test",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            )
        )
        return outcome
    }
#endif

    private func add(
        _ reminder: PrepReminder,
        at hour: Int,
        identifierPrefix: String
    ) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        // Mirrors the server's data-only payload so a tap is handled identically.
        content.userInfo = [
            "type": "prep_reminder",
            "slot": identifierPrefix == Self.afternoonIdentifierPrefix ? "afternoon" : "evening",
            "targetDate": reminder.targetDate.isoString,
            "lines": reminder.lines,
        ]

        var components = DateComponents()
        components.year = reminder.fireDate.year
        components.month = reminder.fireDate.month
        components.day = reminder.fireDate.day
        components.hour = hour
        components.minute = 0

        let request = UNNotificationRequest(
            identifier: identifierPrefix + reminder.targetDate.isoString,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        await center.schedule(request)
    }
}
