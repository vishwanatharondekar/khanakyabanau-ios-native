import KhanaKit
import SwiftUI

/// Shopping, as a view of the week rather than a sheet over it.
///
/// Every state renders in place. Nothing here blocks navigation — the tab bar
/// stays live throughout, including during a generation, and a generation the
/// user walks away from still finishes and still writes the server's cache, so
/// coming back finds it.
struct ShoppingPane: View {
    var state: ShoppingPaneState
    var session: ShoppingSession?
    /// The week the list belongs to: the list model writes its ticks and orders
    /// back to it, and re-reads the cached list through it.
    var week: WeekViewModel
    /// Owned above the panes (`HomeView`) so a cart build or checkout in flight
    /// survives a trip to Meals and back.
    var instamart: InstamartViewModel
    var onRetry: () -> Void
    var onCreateAccount: () -> Void
    var onPlanWeek: () -> Void

    var body: some View {
        switch state {
        // The probe is quick and free; saying "checking" rather than "building"
        // keeps the slow word for the slow path.
        case .probing:
            busy("Checking for a list")
        case .loading:
            ShoppingBuildingLoader(dishes: week.plan.allDishNames())
        case .ready:
            if let session {
                ShoppingListContent(
                    list: session.list,
                    weekStartDate: session.weekStartDate,
                    week: week,
                    instamart: instamart
                )
            } else {
                busy("Building your shopping list")
            }
        case let .error(text):
            message(
                title: "Couldn't build the list",
                body: text,
                actionTitle: "Try again",
                action: onRetry
            )
        case .limit:
            message(
                title: "You've used your free lists",
                body: "Create an account for unlimited shopping lists.",
                actionTitle: "Create account",
                action: onCreateAccount
            )
        case .empty:
            message(
                title: "Nothing to shop for yet",
                body: "Plan some meals this week and the list writes itself.",
                actionTitle: "Plan the week",
                action: onPlanWeek
            )
        // Deliberately no action: generating for a week that has already
        // happened would spend an AI call on a shop that is over.
        case .past:
            message(
                title: "No list from that week",
                body: "That week has already happened, so there is nothing left to shop for.",
                actionTitle: nil,
                action: {}
            )
        }
    }

    private func busy(_ text: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Kkb.terracotta500)
                .controlSize(.large)
            Text(text)
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func message(
        title: String,
        body: String,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .kkbFont(.displaySmall)
                .foregroundStyle(Kkb.textPrimary)
                .multilineTextAlignment(.center)
            Text(body)
                .kkbFont(.bodyMedium)
                .foregroundStyle(Kkb.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle {
                KkbPrimaryButton(title: actionTitle, action: action)
                    .padding(.top, 12)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

/// The wait while a list is generated — an AI call of several seconds, long
/// enough that a bare spinner reads as stuck.
///
/// Three things move, each saying something true: the basket pulses (work is
/// happening), the caption walks through the week's own dishes (this is what
/// the list is being built from), and the outline below shimmers in the shape
/// the list will take (what is coming). The quick cache probe does not use
/// this; it would only flash.
private struct ShoppingBuildingLoader: View {
    var dishes: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var pulsing = false

    /// The week's dishes first, then the steps after them. Capped so a full
    /// week does not keep the steps from ever showing.
    private var captions: [String] {
        var seen = Set<String>()
        let named = dishes
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .prefix(6)
            .map { "Working out what \($0) needs" }
        return named + ["Adding up quantities", "Sorting by aisle"]
    }

    var body: some View {
        let captions = captions
        ScrollView {
            VStack(spacing: 0) {
                basket
                    .padding(.bottom, 20)
                Text("Building your shopping list")
                    .kkbFont(.displaySmall)
                    .foregroundStyle(Kkb.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 6)
                Text(captions[index % captions.count])
                    .kkbFont(.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundStyle(Kkb.accentText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .clipped()
                    .padding(.bottom, 28)
                outline
                    .frame(maxWidth: 480)
                    .padding(.bottom, 20)
                Text("Takes a few seconds. You can keep using the app — it'll be here when you're back.")
                    .kkbFont(.bodySmall)
                    .foregroundStyle(Kkb.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .task(id: captions) {
            index = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1_800))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.35)) { index += 1 }
            }
        }
        .onAppear { pulsing = !reduceMotion }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Building your shopping list")
    }

    /// An expanding ring that fades as it grows — a heartbeat, not a spinner.
    private var basket: some View {
        ZStack {
            Circle()
                .fill(Kkb.terracotta200)
                .frame(width: 72, height: 72)
                .scaleEffect(pulsing ? 1.45 : 1)
                .opacity(pulsing ? 0 : 1)
                .animation(
                    pulsing ? .easeOut(duration: 1.6).repeatForever(autoreverses: false) : nil,
                    value: pulsing
                )
            Circle()
                .fill(Kkb.terracottaSurface)
                .frame(width: 72, height: 72)
            Image(systemName: "basket")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Kkb.accentText)
                .offset(y: pulsing ? -4 : 0)
                .animation(
                    pulsing ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : nil,
                    value: pulsing
                )
        }
        .frame(width: 104, height: 104)
    }

    /// Two aisles of shimmering rows, in the shape the finished list takes.
    private var outline: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array([[0.62, 0.48, 0.7], [0.55, 0.66]].enumerated()), id: \.offset) { group, rows in
                if group > 0 { Spacer().frame(height: 6) }
                bar(height: 12, radius: 6)
                    .frame(width: 110)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, width in
                    HStack(spacing: 12) {
                        bar(height: 18, radius: 5).frame(width: 18)
                        GeometryReader { proxy in
                            bar(height: 14, radius: 7)
                                .frame(width: proxy.size.width * width)
                        }
                        .frame(height: 14)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Kkb.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func bar(height: CGFloat, radius: CGFloat) -> some View {
        Shimmer()
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
