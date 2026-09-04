import Foundation
import KhanaKit
import UIKit
import WidgetKit

/// Keeps the widget's shared snapshot in step with the app.
///
/// The extension cannot fetch, cannot wait, and cannot ask a question, so
/// everything it needs is resolved here — in the app, where there is already a
/// network and a user watching a spinner. This is the iOS counterpart of
/// Android's `requestRefresh()`.
///
/// Every dependency is injected so the writer is testable without a container,
/// a network, or WidgetKit: `loadWeek` stands in for `MealRepository`, and
/// `reloadTimelines` for `WidgetCenter`.
@MainActor
final class WidgetSnapshotWriter {

    private let container: WidgetContainer?
    private let settings: SettingsRepository
    private let loadWeek: (String) async throws -> MealPlan
    private let reloadTimelines: () -> Void
    private let isAuthenticated: () -> Bool

    /// Re-entrancy guard.
    ///
    /// `rebuild()` loads weeks through `MealRepository`, and that is the very
    /// thing whose change hook triggers a rebuild — so without this the writer
    /// re-triggers itself forever, hammering the API from a background Task with
    /// nothing on screen to show for it.
    ///
    /// A plain flag rather than a queue: the rebuild reads whatever is current
    /// when it runs, so a change arriving mid-rebuild is either already included
    /// or will arrive with the next hook. There is nothing to remember.
    private var isRebuilding = false

    /// Matches Android's widget thumbnail budget. Anything larger is wasted on a
    /// 72pt row and costs shared-container space that nothing ever reclaims.
    private static let thumbnailPixels: CGFloat = 256

    init(
        container: WidgetContainer? = WidgetContainer.shared(),
        settings: SettingsRepository,
        loadWeek: @escaping (String) async throws -> MealPlan,
        isAuthenticated: @escaping () -> Bool,
        reloadTimelines: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.container = container
        self.settings = settings
        self.loadWeek = loadWeek
        self.isAuthenticated = isAuthenticated
        self.reloadTimelines = reloadTimelines
    }

    /// Rebuild and publish the snapshot.
    ///
    /// Silent on every failure. A widget that cannot be updated is a widget
    /// showing slightly old meals; surfacing that to someone who is in the middle
    /// of editing their week would be noise about a screen they are not looking at.
    func rebuild() async {
        guard let container, !isRebuilding else { return }
        isRebuilding = true
        defer { isRebuilding = false }

        guard isAuthenticated() else {
            // Explicitly publish the signed-out state rather than leaving the old
            // snapshot in place: a stale widget showing the previous account's
            // meals after a sign-out is a privacy problem, not a staleness one.
            try? WidgetSnapshotStore.write(
                WidgetSnapshot(isAuthenticated: false, writtenAt: Date(), days: []),
                to: container
            )
            WidgetSnapshotStore.pruneThumbnails(keeping: [], in: container)
            reloadTimelines()
            return
        }

        let today = PlanDate.today()
        let tomorrow = today.adding(days: 1)

        guard let todayPlan = try? await loadWeek(WeekDates.format(WeekDates.mondayOf(today)))
        else { return }

        // Six days a week this is the same document; only a Sunday needs the
        // second fetch, and MealRepository caches it either way.
        let tomorrowPlan: MealPlan
        if WeekDates.mondayOf(tomorrow) == WeekDates.mondayOf(today) {
            tomorrowPlan = todayPlan
        } else if let next = try? await loadWeek(WeekDates.format(WeekDates.mondayOf(tomorrow))) {
            tomorrowPlan = next
        } else {
            tomorrowPlan = todayPlan
        }

        var snapshot = WidgetSnapshot.build(
            today: todayPlan,
            tomorrow: tomorrowPlan,
            on: Date(),
            enabledTypes: settings.enabledTypes,
            isAuthenticated: true,
            thumbnailKey: { meal in
                guard let url = meal.imageUrl, !url.isEmpty else { return nil }
                return WidgetSnapshotStore.thumbnailKey(forImageURL: url)
            }
        )

        await cacheThumbnails(for: [todayPlan, tomorrowPlan], snapshot: &snapshot, in: container)

        try? WidgetSnapshotStore.write(snapshot, to: container)
        WidgetSnapshotStore.pruneThumbnails(
            keeping: Set(snapshot.days.flatMap { $0.meals.compactMap(\.thumbnailKey) }),
            in: container
        )
        reloadTimelines()
    }

    /// Download any thumbnail the container does not already hold.
    ///
    /// Keys that fail are cleared from the snapshot rather than left dangling, so
    /// the extension never asks for a file that is not there and renders its
    /// emoji placeholder instead — the same fallback Android uses.
    private func cacheThumbnails(
        for plans: [MealPlan],
        snapshot: inout WidgetSnapshot,
        in container: WidgetContainer
    ) async {
        var urlsByKey: [String: String] = [:]
        for plan in plans {
            for day in plan.meals.values {
                for type in MealType.allCases {
                    let meal = day[type]
                    guard let url = meal.imageUrl, !url.isEmpty else { continue }
                    urlsByKey[WidgetSnapshotStore.thumbnailKey(forImageURL: url)] = url
                }
            }
        }

        var usable = Set(urlsByKey.keys.filter {
            WidgetSnapshotStore.thumbnailData(key: $0, in: container) != nil
        })

        for (key, url) in urlsByKey where !usable.contains(key) {
            guard let data = await downscaled(from: url) else { continue }
            guard (try? WidgetSnapshotStore.writeThumbnail(data, key: key, to: container)) != nil
            else { continue }
            usable.insert(key)
        }

        snapshot.days = snapshot.days.map { day in
            var day = day
            day.meals = day.meals.map { meal in
                var meal = meal
                if let key = meal.thumbnailKey, !usable.contains(key) { meal.thumbnailKey = nil }
                return meal
            }
            return day
        }
    }

    private func downscaled(from url: String) async -> Data? {
        guard let url = URL(string: url) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data)
        else { return nil }

        let side = Self.thumbnailPixels
        let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1), 1)
        guard scale < 1 else { return image.jpegData(compressionQuality: 0.8) }

        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.8)
    }
}
