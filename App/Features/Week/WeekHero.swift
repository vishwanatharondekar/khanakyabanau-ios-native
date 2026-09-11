import KhanaKit
import SwiftUI

/// The one thing worth doing on a week that is mostly still blank.
///
/// Promoted out of the overflow only in this state. On a week that is largely
/// planned, generating would replace work the user did, so it belongs where the
/// other rare things are.
///
/// Not only on a wholly empty week: that made the hero vanish the moment anyone
/// typed a single dish, leaving six blank days and the one action that helps
/// hidden behind an overflow menu.
struct WeekHero: View {
    var brand: Brand
    var generateLabel: String
    /// True when the week holds nothing at all, rather than merely mostly so.
    var isWhollyEmpty: Bool
    var onGenerate: () -> Void

    var body: some View {
        PaperCard(cornerRadius: 24, padding: 24) {
            VStack(spacing: 6) {
                Text(isWhollyEmpty
                     ? brand.labels.emptyWeekTitle
                     : brand.labels.mostlyEmptyWeekTitle)
                    .kkbFont(.displaySmall)
                    .foregroundStyle(Kkb.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Fill it in one go, or tap a day to pick a meal yourself.")
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
