import XCTest
@testable import KhanaKit

/// Port-parity tests for the brand seam. Mirrors the webapp's `lib/brand.ts`;
/// when in doubt, that file is the specification.
final class BrandTests: XCTestCase {

    private let brand = Brand.current

    private func user(isGuest: Bool = false, pdfImport: Bool = false) -> User {
        User(
            id: "user_1",
            name: "Test",
            isGuest: isGuest,
            features: UserFeatures(pdfImport: pdfImport)
        )
    }

    func testKkbHasEveryCapabilitySwitchedOn() {
        XCTAssertTrue(brand.capabilities.aiGeneration)
        XCTAssertTrue(brand.capabilities.pdfImport)
        XCTAssertTrue(brand.capabilities.readyMadePlans)
        XCTAssertTrue(brand.capabilities.canEditPlan)
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
        XCTAssertFalse(canImportPlan(brand, for: user(pdfImport: false)))
        XCTAssertTrue(canImportPlan(brand, for: user(pdfImport: true)))
    }

    func testGuestsNeverImport() {
        XCTAssertFalse(canImportPlan(brand, for: user(isGuest: true, pdfImport: true)))
    }

    func testNoUserMeansNoImport() {
        XCTAssertFalse(canImportPlan(brand, for: nil))
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
