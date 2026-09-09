import KhanaKit
import SwiftUI

/// The Plan destination: one week header, and whichever view of the week is
/// selected below it.
///
/// The header lives here rather than in either pane because Meals and Shopping
/// are siblings under one week. Whichever of them owned the selector, the other
/// would either duplicate it or go without — which is exactly how Shopping
/// first shipped on the webapp with no week selector at all.
struct PlanView: View {
    @Environment(\.app) private var env
    @Environment(SessionStore.self) private var session

    /// Owned by `HomeView` so it survives tab switches, matching Android's
    /// Activity-scoped view models.
    let model: WeekViewModel
    var onOpenVideo: (RecipeVideoContext) -> Void
    var onRequestAccount: () -> Void

    /// Unlike Android, the ceiling is known before anything is spent — so a
    /// guest at their limit is told rather than shown a 403.
    private var isGuestAtLimit: Bool {
        session.isGuest && (session.user?.remainingShoppingLists ?? 1) <= 0
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                WeekPicker(
                    chips: model.chips,
                    currentWeekStartDate: model.weekStartDate,
                    offRails: isOffRails(model.weekStartDate, in: model.chips),
                    onSelect: { week in Task { await model.selectWeek(week) } }
                )
                Spacer()
                // Task 10 puts WeekActions here.
            }
            .padding(.horizontal, 16)

            WeekSubTabs(active: model.pane, onSelect: model.selectPane)
                .padding(.horizontal, 12)

            switch model.pane {
            case .meals:
                WeekView(
                    model: model,
                    onOpenVideo: onOpenVideo,
                    onRequestAccount: onRequestAccount
                )
            case .shopping:
                ShoppingPane(
                    state: model.shoppingState,
                    session: model.shoppingSession,
                    onRetry: { Task { await model.retryShopping() } },
                    onCreateAccount: onRequestAccount,
                    onPlanWeek: { model.selectPane(.meals) }
                )
                // Opening the tab is the request. The probe inside is free, so
                // this cannot charge a guest for walking past.
                .task(id: model.weekStartDate) {
                    await model.openShopping(isGuestAtLimit: isGuestAtLimit)
                }
            }
        }
    }
}
