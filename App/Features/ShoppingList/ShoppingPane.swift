import KhanaKit
import SwiftUI

/// Shopping, as a view of the week rather than a sheet over it.
///
/// Every state renders in place. Nothing here blocks navigation — the tab bar
/// stays live throughout, including during a generation, and a generation the
/// user walks away from still finishes and still writes the server's cache, so
/// coming back finds it.
struct ShoppingPane: View {
    var state: ShoppingPaneState
    var session: ShoppingSession?
    var onRetry: () -> Void
    var onCreateAccount: () -> Void
    var onPlanWeek: () -> Void

    var body: some View {
        switch state {
        // The probe is quick and free; saying "checking" rather than "building"
        // keeps the slow word for the slow path.
        case .probing:
            busy("Checking for a list")
        case .loading:
            busy("Building your shopping list")
        case .ready:
            if let session {
                ShoppingListContent(list: session.list, weekStartDate: session.weekStartDate)
            } else {
                busy("Building your shopping list")
            }
        case let .error(text):
            message(
                title: "Couldn't build the list",
                body: text,
                actionTitle: "Try again",
                action: onRetry
            )
        case .limit:
            message(
                title: "You've used your free lists",
                body: "Create an account for unlimited shopping lists.",
                actionTitle: "Create account",
                action: onCreateAccount
            )
        case .empty:
            message(
                title: "Nothing to shop for yet",
                body: "Plan some meals this week and the list writes itself.",
                actionTitle: "Plan the week",
                action: onPlanWeek
            )
        // Deliberately no action: generating for a week that has already
        // happened would spend an AI call on a shop that is over.
        case .past:
            message(
                title: "No list from that week",
                body: "That week has already happened, so there is nothing left to shop for.",
                actionTitle: nil,
                action: {}
            )
        }
    }

    private func busy(_ text: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Kkb.terracotta500)
                .controlSize(.large)
            Text(text)
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func message(
        title: String,
        body: String,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .kkbFont(.displaySmall)
                .foregroundStyle(Kkb.textPrimary)
                .multilineTextAlignment(.center)
            Text(body)
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle {
                KkbPrimaryButton(title: actionTitle, action: action)
                    .padding(.top, 12)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
