import Foundation

/// See `InstamartCartLogic.addressLabelFor`.
public struct AddressLabel: Hashable, Sendable {
    /// Nil rather than empty, so the caller renders no chip at all.
    public var tag: String?
    public var detail: String

    public init(tag: String?, detail: String) {
        self.tag = tag
        self.detail = detail
    }
}

/// See `InstamartCartLogic.splitForRebuild`.
public struct RebuildSplit: Hashable, Sendable {
    /// Sent to `cart/rebuild`.
    public var kept: [CartPlanLine]
    /// Shown as "Removed from this order", each with a restore tick.
    public var removed: [CartPlanLine]

    public init(kept: [CartPlanLine], removed: [CartPlanLine]) {
        self.kept = kept
        self.removed = removed
    }
}

/// Pure decisions behind the Instamart review and receipt screens. Port of
/// Android's `InstamartCartLogic` (`InstamartCart.kt`).
public enum InstamartCartLogic {

    /// The address split into a short tag and the line beneath it. Port of the
    /// webapp's `addressLabelFor` (`lib/swiggy/address.ts`).
    ///
    /// Two fields that often say the same thing: tags in the live payload are
    /// place names, not the "Home"/"Office" the docs imply, and `addressLine`
    /// frequently opens with the same words. Joining them blindly gives "SRS
    /// Vivanta Hotel — SRS Vivanta Hotel", which is not a label. When the line
    /// already leads with the tag, the line wins — it is the fuller of the two.
    public static func addressLabelFor(addressTag: String?, addressLine: String?) -> AddressLabel {
        let tag = (addressTag ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (addressLine ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if detail.isEmpty { return AddressLabel(tag: nil, detail: tag) }
        if tag.isEmpty { return AddressLabel(tag: nil, detail: detail) }
        if detail.lowercased().hasPrefix(tag.lowercased()) { return AddressLabel(tag: nil, detail: detail) }

        return AddressLabel(tag: tag, detail: detail)
    }

    /// Swiggy formats money as display copy, e.g. "₹1,234.50". Everything but
    /// ASCII digits and dots is dropped, then the leading number read the way
    /// JavaScript's `parseFloat` reads it; unreadable is 0. This is the figure
    /// sent to checkout as `expectedTotal`, which the server compares against
    /// the same parse of the same string — so it must parse identically. ASCII
    /// only, as the server's `\d` is: a Unicode-aware digit class would read
    /// "१२" as digits and disagree with it.
    public static func parseRupees(_ value: String?) -> Double {
        let cleaned = (value ?? "").unicodeScalars.filter { ("0"..."9").contains($0) || $0 == "." }

        // ^\d*\.?\d* — the longest prefix parseFloat would accept.
        var leading = ""
        var seenDot = false
        for scalar in cleaned {
            if scalar == "." {
                if seenDot { break }
                seenDot = true
            }
            leading.unicodeScalars.append(scalar)
        }
        return Double(leading) ?? 0
    }

    /// A line price as the webapp renders `₹{chargedPrice}` straight from the
    /// number: JavaScript's number-to-string, so no trailing ".0" on whole
    /// rupees ("₹45", where `"\(45.0)"` would print "45.0"), and the shortest
    /// round-tripping digits otherwise ("₹45.5").
    ///
    /// Only for Swiggy's own per-line figure. Bill rows and the total arrive as
    /// display copy and are shown verbatim, never re-formatted.
    public static func formatRupees(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 {
            return "₹\(Int64(value))"
        }
        return "₹\(value)"
    }

    /// Which lines a rebuild keeps. Port of the universe logic in the webapp's
    /// `ShoppingListModal.rebuildSwiggyCart`.
    ///
    /// Everything the user could have ticked in this round: what Swiggy is
    /// holding now, plus what they took out earlier and may be putting back.
    /// Keyed by spinId so a line that moved between the two lists appears once,
    /// at its first position.
    ///
    /// Unticking is a choice, not a stock problem. The unticked lines stay on
    /// screen as their own section so the user can put them back; folding them
    /// into `misses` would tell them Instamart does not sell something it sells
    /// perfectly well.
    public static func splitForRebuild(
        current: [CartPlanLine],
        removed: [CartPlanLine],
        keptSpinIds: Set<String>
    ) -> RebuildSplit {
        // A JS Map built from entries: first insertion fixes the position, a
        // later duplicate replaces the value.
        var order: [String] = []
        var universe: [String: CartPlanLine] = [:]
        for line in current + removed {
            if universe[line.spinId] == nil { order.append(line.spinId) }
            universe[line.spinId] = line
        }

        let lines = order.compactMap { universe[$0] }
        return RebuildSplit(
            kept: lines.filter { keptSpinIds.contains($0.spinId) },
            removed: lines.filter { !keptSpinIds.contains($0.spinId) }
        )
    }

    /// What the order did not cover, for the receipt's "Still to buy yourself".
    ///
    /// Four different causes inside the code — matcher misses, items Swiggy
    /// will not deliver to this address, lines the user unticked, and lines
    /// Swiggy left out of the cart — but one idea from the user's side. Captured
    /// at checkout, because the cart that knew it is torn down straight after.
    public static func stillToBuy(build: CartBuild, removed: [CartPlanLine]) -> [String] {
        let all = build.plan.misses
            + build.cart.unserviceableItems.map(\.itemName)
            + removed.map(\.display)
            + build.priced.filter { !$0.inCart }.map(\.display)
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    /// The items a placed order records. Only what Swiggy actually has in the
    /// cart: a planned line it left out is not on its way, and recording it
    /// would tick it off the list.
    public static func orderedItems(priced: [PricedCartLine]) -> [OrderedItem] {
        priced.filter(\.inCart).map { OrderedItem(name: $0.ingredient, display: $0.display) }
    }
}
