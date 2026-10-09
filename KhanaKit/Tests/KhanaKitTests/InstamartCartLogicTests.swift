import XCTest
@testable import KhanaKit

/// Port-parity tests for the Instamart cart models and `InstamartCartLogic`,
/// mirroring Android's `InstamartCartTest.kt`. The webapp's
/// `lib/swiggy/address.ts`, `components/SwiggyCartReview.tsx` and
/// `components/ShoppingListModal.tsx` are the specification.
final class InstamartCartLogicTests: XCTestCase {

    private func planLine(_ spinId: String, _ display: String? = nil) -> CartPlanLine {
        let display = display ?? spinId
        return CartPlanLine(
            ingredient: display.lowercased(),
            display: display,
            spinId: spinId,
            skuId: "sku-\(spinId)",
            packDescription: "500 g",
            packLabel: "Fresho \(display)",
            quantity: 1,
            unitPrice: 40,
            confidence: "high"
        )
    }

    private func priced(_ spinId: String, _ display: String? = nil, inCart: Bool = true) -> PricedCartLine {
        let line = planLine(spinId, display)
        return PricedCartLine(
            ingredient: line.ingredient,
            display: line.display,
            spinId: line.spinId,
            skuId: line.skuId,
            packDescription: line.packDescription,
            packLabel: line.packLabel,
            quantity: line.quantity,
            unitPrice: line.unitPrice,
            confidence: line.confidence,
            inCart: inCart,
            chargedPrice: inCart ? 38 : nil,
            chargedQuantity: inCart ? 1 : 0
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Decoding the cart response

    private let cartResponse = """
        {"address":{"id":"addr-1","addressLine":"12 MG Road, Bengaluru","addressTag":"Home","phoneNumber":"x"},
         "plan":{"lines":[{"ingredient":"tomatoes","display":"Tomatoes","spinId":"S1","skuId":"K1",
                           "packDescription":"500 g","packLabel":"Fresho Tomato","quantity":2,"unitPrice":20,
                           "confidence":"low","notes":["Rounded up to 2 packs"]}],
                 "misses":["Saffron"]},
         "cart":{"cartTotalAmount":"₹76","items":[{"spinId":"S1"}],
                 "billBreakdown":{"lineItems":[{"label":"Item total","value":"₹76"}],
                                  "toPay":{"label":"To pay","value":"₹1,076.50"}},
                 "unserviceableItems":[{"itemName":"Paneer"}]},
         "priced":[{"ingredient":"tomatoes","display":"Tomatoes","spinId":"S1","skuId":"K1",
                    "packDescription":"500 g","packLabel":"Fresho Tomato","quantity":2,"unitPrice":20,
                    "imageUrl":"https://img/x.png","confidence":"low","notes":["Rounded up to 2 packs"],
                    "inCart":true,"chargedPrice":76,"chargedQuantity":1,"quantityMismatch":true}],
         "maxIngredients":35}
        """

    func testACartBuildDecodesFromTheServerResponse() throws {
        let build = try decode(CartBuild.self, cartResponse)

        XCTAssertEqual(
            build.address,
            InstamartAddress(id: "addr-1", addressLine: "12 MG Road, Bengaluru", addressTag: "Home")
        )
        XCTAssertEqual(build.plan.misses, ["Saffron"])
        XCTAssertEqual(build.plan.lines.first?.quantity, 2)
        XCTAssertEqual(build.plan.lines.first?.notes, ["Rounded up to 2 packs"])
        XCTAssertEqual(build.cart.cartTotalAmount, "₹76")
        XCTAssertEqual(build.cart.billBreakdown.lineItems, [BillRow(label: "Item total", value: "₹76")])
        XCTAssertEqual(build.cart.billBreakdown.toPay.label, "To pay")
        XCTAssertEqual(build.cart.billBreakdown.toPay.value, "₹1,076.50")
        XCTAssertEqual(build.cart.unserviceableItems, [UnserviceableItem(itemName: "Paneer")])
        XCTAssertFalse(build.cart.cartAbsent)
        XCTAssertNil(build.cart.addressWarning)
        XCTAssertEqual(build.maxIngredients, 35)

        let line = try XCTUnwrap(build.priced.first)
        XCTAssertEqual(build.priced.count, 1)
        XCTAssertTrue(line.inCart)
        XCTAssertEqual(line.chargedPrice, 76)
        XCTAssertEqual(line.chargedQuantity, 1)
        XCTAssertTrue(line.quantityMismatch)
        XCTAssertTrue(line.isLowConfidence)
        XCTAssertEqual(line.imageUrl, "https://img/x.png")
    }

    /// The rebuild route answers without maxIngredients, and a line Swiggy did
    /// not put in the cart carries `chargedPrice: null`.
    func testASparseRebuildResponseDecodesWithDefaults() throws {
        let build = try decode(
            CartBuild.self,
            #"{"address":{"id":"a","addressLine":"x"},"plan":{"lines":[]},"cart":{},"priced":[{"spinId":"S","inCart":false,"chargedPrice":null}]}"#
        )
        XCTAssertEqual(build.maxIngredients, 0)
        XCTAssertEqual(build.plan.misses, [])
        XCTAssertNil(build.address.addressTag)
        XCTAssertNil(build.priced.first?.chargedPrice)
        XCTAssertEqual(build.priced.first?.isLowConfidence, true)
    }

    func testAnEmptyBodyDecodesToAnEmptyBuild() throws {
        let build = try decode(CartBuild.self, "{}")
        XCTAssertEqual(build, CartBuild())
    }

    /// One malformed field degrades a line rather than failing the payment screen.
    func testAWrongTypedFieldFallsBackToItsDefault() throws {
        let line = try decode(PricedCartLine.self, #"{"spinId":"S","quantity":"two","notes":null,"inCart":true}"#)
        XCTAssertEqual(line.spinId, "S")
        XCTAssertEqual(line.quantity, 0)
        XCTAssertEqual(line.notes, [])
        XCTAssertTrue(line.inCart)
    }

    func testAPricedLineConvertsBackToAPlanLineWithEveryPlanField() throws {
        let line = try XCTUnwrap(try decode(CartBuild.self, cartResponse).priced.first)
        let plan = line.toPlanLine()
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any]

        XCTAssertEqual(
            Set(encoded?.keys.map { $0 } ?? []),
            [
                "ingredient", "display", "spinId", "skuId", "packDescription", "packLabel",
                "quantity", "unitPrice", "imageUrl", "confidence", "notes",
            ]
        )
        XCTAssertEqual(encoded?["quantity"] as? Int, 2)
        XCTAssertEqual((encoded?["notes"] as? [String])?.count, 1)
    }

    /// No image is the normal case, and the wire leaves the key out rather than
    /// sending null — the rebuild route reads either as "no image".
    func testAPlanLineWithoutAnImageOmitsTheKey() throws {
        let encoded = String(decoding: try JSONEncoder().encode(planLine("A")), as: UTF8.self)
        XCTAssertFalse(encoded.contains("imageUrl"))
    }

    // MARK: - addressLabelFor

    func testADistinctTagAndLineAreBothKept() {
        XCTAssertEqual(
            InstamartCartLogic.addressLabelFor(addressTag: " Home ", addressLine: " 12 MG Road "),
            AddressLabel(tag: "Home", detail: "12 MG Road")
        )
    }

    /// "SRS Vivanta Hotel — SRS Vivanta Hotel" is not a label.
    func testTheLineWinsWhenItAlreadyLeadsWithTheTag() {
        XCTAssertEqual(
            InstamartCartLogic.addressLabelFor(
                addressTag: "srs vivanta hotel", addressLine: "SRS Vivanta Hotel, Koramangala"
            ),
            AddressLabel(tag: nil, detail: "SRS Vivanta Hotel, Koramangala")
        )
    }

    func testAMissingTagGivesNoChip() {
        XCTAssertEqual(
            InstamartCartLogic.addressLabelFor(addressTag: nil, addressLine: "12 MG Road"),
            AddressLabel(tag: nil, detail: "12 MG Road")
        )
        XCTAssertEqual(
            InstamartCartLogic.addressLabelFor(addressTag: "  ", addressLine: "12 MG Road"),
            AddressLabel(tag: nil, detail: "12 MG Road")
        )
    }

    func testAMissingLineFallsBackToTheTagAsTheDetail() {
        XCTAssertEqual(
            InstamartCartLogic.addressLabelFor(addressTag: "Home", addressLine: " "),
            AddressLabel(tag: nil, detail: "Home")
        )
    }

    // MARK: - parseRupees

    func testParsesSwiggyDisplayCopy() {
        XCTAssertEqual(InstamartCartLogic.parseRupees("₹1,234.50"), 1234.5)
        XCTAssertEqual(InstamartCartLogic.parseRupees("₹76"), 76)
    }

    func testUnreadableMoneyIsZero() {
        XCTAssertEqual(InstamartCartLogic.parseRupees(nil), 0)
        XCTAssertEqual(InstamartCartLogic.parseRupees(""), 0)
        XCTAssertEqual(InstamartCartLogic.parseRupees("—"), 0)
        XCTAssertEqual(InstamartCartLogic.parseRupees("."), 0)
    }

    /// parseFloat reads the longest numeric prefix rather than failing outright.
    func testReadsTheLeadingNumberLikeParseFloat() {
        XCTAssertEqual(InstamartCartLogic.parseRupees("1.2.3"), 1.2)
        XCTAssertEqual(InstamartCartLogic.parseRupees("₹45."), 45)
        XCTAssertEqual(InstamartCartLogic.parseRupees(".5"), 0.5)
    }

    /// The server's regex is ASCII `\d`; a Devanagari digit is not a digit to it,
    /// so it must not be one here either or the two totals would disagree.
    func testOnlyASCIIDigitsCount() {
        XCTAssertEqual(InstamartCartLogic.parseRupees("₹१२3"), 3)
    }

    // MARK: - formatRupees

    /// The review's line price must read like the webapp's `₹{chargedPrice}`.
    func testWholeRupeesDropTheTrailingPointZero() {
        XCTAssertEqual(InstamartCartLogic.formatRupees(45), "₹45")
        XCTAssertEqual(InstamartCartLogic.formatRupees(0), "₹0")
        XCTAssertEqual(InstamartCartLogic.formatRupees(1200), "₹1200")
    }

    func testFractionsPrintAsJavaScriptWould() {
        XCTAssertEqual(InstamartCartLogic.formatRupees(45.5), "₹45.5")
        XCTAssertEqual(InstamartCartLogic.formatRupees(99.25), "₹99.25")
    }

    // MARK: - splitForRebuild

    func testKeptLinesGoToTheRebuildAndTheRestBecomeRemoved() {
        let split = InstamartCartLogic.splitForRebuild(
            current: [planLine("A"), planLine("B"), planLine("C")], removed: [], keptSpinIds: ["A", "C"]
        )
        XCTAssertEqual(split.kept.map(\.spinId), ["A", "C"])
        XCTAssertEqual(split.removed.map(\.spinId), ["B"])
    }

    /// Restoring is ticking a removed line back on: it rejoins the cart.
    func testARestoredLineRejoinsTheCart() {
        let split = InstamartCartLogic.splitForRebuild(
            current: [planLine("A")], removed: [planLine("B")], keptSpinIds: ["A", "B"]
        )
        XCTAssertEqual(split.kept.map(\.spinId), ["A", "B"])
        XCTAssertEqual(split.removed, [])
    }

    /// A line in both lists appears once, at its place in the current cart.
    func testTheUniverseIsKeyedBySpinIdWithTheCurrentCartFirst() {
        let split = InstamartCartLogic.splitForRebuild(
            current: [planLine("A"), planLine("B")],
            removed: [planLine("C"), planLine("A")],
            keptSpinIds: ["C"]
        )
        XCTAssertEqual(split.kept.map(\.spinId), ["C"])
        XCTAssertEqual(split.removed.map(\.spinId), ["A", "B"])
    }

    /// A JS Map built from entries: the first insertion fixes the position, a
    /// later duplicate replaces the value.
    func testALaterDuplicateReplacesTheValueButKeepsThePosition() {
        var restored = planLine("A")
        restored.quantity = 3
        let split = InstamartCartLogic.splitForRebuild(
            current: [planLine("A"), planLine("B")], removed: [restored], keptSpinIds: ["A", "B"]
        )
        XCTAssertEqual(split.kept.map(\.spinId), ["A", "B"])
        XCTAssertEqual(split.kept.first?.quantity, 3)
    }

    // MARK: - stillToBuy

    func testStillToBuyMergesMissesUnserviceableRemovedAndNotInCartInOrder() {
        let build = CartBuild(
            address: InstamartAddress(id: "a", addressLine: "x"),
            plan: CartPlan(lines: [], misses: ["Saffron", "Paneer"]),
            cart: InstamartCart(unserviceableItems: [
                UnserviceableItem(itemName: "Paneer"), UnserviceableItem(itemName: "Milk"),
            ]),
            priced: [priced("S1", "Tomatoes"), priced("S2", "Onions", inCart: false)]
        )
        XCTAssertEqual(
            InstamartCartLogic.stillToBuy(build: build, removed: [planLine("S3", "Ginger")]),
            ["Saffron", "Paneer", "Milk", "Ginger", "Onions"]
        )
    }

    // MARK: - orderedItems

    /// A planned line Swiggy left out is not on its way; recording it would tick
    /// it off the list.
    func testOnlyInCartLinesAreRecordedAsOrdered() {
        XCTAssertEqual(
            InstamartCartLogic.orderedItems(
                priced: [priced("S1", "Tomatoes"), priced("S2", "Onions", inCart: false)]
            ),
            [OrderedItem(name: "tomatoes", display: "Tomatoes")]
        )
    }
}
