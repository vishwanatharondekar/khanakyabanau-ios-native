import Foundation
import KhanaKit

/// Translated strings for one language, keyed by the lowercased original.
struct Translations {
    static let empty = Translations(map: [:])
    private let map: [String: String]

    init(map: [String: String]) { self.map = map }

    /// Falls back to the original when there is no translation, so a partial
    /// response degrades to English rather than to a blank cell.
    func callAsFunction(_ original: String) -> String {
        map[original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? original
    }

    var isEmpty: Bool { map.isEmpty }
}

/// Translates dish and ingredient names for the PDF exporters.
///
/// Only the PDFs are translated — neither Android nor the web app localizes the UI
/// itself, and the language picker's own copy says it is for "PDF & shopping list".
/// Resolution order matches Android: a small bundled dictionary, then a per-language
/// process cache, then one batched network call for whatever is left.
@MainActor
final class TranslationRepository {
    private let api: APIClient
    /// language code → (lowercased original → translation)
    private var cache: [String: [String: String]] = [:]

    init(api: APIClient) {
        self.api = api
    }

    func translations(for language: String, texts: [String]) async -> Translations {
        let code = language.lowercased()
        guard code != "en", !code.isEmpty else { return .empty }

        var resolved = cache[code] ?? [:]
        var misses: [String] = []
        var seen = Set<String>()

        for text in texts {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if resolved[key] != nil { continue }
            if seen.insert(key).inserted { misses.append(trimmed) }
        }

        if !misses.isEmpty {
            do {
                let response = try await api.send(
                    Endpoints.translateBatch(
                        TranslateBatchRequest(texts: misses, targetLanguage: code)
                    ),
                    as: TranslateBatchResponse.self
                )
                // The response is positional. If the counts disagree we cannot tell
                // which translation belongs to which ingredient, and mislabelling
                // "sugar" as "salt" is worse than staying in English — so the whole
                // batch is discarded rather than zipped optimistically.
                if response.translatedTexts.count == misses.count {
                    for (original, translated) in zip(misses, response.translatedTexts) {
                        // A blank translation would render an empty cell. Leaving
                        // it unresolved falls back to English, which is legible.
                        let cleaned = translated
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .precomposedStringWithCanonicalMapping
                        guard !cleaned.isEmpty else { continue }
                        resolved[original.lowercased()] = cleaned
                    }
                    cache[code] = resolved
                }
            } catch {
                // Leave the misses unresolved; the PDF renders them in English.
            }
        }

        return Translations(map: resolved)
    }

    func reset() {
        cache.removeAll()
    }
}
