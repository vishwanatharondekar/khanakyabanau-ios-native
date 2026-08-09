import KhanaKit
import PDFKit
import XCTest
@testable import KhanaKyaBanau

/// The PDF exporters are pure rendering, so they can be driven directly rather
/// than through a share sheet. These assert the documents are structurally valid
/// and that Indic scripts actually produce glyphs rather than blank boxes.
@MainActor
final class PDFExportTests: XCTestCase {

    private let week = "2026-08-03"

    private func fullWeekPlan() -> MealPlan {
        var plan = MealPlan.empty(weekStartDate: week)
        for (index, day) in DayOfWeek.allCases.enumerated() {
            plan.meals[day.key] = DayMeals(
                breakfast: Meal(name: "Poha \(index)", calories: 250),
                lunch: Meal(
                    name: "Rajma Chawal \(index)",
                    calories: 520,
                    prep: MealPrep(
                        steps: [PrepStep(text: "Soak rajma", leadTimeMinutes: 480, category: .soak)],
                        maxLeadTimeMinutes: 480
                    ),
                    prepFor: "Rajma Chawal \(index)",
                    videoUrl: "https://youtu.be/dQw4w9WgXcQ"
                ),
                dinner: Meal(name: "Varan Bhaat \(index)")
            )
        }
        return plan
    }

    private func document(at url: URL) throws -> PDFDocument {
        try XCTUnwrap(PDFDocument(url: url), "Rendered file is not a readable PDF")
    }

    // MARK: - Meal plan

    func testMealPlanPDFRendersEveryDayAcrossPages() throws {
        let url = try XCTUnwrap(
            MealPlanPDF.render(
                plan: fullWeekPlan(),
                enabledTypes: [.breakfast, .lunch, .dinner],
                weekRangeLabel: "Aug 3–9, 2026",
                translations: .empty,
                language: "en",
                videoURL: { $0.videoUrl }
            ),
            "Meal plan PDF was not produced"
        )
        let pdf = try document(at: url)

        // Seven day cards do not fit on one phone-sized page.
        XCTAssertGreaterThan(pdf.pageCount, 1, "A full week should paginate")

        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()
        XCTAssertTrue(text.contains("Weekly Meal Plan"))
        XCTAssertTrue(text.contains("Aug 3–9, 2026"))
        for day in DayOfWeek.allCases {
            XCTAssertTrue(
                text.localizedCaseInsensitiveContains(day.displayName),
                "\(day.displayName) is missing from the document"
            )
        }
        XCTAssertTrue(text.contains("Poha 0"), "Dishes are missing")
        XCTAssertTrue(text.contains("250 kcal"), "Calories are missing")
    }

    /// Dishes with a resolved video get a tappable link annotation.
    func testMealPlanPDFAddsLinkAnnotationsForVideos() throws {
        let url = try XCTUnwrap(
            MealPlanPDF.render(
                plan: fullWeekPlan(),
                enabledTypes: [.breakfast, .lunch, .dinner],
                weekRangeLabel: "Aug 3–9, 2026",
                translations: .empty,
                language: "en",
                videoURL: { $0.videoUrl }
            )
        )
        let pdf = try document(at: url)
        let annotations = (0..<pdf.pageCount).flatMap { pdf.page(at: $0)?.annotations ?? [] }
        XCTAssertFalse(annotations.isEmpty, "Expected tappable recipe-video links")
    }

    func testMealPlanPDFHandlesAnEmptyWeek() throws {
        let url = try XCTUnwrap(
            MealPlanPDF.render(
                plan: .empty(weekStartDate: week),
                enabledTypes: [.breakfast, .lunch, .dinner],
                weekRangeLabel: "Aug 3–9, 2026",
                translations: .empty,
                language: "en",
                videoURL: { _ in nil }
            ),
            "An empty week must still export"
        )
        XCTAssertGreaterThan(try document(at: url).pageCount, 0)
    }

    // MARK: - Shopping list

    private func scopedList() -> ScopedShoppingList {
        ScopedShoppingList(
            categorized: [
                CategorySection(name: "Vegetables", items: [
                    Ingredient(name: "Onion", amount: 300, unit: "g"),
                    Ingredient(name: "Tomato", amount: 2, unit: "pieces"),
                ]),
                CategorySection(name: "Grains & Pulses", items: [
                    Ingredient(name: "Rajma", amount: 1.2, unit: "kg"),
                ]),
            ],
            ingredients: ["Onion", "Tomato", "Rajma"],
            weights: [:]
        )
    }

    func testShoppingListPDFIncludesQuantitiesAndCategories() throws {
        let url = try XCTUnwrap(
            ShoppingListPDF.render(
                scoped: scopedList(),
                haveAlready: [],
                scopeLabel: "Aug 3 – Aug 5",
                translations: .empty,
                language: "en"
            )
        )
        let pdf = try document(at: url)
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()

        XCTAssertTrue(text.contains("Shopping List"))
        XCTAssertTrue(text.contains("Aug 3 – Aug 5"))
        XCTAssertTrue(text.contains("Vegetables"))
        XCTAssertTrue(text.contains("Onion"))
        XCTAssertTrue(text.contains("300 g"))
        XCTAssertTrue(text.contains("1.2 kg"))
        XCTAssertTrue(text.contains("3 items"))
    }

    /// The whole point of the document is the trip to the shop, so anything the
    /// user already has must not be printed.
    func testShoppingListPDFOmitsTickedItemsAndEmptiedCategories() throws {
        let url = try XCTUnwrap(
            ShoppingListPDF.render(
                scoped: scopedList(),
                haveAlready: ["onion", "tomato"],
                scopeLabel: "Aug 3",
                translations: .empty,
                language: "en"
            )
        )
        let text = (0..<(try document(at: url).pageCount))
            .compactMap { try? document(at: url).page(at: $0)?.string }
            .compactMap { $0 }
            .joined()

        XCTAssertFalse(text.contains("Onion"), "A ticked item was printed")
        XCTAssertFalse(text.contains("Vegetables"), "An emptied category was printed")
        XCTAssertTrue(text.contains("Rajma"))
        XCTAssertTrue(text.contains("1 item"), "Count should be singular and exclude ticked items")
    }

    func testShoppingListPDFHandlesAnEmptyList() throws {
        let url = try XCTUnwrap(
            ShoppingListPDF.render(
                scoped: ScopedShoppingList(),
                haveAlready: [],
                scopeLabel: "Aug 3",
                translations: .empty,
                language: "en"
            )
        )
        let pdf = try document(at: url)
        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertTrue(
            (pdf.page(at: 0)?.string ?? "").contains("nothing left to buy")
        )
    }

    // MARK: - Indic scripts

    /// A Devanagari PDF that renders empty boxes is worse than an English one, so
    /// this checks the bundled Noto face is actually found and used.
    func testHindiExportUsesADevanagariFace() {
        let font = PDFFonts.font(for: "hi", size: 12)
        XCTAssertFalse(
            font.fontName.hasPrefix(".SFUI"),
            "Hindi fell back to the system font — the Noto Devanagari file is missing from the bundle"
        )
        XCTAssertTrue(
            font.fontName.localizedCaseInsensitiveContains("Devanagari"),
            "Expected a Devanagari face, got \(font.fontName)"
        )
    }

    func testEveryNonEnglishLanguageResolvesAScriptFont() {
        for language in SupportedLanguage.allCases where language != .english {
            let font = PDFFonts.font(for: language.code, size: 12)
            XCTAssertFalse(
                font.fontName.hasPrefix(".SFUI"),
                "\(language.displayName) has no bundled script font"
            )
        }
    }

    func testTranslatedShoppingListRendersTranslatedText() throws {
        let hindi = Translations(map: ["onion": "प्याज", "vegetables": "सब्ज़ियाँ"])
        let url = try XCTUnwrap(
            ShoppingListPDF.render(
                scoped: scopedList(),
                haveAlready: [],
                scopeLabel: "Aug 3",
                translations: hindi,
                language: "hi"
            )
        )
        let pdf = try document(at: url)
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()
        XCTAssertTrue(text.contains("प्याज"), "Translated ingredient did not render")
        XCTAssertFalse(text.contains("Onion"), "Untranslated name leaked through")
    }
}
