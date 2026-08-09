import Foundation
import KhanaKit

/// Reads and writes meal plans, and resolves dish thumbnails.
@MainActor
final class MealRepository {
    private let api: APIClient

    /// Lowercased dish name → resolved URL. Misses are cached as `nil` too, so
    /// reopening a sheet doesn't re-ask the server about a dish it has no photo for.
    private var imageCache: [String: String?] = [:]

    init(api: APIClient) {
        self.api = api
    }

    /// The GET creates an empty plan server-side when none exists, so this never
    /// 404s and callers don't need a "no plan yet" branch.
    func week(_ weekStartDate: String) async throws -> MealPlan {
        let plan = try await api.send(Endpoints.week(weekStartDate), as: MealPlan.self)
        return plan.normalizingImageURLs(MealImageURLs.absolutize)
    }

    /// Saves the whole grid and returns only the server-assigned identifiers.
    ///
    /// The response deliberately is **not** adopted as the new local plan: PUT
    /// echoes back exactly what we sent, with no image enhancement (only the GET
    /// path enhances). Replacing local state with it would strip every cached
    /// `imageUrl` and shimmer the entire week.
    @discardableResult
    func save(_ plan: MealPlan) async throws -> (id: String?, userId: String?) {
        let response = try await api.send(
            Endpoints.saveWeek(plan.weekStartDate, SaveMealsRequest(meals: plan.meals)),
            as: MealPlan.self
        )
        return (response.id, response.userId)
    }

    /// Previous weeks, newest first, used to seed local suggestions.
    func history(targetWeek: String, limit: Int = 10) async throws -> [MealPlan] {
        try await api.send(
            Endpoints.history(targetWeek: targetWeek, limit: limit), as: [MealPlan].self
        )
    }

    /// Asks the server to generate advance prep, then returns the refreshed plan so
    /// the caller can merge **only** prep across via `withPrepFrom`.
    func generatePrep(
        weekStartDate: String,
        targets: [(day: DayOfWeek, type: MealType)] = [],
        wholeWeek: Bool = false
    ) async throws -> MealPlan? {
        var didUpdate = false

        if wholeWeek {
            let response = try await api.send(
                Endpoints.generatePrep(weekStartDate, GeneratePrepRequest()),
                as: GeneratePrepResponse.self
            )
            didUpdate = response.updated > 0
        } else {
            for target in targets {
                let response = try await api.send(
                    Endpoints.generatePrep(
                        weekStartDate,
                        GeneratePrepRequest(day: target.day.key, mealType: target.type.key)
                    ),
                    as: GeneratePrepResponse.self
                )
                didUpdate = didUpdate || response.updated > 0
            }
        }

        guard didUpdate else { return nil }
        return try await week(weekStartDate)
    }

    func setSlotVideo(
        weekStartDate: String,
        day: DayOfWeek,
        type: MealType,
        videoUrl: String
    ) async throws {
        _ = try await api.send(Endpoints.setSlotVideo(
            weekStartDate,
            SetSlotVideoRequest(day: day.key, mealType: type.key, videoUrl: videoUrl)
        ))
    }

    // MARK: - Images

    /// Resolves thumbnails for the given dish names, consulting the in-memory cache
    /// first. The endpoint is unauthenticated and never errors — it returns `{}` on
    /// any server-side problem — so a failure here degrades to placeholder tiles.
    func resolveImages(for names: [String]) async -> [String: String] {
        var resolved: [String: String] = [:]
        var missing: [String] = []

        for name in names {
            let key = name.lowercased()
            if let cached = imageCache[key] {
                if let cached { resolved[key] = cached }
            } else {
                missing.append(name)
            }
        }
        guard !missing.isEmpty else { return resolved }

        do {
            let response = try await api.send(
                Endpoints.imageMapping(ImageMappingRequest(mealNames: missing)),
                as: ImageMappingResponse.self
            )
            for name in missing {
                let key = name.lowercased()
                let raw = response.mealImageMappings[name] ?? response.mealImageMappings[key]
                let absolute = MealImageURLs.absolutize(raw)
                // Cache misses as nil so we stop asking about dishes with no photo.
                imageCache[key] = absolute
                if let absolute { resolved[key] = absolute }
            }
        } catch {
            // Leave `missing` uncached so a transient failure can be retried.
        }
        return resolved
    }

    /// A single dish's thumbnail, for suggestion cards.
    func image(for name: String) async -> String? {
        await resolveImages(for: [name])[name.lowercased()]
    }

    func clearImageCache() {
        imageCache.removeAll()
    }
}
