import XCTest
@testable import KhanaKit

/// Port-parity tests for the brand seam. Mirrors the webapp's `lib/brand.ts`;
/// when in doubt, that file is the specification.
final class BrandTests: XCTestCase {

    private let brand = Brand.current

    /// The shipping brand with PDF import switched on — what iOS becomes the
    /// day the import screen lands. The user half of `canImportPlan` is tested
    /// against this so it stays covered while the capability is off.
    private var withImport: Brand {
        var b = Brand.current
        b.capabilities.pdfImport = true
        return b
    }

    private func user(
        id: String = "user_1",
        isGuest: Bool = false,
        pdfImport: Bool = false,
        swiggyInstamart: Bool = false
    ) -> User {
        User(
            id: id,
            name: "Test",
            isGuest: isGuest,
            features: UserFeatures(pdfImport: pdfImport, swiggyInstamart: swiggyInstamart)
        )
    }

    func testKkbCanDoEverythingExceptImportAPlan() {
        XCTAssertTrue(brand.capabilities.aiGeneration)
        XCTAssertTrue(brand.capabilities.readyMadePlans)
        XCTAssertTrue(brand.capabilities.canEditPlan)
    }

    func testPdfImportIsOffUntilTheScreenExists() {
        // The server can already switch the per-user flag on. Without the brand
        // gate, those users would be offered an action with nothing behind it.
        XCTAssertFalse(brand.capabilities.pdfImport)
        XCTAssertFalse(canImportPlan(brand, for: user(pdfImport: true)))
    }

    func testLabelsSayWhatTheActionDoes() {
        XCTAssertEqual(brand.labels.fillWeek, "Fill empty days")
        XCTAssertEqual(brand.labels.regenerateWeek, "Regenerate week")
        XCTAssertEqual(brand.labels.importPlan, "Import plan")
        XCTAssertEqual(brand.labels.emptyTodayTitle, "Nothing planned for today")
        XCTAssertEqual(brand.labels.emptyTodayCTA, "Plan your week")
        XCTAssertEqual(brand.labels.emptyWeekTitle, "No meals yet this week")
    }

    // MARK: - canImportPlan: brand first, then user

    func testImportNeedsTheUserFlagSwitchedOn() {
        XCTAssertFalse(canImportPlan(withImport, for: user(pdfImport: false)))
        XCTAssertTrue(canImportPlan(withImport, for: user(pdfImport: true)))
    }

    func testGuestsNeverImport() {
        XCTAssertFalse(canImportPlan(withImport, for: user(isGuest: true, pdfImport: true)))
    }

    func testNoUserMeansNoImport() {
        XCTAssertFalse(canImportPlan(withImport, for: nil))
    }

    func testABrandWithoutPdfImportRefusesEvenAFlaggedUser() {
        var noImport = brand
        noImport.capabilities.pdfImport = false
        XCTAssertFalse(canImportPlan(noImport, for: user(pdfImport: true)))
    }

    // MARK: - canGenerate: guests may; the ceiling is checked at the point of use

    func testGuestsMayGenerate() {
        XCTAssertTrue(canGenerate(brand, for: user(isGuest: true)))
    }

    func testNoUserMeansNoGeneration() {
        XCTAssertFalse(canGenerate(brand, for: nil))
    }

    func testABrandWithoutAiGenerationRefusesEveryone() {
        var noAI = brand
        noAI.capabilities.aiGeneration = false
        XCTAssertFalse(canGenerate(noAI, for: user()))
    }

    // MARK: - canEditPlan: the read-only path the nutrition brand needs

    func testEditingFollowsTheBrandAlone() {
        XCTAssertTrue(canEditPlan(brand))
        var readOnly = brand
        readOnly.capabilities.canEditPlan = false
        XCTAssertFalse(canEditPlan(readOnly))
    }

    func testFeaturesDefaultToOffSoAnOldProfileResponseCannotSwitchOneOn() {
        XCTAssertFalse(User(id: "u", name: "T").features.pdfImport)
    }

    func testDecodingAProfileWithoutFeaturesLeavesThemOff() throws {
        let json = Data(#"{"id":"u","name":"T"}"#.utf8)
        let decoded = try JSONDecoder().decode(User.self, from: json)
        XCTAssertFalse(decoded.features.pdfImport)
    }

    func testDecodingAProfileWithFeaturesReadsThem() throws {
        let json = Data(#"{"id":"u","name":"T","features":{"pdfImport":true}}"#.utf8)
        let decoded = try JSONDecoder().decode(User.self, from: json)
        XCTAssertTrue(decoded.features.pdfImport)
    }

    func testDecodingAProfileReadsTheInstamartFlag() throws {
        let json = Data(#"{"id":"u","name":"T","features":{"swiggyInstamart":true}}"#.utf8)
        let decoded = try JSONDecoder().decode(User.self, from: json)
        XCTAssertTrue(decoded.features.swiggyInstamart)
        XCTAssertFalse(decoded.features.pdfImport)
        XCTAssertFalse(User(id: "u", name: "T").features.swiggyInstamart)
    }

    // MARK: - canOrderInstamart: brand, then user, then country — all must agree

    private func shopper() -> User { user(swiggyInstamart: true) }

    func testInstamartIsOnForAFlaggedRegisteredShopperInIndia() {
        XCTAssertTrue(brand.capabilities.instamart)
        XCTAssertTrue(canOrderInstamart(brand: brand, user: shopper(), country: "IN"))
    }

    func testInstamartCountryCheckIgnoresCaseAndWhitespace() {
        XCTAssertTrue(canOrderInstamart(brand: brand, user: shopper(), country: "in"))
        XCTAssertTrue(canOrderInstamart(brand: brand, user: shopper(), country: " IN "))
    }

    /// Instamart serves India only, and the moment before the first geo answer
    /// arrives as nil: both must hide the button rather than guess.
    func testInstamartFailsClosedOutsideIndiaOrWithoutACountry() {
        XCTAssertFalse(canOrderInstamart(brand: brand, user: shopper(), country: "US"))
        XCTAssertFalse(canOrderInstamart(brand: brand, user: shopper(), country: nil))
        XCTAssertFalse(canOrderInstamart(brand: brand, user: shopper(), country: ""))
        XCTAssertFalse(canOrderInstamart(brand: brand, user: shopper(), country: "  "))
    }

    func testInstamartNeedsTheUserFlagSwitchedOn() {
        XCTAssertFalse(canOrderInstamart(brand: brand, user: user(swiggyInstamart: false), country: "IN"))
    }

    /// Every order is an uncancellable COD order on a real Swiggy account.
    func testGuestsNeverOrderFromInstamartWhateverTheirFlagSays() {
        XCTAssertFalse(canOrderInstamart(
            brand: brand, user: user(isGuest: true, swiggyInstamart: true), country: "IN"
        ))
    }

    func testNoUserOrABlankIdMeansNoInstamart() {
        XCTAssertFalse(canOrderInstamart(brand: brand, user: nil, country: "IN"))
        XCTAssertFalse(canOrderInstamart(brand: brand, user: user(id: " ", swiggyInstamart: true), country: "IN"))
    }

    func testABrandWithoutInstamartRefusesEvenAFlaggedIndianShopper() {
        var noInstamart = brand
        noInstamart.capabilities.instamart = false
        XCTAssertFalse(canOrderInstamart(brand: noInstamart, user: shopper(), country: "IN"))
    }

    // MARK: - The generate label

    func testGenerateLabelNamesThePromise() {
        XCTAssertEqual(primaryGenerateLabel(brand, hasEmptySlots: true), "Fill empty days")
        XCTAssertEqual(primaryGenerateLabel(brand, hasEmptySlots: false), "Regenerate week")
    }

    func testGenerateLabelComesFromTheBrandNotTheView() {
        var other = brand
        other.labels.fillWeek = "Complete plan"
        XCTAssertEqual(primaryGenerateLabel(other, hasEmptySlots: true), "Complete plan")
    }
}
