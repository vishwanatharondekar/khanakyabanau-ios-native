import SwiftUI

/// Two views of one week.
///
/// Shopping is a child of the week rather than a top-level destination, because
/// a top-level Shopping tab would have to answer "shopping for which week?" and
/// could only do it by carrying a second week selector that would drift out of
/// sync with the first.
///
/// Deliberately underlined rather than a segmented pill. The week selector
/// above is a pill, and the two do different jobs — one picks the scope, the
/// other picks the view of it. Matching shapes said they were the same kind of
/// control, and stacking two rounded containers made the header read as
/// decoration.
///
/// Set in the title register rather than the body one. At bodyMedium these read
/// as two words of content that happened to be tappable; a tab title has to
/// out-weigh the list beneath it to be read as navigation at all.
struct WeekSubTabs: View {
    var active: WeekPane
    var onSelect: (WeekPane) -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(.meals, "Meals")
            tab(.shopping, "Shopping")
        }
    }

    private func tab(_ pane: WeekPane, _ title: String) -> some View {
        let isActive = pane == active
        return Button { onSelect(pane) } label: {
            VStack(spacing: 10) {
                Text(title)
                    .kkbFont(.titleMedium)
                    .fontWeight(isActive ? .bold : .medium)
                    .foregroundStyle(isActive ? Kkb.accentText : Kkb.textSecondary)
                    .frame(maxWidth: .infinity)
                Rectangle()
                    .fill(isActive ? Kkb.terracotta600 : Kkb.hairline)
                    // Thicker under the selected tab: with two labels this close
                    // in weight, the rule is what settles which one you are on.
                    .frame(height: isActive ? 3 : 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
