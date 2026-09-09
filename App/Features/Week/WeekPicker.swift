import KhanaKit
import SwiftUI

/// The week selector, collapsed to one line.
///
/// A row of chips is the right shape where there is room to show every week at
/// once. On a phone it was a whole row spent on two or three options, stacked
/// above a second row of tabs and a third of buttons. Here the current week is
/// the only thing shown until asked, which is how a phone app shows a scope
/// selector.
///
/// Outlined rather than bare text: this doubles as the screen's title, so it
/// keeps the weight of one — but a bold word with a chevron beside it reads as
/// a heading that happens to have an icon. The border is what makes it a
/// control.
struct WeekPicker: View {
    var chips: [WeekChip]
    var currentWeekStartDate: String
    var offRails: Bool
    var onSelect: (String) -> Void

    @State private var isPickerOpen = false

    private var label: String {
        // An off-rails week — reached from a months-old reminder — has no chip,
        // so name it plainly rather than claiming to be a week the strip knows
        // about.
        if offRails { return "Another week" }
        return chips.first { $0.weekStartDate == currentWeekStartDate }?.label ?? "This week"
    }

    var body: some View {
        Button { isPickerOpen = true } label: {
            HStack(spacing: 4) {
                Text(label)
                    .kkbFont(.displaySmall)
                    .foregroundStyle(Kkb.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Kkb.textSecondary)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Kkb.cream50)
                    .overlay(Capsule().stroke(Kkb.hairline, lineWidth: 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change week, currently \(label)")
        .confirmationDialog("Which week?", isPresented: $isPickerOpen, titleVisibility: .visible) {
            ForEach(chips) { chip in
                Button(chip.weekStartDate == currentWeekStartDate && !offRails
                       ? "\(chip.label) ✓"
                       : chip.label) {
                    onSelect(chip.weekStartDate)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
