import KhanaKit
import SwiftUI

/// The look-ahead at the bottom of Today: what's on tomorrow's menu, and anything
/// that has to be started tonight.
struct TomorrowCard: View {
    var section: DaySection
    var enabledTypes: [MealType]
    var prepItems: [PrepTonightItem]
    var isResolvingImages: Bool
    var onOpen: () -> Void
    var onOpenMeal: (MealType) -> Void

    private var hasAnyDish: Bool {
        enabledTypes.contains { !section.meals[$0].isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Kkb.sage300, Kkb.sage500],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Kkb.cream50)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("COMING UP")
                            .kkbFont(.sectionLabel)
                            .tracking(5)
                            .foregroundStyle(Kkb.sageText)
                        Text("Tomorrow · \(section.day.displayName)  \(section.date.shortMonthName) \(section.date.day)")
                            .kkbFont(.displaySmall)
                            .foregroundStyle(Kkb.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Kkb.textSecondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens tomorrow's menu")

            Divider().overlay(Kkb.hairline)

            VStack(alignment: .leading, spacing: 12) {
                if !prepItems.isEmpty {
                    PrepTonightBox(items: prepItems, isCompact: true)
                    NotificationOptIn()
                }

                if hasAnyDish {
                    ForEach(enabledTypes) { type in
                        let meal = section.meals[type]
                        if !meal.isEmpty {
                            TomorrowMealRow(
                                type: type,
                                meal: meal,
                                isResolvingImages: isResolvingImages,
                                onTap: { onOpenMeal(type) }
                            )
                            if type != enabledTypes.last {
                                Divider().overlay(Kkb.sageSurface)
                            }
                        }
                    }
                } else {
                    KkbEmptyState(
                        script: "— a blank page awaits —",
                        caption: "No dishes written for tomorrow yet",
                        alignment: .leading
                    )
                    .padding(.vertical, 8)
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Kkb.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Kkb.hairline, lineWidth: 1)
        )
        .shadow(color: Kkb.ink800.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

/// The marigold "PREP TONIGHT" box. Compact on the Today card, full on the
/// Tomorrow screen. Also reused, compact, for this afternoon's prep on Today —
/// `heading` and `timePhrase` default to the evening wording so those two call
/// sites are unaffected.
struct PrepTonightBox: View {
    var items: [PrepTonightItem]
    var isCompact: Bool
    var heading: String = "PREP TONIGHT"
    var timePhrase: String = "tonight"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Kkb.marigoldText)
                Text(heading)
                    .kkbFont(.sectionLabel)
                    .tracking(3)
                    .foregroundStyle(Kkb.marigoldText)
                Spacer()
            }

            if isCompact, items.count > 3 {
                // Too many to list on a summary card; lead with the most urgent.
                Text("\(items.count) thing\(items.count == 1 ? "" : "s") to prep \(timePhrase)")
                    .kkbFont(.bodyMedium)
                    .foregroundStyle(Kkb.textPrimary)
                if let first = items.first {
                    Text("Start with \(first.step.text.lowercasedFirst)")
                        .kkbFont(.bodySmall)
                        .foregroundStyle(Kkb.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                if !isCompact {
                    Text("\(items.count) thing\(items.count == 1 ? "" : "s") to start before you turn in.")
                        .kkbFont(.bodyMedium)
                        .foregroundStyle(Kkb.textSecondary)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    PrepStepRow(item: item)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Kkb.marigoldSurface.opacity(0.7))
        )
    }
}

struct PrepStepRow: View {
    var item: PrepTonightItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(item.step.category.emoji).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.step.text)
                    .kkbFont(.bodyMedium)
                    .foregroundStyle(Kkb.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(item.dish.uppercased()) · \(formatLeadTime(item.step.leadTimeMinutes).uppercased())")
                    .kkbFont(.sectionLabel)
                    .foregroundStyle(Kkb.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The contextual nudge to switch notifications on.
///
/// Never shown when notifications are already allowed, and never at cold start:
/// iOS gives one shot at the system prompt, so it is only asked for at a moment
/// when the value is obvious — right beside tonight's prep list.
struct NotificationOptIn: View {
    @Environment(\.app) private var env
    @State private var isDismissed = false

    var body: some View {
        // Not gated on Firebase: with or without push configured, granting
        // permission is what makes the evening reminder arrive, because the app
        // schedules it locally from the plan it already has.
        if !isDismissed, !env.push.areNotificationsEnabled {
            HStack(spacing: 10) {
                Text("Get reminded this evening?")
                    .kkbFont(.bodyMedium)
                    .foregroundStyle(Kkb.textPrimary)
                Spacer()
                Button("Turn on") {
                    Task {
                        if env.push.authorizationStatus == .denied {
                            env.push.openSystemSettings()
                        } else if await env.push.requestAuthorization() {
                            // Permission is the only thing that was missing; lay
                            // the reminders down straight away.
                            await env.prepReminders.reschedule()
                        }
                    }
                }
                .kkbFont(.labelLarge)
                .foregroundStyle(Kkb.accentText)

                Button {
                    isDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Kkb.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 4)
        }
    }
}

struct TomorrowMealRow: View {
    var type: MealType
    var meal: Meal
    var isResolvingImages: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                MealThumbnail(
                    imageUrl: meal.imageUrl,
                    size: 56,
                    cornerRadius: 14,
                    isResolving: isResolvingImages && meal.imageUrl == nil,
                    emoji: type.emoji
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName.eyebrow)
                        .kkbFont(.sectionLabel)
                        .foregroundStyle(type.chipText)
                    Text(meal.name)
                        .kkbFont(.bodyLarge)
                        .foregroundStyle(Kkb.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Kkb.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.displayName), \(meal.name)")
    }
}

extension String {
    /// "Soak the chana" → "soak the chana", for use mid-sentence.
    var lowercasedFirst: String {
        guard let first else { return self }
        return String(first).lowercased() + dropFirst()
    }
}
