import KhanaKit
import SwiftUI

/// The dietary controls, shared between onboarding's third step and the Dietary
/// Preferences sheet. Android duplicates the layout in both places; sharing it here
/// guarantees the two can't drift.
struct DietaryControls: View {
    @Binding var preferences: DietaryPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            KkbToggleRow(
                title: "I am vegetarian",
                subtitle: "We'll keep meat and fish off the plan",
                isOn: $preferences.isVegetarian
            )

            if !preferences.isVegetarian {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Non-veg days".eyebrow)
                        .kkbFont(.sectionLabel)
                        .foregroundStyle(Kkb.accentText)
                    Text("Days when non-vegetarian dishes are welcome.")
                        .kkbFont(.bodySmall)
                        .foregroundStyle(Kkb.textSecondary)

                    FlowLayout(spacing: 8) {
                        ForEach(DayOfWeek.allCases) { day in
                            let isOn = preferences.nonVegDays.contains(day.key)
                            KkbChip(title: String(day.displayName.prefix(3)), isSelected: isOn) {
                                if isOn {
                                    preferences.nonVegDays.removeAll { $0 == day.key }
                                } else {
                                    preferences.nonVegDays.append(day.key)
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().overlay(Kkb.hairline)

            VStack(alignment: .leading, spacing: 12) {
                Text("Calorie tracking".eyebrow)
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(Kkb.accentText)

                KkbToggleRow(
                    title: "Show calorie count",
                    subtitle: "The AI plans within your daily target",
                    isOn: $preferences.showCalories
                )

                if preferences.showCalories {
                    CalorieStepper(target: $preferences.dailyCalorieTarget)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Divider().overlay(Kkb.hairline)

            VStack(alignment: .leading, spacing: 12) {
                Text("Preferences & restrictions".eyebrow)
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(Kkb.accentText)

                KkbToggleRow(
                    title: "Prefer healthy meals",
                    subtitle: "Leans towards high-protein, lighter dishes",
                    isOn: $preferences.preferHealthy
                )
                KkbToggleRow(title: "Gluten free", isOn: $preferences.glutenFree)
                KkbToggleRow(title: "Nuts free", isOn: $preferences.nutsFree)
                KkbToggleRow(title: "Lactose intolerant", isOn: $preferences.lactoseIntolerant)
            }
        }
        .animation(.snappy(duration: 0.2), value: preferences.isVegetarian)
        .animation(.snappy(duration: 0.2), value: preferences.showCalories)
    }
}

/// ±100 kcal, clamped to 500–5000, matching Android's `CalorieStepper`.
struct CalorieStepper: View {
    @Binding var target: Int

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily calorie target")
                    .kkbFont(.bodyMedium)
                    .foregroundStyle(Kkb.textPrimary)
                Text("Range: \(DietaryPreferences.calorieRange.lowerBound) – \(DietaryPreferences.calorieRange.upperBound) kcal")
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary)
            }
            Spacer()
            HStack(spacing: 10) {
                stepButton(systemImage: "minus", enabled: target > DietaryPreferences.calorieRange.lowerBound) {
                    target = max(DietaryPreferences.calorieRange.lowerBound,
                                 target - DietaryPreferences.calorieStep)
                }
                Text("\(target)")
                    .kkbFont(.displaySmall)
                    .foregroundStyle(Kkb.textPrimary)
                    .frame(minWidth: 56)
                    .monospacedDigit()
                stepButton(systemImage: "plus", enabled: target < DietaryPreferences.calorieRange.upperBound) {
                    target = min(DietaryPreferences.calorieRange.upperBound,
                                 target + DietaryPreferences.calorieStep)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Daily calorie target")
        .accessibilityValue("\(target) kilocalories")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                target = min(DietaryPreferences.calorieRange.upperBound,
                             target + DietaryPreferences.calorieStep)
            case .decrement:
                target = max(DietaryPreferences.calorieRange.lowerBound,
                             target - DietaryPreferences.calorieStep)
            @unknown default: break
            }
        }
    }

    private func stepButton(
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Kkb.accentText)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Kkb.terracottaSurface))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityHidden(true)
    }
}

struct KkbToggleRow: View {
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .kkbFont(.bodyLarge)
                    .foregroundStyle(Kkb.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .kkbFont(.bodySmall)
                        .foregroundStyle(Kkb.textSecondary)
                }
            }
        }
        .tint(Kkb.terracotta500)
        // Without this the toggle's label becomes "title, subtitle" run together.
        // The subtitle is explanatory, so it belongs in the hint.
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
    }
}

struct KkbChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .kkbFont(.labelLarge)
                .foregroundStyle(isSelected ? Kkb.cream50 : Kkb.ink700)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? Kkb.terracotta500 : Kkb.cream100))
                .overlay(
                    Capsule().stroke(
                        isSelected ? Kkb.terracotta500 : Kkb.hairline, lineWidth: 1
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Wrapping row layout for chips. `Layout` rather than a `LazyVGrid` because the
/// chips are intrinsically sized and a fixed column count looks wrong for them.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
