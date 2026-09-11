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
/// Set in the product's label register: upper case, wide tracking. Weight alone
/// did not carry it — a step from medium to bold between two short words is a
/// difference of degree, and the eye reads it as the same text slightly darker.
/// Upper case changes the shape of the words, which is a difference of kind, and
/// the wide tracking is this product's own signature for a label that is not
/// content.
///
/// Smaller than the body text it sits above, not larger. Capitals already read
/// bigger than their point size, and a tab does not need to win on size once it
/// has stopped looking like a sentence.
struct WeekSubTabs: View {
    var active: WeekPane
    var onSelect: (WeekPane) -> Void

    /// sectionLabel is the eyebrow style at 11pt/3 tracking. Sized up and
    /// tracked in a little, it becomes a tab without inventing a second label
    /// voice for the product. Built as a KkbTextStyle rather than a raw
    /// `.system` font so it still scales with Dynamic Type.
    private static let tabStyle = KkbTextStyle(
        size: 13, weight: .semibold, tracking: 1.5, relativeTo: .subheadline
    )

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
                Text(title.uppercased())
                    .kkbFont(Self.tabStyle)
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
