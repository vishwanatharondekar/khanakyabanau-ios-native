import KhanaKit
import SwiftUI

/// One day: its name as a heading, then a card per meal beneath it.
///
/// The day used to be a single card with the meals as rows inside it. Pulling the
/// heading out and giving each meal its own card is what lets a dish name run the
/// full width of the screen — the width a day card spent on its own chrome was
/// width the name could not use.
struct WeekDaySection: View {
    var day: DayOfWeek
    var date: PlanDate
    var meals: DayMeals
    var enabledTypes: [MealType]
    var isToday: Bool
    var isTomorrow: Bool
    var isResolvingImages: Bool
    /// False for a week that has already happened, a day already gone, or a
    /// read-only brand.
    var canEdit: Bool = true
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

    /// On Today and Tomorrow the weekday is no longer the title, so it joins the
    /// date here rather than being lost.
    private var trailing: String {
        let parts = [
            isToday || isTomorrow ? day.displayName : nil,
            "\(date.day) \(date.shortMonthName)",
        ]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    /// With the heading outside a card there is nothing else carrying "this is
    /// today" down the list, so the tint moves onto the day's meal cards.
    private var bodyTint: Color {
        if isToday { return Kkb.marigoldSurface.opacity(0.45) }
        if isTomorrow { return Kkb.marigoldSurface.opacity(0.20) }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .kkbFont(.displayMedium)
                    .foregroundStyle(Kkb.textPrimary)
                    .modifier(ConditionalHighlight(isOn: isToday || isTomorrow))
                Text(trailing)
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(Kkb.textSecondary)
                Spacer(minLength: 0)
            }

            ForEach(enabledTypes) { type in
                MealRow(
                    day: day,
                    type: type,
                    meal: meals[type],
                    isResolvingImages: isResolvingImages,
                    canEdit: canEdit,
                    videoURL: videoURL(meals[type]),
                    onTap: { onTapRow(type) },
                    onEdit: { onEdit(type) },
                    onSwap: { onSwap(type) },
                    onVideo: { onVideo(type) }
                )
                // 14, not the 4 the card wrapper alone would give: MealRow has no
                // vertical padding of its own — it used to take its breathing room
                // from the day card's .padding(14). Matches Android, where the
                // meal row contributes 10 of its own on top of the card's 4.
                .padding(.vertical, 14)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Kkb.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(bodyTint)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Kkb.hairline, lineWidth: 1)
                )
                .shadow(color: Kkb.ink800.opacity(0.08), radius: 10, x: 0, y: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    var canEdit: Bool = true
    var videoURL: String?
    var onTap: () -> Void
    var onEdit: () -> Void
    var onSwap: () -> Void
    var onVideo: () -> Void

    var body: some View {
        if meal.isEmpty {
            emptySlot
        } else {
            filledRow
        }
    }

    /// A slot with nothing in it.
    ///
    /// Centred, and without the thumbnail or the trailing plus the filled row
    /// carries. A 110pt placeholder image for a dish that does not exist was the
    /// loudest thing on a blank week, and nothing can be centred horizontally
    /// while it sits alongside. What is left is one target saying what it does.
    ///
    /// Held at the thumbnail's height so filling a slot does not make the day
    /// jump.
    private var emptySlot: some View {
        Button(action: { if canEdit { onTap() } }) {
            VStack(spacing: 8) {
                if canEdit {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Kkb.accentText.opacity(0.7))
                }
                // Names the course rather than the mechanism: this line is the
                // one anyone actually reads, so it says which meal it will
                // fill.
                //
                // Sans rather than the handwritten face the other empty states
                // use — those whisper that something is absent, and this is an
                // instruction. Regular weight and 0.8 ink: 4.74:1 against the
                // card, which is recessive while staying above the 4.5:1 floor
                // for text this size. Colour cannot go further without dropping
                // under it, so the weight carries the rest.
                //
                // On a day already gone there is nothing to add — a dash says
                // empty without asking for anything.
                Text(canEdit ? "Add \(type.displayName)" : "—")
                    .kkbFont(.bodyLarge)
                    .foregroundStyle(Kkb.textSecondary.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            canEdit
                ? "Add a \(type.displayName.lowercased()) for \(day.displayName)"
                : "\(type.displayName) on \(day.displayName), empty"
        )
    }

    private var filledRow: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                // Top, not centre: a two- or three-line dish name should grow
                // downwards from the thumbnail's top edge rather than push the
                // eyebrow up away from it.
                HStack(alignment: .top, spacing: 12) {
                    MealThumbnail(
                        imageUrl: meal.imageUrl,
                        size: 110,
                        cornerRadius: 18,
                        isResolving: isResolvingImages && meal.imageUrl == nil,
                        emoji: type.emoji
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(type.displayName.eyebrow)
                            .kkbFont(.sectionLabel)
                            .foregroundStyle(type.chipText)

                        Text(meal.name)
                            .kkbFont(.displaySmall)
                            .foregroundStyle(Kkb.textPrimary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
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
        .accessibilityLabel("\(type.displayName) on \(day.displayName), \(meal.name)")
    }

    /// The filled row's controls. The empty state has its own single target,
    /// so there is no empty arm here.
    private var controls: some View {
        VStack(spacing: 8) {
            circleButton(
                systemImage: "play.rectangle",
                tint: videoURL != nil ? Kkb.sageText : Kkb.textSecondary,
                fill: videoURL != nil ? Kkb.sageSurface : Kkb.surfaceSunken,
                border: videoURL != nil ? Kkb.sage300 : Kkb.hairline,
                label: videoURL != nil ? "Watch recipe video" : "Add a recipe video",
                action: onVideo
            )
            // Watching how something was cooked is not editing it, so the
            // video control above stays; these two go.
            if canEdit {
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
