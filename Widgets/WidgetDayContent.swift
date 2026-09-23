import KhanaKit
import SwiftUI
import WidgetKit

/// One dated group of rows. The evening phase renders two — tonight, then
/// tomorrow — which is the whole reason the widget merged into one kind.
struct WidgetSection: Identifiable {
    let eyebrow: String
    let day: WidgetDay
    let meals: [WidgetMeal]
    /// Beside the eyebrow: the day's name by default, the meal type under UP
    /// NEXT, nothing under LATER TODAY — where the day is the one above.
    var label: String? = nil
    /// The large family's UP NEXT section: one meal, rendered as a card.
    var isFeature = false
    /// Tomorrow shown beneath what is left of today — the section the glance can
    /// stand in for. Not set when tomorrow is all the widget is showing.
    var isLookAhead = false

    var id: String { "\(eyebrow)-\(day.date)" }
    var dayLabel: String { label ?? day.day.displayName }

    func with(meals: [WidgetMeal]) -> WidgetSection {
        WidgetSection(
            eyebrow: eyebrow, day: day, meals: meals,
            label: label, isFeature: isFeature, isLookAhead: isLookAhead
        )
    }
}

struct WidgetDayContent: View {
    let entry: WidgetDayEntry
    let family: WidgetFamily

    /// Today's meals still ahead. Breakfast stops occupying a row at 08:00 and
    /// lunch at 13:00, so by mid-afternoon the widget is about dinner.
    private var remaining: [WidgetMeal] {
        guard let today = entry.today else { return [] }
        let ahead = WidgetPhase.upcoming(
            today.meals.map(\.type), at: entry.date, calendar: .current
        )
        return today.meals.filter { ahead.contains($0.type) }
    }

    /// The body as one or two sections.
    ///
    /// Three shapes, and which one appears is decided by what is left to cook
    /// rather than by the hour alone — see `WidgetPhase.phase`.
    private var phase: WidgetPhase.Phase {
        WidgetPhase.phase(
            remainingToday: remaining.map(\.type), at: entry.date, calendar: .current
        )
    }

    private var sections: [WidgetSection] {
        guard let today = entry.today else { return [] }
        let tomorrow = entry.tomorrow
        let lookAhead = tomorrow.flatMap { day in
            day.hasAnyMeal
                ? WidgetSection(eyebrow: "TOMORROW", day: day, meals: day.meals, isLookAhead: true)
                : nil
        }

        switch phase {
        case .today, .tonight:
            var out = family == .systemLarge
                ? upNextSections(today: today)
                : [WidgetSection(eyebrow: greeting, day: today, meals: remaining)]
            // A look ahead, not a second menu: tomorrow gets whatever rows are
            // left after tonight has what it needs, and the budget does the rest.
            if phase == .tonight, let lookAhead { out.append(lookAhead) }
            return out

        case .tomorrow:
            // Nothing left to cook today. Showing this morning's breakfast now
            // would be a widget about the past.
            guard let tomorrow, tomorrow.hasAnyMeal else { return [] }
            return [WidgetSection(eyebrow: "TOMORROW", day: tomorrow, meals: tomorrow.meals)]
        }
    }

    /// The large family splits today in two: the next meal on its own under UP
    /// NEXT, and the rest as rows under LATER TODAY.
    ///
    /// Two sections rather than one list with a big first row, because a card
    /// followed by rows in the same stack reads as a list whose first item is
    /// broken. The divider between them says these are different things: what to
    /// cook now, and what comes after.
    private func upNextSections(today: WidgetDay) -> [WidgetSection] {
        guard let next = remaining.first else { return [] }
        var out = [WidgetSection(
            eyebrow: "UP NEXT", day: today, meals: [next],
            label: next.type.displayName, isFeature: true
        )]
        let later = Array(remaining.dropFirst())
        if !later.isEmpty {
            out.append(WidgetSection(eyebrow: "LATER TODAY", day: today, meals: later, label: ""))
        }
        return out
    }

    /// A word that changes through the day.
    ///
    /// Free warmth: it replaces the static "TODAY" eyebrow, so it costs no
    /// height at all, and it is the cheapest thing on the widget that makes it
    /// feel like it knows what time it is.
    private var greeting: String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: entry.date)
        let minutes = calendar.dateComponents([.minute], from: start, to: entry.date).minute ?? 0

        // Derived from the same cutoffs that decide the rows, so the words and
        // the meals can never disagree: while breakfast is still up it is
        // morning, and once lunch has gone it is tonight.
        if minutes < WidgetPhase.showsUntil(.breakfast) ?? 0 { return "GOOD MORNING" }
        if minutes < WidgetPhase.eveningPivotMinutes { return "LATER TODAY" }
        return "TONIGHT"
    }

    /// How many rows the family can hold at Android's row height.
    ///
    /// Android's widget is a Glance `LazyColumn`, which **scrolls**. An iOS
    /// widget cannot, so a row count that overflows does not become a scroll — it
    /// silently hides food. These are what fits, and `KkbWidget.thumbnail`
    /// shrinks the row to make the rest fit rather than dropping it.
    ///
    /// The budget spans sections, so an evening small widget shows dinner and
    /// then, once dinner has passed, tomorrow's breakfast — crossing midnight
    /// with no phase logic of its own.
    /// How many prep steps the focused section shows.
    ///
    /// Two on a large widget, one on a medium — where the section plus a header
    /// already eats 82 of 120 points and a second step would leave no room for
    /// the meal it is prep *for*.
    private var focusStepLimit: Int { family == .systemLarge ? 2 : 1 }

    /// Height the focused section takes, for the row arithmetic below.
    ///
    /// Each step is now up to two lines, which is roughly 26pt at 11pt type,
    /// plus a 12pt eyebrow, 3pt gaps and 14pt of padding.
    private var focusHeight: CGFloat {
        guard focusedPrep != nil else { return 0 }
        return focusStepLimit == 2 ? 84 : 55
    }

    private var budget: Int {
        // Prep is why the user is looking in these states, so meals give up the
        // space rather than prep. One row is enough: `thumbnailSide` shrinks what
        // is left to fit around the section.
        let focusCost = focusedPrep == nil ? 0 : 1
        // The glance is a divider and a line — about half a row, but a medium has
        // no half rows to give. Between 14:00 and 18:00 an evening snack and
        // dinner are both still ahead, and without this they overrun the card by
        // thirty points.
        let glanceCost = tomorrowGlance == nil ? 0 : 1

        switch family {
        case .systemSmall: return 1
        // Two rows at Android's minimum row height exactly fills a medium; the
        // banner costs one of them. Three overflows by half a row.
        case .systemMedium: return max(1, (banner == nil ? 2 : 1) - focusCost - glanceCost)
        // As many rows as the height allows, plus the feature card when there is
        // one. On the smallest phones five meal types do not all fit; the last is
        // the furthest away and the one most worth giving up.
        case .systemLarge:
            let featured = rowSections.first?.isFeature == true ? 1 : 0
            let capacity = largeRowCapacity(
                extraSections: max(0, rowSections.count - 1),
                glance: tomorrowGlance != nil
            )
            return max(1, featured + capacity)
        default: return max(1, 2 - focusCost)
        }
    }

    /// Usable height for the row arithmetic.
    ///
    /// Large uses the size WidgetKit reports, less the standard 16pt content
    /// margin top and bottom: its fixed estimate is sized for the smallest phone,
    /// and on a Pro that left 40pt empty while the feature block pushed a meal off.
    /// Small and medium keep their estimates — their row counts are fixed anyway.
    private var contentHeight: CGFloat {
        guard family == .systemLarge, entry.displaySize.height > 0 else { return family.contentHeight }
        return entry.displaySize.height - 32
    }

    /// Compact rows that fit on the large family, around everything else.
    ///
    /// Worked from heights rather than a fixed count, because the feature card,
    /// the done line, the prep section and each extra section's header all take
    /// from the same height. Deliberately independent of `allocated` — the budget
    /// is derived from it.
    private func largeRowCapacity(extraSections: Int, glance: Bool) -> Int {
        let hasFeature = sections.first?.isFeature == true
        let fixed = KkbWidget.headerHeight
            + (hasFeature ? KkbWidget.featureHeight + KkbWidget.rowPadding : 0)
            + doneChrome
            + (banner == nil ? 0 : KkbWidget.bannerHeight)
            + focusHeight
            + CGFloat(extraSections) * (KkbWidget.headerHeight + KkbWidget.dividerHeight)
            + (glance ? KkbWidget.dividerHeight + KkbWidget.glanceHeight : 0)
        return max(0, Int((contentHeight - fixed) / KkbWidget.minimumRowHeight))
    }

    /// Android's 72dp thumbnail, shrunk only when the rows would not otherwise fit.
    ///
    /// Matching Android exactly is the goal and the common case reaches it: three
    /// meals on a large widget get the full 72. Five do not — 72pt rows need
    /// 440pt and `.systemLarge` has about 310 — so rather than hiding two meals
    /// the rows get shorter. A smaller photo is a much smaller loss than a
    /// missing dinner.
    private var thumbnailSide: CGFloat {
        let featured = allocated.first?.isFeature == true ? 1 : 0
        let rows = max(allocated.reduce(0) { $0 + $1.meals.count } - featured, 1)
        // Each extra row section costs its own header and the divider above it.
        // The glance costs a divider and a single line.
        let extraSections = CGFloat(max(0, allocated.count - 1))
        let chrome = KkbWidget.headerHeight
            + heroChrome
            + doneChrome
            + (banner == nil ? 0 : KkbWidget.bannerHeight)
            + focusHeight
            + extraSections * (KkbWidget.headerHeight + KkbWidget.dividerHeight)
            + (tomorrowGlance == nil ? 0 : KkbWidget.dividerHeight + KkbWidget.glanceHeight)
        // A slightly smaller floor when the prep section is present. Two-line
        // steps leave a medium widget about three points short of a 36pt
        // thumbnail, and shrinking the photo is a better trade than dropping the
        // meal the prep is for.
        let floor: CGFloat = focusedPrep == nil ? 36 : 30
        let perRow = (contentHeight - chrome) / CGFloat(rows)
        // The small family is short on width, not height: a full 72pt photo in a
        // 138pt card leaves the dish name 54pt and wraps "Masala poha" mid-word.
        let ceiling: CGFloat
        if family == .systemSmall {
            ceiling = KkbWidget.smallThumbnail
        } else if featured == 1 {
            ceiling = KkbWidget.belowFeatureThumbnail
        } else {
            ceiling = KkbWidget.thumbnail
        }
        return min(ceiling, max(floor, perRow - KkbWidget.rowPadding * 2))
    }

    /// Prep promoted out of a cramped line and into its own block.
    ///
    /// Only when the widget is focused — tomorrow alone, or a single meal left
    /// tonight. Those are exactly the states with rows to spare, and they are
    /// also the states where prep is the most useful thing on screen: if you are
    /// looking at tomorrow at 21:00, what to start *now* matters more than what
    /// you will eat in fourteen hours.
    ///
    /// `nil` in every other state, where the banner covers urgency and the
    /// per-meal lines cover the rest.
    private var focusedPrep: (eyebrow: String, dish: String?, items: [PrepTonightItem])? {
        guard family != .systemSmall else { return nil }

        switch phase {
        case .tomorrow:
            guard let tomorrow = entry.tomorrow else { return nil }
            let items = PrepNow.steps(for: tomorrow.meals, source: .tonight)
            return items.isEmpty ? nil : ("START TONIGHT", dish(in: items), items)

        case .today, .tonight:
            // Morning too, not just the evening. An eight-hour soak for tonight's
            // dinner has to start at noon, and a nine-point line under a dish
            // eleven hours before you eat it is the wrong place to say so.
            //
            // `.afternoon` narrows to the evening meals by itself, so this is
            // "what does tonight need" whatever else is still ahead today.
            let items = PrepNow.steps(for: remaining, source: .afternoon)
            return items.isEmpty ? nil : (eyebrow(for: items), dish(in: items), items)
        }
    }

    /// Names the meal when every step belongs to one, and stays general when they
    /// do not — "BEFORE DINNER" is worth more than "PREP TODAY", but only when
    /// it is true.
    private func eyebrow(for items: [PrepTonightItem]) -> String {
        let types = Set(items.map(\.mealType))
        guard types.count == 1, let only = types.first else { return "PREP TODAY" }
        return "BEFORE \(only.displayName.uppercased())"
    }

    /// The dish these steps belong to, when they all belong to one.
    ///
    /// The section has to stand on its own, because the row it refers to may not
    /// be on screen: before 09:00 with five meals ahead the budget trims to four
    /// and drops dinner — the very meal a "BEFORE DINNER" section is about.
    private func dish(in items: [PrepTonightItem]) -> String? {
        let dishes = Set(items.map(\.dish))
        return dishes.count == 1 ? dishes.first : nil
    }

    /// The one clock-aware thing on the widget, and deliberately not per-section:
    /// at 19:00 the step that matters usually belongs to tomorrow's breakfast, so
    /// scoping it to the day on screen would hide the only urgent fact there is.
    private var banner: PrepDue? {
        guard family != .systemSmall else { return nil }
        // The focused section already says this, in more detail and with more
        // room. Two urgency notices in a 155pt card is one too many.
        guard focusedPrep == nil else { return nil }
        guard let today = entry.today else { return nil }

        return PrepNow.due(
            today: today.meals,
            tomorrow: entry.tomorrow?.meals ?? [],
            now: entry.date,
            calendar: .current
        ).first
    }

    /// How the next meal's row is set apart.
    ///
    /// Medium only. Large gives the next meal a section of its own — see
    /// `upNextSections` — and small is one row already, as prominent as it gets.
    /// Medium has room for neither, since two rows already fill it, so the row
    /// itself gets a card.
    ///
    /// Never once today is done: tomorrow is a menu to glance over, not a meal
    /// to start, so its rows are all alike.
    private var heroStyle: WidgetMealRow.Hero? {
        family == .systemMedium && phase != .tomorrow ? .card : nil
    }

    /// Height the hero adds over an ordinary row, for the row arithmetic.
    private var heroChrome: CGFloat {
        if allocated.first?.isFeature == true {
            return KkbWidget.featureHeight + KkbWidget.rowPadding
        }
        return heroStyle == .card && !allocated.isEmpty ? KkbWidget.heroExtraHeight : 0
    }

    /// Once today is cooked, the widget says so before anything else — above the
    /// prep block too, since "start tonight" only makes sense once the reader
    /// knows the meals below are tomorrow's.
    ///
    /// From `sections`, not `allocated`: the row budget depends on this line's
    /// height, so reading the trimmed rows here would recurse. Only the header
    /// text is used, and trimming never changes that.
    private var doneHeader: WidgetSection? {
        guard phase == .tomorrow else { return nil }
        return sections.first
    }

    /// Large says it on a line of its own, in larger type; the smaller families
    /// fold it into the section header, where it costs no height.
    private var showsDoneLine: Bool { family == .systemLarge && doneHeader != nil }

    private var doneChrome: CGFloat {
        showsDoneLine ? KkbWidget.doneLineHeight + KkbWidget.rowPadding : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KkbWidget.rowPadding) {
            if showsDoneLine {
                DayDoneLine()
            } else if let doneHeader {
                WidgetHeader(
                    eyebrow: doneHeader.eyebrow,
                    dayLabel: doneHeader.dayLabel,
                    acknowledgement: "Today's done",
                    shortAcknowledgement: "Done"
                )
            }

            if let banner {
                PrepBanner(due: banner)
            }

            if let focusedPrep {
                PrepFocusSection(
                    eyebrow: focusedPrep.eyebrow,
                    dish: focusedPrep.dish,
                    items: focusedPrep.items,
                    limit: focusStepLimit
                )
            }

            // Today is cooked and tomorrow is not planned yet. Reached only in
            // the evening, and a blank card would read as a broken widget rather
            // than a finished day.
            if allocated.isEmpty {
                RestedState(phase: phase)
            }

            ForEach(Array(allocated.enumerated()), id: \.element.id) { index, section in
                // Only between sections, never above the first. Reached in one
                // state — tonight's dinner above tomorrow's plan — where two
                // stacks of meal rows otherwise read as one long list and the
                // TOMORROW eyebrow gets lost among them.
                if index > 0 { SectionDivider() }

                // The folded-in done header already named this section.
                if !(index == 0 && doneHeader != nil && !showsDoneLine) {
                    WidgetHeader(eyebrow: section.eyebrow, dayLabel: section.dayLabel)
                }
                if section.isFeature, let meal = section.meals.first {
                    FeatureMealCard(meal: meal, day: section.day, container: entry.container)
                } else {
                    ForEach(Array(section.meals.enumerated()), id: \.element.type) { row, meal in
                        // The first row on the widget is the next thing to cook,
                        // in every phase — the rows ahead of it have already been
                        // filtered out by the clock.
                        let isHero = index == 0 && row == 0
                        WidgetMealRow(
                            meal: meal,
                            day: section.day,
                            container: entry.container,
                            side: thumbnailSide,
                            showPrepLine: family != .systemSmall,
                            hero: isHero ? heroStyle : nil
                        )
                    }
                }
            }
            if let tomorrowGlance {
                SectionDivider()
                TomorrowGlance(section: tomorrowGlance)
            }

            if family != .systemSmall { Spacer(minLength: 0) }
        }
        // Tap where the widget is looking. Once today is cooked, opening the app
        // on today's finished plan would be answering a question nobody asked.
        .widgetURL(WidgetDeepLink.url(target: phase == .tomorrow ? "tomorrow" : "today"))
    }

    /// Tomorrow reduced to a single line, for families that cannot afford rows.
    ///
    /// A medium widget showing tonight *and* tomorrow as two row stacks needs 145
    /// of its 120 points once the divider and second header are counted. Rather
    /// than dropping the preview — which is half the reason the evening layout
    /// exists — tomorrow becomes what it was always described as: a quick
    /// snapshot. Large has the room and keeps full rows.
    private var tomorrowGlance: WidgetSection? {
        guard let tomorrow = sections.last, tomorrow.isLookAhead else { return nil }
        guard family == .systemLarge else { return tomorrow }
        // Large keeps full rows for tomorrow whenever they all fit under tonight.
        // When they do not, a line naming every dish beats rows that silently
        // stop at lunch.
        let rowsNeeded = sections.filter { !$0.isFeature }.reduce(0) { $0 + $1.meals.count }
        let capacity = largeRowCapacity(extraSections: sections.count - 1, glance: false)
        return rowsNeeded <= capacity ? nil : tomorrow
    }

    /// Sections that render as rows. The glance, when there is one, is not among
    /// them — it is a line, and it is rendered separately.
    private var rowSections: [WidgetSection] {
        tomorrowGlance == nil ? sections : Array(sections.dropLast())
    }

    /// Trim to the family's budget, keeping section order and dropping whole
    /// sections that end up empty.
    private var allocated: [WidgetSection] {
        var remaining = budget
        var out: [WidgetSection] = []

        for section in rowSections where remaining > 0 {
            let take = Array(section.meals.prefix(remaining))
            guard !take.isEmpty else { continue }
            remaining -= take.count
            out.append(section.with(meals: take))
        }
        return out
    }
}

struct WidgetHeader: View {
    let eyebrow: String
    let dayLabel: String
    /// A short lead-in ahead of the eyebrow — "Today's done" once only tomorrow
    /// is left to show, so the switch of day reads as intended rather than as
    /// the widget having skipped ahead.
    var acknowledgement: String? = nil
    /// What the small family has room for.
    var shortAcknowledgement: String? = nil

    var body: some View {
        // Narrow widths drop the day name first, then shorten the lead-in, then
        // drop it: the eyebrow is the one part that says which day the rows are for.
        ViewThatFits(in: .horizontal) {
            line(ack: acknowledgement, showDay: true)
            line(ack: acknowledgement, showDay: false)
            line(ack: shortAcknowledgement, showDay: false)
            line(ack: nil, showDay: true)
        }
    }

    private func line(ack: String?, showDay: Bool) -> some View {
        HStack(spacing: 6) {
            if let ack {
                Text("✓ \(ack)")
                    .font(.system(size: KkbWidget.eyebrowSize, weight: .semibold))
                    .foregroundStyle(KkbWidget.ink600)
                Text("·")
                    .font(.system(size: KkbWidget.eyebrowSize))
                    .foregroundStyle(KkbWidget.ink600)
            }
            Text(eyebrow)
                .font(.system(size: KkbWidget.eyebrowSize, weight: .bold))
                .foregroundStyle(KkbWidget.terracotta600)
            if showDay, !dayLabel.isEmpty {
                Text(dayLabel)
                    .font(.system(size: KkbWidget.eyebrowSize, weight: .regular))
                    .foregroundStyle(KkbWidget.ink600)
            }
        }
        .lineLimit(1)
        .fixedSize()
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
            .font(.system(size: KkbWidget.bannerSize, weight: .medium))
            .foregroundStyle(KkbWidget.ink900)
            .lineLimit(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(due.isOverdue ? KkbWidget.terracotta200 : KkbWidget.marigold100)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct WidgetMealRow: View {
    let meal: WidgetMeal
    let day: WidgetDay
    let container: WidgetContainer?
    /// Android's 72dp, or less when the rows would not otherwise fit.
    let side: CGFloat
    let showPrepLine: Bool
    /// Set on the first row only: the meal the user is about to cook.
    var hero: Hero? = nil

    enum Hero {
        /// Larger name and an UP NEXT label on a raised card.
        case card
    }

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
            // Top, not centre. A two-line dish name grows downward, and centring
            // pushes the meal-type label out of line with its thumbnail — so
            // rows with long names sit visibly lower than rows with short ones.
            HStack(alignment: .top, spacing: KkbWidget.thumbnailGap) {
                thumbnailView
                VStack(alignment: .leading, spacing: 2) {
                    Text(hero == nil
                         ? meal.type.displayName.uppercased()
                         : "UP NEXT · \(meal.type.displayName.uppercased())")
                        .font(.system(size: KkbWidget.eyebrowSize, weight: .bold))
                        .foregroundStyle(KkbWidget.terracotta600)
                        .lineLimit(1)
                    Text(meal.name)
                        .font(.system(
                            size: hero == nil ? KkbWidget.mealNameSize : KkbWidget.heroNameSize,
                            weight: hero == nil ? .medium : .semibold
                        ))
                        .foregroundStyle(KkbWidget.ink900)
                        .lineLimit(2)
                    if showPrepLine, let prepLine {
                        Text(prepLine)
                            .font(.system(size: KkbWidget.prepLineSize))
                            .foregroundStyle(KkbWidget.ink600)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(hero == .card ? KkbWidget.heroPadding : 0)
            .background {
                if hero == .card {
                    RoundedRectangle(cornerRadius: KkbWidget.thumbnailRadius + KkbWidget.heroPadding)
                        .fill(KkbWidget.heroCard)
                }
            }
            // Bleed the card into the margin instead of insetting the row, so the
            // hero's thumbnail stays in line with the thumbnails below it.
            .padding(.horizontal, hero == .card ? -KkbWidget.heroPadding : 0)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            thumbnail
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: KkbWidget.thumbnailRadius))
        } else {
            // Same fallback as Android: the meal-type emoji on a cream tile,
            // used when the dish has no photo or the download failed.
            RoundedRectangle(cornerRadius: KkbWidget.thumbnailRadius)
                .fill(KkbWidget.cream100)
                .frame(width: side, height: side)
                .overlay(Text(meal.type.emoji).font(.system(size: side * 0.5)))
        }
    }
}

/// "Today's done", given a line of its own on the large widget.
///
/// Larger than an eyebrow because it is the answer to the question the widget
/// would otherwise raise at 22:00 — why is it showing Thursday? — and it has to
/// be read before the rows below make sense.
struct DayDoneLine: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: KkbWidget.doneLineSize, weight: .semibold))
                .foregroundStyle(KkbWidget.terracotta600)
            Text("Today's done")
                .font(.system(size: KkbWidget.doneLineSize, weight: .semibold))
                .foregroundStyle(KkbWidget.ink900)
        }
        .frame(height: KkbWidget.doneLineHeight)
    }
}

/// The next meal, given the large widget's lead.
///
/// Its own section rather than a bigger row: a row can only grow so far before
/// it reads as a row with a large photo, and the ask was for this meal to be the
/// thing the widget is about. The name gets three lines at 20pt because it is
/// the one piece of text meant to be read from across a room.
struct FeatureMealCard: View {
    let meal: WidgetMeal
    let day: WidgetDay
    let container: WidgetContainer?

    /// Every step at full length, earliest-starting first. There is room here for
    /// two lines, so the `+N` shorthand of the compact row is not needed.
    private var prepLine: String? {
        guard let prep = meal.prep,
              let step = prep.steps.max(by: { $0.leadTimeMinutes < $1.leadTimeMinutes })
        else { return nil }
        return "\(step.category.emoji) \(step.text) · \(formatLeadTime(step.leadTimeMinutes))"
    }

    private var photo: Image? {
        guard let key = meal.thumbnailKey, let container,
              let data = WidgetSnapshotStore.thumbnailData(key: key, in: container),
              let image = UIImage(data: data)
        else { return nil }
        return Image(uiImage: image)
    }

    var body: some View {
        Link(destination: WidgetDeepLink.url(day: day.day, mealType: meal.type)) {
            HStack(alignment: .center, spacing: 14) {
                photoView
                // No eyebrow: the UP NEXT header above the card already names
                // the meal, and saying it twice is what made it look like a row.
                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name)
                        .font(.system(size: KkbWidget.featureNameSize, weight: .semibold))
                        .foregroundStyle(KkbWidget.ink900)
                        .multilineTextAlignment(.leading)
                        .lineLimit(prepLine == nil ? 3 : 2)
                        .minimumScaleFactor(0.85)
                    if let prepLine {
                        Text(prepLine)
                            .font(.system(size: KkbWidget.prepLineSize))
                            .foregroundStyle(KkbWidget.ink600)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: KkbWidget.featureHeight)
        }
    }

    @ViewBuilder
    private var photoView: some View {
        let side = KkbWidget.featurePhoto
        if let photo {
            photo
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: KkbWidget.thumbnailRadius))
        } else {
            RoundedRectangle(cornerRadius: KkbWidget.thumbnailRadius)
                .fill(KkbWidget.cream100)
                .frame(width: side, height: side)
                .overlay(Text(meal.type.emoji).font(.system(size: side * 0.5)))
        }
    }
}

extension WidgetFamily {
    /// Usable height, after WidgetKit's own container inset.
    ///
    /// Approximate on purpose: this decides only how many rows fit and how far
    /// the thumbnail must shrink, never the layout itself, which SwiftUI does.
    /// Erring small costs a few points of whitespace; erring large clips a row.
    var contentHeight: CGFloat {
        switch self {
        case .systemSmall: return 120
        case .systemMedium: return 120
        case .systemLarge: return 310
        default: return 120
        }
    }
}


/// The end of a day that went to plan.
///
/// Warmth is the whole job here: this is the state a user lands on every evening
/// once dinner is behind them, and "no meals" would be a poor way to describe
/// having cooked everything you meant to.
struct RestedState: View {
    let phase: WidgetPhase.Phase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🍽️")
                .font(.system(size: 22))
            Text(phase == .tomorrow ? "That's today sorted" : "Nothing planned yet")
                .font(.system(size: KkbWidget.mealNameSize, weight: .medium))
                .foregroundStyle(KkbWidget.ink900)
            Text(phase == .tomorrow ? "Tap to plan tomorrow" : "Tap to pick meals")
                .font(.system(size: KkbWidget.prepLineSize))
                .foregroundStyle(KkbWidget.ink600)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


/// Prep, given room to be read.
///
/// The per-meal line states a step in nine points under a dish name. This states
/// it at full size with the hour it has to start, because in the two states that
/// reach here — tomorrow alone, or one meal left tonight — it is the actionable
/// thing on the card and the meal is context for it, rather than the other way
/// round.
struct PrepFocusSection: View {
    let eyebrow: String
    /// Named so the section reads on its own when the meal's row was trimmed.
    let dish: String?
    let items: [PrepTonightItem]
    let limit: Int

    /// Earliest first, so the one shown is the one that has to start soonest —
    /// and a `+N` says how much is not on screen.
    private var visible: [PrepTonightItem] {
        Array(items.sorted { $0.startByMinutes < $1.startByMinutes }.prefix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(eyebrow)
                    .font(.system(size: KkbWidget.eyebrowSize, weight: .bold))
                    .foregroundStyle(KkbWidget.terracotta600)
                    .fixedSize()
                if let dish {
                    Text(dish)
                        .font(.system(size: KkbWidget.eyebrowSize))
                        .foregroundStyle(KkbWidget.ink600)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if items.count > visible.count {
                    Text("+\(items.count - visible.count)")
                        .font(.system(size: KkbWidget.eyebrowSize))
                        .foregroundStyle(KkbWidget.ink600)
                        .fixedSize()
                }
            }

            ForEach(visible, id: \.id) { item in
                // firstTextBaseline, so the lead time stays pinned to the step's
                // *first* line rather than drifting down when the text wraps.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.step.category.emoji)
                        .font(.system(size: KkbWidget.prepLineSize))
                    Text(item.step.text)
                        .font(.system(size: KkbWidget.prepLineSize, weight: .medium))
                        .foregroundStyle(KkbWidget.ink900)
                        // Two lines: "Soak the rajma overnight in plenty of
                        // water" is a real step, and truncating it to a hyphen
                        // loses the half that says what to do.
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(formatLeadTime(item.step.leadTimeMinutes))
                        .font(.system(size: KkbWidget.eyebrowSize))
                        .foregroundStyle(KkbWidget.ink600)
                        // Never wraps and never yields width — the step text is
                        // what gives way, since it has two lines to give.
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KkbWidget.marigold100.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}


/// The line between tonight and tomorrow.
///
/// A hairline rather than a heavier rule or a gap: the widget has no height to
/// spend on emphasis, and the row above it is already the last thing being
/// cooked today. It only needs to say "that was today" clearly enough that the
/// TOMORROW eyebrow beneath is read as a new heading rather than another meal.
struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(KkbWidget.terracotta600.opacity(0.22))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}


/// Tomorrow in one line.
///
/// What the evening layout was always described as offering — a quick snapshot,
/// not a second menu. On a medium widget it is also the only version that fits:
/// two stacks of rows plus a divider and a second header overrun the card.
struct TomorrowGlance: View {
    let section: WidgetSection

    private var summary: String {
        section.meals.map(\.name).joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("TOMORROW")
                .font(.system(size: KkbWidget.eyebrowSize, weight: .bold))
                .foregroundStyle(KkbWidget.terracotta600)
                .fixedSize()
            Text(summary)
                .font(.system(size: KkbWidget.prepLineSize))
                .foregroundStyle(KkbWidget.ink600)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
