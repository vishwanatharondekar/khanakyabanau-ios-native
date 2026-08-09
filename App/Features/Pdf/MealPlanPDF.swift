import KhanaKit
import PDFKit
import UIKit

/// Shared drawing helpers for both exporters.
enum PDFLayout {
    /// Phone-shaped pages, matching the web app's mobile-optimised generator and
    /// Android's port of it — these documents are read on a phone far more often
    /// than they are printed.
    static let pageSize = CGSize(width: 414, height: 896)
    static let margin: CGFloat = 24

    static func draw(
        _ text: String,
        at point: CGPoint,
        width: CGFloat,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ]
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        (text as NSString).draw(
            with: CGRect(x: point.x, y: point.y, width: width, height: ceil(bounding.height)),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return ceil(bounding.height)
    }

    static func height(
        of text: String,
        width: CGFloat,
        font: UIFont
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return ceil((text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph],
            context: nil
        ).height)
    }

    static func roundedRect(
        _ rect: CGRect,
        radius: CGFloat,
        fill: UIColor,
        stroke: UIColor? = nil,
        lineWidth: CGFloat = 1
    ) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        fill.setFill()
        path.fill()
        if let stroke {
            stroke.setStroke()
            path.lineWidth = lineWidth
            path.stroke()
        }
    }

    static func gradient(in rect: CGRect, colors: [UIColor], context: CGContext) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors.map(\.cgColor) as CFArray,
            locations: [0, 1]
        ) else { return }
        context.saveGState()
        context.addRect(rect)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
        )
        context.restoreGState()
    }

    static func writeToTemporary(_ data: Data, named name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// The brand palette as `UIColor`, for PDF drawing.
enum PDFColors {
    static let cream50 = UIColor(red: 0xFE / 255, green: 0xFA / 255, blue: 0xF3 / 255, alpha: 1)
    static let cream100 = UIColor(red: 0xFD / 255, green: 0xF5 / 255, blue: 0xE6 / 255, alpha: 1)
    static let cream200 = UIColor(red: 0xFB / 255, green: 0xEC / 255, blue: 0xD0 / 255, alpha: 1)
    static let cream300 = UIColor(red: 0xF7 / 255, green: 0xDF / 255, blue: 0xAE / 255, alpha: 1)
    static let terracotta300 = UIColor(red: 0xEB / 255, green: 0x9F / 255, blue: 0x65 / 255, alpha: 1)
    static let terracotta400 = UIColor(red: 0xE0 / 255, green: 0x7A / 255, blue: 0x3F / 255, alpha: 1)
    static let terracotta500 = UIColor(red: 0xD5 / 255, green: 0x5F / 255, blue: 0x24 / 255, alpha: 1)
    static let terracotta600 = UIColor(red: 0xB8 / 255, green: 0x48 / 255, blue: 0x1D / 255, alpha: 1)
    static let sage100 = UIColor(red: 0xE1 / 255, green: 0xEC / 255, blue: 0xDF / 255, alpha: 1)
    static let sage500 = UIColor(red: 0x57 / 255, green: 0x85 / 255, blue: 0x5A / 255, alpha: 1)
    static let sage700 = UIColor(red: 0x37 / 255, green: 0x55 / 255, blue: 0x3B / 255, alpha: 1)
    static let marigold100 = UIColor(red: 0xFE / 255, green: 0xF0 / 255, blue: 0xC7 / 255, alpha: 1)
    static let marigold500 = UIColor(red: 0xF2 / 255, green: 0x93 / 255, blue: 0x0B / 255, alpha: 1)
    static let marigold600 = UIColor(red: 0xD6 / 255, green: 0x71 / 255, blue: 0x05 / 255, alpha: 1)
    static let marigold700 = UIColor(red: 0xB1 / 255, green: 0x51 / 255, blue: 0x08 / 255, alpha: 1)
    static let ink600 = UIColor(red: 0x5F / 255, green: 0x4A / 255, blue: 0x3A / 255, alpha: 1)
    static let ink700 = UIColor(red: 0x4A / 255, green: 0x3A / 255, blue: 0x2D / 255, alpha: 1)
    static let ink900 = UIColor(red: 0x2A / 255, green: 0x1F / 255, blue: 0x17 / 255, alpha: 1)
    static let link = UIColor(red: 0.13, green: 0.36, blue: 0.78, alpha: 1)
}

/// The weekly menu as a shareable PDF: one card per day, never split across a page
/// break, with tappable links on dishes that have a saved recipe video.
enum MealPlanPDF {

    @MainActor
    static func render(
        plan: MealPlan,
        enabledTypes: [MealType],
        weekRangeLabel: String,
        translations: Translations,
        language: String,
        videoURL: (Meal) -> String?
    ) -> URL? {
        let pageRect = CGRect(origin: .zero, size: PDFLayout.pageSize)
        let contentWidth = pageRect.width - PDFLayout.margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        // Link targets are collected as the cards are drawn and applied afterwards,
        // because a PDF annotation belongs to a finished page.
        var links: [(page: Int, rect: CGRect, url: URL)] = []

        let data = renderer.pdfData { ctx in
            var pageIndex = 0
            ctx.beginPage()
            var y = drawHeader(
                in: pageRect, weekRangeLabel: weekRangeLabel, context: ctx.cgContext
            )

            for day in DayOfWeek.allCases {
                let meals = plan.meals(for: day)
                let cardHeight = dayCardHeight(
                    meals: meals,
                    enabledTypes: enabledTypes,
                    width: contentWidth,
                    translations: translations,
                    language: language
                )

                // A day card is a unit; splitting one across pages makes the
                // document much harder to cook from.
                if y + cardHeight > pageRect.height - PDFLayout.margin {
                    drawFooter(in: pageRect)
                    ctx.beginPage()
                    pageIndex += 1
                    y = PDFLayout.margin
                }

                let cardRect = CGRect(
                    x: PDFLayout.margin, y: y, width: contentWidth, height: cardHeight
                )
                drawDayCard(
                    rect: cardRect,
                    day: day,
                    meals: meals,
                    enabledTypes: enabledTypes,
                    translations: translations,
                    language: language,
                    videoURL: videoURL,
                    pageIndex: pageIndex,
                    links: &links
                )
                y += cardHeight + 12
            }
            drawFooter(in: pageRect)
        }

        guard let document = PDFDocument(data: data) else {
            return PDFLayout.writeToTemporary(data, named: "khanakyabanau-meal-plan")
        }
        for link in links {
            guard let page = document.page(at: link.page) else { continue }
            let annotation = PDFAnnotation(
                bounds: link.rect, forType: .link, withProperties: nil
            )
            annotation.action = PDFActionURL(url: link.url)
            page.addAnnotation(annotation)
        }
        guard let linked = document.dataRepresentation() else {
            return PDFLayout.writeToTemporary(data, named: "khanakyabanau-meal-plan")
        }
        return PDFLayout.writeToTemporary(linked, named: "khanakyabanau-meal-plan")
    }

    // MARK: - Sections

    private static func drawHeader(
        in pageRect: CGRect,
        weekRangeLabel: String,
        context: CGContext
    ) -> CGFloat {
        let headerRect = CGRect(x: 0, y: 0, width: pageRect.width, height: 128)
        PDFLayout.gradient(
            in: headerRect,
            colors: [PDFColors.terracotta500, PDFColors.marigold500],
            context: context
        )

        var y: CGFloat = 30
        y += PDFLayout.draw(
            "KHANA KYA BANAU",
            at: CGPoint(x: PDFLayout.margin, y: y),
            width: pageRect.width - PDFLayout.margin * 2,
            font: PDFFonts.latin(size: 11, weight: .semibold),
            color: UIColor.white.withAlphaComponent(0.9)
        )
        y += 4
        y += PDFLayout.draw(
            "Weekly Meal Plan",
            at: CGPoint(x: PDFLayout.margin, y: y),
            width: pageRect.width - PDFLayout.margin * 2,
            font: PDFFonts.latin(size: 26, weight: .bold),
            color: .white
        )
        y += 10

        // Week range in a translucent pill.
        let pillFont = PDFFonts.latin(size: 12, weight: .semibold)
        let pillWidth = (weekRangeLabel as NSString)
            .size(withAttributes: [.font: pillFont]).width + 24
        let pillRect = CGRect(x: PDFLayout.margin, y: y, width: pillWidth, height: 26)
        PDFLayout.roundedRect(
            pillRect, radius: 13, fill: UIColor.white.withAlphaComponent(0.25)
        )
        _ = PDFLayout.draw(
            weekRangeLabel,
            at: CGPoint(x: pillRect.minX + 12, y: pillRect.minY + 6),
            width: pillWidth,
            font: pillFont,
            color: .white
        )
        return headerRect.maxY + 16
    }

    private static func drawFooter(in pageRect: CGRect) {
        _ = PDFLayout.draw(
            "khanakyabanau.in",
            at: CGPoint(x: PDFLayout.margin, y: pageRect.height - 28),
            width: pageRect.width - PDFLayout.margin * 2,
            font: PDFFonts.latin(size: 9),
            color: PDFColors.ink600.withAlphaComponent(0.6),
            alignment: .center
        )
    }

    private static func rowHeight(
        name: String,
        width: CGFloat,
        translations: Translations,
        language: String
    ) -> CGFloat {
        let nameFont = PDFFonts.font(for: language, size: 13, weight: .semibold)
        let text = translations(name)
        return max(34, PDFLayout.height(of: text, width: width - 96, font: nameFont) + 22)
    }

    private static func dayCardHeight(
        meals: DayMeals,
        enabledTypes: [MealType],
        width: CGFloat,
        translations: Translations,
        language: String
    ) -> CGFloat {
        var height: CGFloat = 44 // day header
        for type in enabledTypes {
            let meal = meals[type]
            height += rowHeight(
                name: meal.isEmpty ? "—" : meal.name,
                width: width,
                translations: translations,
                language: language
            )
        }
        return height + 12
    }

    private static func drawDayCard(
        rect: CGRect,
        day: DayOfWeek,
        meals: DayMeals,
        enabledTypes: [MealType],
        translations: Translations,
        language: String,
        videoURL: (Meal) -> String?,
        pageIndex: Int,
        links: inout [(page: Int, rect: CGRect, url: URL)]
    ) {
        PDFLayout.roundedRect(
            rect, radius: 14, fill: PDFColors.cream50,
            stroke: PDFColors.cream300, lineWidth: 1
        )

        var y = rect.minY + 12
        // Day names stay English: they pair with the server's own day keys and the
        // date pills, and mixing scripts mid-line reads badly.
        _ = PDFLayout.draw(
            day.displayName.uppercased(),
            at: CGPoint(x: rect.minX + 14, y: y),
            width: rect.width - 28,
            font: PDFFonts.latin(size: 12, weight: .bold),
            color: PDFColors.terracotta600
        )
        y += 22

        for type in enabledTypes {
            let meal = meals[type]
            let height = rowHeight(
                name: meal.isEmpty ? "—" : meal.name,
                width: rect.width,
                translations: translations,
                language: language
            )

            // Per-course accent stripe.
            let accent = accentColor(for: type)
            PDFLayout.roundedRect(
                CGRect(x: rect.minX + 14, y: y + 4, width: 3, height: height - 12),
                radius: 1.5, fill: accent
            )

            _ = PDFLayout.draw(
                type.displayName.uppercased(),
                at: CGPoint(x: rect.minX + 26, y: y + 2),
                width: 90,
                font: PDFFonts.latin(size: 8, weight: .semibold),
                color: PDFColors.ink600
            )

            let nameOrigin = CGPoint(x: rect.minX + 26, y: y + 14)
            let nameWidth = rect.width - 96
            let hasVideo = !meal.isEmpty && videoURL(meal) != nil

            if meal.isEmpty {
                _ = PDFLayout.draw(
                    "—",
                    at: nameOrigin, width: nameWidth,
                    font: PDFFonts.font(for: language, size: 13),
                    color: PDFColors.ink600.withAlphaComponent(0.5)
                )
            } else {
                let drawn = PDFLayout.draw(
                    translations(meal.name),
                    at: nameOrigin, width: nameWidth,
                    font: PDFFonts.font(for: language, size: 13, weight: .semibold),
                    color: hasVideo ? PDFColors.link : PDFColors.ink900
                )

                if hasVideo, let raw = videoURL(meal), let url = URL(string: raw) {
                    // A circular play badge, and the whole row becomes tappable.
                    let badge = CGRect(x: rect.maxX - 40, y: y + 8, width: 22, height: 22)
                    PDFLayout.roundedRect(badge, radius: 11, fill: PDFColors.terracotta500)
                    _ = PDFLayout.draw(
                        "▶",
                        at: CGPoint(x: badge.minX + 6, y: badge.minY + 4),
                        width: 22,
                        font: PDFFonts.latin(size: 10, weight: .bold),
                        color: .white
                    )
                    // PDF annotations use a bottom-left origin, so the y flips.
                    let linkRect = CGRect(
                        x: nameOrigin.x,
                        y: PDFLayout.pageSize.height - (nameOrigin.y + drawn),
                        width: rect.width - 40,
                        height: drawn + 8
                    )
                    links.append((pageIndex, linkRect, url))
                }

                if let calories = meal.calories {
                    _ = PDFLayout.draw(
                        "\(calories) kcal",
                        at: CGPoint(x: rect.minX + 26, y: y + 14 + drawn + 1),
                        width: nameWidth,
                        font: PDFFonts.latin(size: 9),
                        color: PDFColors.marigold700
                    )
                }
            }
            y += height
        }
    }

    private static func accentColor(for type: MealType) -> UIColor {
        switch type {
        case .breakfast: PDFColors.marigold500
        case .morningSnack: PDFColors.sage500
        case .lunch: PDFColors.terracotta500
        case .eveningSnack: PDFColors.terracotta300
        case .dinner: PDFColors.terracotta600
        }
    }
}
