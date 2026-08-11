import KhanaKit
import SwiftUI
import UIKit

/// The signed-in shell: brand header, the two-tab switch, and the drill-downs.
///
/// Android has no navigation graph — Tomorrow and Meal Detail are full-screen
/// early-returns over local state. Here they become a `NavigationStack` path, which
/// preserves the same priority (detail sits above tomorrow) while giving iOS users
/// the swipe-back gesture they expect.
struct HomeView: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session

    @State private var tab = 0
    @State private var path: [AppRoute] = []
    @State private var showingDrawer = false
    @State private var activeSettings: SettingsScreen?
    @State private var showingGuestUpgrade = false
    @State private var videoContext: RecipeVideoContext?
    @Namespace private var segmentNamespace

    // Android's view models are Activity-scoped, so switching tabs or opening a
    // meal never refetches. These are owned here for the same reason: created
    // inside `WeekView`/`TodayView` they would be torn down on every tab switch.
    @State private var weekModel: WeekViewModel?
    @State private var todayModel: TodayViewModel?

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 14) {
                header

                SegmentedTabs(
                    options: [
                        .init("Today's Menu", systemImage: "fork.knife"),
                        .init("The Week", systemImage: "calendar"),
                    ],
                    selection: Binding(
                        get: { tab },
                        set: { newValue in
                            guard newValue != tab else { return }
                            env.analytics.track(
                                AnalyticsEvents.Navigation.modeSwitch,
                                category: AnalyticsEvents.Category.navigation,
                                parameters: [
                                    AnalyticsProperties.fromMode: tab == 0 ? "today" : "week",
                                    AnalyticsProperties.toMode: newValue == 0 ? "today" : "week",
                                ]
                            )
                            tab = newValue
                        }
                    ),
                    namespace: segmentNamespace
                )
                .padding(.horizontal, 16)

                if tab == 0 {
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
                } else if let weekModel {
                    WeekView(
                        model: weekModel,
                        onOpenVideo: { videoContext = $0 },
                        onRequestAccount: { showingGuestUpgrade = true }
                    )
                }
                Spacer(minLength: 0)
            }
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
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingDrawer) {
            AppDrawer(
                onSelectSettings: { screen in
                    showingDrawer = false
                    activeSettings = screen
                },
                onCreateAccount: {
                    showingDrawer = false
                    showingGuestUpgrade = true
                },
                onSignIn: {
                    showingDrawer = false
                    // Flag first, then sign out: the state flip is what swaps the
                    // root view, and it must find the flag already set.
                    session.wantsSignIn = true
                    Task { await session.signOut() }
                },
                onSignOut: {
                    showingDrawer = false
                    Task { await session.signOut() }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $activeSettings) { screen in
            SettingsSheet(screen: screen) { activeSettings = nil }
        }
        .sheet(isPresented: $showingGuestUpgrade) {
            GuestUpgradeView { activeSettings = nil }
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

    /// A prep-reminder tap asks for Tomorrow, or for Today when it came from the
    /// midday reminder. Consumed once so a redraw doesn't re-navigate, and so a
    /// stale value can never wedge later notifications.
    private func consumePendingDestination() {
        guard let destination = env.push.pendingDestination else { return }
        // Today is this stack's root rather than a pushed route, so it is reached
        // by clearing the path — pushing `.today` would stack a duplicate screen
        // over the one already showing.
        path = destination == .today ? [] : [destination]
        env.push.pendingDestination = nil
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text("khana kya banau")
                    .kkbFont(.displayMedium)
                    .foregroundStyle(Kkb.textPrimary)
                Text("WEEKLY MEAL PLANNER")
                    .kkbFont(.sectionLabel)
                    .tracking(4)
                    .foregroundStyle(Kkb.accentText)
            }

            HStack {
                Button { showingDrawer = true } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Kkb.ink700)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Menu")
                Spacer()
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 4)
    }
}
