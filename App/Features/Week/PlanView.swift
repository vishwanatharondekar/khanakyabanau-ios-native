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
                // Task 9 puts ShoppingPane here.
                Spacer()
            }
        }
    }
}
