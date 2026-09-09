import KhanaKit
import SwiftUI

/// The one thing worth doing on a week with nothing on it.
///
/// Promoted out of the overflow only in this state. On a week that already has
/// meals, generating replaces work the user did and belongs where the other
/// rare things are.
struct WeekHero: View {
    var brand: Brand
    var generateLabel: String
    var onGenerate: () -> Void

    var body: some View {
        PaperCard(cornerRadius: 24, padding: 24) {
            VStack(spacing: 6) {
                Text(brand.labels.emptyWeekTitle)
                    .kkbFont(.displaySmall)
                    .foregroundStyle(Kkb.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Fill it in one go, or tap a day to add a meal yourself.")
                    .kkbFont(.bodyMedium)
                    .foregroundStyle(Kkb.textSecondary)
                    .multilineTextAlignment(.center)
                KkbPrimaryButton(title: generateLabel, action: onGenerate)
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
