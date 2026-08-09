import Foundation

/// A single meal cell in a day's plan.
///
/// The server's GET response can return either a plain string (`"Dosa"`) or an
/// object (`{"name": "Dosa", "imageUrl": "…", "calories": 500}`) — see
/// `lib/meal-cell.ts:11-29`. When the user has `showCalories` enabled and asks for
/// AI suggestions, the server returns the object form with calories; we keep them
/// on the client and round-trip them through save so the badge survives a refresh.
public struct Meal: Hashable, Sendable {
    public var name: String
    public var imageUrl: String?
    public var calories: Int?
    public var prep: MealPrep?
    /// The dish name `prep` was generated for. Prep describes one dish, so a slot
    /// edited since generation has prep that no longer applies — see `validPrep`.
    public var prepFor: String?
    /// Recipe video for this dish, resolved server-side (the web app's meal detail
    /// page stores the top pick against the slot).
    public var videoUrl: String?

    public init(
        name: String,
        imageUrl: String? = nil,
        calories: Int? = nil,
        prep: MealPrep? = nil,
        prepFor: String? = nil,
        videoUrl: String? = nil
    ) {
        self.name = name
        self.imageUrl = imageUrl
        self.calories = calories
        self.prep = prep
        self.prepFor = prepFor
        self.videoUrl = videoUrl
    }

    public static let empty = Meal(name: "")

    public var isEmpty: Bool { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Prep, but only when it still describes the dish in this slot.
    ///
    /// The single staleness rule, in one place so no call site can forget it:
    /// telling someone to soak chana for a dish they swapped out is worse than
    /// saying nothing. The web app guards identically before rendering prep.
    public var validPrep: MealPrep? {
        guard let prep,
              prepFor?.trimmingCharacters(in: .whitespaces)
                  == name.trimmingCharacters(in: .whitespaces)
        else { return nil }
        return prep
    }
}

extension Meal: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, imageUrl, calories, prep, prepFor, videoUrl
    }

    public init(from decoder: any Decoder) throws {
        // A bare string is the common case for an unadorned dish.
        if let single = try? decoder.singleValueContainer() {
            if single.decodeNil() {
                self = .empty
                return
            }
            if let name = try? single.decode(String.self) {
                self = Meal(name: name)
                return
            }
        }

        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            // Neither a string nor an object (a number, an array, …). Android's
            // serializer degrades to Empty here rather than failing the response.
            self = .empty
            return
        }

        // `try? decode` (not `decodeIfPresent`) throughout: a missing key, an
        // explicit null and a wrong-typed value all collapse to nil in one level
        // of optionality, which is exactly the tolerance the wire format needs.
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.imageUrl = try? c.decode(String.self, forKey: .imageUrl)
        self.calories = try? c.decode(Int.self, forKey: .calories)
        // A whole week is 35 slots decoded in one pass, so a malformed prep on any
        // single slot must degrade to nil rather than throwing out the entire
        // response. `try?` is the point here, not an oversight.
        self.prep = try? c.decode(MealPrep.self, forKey: .prep)
        self.prepFor = try? c.decode(String.self, forKey: .prepFor)
        self.videoUrl = try? c.decode(String.self, forKey: .videoUrl)
    }

    public func encode(to encoder: any Encoder) throws {
        // With nothing but a name, persist as a plain string — the server's image
        // pipeline re-attaches imageUrl on read, so emitting an object would just
        // churn data.
        //
        // prep travels with prepFor or not at all: prepFor is what makes prep
        // interpretable, and what lets the server notice the dish has changed.
        // Sending prep alone would read as freshly generated and stop it ever
        // being regenerated.
        //
        // Both prep and videoUrl have to be round-tripped because
        // `PUT api/meals/{week}` replaces the whole `meals` map with what we send —
        // omitting either deletes it server-side for every slot in the week.
        let emitPrep: (MealPrep, String)? = {
            guard let prep, let prepFor else { return nil }
            return (prep, prepFor)
        }()

        guard calories != nil || emitPrep != nil || videoUrl != nil else {
            var single = encoder.singleValueContainer()
            try single.encode(name)
            return
        }

        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(calories, forKey: .calories)
        try c.encodeIfPresent(videoUrl, forKey: .videoUrl)
        if let (prep, prepFor) = emitPrep {
            try c.encode(prep, forKey: .prep)
            try c.encode(prepFor, forKey: .prepFor)
        }
    }
}
