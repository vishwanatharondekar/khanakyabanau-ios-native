import Foundation

/// A stored recipe→video entry that belongs to a meal, with the key it is filed under.
public struct SavedVideoMatch: Equatable {
    /// The stored key, which doubles as the dish name to label the match with.
    public let key: String
    public let url: String

    public init(key: String, url: String) {
        self.key = key
        self.url = url
    }
}

/// Which saved recipe video belongs to which meal.
///
/// Videos are keyed on a dish, and a meal names several — "Gujarati dal, steamed
/// rice, bhindi nu shaak and phulka". A key belongs to a meal when its words appear
/// as a contiguous run of whole words in the meal name, which resolves
/// "gujarati dal" for that whole line while keeping "dal" out of "Dalia Upma".
///
/// Ported from the web app's `lib/recipe-video-keys.ts`, function for function and
/// test for test (`RecipeVideoKeysTests` mirrors `recipe-video-keys.test.ts`, as
/// does Android's `RecipeVideoKeysTest`). All three clients read the same map, so
/// the rule cannot drift between them: a video the web app files under a dish has
/// to resolve here, and one saved here has to resolve there.
public enum RecipeVideoKeys {

    /// The storage key rule. Frozen: the server writes
    /// `recipeName.toLowerCase().trim()` (`api/auth/video-urls`), and every client
    /// reads with the same rule. The read-side normalising below — stemming, and
    /// ignoring punctuation — is a separate thing and is never written anywhere.
    public static func storageKey(_ dishName: String) -> String {
        dishName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// One trailing `s` off tokens of four characters or more, so "idlis" and "idli"
    /// compare equal. Applied to both sides, which is what makes it safe: stemming
    /// can then only merge a word with its plural, never cause a miss.
    ///
    /// `es` is deliberately left alone — stripping it turns "fries" into "fri",
    /// which breaks more than the "Fish Fry" / "Fish Fries" miss it would fix. The
    /// four-character floor is load-bearing too: "das" must not become "da".
    private static func stem(_ token: String) -> String {
        guard token.count >= 4, token.hasSuffix("s") else { return token }
        return String(token.dropLast())
    }

    /// One word of a name: its stem, and where it sits in the source.
    ///
    /// The offsets index the source's `Character` array, and exist so
    /// `findDishSlice` can hand back the meal's own casing — they are part of the
    /// contract rather than a convenience.
    public struct Token: Equatable {
        public let stem: String
        public let start: Int
        public let end: Int
    }

    /// ASCII letters and digits only, matching the `[a-z0-9]+` the web app scans
    /// with. Widening this on one client would let a key match there and miss
    /// everywhere else.
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

    /// Runs of word characters, lowercased and stemmed, each carrying where it came from.
    public static func tokenize(_ value: String) -> [Token] {
        let characters = Array(value)
        var tokens: [Token] = []
        var index = 0

        while index < characters.count {
            guard isWordCharacter(characters[index]) else {
                index += 1
                continue
            }
            let start = index
            while index < characters.count, isWordCharacter(characters[index]) {
                index += 1
            }
            tokens.append(
                Token(
                    stem: stem(String(characters[start..<index]).lowercased()),
                    start: start,
                    end: index
                )
            )
        }

        return tokens
    }

    /// Where `needle` starts as a contiguous run inside `haystack`, or nil.
    public static func runIndex(haystack: [Token], needle: [Token]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            if needle.indices.allSatisfy({ haystack[start + $0].stem == needle[$0].stem }) {
                return start
            }
        }
        return nil
    }

    public static func keyMatchesMeal(_ key: String, mealName: String) -> Bool {
        runIndex(haystack: tokenize(mealName), needle: tokenize(key)) != nil
    }

    /// The slice of `mealName` that `candidate` names, in the meal's own casing, or
    /// nil when the candidate is not a contiguous run of whole words in it.
    ///
    /// Validating and canonicalising in one call is the point. The returned string
    /// becomes the storage key, so "the key is a substring of the meal name" has to
    /// be produced here rather than hoped for downstream. A model that translates
    /// the dish ("Spinach Cottage Cheese" for "Palak Paneer"), reorders it or
    /// invents one fails the run test, and the caller falls back to the full meal
    /// name — the behaviour that existed before any of this.
    public static func findDishSlice(candidate: String, mealName: String) -> String? {
        let haystack = tokenize(mealName)
        let needle = tokenize(candidate)
        guard let at = runIndex(haystack: haystack, needle: needle) else { return nil }

        let characters = Array(mealName)
        return String(characters[haystack[at].start..<haystack[at + needle.count - 1].end])
    }

    /// The dish to use for `mealName`, given a proposed dish name: the model's answer
    /// on a cache miss, the stored answer on a cache hit. Nil when the proposal is
    /// not a contiguous run of whole words in this meal name, which is the caller's
    /// cue to fall back to the full meal name.
    ///
    /// A cached answer is re-sliced rather than returned verbatim: a cache keyed
    /// case-insensitively carries whichever casing populated the entry, and handing
    /// that back would undo the casing guarantee `findDishSlice` provides.
    public static func resolveMainDish(candidate: String, mealName: String) -> String? {
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return findDishSlice(candidate: candidate, mealName: mealName)
    }

    /// Every saved entry whose key belongs to this meal, most specific first.
    ///
    /// Ordering is token count, then character length, then the key itself. The
    /// alphabetical tie-break is not decoration: the PDF resolves one link per meal
    /// and has to produce the same one on every run.
    public static func matchSavedVideos(
        mealName: String,
        videoURLs: [String: String]?
    ) -> [SavedVideoMatch] {
        guard !mealName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let videoURLs, !videoURLs.isEmpty
        else { return [] }

        let haystack = tokenize(mealName)

        return videoURLs
            // A blank URL is how the native clients clear a pick, and a blank hero
            // is worse than no hero.
            .filter { key, url in
                !url.isEmpty && runIndex(haystack: haystack, needle: tokenize(key)) != nil
            }
            .map { SavedVideoMatch(key: $0.key, url: $0.value) }
            .sorted { first, second in
                let firstTokens = tokenize(first.key).count
                let secondTokens = tokenize(second.key).count
                if firstTokens != secondTokens { return firstTokens > secondTokens }
                // UTF-16 length, which is what the web app and Android compare.
                if first.key.utf16.count != second.key.utf16.count {
                    return first.key.utf16.count > second.key.utf16.count
                }
                return first.key < second.key
            }
    }

    /// The one video for surfaces that can only show one — the PDF row, the meal
    /// detail hero, the week grid's chip state. Most specific match, or nil.
    public static func matchSavedVideo(mealName: String, videoURLs: [String: String]?) -> String? {
        matchSavedVideos(mealName: mealName, videoURLs: videoURLs).first?.url
    }

    /// Two words or fewer is already a dish, so it is not worth an AI call.
    private static let minWordsForLookup = 2

    /// Whether `mealName` is long enough to be worth asking which dish inside it a
    /// recipe video should be about. Names of two words or fewer are already a dish
    /// ("Palak Paneer", "Poha"). Mirrors `needsMainDishLookup` in the web app's
    /// `lib/main-dish.ts`, and `api/ai/main-dish` enforces the same floor itself.
    public static func needsMainDishLookup(_ mealName: String) -> Bool {
        mealName
            .split(whereSeparator: \.isWhitespace)
            .count > minWordsForLookup
    }
}
