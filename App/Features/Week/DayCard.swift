import KhanaKit
import SwiftUI

/// One day of the week grid. Today and tomorrow get a coloured ribbon and a tinted
/// body so the eye lands on them first.
struct DayCard: View {
    var day: DayOfWeek
    var date: PlanDate
    var meals: DayMeals
    var enabledTypes: [MealType]
    var isToday: Bool
    var isTomorrow: Bool
    var isResolvingImages: Bool
    var showCalories: Bool
    var videoURL: (Meal) -> String?
    var onTapRow: (MealType) -> Void
    var onEdit: (MealType) -> Void
    var onSwap: (MealType) -> Void
    var onVideo: (MealType) -> Void

    private var title: String {
        if isToday { return "Today" }
        if isTomorrow { return "Tomorrow" }
        return day.displayName
    }

    private var bodyTint: Color {
        if isToday { return Kkb.marigoldSurface.opacity(0.45) }
        if isTomorrow { return Kkb.marigoldSurface.opacity(0.20) }
        return .clear
    }

    var body: some View {
        HStack(spacing: 0) {
            if isToday {
                Ribbon(kind: .today).padding(.vertical, 14).padding(.leading, 6)
            } else if isTomorrow {
                Ribbon(kind: .tomorrow).padding(.vertical, 14).padding(.leading, 6)
            } else {
                Color.clear.frame(width: 3).padding(.leading, 6)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .kkbFont(.displayMedium)
                        .foregroundStyle(Kkb.textPrimary)
                        .modifier(ConditionalHighlight(isOn: isToday || isTomorrow))
                    if isToday || isTomorrow {
                        Text("· \(day.displayName)")
                            .kkbFont(.bodyMedium)
                            .foregroundStyle(Kkb.textSecondary)
                    }
                    Spacer()
                    Text("\(date.shortMonthName) \(date.day)")
                        .kkbFont(.sectionLabel)
                        .foregroundStyle(Kkb.textSecondary)
                }

                ForEach(enabledTypes) { type in
                    MealRow(
                        day: day,
                        type: type,
                        meal: meals[type],
                        isResolvingImages: isResolvingImages,
                        showCalories: showCalories,
                        videoURL: videoURL(meals[type]),
                        onTap: { onTapRow(type) },
                        onEdit: { onEdit(type) },
                        onSwap: { onSwap(type) },
                        onVideo: { onVideo(type) }
                    )
                    if type != enabledTypes.last {
                        Divider().overlay(Kkb.hairline.opacity(0.5))
                    }
                }
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Kkb.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous).fill(bodyTint)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Kkb.hairline, lineWidth: 1)
        )
        .shadow(color: Kkb.ink800.opacity(0.08), radius: 10, x: 0, y: 3)
    }
}

private struct ConditionalHighlight: ViewModifier {
    var isOn: Bool
    func body(content: Content) -> some View {
        if isOn { content.editorialHighlight() } else { content }
    }
}

/// One course within a day. An empty slot shows a single add affordance; a filled
/// one shows the video, swap and edit controls.
struct MealRow: View {
    var day: DayOfWeek
    var type: MealType
    var meal: Meal
    var isResolvingImages: Bool
    var showCalories: Bool
    var videoURL: String?
    var onTap: () -> Void
    var onEdit: () -> Void
    var onSwap: () -> Void
    var onVideo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    MealThumbnail(
                        imageUrl: meal.imageUrl,
                        size: 88,
                        cornerRadius: 18,
                        isResolving: isResolvingImages && meal.imageUrl == nil && !meal.isEmpty,
                        emoji: type.emoji
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(type.displayName.eyebrow)
                            .kkbFont(.sectionLabel)
                            .foregroundStyle(type.chipText)

                        if meal.isEmpty {
                            Text("write a dish…")
                                .kkbFont(.handwritten)
                                .foregroundStyle(Kkb.textSecondary.opacity(0.8))
                        } else {
                            Text(meal.name)
                                .kkbFont(.displaySmall)
                                .foregroundStyle(Kkb.textPrimary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }

                        HStack(spacing: 6) {
                            if showCalories, let calories = meal.calories {
                                CalorieBadge(calories: calories)
                            }
                            if let prep = meal.validPrep, prep.maxLeadTimeMinutes > 0 {
                                PrepAheadBadge(leadTimeMinutes: prep.maxLeadTimeMinutes)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            controls
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            meal.isEmpty
                ? "\(type.displayName) on \(day.displayName), empty"
                : "\(type.displayName) on \(day.displayName), \(meal.name)"
        )
    }

    @ViewBuilder
    private var controls: some View {
        if meal.isEmpty {
            Button(action: onTap) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Kkb.accentText)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Kkb.terracottaSurface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a \(type.displayName.lowercased()) for \(day.displayName)")
        } else {
            VStack(spacing: 8) {
                circleButton(
                    systemImage: "play.rectangle",
                    tint: videoURL != nil ? Kkb.sageText : Kkb.textSecondary,
                    fill: videoURL != nil ? Kkb.sageSurface : Kkb.surfaceSunken,
                    border: videoURL != nil ? Kkb.sage300 : Kkb.hairline,
                    label: videoURL != nil ? "Watch recipe video" : "Add a recipe video",
                    action: onVideo
                )
                circleButton(
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: Kkb.textSecondary,
                    fill: Kkb.cream100,
                    border: Kkb.hairline,
                    label: "Switch meal",
                    action: onSwap
                )
                circleButton(
                    systemImage: "pencil",
                    tint: Kkb.textSecondary,
                    fill: Kkb.cream100,
                    border: Kkb.hairline,
                    label: "Edit meal",
                    action: onEdit
                )
            }
        }
    }

    private func circleButton(
        systemImage: String,
        tint: Color,
        fill: Color,
        border: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(fill))
                .overlay(Circle().stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
