import KhanaKit
import SwiftUI

/// Shown only while looking at a week that has already happened.
///
/// It has to say three things at once, because a past week otherwise looks
/// exactly like the current one and someone will try to edit it: that this is
/// history, that it cannot be changed, and how to get out.
///
/// The backwards step lives here rather than in the week header on purpose. A
/// permanent pager is what the header replaced; this one exists only once you
/// have already chosen to look back, and it disappears at the oldest week with
/// a plan rather than walking into empty years.
struct PastWeekBar: View {
    var weekStartDate: String
    var hasEarlierWeek: Bool
    var onEarlier: () -> Void
    var onThisWeek: () -> Void

    private var dateLabel: String {
        guard let date = PlanDate(iso: weekStartDate) else { return weekStartDate }
        return "\(date.day) \(date.shortMonthName) \(date.year)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Kkb.marigold700)

            VStack(alignment: .leading, spacing: 1) {
                Text(dateLabel)
                    .kkbFont(.bodyMedium)
                    .fontWeight(.semibold)
                    .foregroundStyle(Kkb.textPrimary)
                Text("Already happened · view only")
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary)
            }

            Spacer(minLength: 6)

            if hasEarlierWeek {
                pill("Earlier", systemImage: "chevron.left", isFilled: false, action: onEarlier)
            }
            pill("This week", systemImage: "arrow.left", isFilled: true, action: onThisWeek)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Kkb.marigold100)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Kkb.marigold300, lineWidth: 1)
                )
        )
    }

    private func pill(
        _ title: String,
        systemImage: String,
        isFilled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
                Text(title).kkbFont(.labelSmall).fontWeight(.semibold)
            }
            .foregroundStyle(isFilled ? Kkb.cream50 : Kkb.ink700)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isFilled ? Kkb.marigold600 : Kkb.cream50)
                    .overlay(Capsule().stroke(Kkb.marigold300, lineWidth: 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
