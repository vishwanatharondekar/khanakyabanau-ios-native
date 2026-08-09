import KhanaKit
import UIKit

/// The scoped shopping list as a PDF, with items the user already has omitted —
/// the point of the document is the trip to the market, not an inventory.
enum ShoppingListPDF {

    @MainActor
    static func render(
        scoped: ScopedShoppingList,
        haveAlready: Set<String>,
        scopeLabel: String,
        translations: Translations,
        language: String,
        /// normalized ingredient name -> the dishes it is needed for.
        ingredientMeals: [String: [String]] = [:]
    ) -> URL? {
        let pageRect = CGRect(origin: .zero, size: PDFLayout.pageSize)
        let contentWidth = pageRect.width - PDFLayout.margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        // Categories that end up entirely ticked off are dropped, rather than
        // printed as empty headings.
        let sections: [(name: String, items: [Ingredient])] = scoped.categorized.compactMap {
            section in
            let needed = section.items.filter {
                !haveAlready.contains(ShoppingScope.normalizeIngredientName($0.name))
            }
            return needed.isEmpty ? nil : (section.name, needed)
        }

        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y = drawHeader(
                in: pageRect, scopeLabel: scopeLabel,
                itemCount: sections.reduce(0) { $0 + $1.items.count },
                context: ctx.cgContext
            )

            if sections.isEmpty {
                _ = PDFLayout.draw(
                    "Everything's covered — nothing left to buy.",
                    at: CGPoint(x: PDFLayout.margin, y: y + 20),
                    width: contentWidth,
                    font: PDFFonts.latin(size: 13),
                    color: PDFColors.ink600,
                    alignment: .center
                )
                return
            }

            for section in sections {
                let headerHeight: CGFloat = 30
                if y + headerHeight + 26 > pageRect.height - PDFLayout.margin {
                    ctx.beginPage()
                    y = PDFLayout.margin
                }

                // Category heading with its colour dot.
                let dot = CGRect(x: PDFLayout.margin, y: y + 6, width: 7, height: 7)
                PDFLayout.roundedRect(
                    dot, radius: 3.5, fill: accentColor(for: section.name)
                )
                _ = PDFLayout.draw(
                    translations(section.name),
                    at: CGPoint(x: PDFLayout.margin + 14, y: y),
                    width: contentWidth - 14,
                    font: PDFFonts.font(for: language, size: 13, weight: .bold),
                    color: PDFColors.terracotta600
                )
                y += 20
                PDFColors.cream300.setFill()
                UIBezierPath(rect: CGRect(
                    x: PDFLayout.margin, y: y, width: contentWidth, height: 1
                )).fill()
                y += 8

                for item in section.items {
                    // Every other surface title-cases these; the server stores them
                    // however the model emitted them.
                    let englishName = ShoppingScope.titleCaseIngredient(item.name)
                    let translated = translations(item.name)
                    let name = translated == item.name ? englishName : translated
                    let dishes = ingredientMeals[
                        ShoppingScope.normalizeIngredientName(item.name)
                    ] ?? []
                    let amount = ShoppingScope.formatAmount(
                        IngredientAmount(amount: item.amount, unit: item.unit)
                    )
                    let font = PDFFonts.font(for: language, size: 12)
                    let contextFont = PDFFonts.latin(size: 9)
                    let context = dishes.isEmpty
                        ? ""
                        : "for " + dishes.prefix(3).joined(separator: " · ")
                        + (dishes.count > 3 ? " +\(dishes.count - 3) more" : "")
                    var rowHeight = max(
                        22, PDFLayout.height(of: name, width: contentWidth - 100, font: font) + 8
                    )
                    if !context.isEmpty {
                        rowHeight += PDFLayout.height(
                            of: context, width: contentWidth - 100, font: contextFont
                        ) + 2
                    }

                    if y + rowHeight > pageRect.height - PDFLayout.margin {
                        ctx.beginPage()
                        y = PDFLayout.margin
                    }

                    // An empty checkbox: this is a list to work through in a shop.
                    let box = CGRect(x: PDFLayout.margin + 2, y: y + 3, width: 11, height: 11)
                    PDFLayout.roundedRect(
                        box, radius: 3, fill: .white,
                        stroke: PDFColors.terracotta300, lineWidth: 1
                    )

                    let nameHeight = PDFLayout.draw(
                        name,
                        at: CGPoint(x: PDFLayout.margin + 22, y: y),
                        width: contentWidth - 100,
                        font: font,
                        color: PDFColors.ink900
                    )
                    if !context.isEmpty {
                        _ = PDFLayout.draw(
                            context,
                            at: CGPoint(x: PDFLayout.margin + 22, y: y + nameHeight + 1),
                            width: contentWidth - 100,
                            font: contextFont,
                            color: PDFColors.ink600
                        )
                    }
                    if !amount.isEmpty {
                        _ = PDFLayout.draw(
                            amount,
                            at: CGPoint(x: pageRect.width - PDFLayout.margin - 76, y: y),
                            width: 76,
                            font: PDFFonts.latin(size: 11, weight: .semibold),
                            color: PDFColors.ink600,
                            alignment: .right
                        )
                    }
                    y += rowHeight
                }
                y += 10
            }
        }

        return PDFLayout.writeToTemporary(data, named: "khanakyabanau-shopping-list")
    }

    private static func drawHeader(
        in pageRect: CGRect,
        scopeLabel: String,
        itemCount: Int,
        context: CGContext
    ) -> CGFloat {
        let headerRect = CGRect(x: 0, y: 0, width: pageRect.width, height: 108)
        PDFLayout.gradient(
            in: headerRect,
            colors: [PDFColors.sage500, PDFColors.terracotta500],
            context: context
        )

        var y: CGFloat = 26
        y += PDFLayout.draw(
            "KHANA KYA BANAU",
            at: CGPoint(x: PDFLayout.margin, y: y),
            width: pageRect.width - PDFLayout.margin * 2,
            font: PDFFonts.latin(size: 11, weight: .semibold),
            color: UIColor.white.withAlphaComponent(0.9)
        )
        y += 4
        y += PDFLayout.draw(
            "Shopping List",
            at: CGPoint(x: PDFLayout.margin, y: y),
            width: pageRect.width - PDFLayout.margin * 2,
            font: PDFFonts.latin(size: 24, weight: .bold),
            color: .white
        )
        y += 4
        let itemLabel = "\(itemCount) item\(itemCount == 1 ? "" : "s")"
        _ = PDFLayout.draw(
            scopeLabel.isEmpty ? itemLabel : "\(scopeLabel)  ·  \(itemLabel)",
            at: CGPoint(x: PDFLayout.margin, y: y),
            width: pageRect.width - PDFLayout.margin * 2,
            font: PDFFonts.latin(size: 12),
            color: UIColor.white.withAlphaComponent(0.9)
        )
        return headerRect.maxY + 18
    }

    /// The same mapping the on-screen sheet uses, so an exported list does not
    /// recolour the headings the user just looked at.
    private static func accentColor(for category: String) -> UIColor {
        switch category {
        case "Vegetables": PDFColors.sage500
        case "Fruits": PDFColors.marigold500
        case "Dairy & Eggs": PDFColors.terracotta400
        case "Meat & Seafood": PDFColors.terracotta500
        case "Grains & Pulses": PDFColors.marigold600
        case "Spices & Herbs": PDFColors.terracotta400
        case "Pantry Items": PDFColors.ink700
        default: PDFColors.ink600
        }
    }
}
