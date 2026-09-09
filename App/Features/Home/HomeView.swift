import KhanaKit
import SwiftUI
import UIKit

/// Where the app can be. Three, and only three.
///
/// Shopping is deliberately not here: it is a view of a week, and a fourth tab
/// would have to answer "shopping for which week?" — which it could only do by
/// carrying a second week selector that would drift out of sync with the first.
enum AppTab: String, Hashable {
    case today, plan, me
}

/// The signed-in shell: three destinations on a tab bar, and the drill-downs.
///
/// Android has no navigation graph — Tomorrow and Meal Detail are full-screen
/// early-returns over local state. Here they become a `NavigationStack` path, which
/// preserves the same priority (detail sits above tomorrow) while giving iOS users
/// the swipe-back gesture they expect. Both hide the tab bar on push, so they stay
/// drill-downs rather than becoming peers of the three destinations.
struct HomeView: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session

    @State private var tab: AppTab = .today
    @State private var path: [AppRoute] = []
    @State private var activeSettings: SettingsScreen?
    @State private var showingGuestUpgrade = false
    @State private var showingAccount = false
    @State private var videoContext: RecipeVideoContext?

    // Android's view models are Activity-scoped, so switching tabs or opening a
    // meal never refetches. These are owned here for the same reason: created
    // inside `WeekView`/`TodayView` they would be torn down on every tab switch.
    @State private var weekModel: WeekViewModel?
    @State private var todayModel: TodayViewModel?

    var body: some View {
        TabView(selection: tabBinding) {
            todayTab
                .tabItem { Label("Today", systemImage: "fork.knife") }
                .tag(AppTab.today)

            planTab
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppTab.plan)

            MeView(
                onSelectSettings: { activeSettings = $0 },
                onCreateAccount: { showingGuestUpgrade = true },
                onSignIn: {
                    // Flag first, then sign out: the state flip is what swaps the
                    // root view, and it must find the flag already set.
                    session.wantsSignIn = true
                    Task { await session.signOut() }
                },
                onOpenAccount: { showingAccount = true }
            )
            .tabItem { Label("Me", systemImage: "person") }
            .tag(AppTab.me)
        }
        .tint(Kkb.terracotta600)
        .sheet(item: $activeSettings) { screen in
            SettingsSheet(screen: screen) { activeSettings = nil }
        }
        .sheet(isPresented: $showingGuestUpgrade) {
            GuestUpgradeView { activeSettings = nil }
        }
        .sheet(isPresented: $showingAccount) {
            AccountSheet()
        }
        .sheet(item: $videoContext) { context in
            RecipeVideoSheet(context: context) { videoContext = nil }
        }
        .task {
            if weekModel == nil {
                let created = WeekViewModel(env: env)
                created.cuisinePreferences = session.user?.cuisinePreferences ?? []
                weekModel = created
            }
            if todayModel == nil { todayModel = TodayViewModel(env: env) }
            // A notification tapped before this view existed sets the destination
            // during launch, so `onChange` never sees a transition. Consume any
            // value already waiting.
            consumePendingDestination()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await env.push.refreshAuthorizationStatus()
                // Local reminders only extend as far as the last time the app ran,
                // so every foreground is a chance to top them up. The reminder time
                // is re-read first: it can have been changed on the web or on
                // Android since this session started, and a warm foreground would
                // otherwise keep relaying the old hour until the app is relaunched.
                await env.settings.loadPrepReminders()
                await env.prepReminders.reschedule()
            }
        }
        .onChange(of: env.push.pendingDestination) { _, _ in
            consumePendingDestination()
        }
    }

    /// Switching destination is tracked here rather than in `MainNav`, so the
    /// event fires once per real change and never on a redraw.
    private var tabBinding: Binding<AppTab> {
        Binding(
            get: { tab },
            set: { newValue in
                guard newValue != tab else { return }
                env.analytics.track(
                    AnalyticsEvents.Navigation.modeSwitch,
                    category: AnalyticsEvents.Category.navigation,
                    parameters: [
                        AnalyticsProperties.fromMode: tab.rawValue,
                        AnalyticsProperties.toMode: newValue.rawValue,
                    ]
                )
                tab = newValue
            }
        )
    }

    /// Today owns the only push stack: Tomorrow and Meal Detail are drill-downs
    /// from it. Plan opens sheets rather than pushing, so it needs none.
    @ViewBuilder
    private var todayTab: some View {
        NavigationStack(path: $path) {
            Group {
                if let todayModel {
                    TodayView(
                        model: todayModel,
                        onOpenTomorrow: { path.append(.tomorrow) },
                        onOpenMeal: { day, type in
                            path.append(.mealDetail(day: day, type: type))
                        },
                        onOpenVideo: { videoContext = $0 }
                    )
                }
            }
            // The NavigationStack paints an opaque `systemBackground` over
            // `AppRootView`'s ground — pure black in dark mode. The shell has to
            // draw the page ground itself, inside the stack.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .kkbPageGround()
            .navigationDestination(for: AppRoute.self) { route in
                // `todayModel` is created in this view's `.task`, which runs before
                // any of these routes can be reached.
                if let todayModel {
                    switch route {
                    case .today:
                        // Never actually pushed: `consumePendingDestination` clears
                        // `path` for `.today` instead of appending it, since Today is
                        // this stack's root. Kept only so this switch stays
                        // exhaustive as `AppRoute` gains cases.
                        EmptyView()
                    case .tomorrow:
                        TomorrowView(
                            model: todayModel,
                            onOpenMeal: { day, type in
                                path.append(.mealDetail(day: day, type: type))
                            },
                            onOpenVideo: { videoContext = $0 }
                        )
                        // A drill-down covers the bar rather than sitting beside
                        // the three destinations.
                        .toolbar(.hidden, for: .tabBar)
                    case let .mealDetail(day, type):
                        MealDetailView(
                            model: todayModel,
                            day: day,
                            mealType: type,
                            onOpenVideo: { videoContext = $0 },
                            onNavigate: { newDay, newType in
                                // Replace rather than push, so prev/next within a
                                // day doesn't grow an unbounded back stack.
                                path.removeLast()
                                path.append(.mealDetail(day: newDay, type: newType))
                            }
                        )
                        .toolbar(.hidden, for: .tabBar)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var planTab: some View {
        Group {
            if let weekModel {
                WeekView(
                    model: weekModel,
                    onOpenVideo: { videoContext = $0 },
                    onRequestAccount: { showingGuestUpgrade = true }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .kkbPageGround()
    }

    /// A prep-reminder tap asks for Tomorrow, or for Today when it came from the
    /// midday reminder. Consumed once so a redraw doesn't re-navigate, and so a
    /// stale value can never wedge later notifications.
    private func consumePendingDestination() {
        guard let destination = env.push.pendingDestination else { return }
        // Today is this stack's root rather than a pushed route, so it is reached
        // by clearing the path — pushing `.today` would stack a duplicate screen
        // over the one already showing.
        path = destination == .today ? [] : [destination]
        // The destination persists across foregrounds, so a user last parked on
        // Plan would otherwise land on the root with no prep card visible.
        if destination == .today {
            tab = .today
        }
        env.push.pendingDestination = nil
    }
}
