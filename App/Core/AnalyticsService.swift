import Foundation
import KhanaKit
import Mixpanel

/// Mixpanel, matching Android's `MixpanelAnalytics`.
///
/// There is no server-side event ingest — the backend's only analytics endpoint is
/// the email tracking pixel — so the client talks to Mixpanel directly, exactly as
/// the other two clients do.
@MainActor
final class AnalyticsService {
    /// Distinguishes this client in every event. Android sends `"android-app"`,
    /// the web app `"web"`.
    private static let devicePlatform = "ios-app"

    private var mixpanel: MixpanelInstance?
    private let isEnabled: Bool

    init() {
        let token = AppConfiguration.mixpanelToken
        isEnabled = AppConfiguration.analyticsEnabled && !token.isEmpty
        guard isEnabled else {
            mixpanel = nil
            return
        }
        Mixpanel.initialize(token: token, trackAutomaticEvents: false)
        mixpanel = Mixpanel.mainInstance()
        registerSuperProperties()
    }

    private func registerSuperProperties() {
        mixpanel?.registerSuperProperties([AnalyticsProperties.device: Self.devicePlatform])
    }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else {
            #if DEBUG
            print("[analytics] \(event.name) \(event.parameters)")
            #endif
            return
        }
        var properties: Properties = ["category": event.category]
        if let label = event.label { properties["label"] = label }
        if let value = event.value { properties["value"] = value }
        for (key, raw) in event.parameters {
            properties[key] = Self.mixpanelValue(raw)
        }
        mixpanel?.track(event: event.name, properties: properties)
    }

    /// Convenience for the common `action + category + params` shape.
    func track(
        _ action: String,
        category: String,
        label: String? = nil,
        parameters: [String: Any] = [:]
    ) {
        track(AnalyticsEvent(
            action: action, category: category, label: label, parameters: parameters
        ))
    }

    func trackScreen(_ path: String, title: String) {
        guard isEnabled else { return }
        mixpanel?.track(event: "Page View", properties: [
            "page_path": path,
            "page_title": title,
        ])
    }

    func trackError(_ name: String, message: String) {
        track(AnalyticsEvent(
            action: "error", category: "error", label: name,
            parameters: ["error_message": message]
        ))
    }

    func identify(_ user: User) {
        guard isEnabled else { return }
        mixpanel?.identify(distinctId: user.id)
        var properties: Properties = [
            AnalyticsProperties.userID: user.id,
            "user_type": user.onboardingCompleted ? "returning" : "new",
            AnalyticsProperties.isGuest: user.isGuest,
        ]
        if let email = user.email { properties["email"] = email }
        if !user.name.isEmpty { properties["name"] = user.name }
        if let dietary = user.dietaryPreferences {
            properties["dietary_preference"] = dietary.analyticsValue
        }
        mixpanel?.people.set(properties: properties)
    }

    /// Called once per real sign-out. Super properties are re-registered because
    /// `reset` clears them.
    func reset() {
        guard isEnabled else { return }
        mixpanel?.reset()
        registerSuperProperties()
    }

    /// Analytics parameters are `[String: Any]` at the call sites (they mirror
    /// Android's map), so each value is narrowed to something Mixpanel accepts.
    /// Anything unexpected is stringified rather than dropped — a slightly odd
    /// property beats a silently missing one when debugging a funnel.
    private static func mixpanelValue(_ raw: Any) -> MixpanelType {
        if let value = raw as? String { return value }
        if let value = raw as? Bool { return value }
        if let value = raw as? Int { return value }
        if let value = raw as? Double { return value }
        if let value = raw as? [String] { return value }
        return String(describing: raw)
    }
}

/// Build-time configuration. Values arrive through the Info.plist so a release
/// build can inject a real token without touching source.
enum AppConfiguration {
    static var mixpanelToken: String {
        (Bundle.main.object(forInfoDictionaryKey: "MixpanelToken") as? String) ?? ""
    }

    static var analyticsEnabled: Bool {
        // Default off when no token is configured, so debug builds don't pollute
        // production funnels.
        guard !mixpanelToken.isEmpty else { return false }
        // Build settings substitute into Info.plist as strings, never as booleans.
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "AnalyticsEnabled") else {
            return true
        }
        if let flag = raw as? Bool { return flag }
        if let text = raw as? String {
            return ["yes", "true", "1"].contains(text.lowercased())
        }
        return true
    }
}
