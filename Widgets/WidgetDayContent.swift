import KhanaKit
import SwiftUI
import WidgetKit

/// One dated group of rows. The evening phase renders two — tonight, then
/// tomorrow — which is the whole reason the widget merged into one kind.
struct WidgetSection: Identifiable {
    let eyebrow: String
    let day: WidgetDay
    let meals: [WidgetMeal]

    var id: String { "\(eyebrow)-\(day.date)" }
}

struct WidgetDayContent: View {
    let entry: WidgetDayEntry
    let family: WidgetFamily

    /// The body as one or two dated sections.
    ///
    /// Day phase is today alone. Evening is tonight's *remaining* meals followed
    /// by tomorrow — `WidgetPhase.upcoming` does the clock work so this view does
    /// none.
    private var sections: [WidgetSection] {
        guard let today = entry.today else { return [] }

        switch entry.phase {
        case .day:
            return [WidgetSection(eyebrow: "TODAY", day: today, meals: today.meals)]

        case .evening:
            let stillAhead = WidgetPhase.upcoming(
                today.meals.map(\.type), at: entry.date, calendar: .current
            )
            let tonight = today.meals.filter { stillAhead.contains($0.type) }

            var out: [WidgetSection] = []
            if !tonight.isEmpty {
                out.append(WidgetSection(eyebrow: "TONIGHT", day: today, meals: tonight))
            }
            if let tomorrow = entry.tomorrow, tomorrow.hasAnyMeal {
                out.append(WidgetSection(eyebrow: "TOMORROW", day: tomorrow, meals: tomorrow.meals))
            }
            // Everything today is behind us and tomorrow is empty: fall back to
            // today rather than rendering nothing at all.
            return out.isEmpty
                ? [WidgetSection(eyebrow: "TODAY", day: today, meals: today.meals)]
                : out
        }
    }

    /// Small shows the next meal still to come; medium three rows, or four with
    /// no banner to make room for; large everything. The budget spans sections,
    /// so an evening small widget shows dinner and then, once dinner has passed,
    /// tomorrow's breakfast — crossing midnight without any phase logic.
    private var budget: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return banner == nil ? 4 : 3
        default: return 99
        }
    }

    /// The one clock-aware thing on the widget, and deliberately not per-section:
    /// at 19:00 the step that matters usually belongs to tomorrow's breakfast, so
    /// scoping it to the day on screen would hide the only urgent fact there is.
    private var banner: PrepDue? {
        guard family != .systemSmall else { return nil }
        guard let today = entry.today else { return nil }

        return PrepNow.due(
            today: today.meals,
            tomorrow: entry.tomorrow?.meals ?? [],
            now: entry.date,
            calendar: .current
        ).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            if let banner {
                PrepBanner(due: banner)
            }

            ForEach(allocated) { section in
                WidgetHeader(eyebrow: section.eyebrow, dayLabel: section.day.day.displayName)
                ForEach(section.meals, id: \.type) { meal in
                    WidgetMealRow(
                        meal: meal,
                        day: section.day,
                        container: entry.container,
                        compact: family == .systemSmall
                    )
                }
            }
            if family != .systemSmall { Spacer(minLength: 0) }
        }
        .widgetURL(WidgetDeepLink.url(target: entry.phase == .evening ? "tomorrow" : "today"))
    }

    /// Trim to the family's budget, keeping section order and dropping whole
    /// sections that end up empty.
    private var allocated: [WidgetSection] {
        var remaining = budget
        var out: [WidgetSection] = []

        for section in sections where remaining > 0 {
            let take = Array(section.meals.prefix(remaining))
            guard !take.isEmpty else { continue }
            remaining -= take.count
            out.append(WidgetSection(eyebrow: section.eyebrow, day: section.day, meals: take))
        }
        return out
    }
}

struct WidgetHeader: View {
    let eyebrow: String
    let dayLabel: String

    var body: some View {
        HStack(spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(KkbWidget.terracotta600)
            Text(dayLabel)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(KkbWidget.ink600)
        }
    }
}

/// What has to be started now, or soon.
struct PrepBanner: View {
    let due: PrepDue

    private var whenText: String {
        guard !due.isOverdue else { return "Start now" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: due.startAt)
    }

    var body: some View {
        Text("⏳ \(whenText) · \(due.item.step.text)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(KkbWidget.ink900)
            .lineLimit(2)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(due.isOverdue ? KkbWidget.terracotta200 : KkbWidget.marigold100)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct WidgetMealRow: View {
    let meal: WidgetMeal
    let day: WidgetDay
    let container: WidgetContainer?
    let compact: Bool

    /// The dish's own longest-lead step, stated without a clock.
    ///
    /// A row is a fact about the dish, not about the present, so all the time
    /// arithmetic stays in `PrepBanner`. Wording comes from `formatLeadTime`, the
    /// same helper the app's PrepAheadBadge uses, so the widget and the app never
    /// disagree in front of the user.
    private var prepLine: String? {
        guard let prep = meal.prep,
              let step = prep.steps.max(by: { $0.leadTimeMinutes < $1.leadTimeMinutes })
        else { return nil }
        let extra = prep.steps.count - 1
        return "\(step.category.emoji) \(step.text) · \(formatLeadTime(step.leadTimeMinutes))"
            + (extra > 0 ? " +\(extra)" : "")
    }

    private var thumbnail: Image? {
        guard let key = meal.thumbnailKey, let container,
              let data = WidgetSnapshotStore.thumbnailData(key: key, in: container),
              let image = UIImage(data: data)
        else { return nil }
        return Image(uiImage: image)
    }

    var body: some View {
        Link(destination: WidgetDeepLink.url(day: day.day, mealType: meal.type)) {
            HStack(spacing: 8) {
                thumbnailView
                VStack(alignment: .leading, spacing: 1) {
                    Text(meal.type.displayName.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(KkbWidget.terracotta600)
                    Text(meal.name)
                        .font(.system(size: compact ? 13 : 12, weight: .medium))
                        .foregroundStyle(KkbWidget.ink900)
                        .lineLimit(2)
                    if !compact, let prepLine {
                        Text(prepLine)
                            .font(.system(size: 9))
                            .foregroundStyle(KkbWidget.ink600)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        let side: CGFloat = compact ? 34 : 30
        if let thumbnail {
            thumbnail
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            // Same fallback as Android: the meal-type emoji on a cream tile,
            // used when the dish has no photo or the download failed.
            RoundedRectangle(cornerRadius: 7)
                .fill(KkbWidget.cream100)
                .frame(width: side, height: side)
                .overlay(Text(meal.type.emoji).font(.system(size: side * 0.5)))
        }
    }
}
