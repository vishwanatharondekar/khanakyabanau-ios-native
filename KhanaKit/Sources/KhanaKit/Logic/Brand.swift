import Foundation

/// The brand seam.
///
/// A second brand is coming — a nutrition product whose users receive a plan
/// rather than compose one — and Khana Kya Banau may itself be retired. Neither
/// is built yet, and this file deliberately ships exactly ONE brand.
///
/// What is not speculative is the rule that makes a brand deletable later:
///
///   Brand differences are expressed as DATA, never as a forked code path.
///   No `if brand.id == .kkb` in feature code, ever. Retiring a brand should be
///   deleting a record and its assets, with no change to any screen.
///
/// Theming is deliberately absent. Colours do not change the shape of a UI;
/// capabilities do.
///
/// Mirrors the webapp's `lib/brand.ts`.
public enum BrandID: String, Sendable {
    case kkb
}

public struct BrandCapabilities: Hashable, Sendable {
    /// Whether the week can be filled by the AI generator at all.
    public var aiGeneration: Bool
    /// Whether importing a plan from a PDF exists in this product. False on iOS
    /// until the import screen is built: the server can already switch the
    /// per-user flag on, and without this gate those users would be offered an
    /// action with nothing behind it.
    public var pdfImport: Bool
    /// Whether the curated public meal plans are offered.
    public var readyMadePlans: Bool
    /// Whether the user may change their own plan. False for a nutrition client
    /// whose plan is authored elsewhere: no cell editing, no replace sheet, no
    /// Clear, no import.
    public var canEditPlan: Bool

    public init(
        aiGeneration: Bool,
        pdfImport: Bool,
        readyMadePlans: Bool,
        canEditPlan: Bool
    ) {
        self.aiGeneration = aiGeneration
        self.pdfImport = pdfImport
        self.readyMadePlans = readyMadePlans
        self.canEditPlan = canEditPlan
    }
}

public struct BrandLabels: Hashable, Sendable {
    /// Primary action when the week still has empty slots.
    public var fillWeek: String
    /// Primary action when the week is full — replaces it wholesale.
    public var regenerateWeek: String
    public var importPlan: String
    /// Shown on Today when there is nothing planned for today.
    public var emptyTodayTitle: String
    /// CTA under `emptyTodayTitle`. Nil when the user cannot act on it.
    public var emptyTodayCTA: String?
    /// Shown on an entirely empty week.
    public var emptyWeekTitle: String
    /// Shown when most of what is left of the week is still blank.
    public var mostlyEmptyWeekTitle: String

    public init(
        fillWeek: String,
        regenerateWeek: String,
        importPlan: String,
        emptyTodayTitle: String,
        emptyTodayCTA: String?,
        emptyWeekTitle: String,
        mostlyEmptyWeekTitle: String
    ) {
        self.fillWeek = fillWeek
        self.regenerateWeek = regenerateWeek
        self.importPlan = importPlan
        self.emptyTodayTitle = emptyTodayTitle
        self.emptyTodayCTA = emptyTodayCTA
        self.emptyWeekTitle = emptyWeekTitle
        self.mostlyEmptyWeekTitle = mostlyEmptyWeekTitle
    }
}

public struct Brand: Hashable, Sendable {
    public var id: BrandID
    public var capabilities: BrandCapabilities
    public var labels: BrandLabels

    public init(id: BrandID, capabilities: BrandCapabilities, labels: BrandLabels) {
        self.id = id
        self.capabilities = capabilities
        self.labels = labels
    }

    public static let current = Brand(
        id: .kkb,
        capabilities: BrandCapabilities(
            aiGeneration: true,
            // Not built on iOS yet. One boolean is the whole of what turns it
            // on when it is — no screen knows this flag exists.
            pdfImport: false,
            readyMadePlans: true,
            canEditPlan: true
        ),
        labels: BrandLabels(
            fillWeek: "Fill empty days",
            regenerateWeek: "Regenerate week",
            importPlan: "Import plan",
            emptyTodayTitle: "Nothing planned for today",
            emptyTodayCTA: "Plan your week",
            emptyWeekTitle: "No meals yet this week",
            mostlyEmptyWeekTitle: "Most of this week is still empty"
        )
    )
}

/// Brand first, then user. The brand flag says the feature exists in this
/// product; the user flag says it is switched on for this person. The server
/// enforces the user half independently — this is the UI half and is not a
/// security boundary.
///
/// Both halves are live logic even though the brand half is currently false on
/// iOS: the user half is what the web app runs on today, and it is what this
/// returns to as soon as the import screen exists.
public func canImportPlan(_ brand: Brand, for user: User?) -> Bool {
    guard brand.capabilities.pdfImport else { return false }
    guard let user, !user.id.isEmpty else { return false }
    guard !user.isGuest else { return false }
    return user.features.pdfImport
}

/// Guests may generate — their ceiling is the separate guest usage limit, which
/// is checked at the point of use, not here.
public func canGenerate(_ brand: Brand, for user: User?) -> Bool {
    guard brand.capabilities.aiGeneration else { return false }
    guard let user, !user.id.isEmpty else { return false }
    return true
}

public func canEditPlan(_ brand: Brand) -> Bool {
    brand.capabilities.canEditPlan
}

/// What the generate action calls itself. Filling gaps and replacing a week are
/// different promises, and a single "Generate with AI" made both and named
/// neither — the AI is not the point, the outcome is.
public func primaryGenerateLabel(_ brand: Brand, hasEmptySlots: Bool) -> String {
    hasEmptySlots ? brand.labels.fillWeek : brand.labels.regenerateWeek
}
