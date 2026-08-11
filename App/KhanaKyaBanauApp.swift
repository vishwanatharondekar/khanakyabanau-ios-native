import KhanaKit
import SwiftUI

/// Sub-screens reachable from Home. There is no route table beyond this: the
/// product has one root switch (session state) and two drill-downs.
enum AppRoute: Hashable {
    case today
    case tomorrow
    case mealDetail(day: DayOfWeek, type: MealType)
}

@main
@MainActor
struct KhanaKyaBanauApp: App {
    @State private var env: AppEnvironment
    @State private var session: SessionStore

    init() {
        let environment = AppEnvironment()
        _env = State(initialValue: environment)
        _session = State(initialValue: SessionStore(env: environment))
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(\.app, env)
                .environment(session)
                // Both existing clients are light-only. iOS keeps a dark variant,
                // but the palette is defined so brand hues never invert.
                .tint(Kkb.accent)
        }
    }
}
