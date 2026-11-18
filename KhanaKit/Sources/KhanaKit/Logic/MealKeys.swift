import Foundation

/// Mirror of the main-dish matching in the web app's `lib/meal-corpus-utils.ts`
/// (`normalizeMealName`, `mealKeyName`, `mainDishKey`); that file is the
/// specification. The same dish is written many ways — "Rajma chawal with curd",
/// "Rajma rice", "Rajma with jeera rice" — and they all key to "rajma", so a
/// suggestion list never spends two slots on one dish.
///
/// Keep the word lists identical to the web app's. `MealKeysTests` checks this
/// port against a fixture generated from the web app; after changing a rule
/// there, regenerate it with `scripts/export-main-dish-key-fixture.ts`.
public enum MealKeys {

    private static let stopwords = try! NSRegularExpression(
        pattern: #"\b(recipe|special|homemade|fresh|tasty|delicious)\b"#, options: [.caseInsensitive]
    )
    private static let notLetterOrDigit = try! NSRegularExpression(pattern: #"[^\p{L}\p{N}\s]"#)
    private static let whitespace = try! NSRegularExpression(pattern: #"\s+"#)
    private static let bracketed = [
        try! NSRegularExpression(pattern: #"\([^)]*\)"#),
        try! NSRegularExpression(pattern: #"\[[^\]]*\]"#),
    ]

    /// Spelling variants → one canonical token. Only variants of the same word
    /// belong here — not different dishes that happen to be similar.
    private static let tokenCanonical: [String: String] = [
        "daal": "dal", "dhal": "dal",
        "chawal": "rice", "chaawal": "rice", "bhaat": "rice", "bhat": "rice",
        "chapati": "roti", "chapathi": "roti", "chappati": "roti", "chapatti": "roti",
        "phulka": "roti", "fulka": "roti",
        "rotis": "roti", "chapatis": "roti",
        "parantha": "paratha", "prantha": "paratha", "parathas": "paratha",
        "dahi": "curd", "yogurt": "curd", "yoghurt": "curd",
        "sabji": "sabzi", "subzi": "sabzi", "sabjee": "sabzi", "subji": "sabzi", "sabzee": "sabzi",
        "alu": "aloo", "aaloo": "aloo",
        "gobhi": "gobi",
        "chhole": "chole", "chholey": "chole", "choley": "chole",
        "khichri": "khichdi", "khichadi": "khichdi", "khichuri": "khichdi", "kichdi": "khichdi",
        "sambhar": "sambar",
        "pulav": "pulao", "pilaf": "pulao",
        "biriyani": "biryani", "briyani": "biryani", "biriani": "biryani",
        "idly": "idli", "idlis": "idli",
        "dosai": "dosa", "dosas": "dosa",
        "poori": "puri", "pooris": "puri", "puris": "puri",
        "kadi": "kadhi",
        "bhendi": "bhindi",
        "raitha": "raita",
        "chatni": "chutney",
        "uppuma": "upma",
        "bhurjee": "bhurji",
        "cheela": "chilla", "chila": "chilla", "cheelas": "chilla", "chillas": "chilla",
        "mutter": "matar", "mattar": "matar",
        "panir": "paneer",
        "rajmah": "rajma",
        "makhni": "makhani",
        "tarka": "tadka",
        "veg": "vegetable", "veggie": "vegetable", "veggies": "vegetable", "vegetables": "vegetable",
    ]

    /// Tokens that join the dishes of a plate: "Rajma chawal with curd".
    private static let joinerTokens: Set<String> = ["with", "and", "n", "plus", "or"]

    /// Descriptors that don't change which dish it is.
    private static let fillerTokens: Set<String> = [
        "served", "side", "of", "a", "the", "on", "in",
        "style", "homestyle", "home", "quick", "easy", "simple", "classic", "traditional",
        "one", "two", "three", "four", "1", "2", "3", "4", "ki", "ka", "ke",
    ]

    /// The base of a plate. A name that leads with only these ("Rice with mushur
    /// dal") is about whatever comes after them.
    private static let stapleTokens: Set<String> = [
        "rice", "roti", "ruti", "rotli", "rotla", "bhakri", "bread", "toast", "naan", "puri", "luchi", "paratha",
        "bajra", "jowar", "makki", "ragi", "plain", "steamed", "jeera", "brown", "multigrain", "white", "quinoa",
    ]

    /// Accompaniments — never the dish a plate is built around.
    private static let sideTokens: Set<String> = ["curd", "raita", "pickle", "achar", "chutney", "salad", "papad"]

    /// Dropped from inside the main dish so "Rajma rice" and "Rajma" match. Only
    /// rice: "Aloo paratha" and "Aloo puri" are different dishes.
    private static let plainRiceTokens: Set<String> = ["rice", "plain", "steamed"]

    /// Lentil words. A plain dal is the constant of a thali — "Rice with mushur dal
    /// and doi maach" and "…and macher bhapa" differ in the other dish — so a main
    /// part made only of these takes the next dish along with it.
    private static let plainDalTokens: Set<String> = [
        "dal", "moong", "mung", "mushur", "masoor", "tuver", "toor", "arhar", "chana", "cholar",
        "urad", "mixed", "yellow", "gujarati", "panchmel", "varan", "amti",
    ]

    /// Lowercased, Unicode-compatibility-folded, punctuation-free, single-spaced.
    public static func normalizeMealName(_ name: String) -> String {
        var text = name.lowercased().precomposedStringWithCompatibilityMapping
        text = replacing(stopwords, in: text)
        text = replacing(notLetterOrDigit, in: text)
        text = replacing(whitespace, in: text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name the keys are computed from: bracketed glosses dropped ("Chole
    /// (Chickpea Curry) with Rice"), unless nothing is left outside them.
    public static func mealKeyName(_ name: String) -> String {
        let stripped = bracketed.reduce(name) { replacing($1, in: $0) }
        let keyName = normalizeMealName(stripped)
        return keyName.isEmpty ? normalizeMealName(name) : keyName
    }

    /// The dish a plate is built around: the first part (split on "with"/"and")
    /// that isn't only staples or sides. Takes a `mealKeyName` result. Returns ""
    /// when there is nothing to key on.
    public static func mainDishKey(_ keyName: String) -> String {
        var parts: [[String]] = [[]]
        for token in canonicalTokens(keyName) {
            if joinerTokens.contains(token) {
                parts.append([])
            } else {
                parts[parts.count - 1].append(token)
            }
        }
        let nonEmpty = parts.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return "" }

        func isDish(_ part: [String]) -> Bool {
            part.contains { !stapleTokens.contains($0) && !sideTokens.contains($0) }
        }
        let mainIndex = nonEmpty.firstIndex(where: isDish)
        let main = mainIndex.map { nonEmpty[$0] } ?? nonEmpty[0]
        // "jeera rice" is all staples; keep it whole rather than reduce it to nothing.
        let withoutRice = main.filter { !plainRiceTokens.contains($0) }
        var key = withoutRice.isEmpty ? main : withoutRice

        if let mainIndex, key.allSatisfy({ plainDalTokens.contains($0) }),
           let companion = nonEmpty[(mainIndex + 1)...].first(where: isDish) {
            key += companion
        }
        // UTF-16 order, as JavaScript's default sort uses.
        return Set(key)
            .sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
            .joined(separator: " ")
    }

    /// `mainDishKey` of a raw meal name as typed or generated.
    public static func mainDishKey(of name: String) -> String {
        mainDishKey(mealKeyName(name))
    }

    private static func canonicalTokens(_ normalizedName: String) -> [String] {
        normalizedName
            .split(separator: " ")
            .map(String.init)
            .filter { !fillerTokens.contains($0) }
            .map { tokenCanonical[$0] ?? $0 }
    }

    private static func replacing(_ regex: NSRegularExpression, in text: String) -> String {
        regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " "
        )
    }
}
