import KhanaKit
import SwiftUI

/// Today with nothing on it.
///
/// The app opens here whether or not today has meals, so this is a designed
/// state rather than something to route around: an empty Today that explains
/// itself and offers the one thing worth doing beats a planner opened to a grid
/// of empty cells.
///
/// The title and the CTA come from the brand's labels, so a product whose users
/// receive their plan can say something else here — and, with a nil CTA, offer
/// nothing to press.
struct EmptyToday: View {
    var onPlanWeek: () -> Void

    private let labels = Brand.current.labels

    var body: some View {
        PaperCard(cornerRadius: 24, padding: 28) {
            VStack(spacing: 6) {
                Text(labels.emptyTodayTitle)
                    .kkbFont(.displaySmall)
                    .foregroundStyle(Kkb.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Plan the week and today fills itself in.")
                    .kkbFont(.bodyMedium)
                    .foregroundStyle(Kkb.textSecondary)
                    .multilineTextAlignment(.center)

                if let cta = labels.emptyTodayCTA {
                    KkbPrimaryButton(title: cta, action: onPlanWeek)
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
