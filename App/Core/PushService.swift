import FirebaseCore
import FirebaseMessaging
import Foundation
import KhanaKit
import UIKit
import UserNotifications

/// Prep reminders: FCM registration, the permission prompt, and keeping the
/// server's reminder slot in step with the device's time zone.
///
/// The server sends **data-only** messages with an `apns` payload (see the
/// accompanying backend change); this class registers the device so it can receive
/// them and surfaces a tap as a request to open Tomorrow.
@MainActor
@Observable
final class PushService: NSObject {
    /// Set when a notification tap should take the user to Tomorrow. `AppRoot`
    /// consumes it once so a re-render doesn't re-navigate.
    var pendingDestination: AppRoute?

    private let api: APIClient
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private var fcmToken: String?

    /// Firebase is only wired up when a real `GoogleService-Info.plist` is present.
    /// The repository ships a placeholder so the project builds before the iOS app
    /// is registered in the Firebase console; configuring with it would crash.
    private(set) var isConfigured = false

    init(api: APIClient) {
        self.api = api
        super.init()
        // Set here, not in `configure()`: iOS requires the notification delegate to
        // be in place before application launch finishes, or a tap that cold-starts
        // the app is delivered to nobody. This needs no Firebase, so it is safe
        // even when push is unconfigured.
        UNUserNotificationCenter.current().delegate = self
    }

    func configure() {
        guard !isConfigured else { return }
        guard let options = FirebaseOptions(
            contentsOfFile: Bundle.main.path(
                forResource: "GoogleService-Info", ofType: "plist"
            ) ?? ""
        ), Self.looksReal(options) else {
            #if DEBUG
            print("[push] GoogleService-Info.plist is a placeholder — push disabled.")
            #endif
            return
        }
        FirebaseApp.configure(options: options)
        Messaging.messaging().delegate = self
        isConfigured = true
        Task {
            await refreshAuthorizationStatus()
            // APNs registration is per-launch, not once-ever: without this the app
            // only ever has a live token in the session where permission was first
            // granted.
            if areNotificationsEnabled {
                UIApplication.shared.registerForRemoteNotifications()
                await registerIfAuthorized()
            }
        }
    }

    /// A placeholder plist has our sentinel values; a real one has a Google API key
    /// and an iOS app id. Binding through `String?` so this compiles regardless of
    /// how the Firebase SDK declares `apiKey`'s optionality.
    private static func looksReal(_ options: FirebaseOptions) -> Bool {
        let apiKey: String? = options.apiKey
        let appID: String? = options.googleAppID
        let senderID: String? = options.gcmSenderID
        guard let apiKey, !apiKey.isEmpty, !apiKey.hasPrefix("REPLACE_ME") else { return false }
        guard let appID, appID.contains(":ios:") else { return false }
        return !(senderID ?? "").isEmpty
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    var areNotificationsEnabled: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }

    /// Asks for permission. Deliberately never called at cold start — Android asks
    /// contextually, from the Tomorrow card's "Turn on" nudge and the prep-reminder
    /// settings sheet, and iOS gives you exactly one chance at this prompt.
    ///
    /// Not gated on Firebase: permission is what *local* prep reminders need, and
    /// those work with no entitlement and no push configuration at all. Only the
    /// remote-registration half below depends on Firebase.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        if granted, isConfigured {
            UIApplication.shared.registerForRemoteNotifications()
            await registerIfAuthorized()
        }
        return granted
    }

    /// Registers this device against the signed-in account.
    ///
    /// Called on every launch so `notifySlotUtc` self-corrects when the user travels
    /// or the clocks change — the server derives its 30-minute UTC slot from the
    /// time zone we send here.
    func registerIfAuthorized() async {
        guard isConfigured, areNotificationsEnabled else { return }
        // Not `??`: its right-hand side is a non-async autoclosure, so the token
        // fetch has to be its own statement.
        var resolved = fcmToken
        if resolved == nil { resolved = try? await Messaging.messaging().token() }
        guard let token = resolved else { return }
        fcmToken = token
        _ = try? await api.send(Endpoints.registerDevice(RegisterDeviceRequest(
            token: token,
            platform: "ios",
            timezone: TimeZone.current.identifier
        )))
    }

    /// Must run *before* the session token is cleared — the endpoint is authenticated.
    func unregisterDevice() async {
        guard isConfigured, let token = fcmToken else { return }
        _ = try? await api.send(
            Endpoints.unregisterDevice(UnregisterDeviceRequest(token: token))
        )
        fcmToken = nil
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension PushService: MessagingDelegate {
    nonisolated func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken token: String?
    ) {
        Task { @MainActor in
            guard let token else { return }
            self.fcmToken = token
            await self.registerIfAuthorized()
        }
    }
}

extension PushService: UNUserNotificationCenterDelegate {
    /// Prep reminders are worth showing even with the app open — the user is
    /// usually in the planner when the evening nudge lands.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard info["type"] as? String == "prep_reminder" else { return }
        await MainActor.run { self.pendingDestination = .tomorrow }
    }
}
