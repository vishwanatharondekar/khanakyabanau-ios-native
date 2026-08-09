import Foundation
import KhanaKit

/// The user's saved recipe→video map, plus YouTube search.
///
/// Videos are saved per *dish*, not per slot, so a pick follows the dish across
/// weeks. This is app-scoped state because the same map drives the week grid's
/// video chips, Today's corner stamps, the meal detail page and the picker itself.
@MainActor
@Observable
final class RecipeVideoRepository {
    private let api: APIClient

    /// `nil` means "never loaded", which is different from "loaded and empty".
    private(set) var videoURLs: [String: String]?
    private var loadTask: Task<Void, Never>?

    /// Search results cached by query. The endpoint allows only ~99 uncached
    /// searches per day *across every user of the product*, so repeating a query
    /// within a session must not hit the network again.
    private var searchCache: [String: RecipeVideoSearchPage] = [:]

    init(api: APIClient) {
        self.api = api
    }

    func url(for meal: Meal) -> String? {
        RecipeVideos.url(in: videoURLs, for: meal)
    }

    /// True when the user has deliberately saved a video for this dish, as opposed
    /// to the server having cached a top pick against the slot. Only the former
    /// earns the "🎥 RECIPE VIDEO" stamp.
    func hasSavedPick(for mealName: String) -> Bool {
        guard let saved = videoURLs?[RecipeVideos.normalizeKey(mealName)] else { return false }
        return !saved.isEmpty
    }

    func ensureLoaded() async {
        if videoURLs != nil { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetch()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    func refresh() async {
        await fetch()
    }

    private func fetch() async {
        do {
            // A 404 here means "nothing saved yet", not a failure.
            let map = try await api.sendAllowingNotFound(
                Endpoints.videoURLs, as: [String: String].self
            )
            videoURLs = map ?? [:]
        } catch {
            // Leave it nil so the next screen that needs it tries again.
        }
    }

    /// Saves a pick. The server echoes the whole map back, which we adopt wholesale
    /// so every surface showing videos updates at once.
    func save(recipeName: String, videoUrl: String) async throws {
        let response = try await api.send(
            Endpoints.saveVideoURL(
                SaveVideoURLRequest(recipeName: recipeName, videoUrl: videoUrl)
            ),
            as: SaveVideoURLResponse.self
        )
        videoURLs = response.videoURLs
    }

    /// Clearing a pick is the same call with an empty URL.
    func clear(recipeName: String) async throws {
        try await save(recipeName: recipeName, videoUrl: "")
    }

    // MARK: - Search

    func search(query: String, pageToken: String? = nil) async throws -> RecipeVideoSearchPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(trimmed.lowercased())|\(pageToken ?? "")"
        if let cached = searchCache[cacheKey] { return cached }

        let page = try await api.send(
            Endpoints.searchVideos(query: trimmed, pageToken: pageToken),
            as: YouTubeSearchResponse.self
        ).asPage
        searchCache[cacheKey] = page
        return page
    }

    func reset() {
        videoURLs = nil
        searchCache.removeAll()
    }
}
