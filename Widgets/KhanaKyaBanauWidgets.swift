import KhanaKit
import SwiftUI
import WidgetKit

@main
struct KhanaKyaBanauWidgetBundle: WidgetBundle {
    var body: some Widget {
        MealsWidget()
    }
}

/// One widget. Which day it shows is decided per timeline entry by
/// `WidgetPhase`, not by which of two widgets the user placed.
///
/// Android ships two receivers sharing `LargeDayContent`; this deliberately
/// diverges. A Tomorrow widget is dead space for most of the day, and there is
/// nothing left to configure once the widget picks the day itself — which is why
/// this stays `StaticConfiguration` rather than becoming an
/// `AppIntentConfiguration` with a day picker. Someone who wants tomorrow's plan
/// while today's is showing opens the app, which is one tap and answers better.
struct MealsWidget: Widget {
    static let kind = "meals"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            WidgetDayView(entry: entry)
        }
        .configurationDisplayName("Meal Plan")
        .description("Today's menu, and tomorrow's once the evening comes round.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetDayEntry: TimelineEntry {
    let date: Date
    /// Both days travel on every entry: the evening phase needs tonight's
    /// remaining meals *and* tomorrow's plan, and `.systemSmall` walks from one
    /// into the other to find the next meal across midnight.
    ///
    /// `nil` means "no readable snapshot" — rendered as the setup shell, never as
    /// an error, because an invitation is more useful than a complaint.
    let today: WidgetDay?
    let tomorrow: WidgetDay?
    let isAuthenticated: Bool
    let container: WidgetContainer?
    /// The size WidgetKit reports for this placement, or `.zero` where it gives
    /// none. Lets the large family plan rows against its real height rather than
    /// against the smallest phone's.
    var displaySize: CGSize = .zero
}

struct SnapshotProvider: TimelineProvider {

    func placeholder(in context: Context) -> WidgetDayEntry {
        WidgetDayEntry(
            date: Date(), today: nil, tomorrow: nil,
            isAuthenticated: false, container: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetDayEntry) -> Void) {
        completion(entry(at: Date(), displaySize: context.displaySize))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetDayEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current

        // No pivot passed: WidgetTimeline adds it itself, precisely so a provider
        // cannot forget to. Prep boundaries will arrive here as extraBoundaries
        // when the banner starts driving them.
        let dates = WidgetTimeline.entryDates(startingAt: now, calendar: calendar)

        completion(
            Timeline(
                entries: dates.map { entry(at: $0, displaySize: context.displaySize) },
                policy: .after(WidgetTimeline.nextMidnight(after: now, calendar: calendar))
            )
        )
    }

    private func entry(at date: Date, displaySize: CGSize) -> WidgetDayEntry {
        let container = WidgetContainer.shared()
        let snapshot = container.flatMap { WidgetSnapshotStore.read(from: $0) }
        // Looked up by the entry's own date, never by position. The app writes
        // the snapshot only when it runs, so the midnight entry — and every reload
        // after it until the app is next opened — must find the new day in the
        // window rather than re-render the one that was first when it was written.
        let days = snapshot?.days(on: PlanDate.today(now: date))
        return WidgetDayEntry(
            date: date,
            today: days?.today,
            tomorrow: days?.tomorrow,
            isAuthenticated: snapshot?.isAuthenticated ?? false,
            container: container,
            displaySize: displaySize
        )
    }
}

struct WidgetDayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetDayEntry

    var body: some View {
        content
            // Required: without it the widget renders blank in StandBy and on iPad.
            //
            // A gradient rather than flat cream. The widget sits among app icons
            // all day and flat paper reads as an empty box; a warm wash reads as
            // a kitchen. It costs no height, which is the only currency here.
            .containerBackground(KkbWidget.warmth, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if entry.container == nil {
            // Not the user's problem and not fixable by tapping: the App Group is
            // missing, so the app and the extension are not sharing a container
            // at all. Shipping copy stays an invitation because a user can do
            // nothing either way, but a developer should not have to guess —
            // this exact state cost an afternoon once.
            #if DEBUG
                WidgetShell(message: "No App Group — check KKB_WIDGET_ENTITLEMENTS", emphasis: true)
            #else
                WidgetShell(message: "Tap to set up", emphasis: true)
            #endif
        } else if !entry.isAuthenticated {
            WidgetShell(message: "Tap to set up", emphasis: true)
        } else if entry.today == nil
                    || (entry.today?.hasAnyMeal == false && entry.tomorrow?.hasAnyMeal != true) {
            // `today == nil` while signed in is a snapshot older than its window:
            // the app has not run for over a week. Opening it rewrites the window.
            WidgetShell(message: "Open the app to pick meals", emphasis: false)
        } else {
            WidgetDayContent(entry: entry, family: family)
        }
    }
}

/// The empty and signed-out states.
///
/// Copy matches Android's exactly, so a screenshot in a support thread means the
/// same thing on both platforms.
struct WidgetShell: View {
    let message: String
    let emphasis: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("KHANA KYA BANAU")
                .font(.system(size: KkbWidget.eyebrowSize, weight: .bold))
                .foregroundStyle(KkbWidget.terracotta600)
            Spacer(minLength: 0)
            Text(message)
                .font(.system(size: emphasis ? 16 : 14, weight: emphasis ? .semibold : .regular))
                .foregroundStyle(emphasis ? KkbWidget.ink900 : KkbWidget.ink600)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The app's palette, duplicated rather than imported.
///
/// `App/DesignSystem` belongs to the app target and the extension is a separate
/// binary; pulling the whole design system across for six colours would drag in
/// its dependencies too. These must stay in step with the app's cream/terracotta
/// values and with Android's `WidgetColors`.
enum KkbWidget {

    // MARK: - Metrics
    //
    // Ported one-for-one from Android's `LargeDayContent.kt`, so the two
    // platforms look like the same product. dp and pt are both
    // density-independent, so the numbers transfer directly.
    //
    // The one place they cannot match: Android's widget is a Glance `LazyColumn`
    // and **scrolls**, so it can afford 72dp rows however many meals there are.
    // An iOS widget cannot scroll, so `WidgetDayContent.thumbnailSide` shrinks
    // the row when the meals would not otherwise fit. A smaller photo is a much
    // smaller loss than a dinner the user cannot see.

    /// Android: `val size = 72.dp`.
    static let thumbnail: CGFloat = 72
    /// The small family's ceiling. Diverges from Android, whose small widget is
    /// wider relative to its text; here the name needs the width more.
    static let smallThumbnail: CGFloat = 48
    /// Android: `val radius = 14.dp`.
    static let thumbnailRadius: CGFloat = 14
    /// Android: `Spacer(GlanceModifier.width(12.dp))`.
    static let thumbnailGap: CGFloat = 12
    /// Android: `.padding(vertical = 8.dp)` on the row.
    static let rowPadding: CGFloat = 8

    /// Android: meal-type label and day label, `fontSize = 10.sp`.
    static let eyebrowSize: CGFloat = 10
    /// Android: meal name, `fontSize = 14.sp`.
    static let mealNameSize: CGFloat = 14
    /// Android: prep line, `fontSize = 11.sp`.
    static let prepLineSize: CGFloat = 11
    /// Android: prep banner, `fontSize = 12.sp`.
    static let bannerSize: CGFloat = 12

    /// Rough heights used only to decide how many rows fit, never to lay out.
    static let headerHeight: CGFloat = 16
    static let bannerHeight: CGFloat = 32
    /// A 1pt rule plus the stack's own gap above it.
    static let dividerHeight: CGFloat = 9
    /// One line of 11pt type, plus the stack's gap.
    static let glanceHeight: CGFloat = 21

    /// The first row's dish name. One step up from `mealNameSize`: enough to lead
    /// the eye without the row needing more height than its two-line name had.
    static let heroNameSize: CGFloat = 16
    /// Inset of the card behind the first row. Vertical padding is the only
    /// height the emphasis costs, which is why it is small.
    static let heroPadding: CGFloat = 6
    static let heroExtraHeight: CGFloat = heroPadding * 2

    /// The large family's feature block for the next meal: a photo twice the
    /// size of the rows beneath it, and a name that leads the whole widget.
    ///
    /// No card behind it. Its own section and its size already set it apart, and
    /// a panel on top of that made the widget look like it had a dialog open.
    ///
    /// 88pt rather than larger because the thumbnails are 256px — at 3x anything
    /// much bigger goes soft — and because every point here is taken from the
    /// rows beneath it.
    static let featurePhoto: CGFloat = 88
    static let featureNameSize: CGFloat = 20
    static let featureHeight: CGFloat = featurePhoto
    /// Row thumbnails beneath a feature block. Half its size, so the eye lands on
    /// the next meal first; the rows under it are there to be scanned, not studied.
    static let belowFeatureThumbnail: CGFloat = 44
    /// The large family's "Today's done" line.
    static let doneLineSize: CGFloat = 16
    static let doneLineHeight: CGFloat = 22
    /// The smallest row the large family will lay out below the feature block —
    /// the 36pt thumbnail floor plus the row's padding.
    static let minimumRowHeight: CGFloat = 36 + rowPadding * 2

    // MARK: - Colours

    /// Cream, warming towards marigold at the bottom-right.
    ///
    /// Low-contrast on purpose: it should be felt rather than noticed, and it
    /// must not fight the meal photographs, which are the actual colour on the
    /// widget.
    static let warmth = LinearGradient(
        colors: [cream50, marigold100.opacity(0.55)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cream50 = Color(red: 0.996, green: 0.980, blue: 0.953)
    static let cream100 = Color(red: 0.992, green: 0.961, blue: 0.902)
    static let terracotta600 = Color(red: 0.722, green: 0.282, blue: 0.114)
    static let terracotta200 = Color(red: 0.953, green: 0.769, blue: 0.604)
    static let marigold100 = Color(red: 0.996, green: 0.941, blue: 0.780)
    static let ink600 = Color(red: 0.380, green: 0.322, blue: 0.278)
    static let ink900 = Color(red: 0.165, green: 0.122, blue: 0.090)
    /// The first row's card. Translucent white rather than a palette tint, so it
    /// reads as raised off the warm wash instead of as another coloured block
    /// competing with the prep banner.
    static let heroCard = Color.white.opacity(0.6)
}
