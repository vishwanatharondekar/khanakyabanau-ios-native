import BackgroundTasks
import Foundation

/// Keeps the widget's snapshot current while the app is not running.
///
/// The day rollover does not need this: the snapshot carries a week ahead and the
/// extension picks each entry's day by date. What only a fetch can catch is the
/// plan changing somewhere else — edited on the web, or regenerated on another
/// device — which the widget would otherwise not show until the app is next opened.
///
/// iOS decides when an app refresh actually runs, weighted by how often the app
/// is used; `earliestBeginDate` is a floor, not a schedule. An hour is the floor
/// because nothing on the widget changes faster than a person editing a plan,
/// and asking more often does not make iOS grant more runs.
enum WidgetRefresh {

    /// Must match `BGTaskSchedulerPermittedIdentifiers` in `App/Info.plist`.
    static let taskIdentifier = "in.khanakyabanau.app.widget-refresh"

    static let interval: TimeInterval = 60 * 60

    /// Ask for the next run. Submitting again replaces the pending request, so
    /// calling this on every trip to the background is safe.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        // Fails in the simulator and when Background App Refresh is off. Either
        // way the widget still rolls over by date; it just misses remote edits.
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func run(_ env: AppEnvironment) async {
        // Chain the next run first, so a rebuild that iOS cuts short still leaves
        // one queued.
        schedule()

        // Never let a background run be the thing that signs the widget out. The
        // writer publishes a signed-out snapshot when it sees no token, which is
        // right after a real sign-out in the foreground and wrong for a keychain
        // that is merely unreadable in the background.
        guard TokenStore.currentToken()?.isEmpty == false else { return }
        await env.widgetSnapshots.rebuild()
    }
}
