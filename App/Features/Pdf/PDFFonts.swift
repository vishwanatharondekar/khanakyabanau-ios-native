import CoreText
import Foundation
import KhanaKit
import UIKit

/// Fonts for PDF export.
///
/// The ten Noto faces are copied from the web app's `public/fonts` and are the same
/// files its server-side generator uses, so Devanagari, Bengali, Tamil and the rest
/// render identically across platforms. They are registered lazily rather than
/// listed in `UIAppFonts`, because ~1.9 MB of Indic fonts should not be paid for at
/// launch by users who never export a PDF.
enum PDFFonts {
    private static var registeredFiles = Set<String>()

    /// Which Noto face covers a given language's script.
    private static func fileName(for language: String) -> String? {
        switch SupportedLanguage.fromCode(language) {
        case .english: nil
        case .hindi, .marathi: "NotoSansDevanagari-Regular"
        case .bengali: "NotoSansBengali-Regular"
        case .tamil: "NotoSansTamil-Regular"
        case .telugu: "NotoSansTelugu-Regular"
        case .kannada: "NotoSansKannada-Regular"
        case .malayalam: "NotoSansMalayalam-Regular"
        case .gujarati: "NotoSansGujarati-Regular"
        case .punjabi: "NotoSansGurmukhi-Regular"
        }
    }

    /// Resources normally land in the bundle root, but a folder reference would put
    /// them under `Fonts/`. Checking both keeps this working either way.
    private static func url(for fileName: String) -> URL? {
        Bundle.main.url(forResource: fileName, withExtension: "ttf")
            ?? Bundle.main.url(forResource: fileName, withExtension: "ttf", subdirectory: "Fonts")
    }

    @discardableResult
    private static func register(_ fileName: String) -> Bool {
        if registeredFiles.contains(fileName) { return true }
        guard let url = url(for: fileName) else { return false }
        // A failure here is almost always "already registered", which is fine —
        // either way the font is usable, so record it and move on.
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        registeredFiles.insert(fileName)
        return true
    }

    /// The PostScript name a registered file exposes, cached after first lookup.
    private static var postScriptNames: [String: String] = [:]

    private static func postScriptName(for fileName: String) -> String? {
        if let cached = postScriptNames[fileName] { return cached }
        guard let url = url(for: fileName),
              let dataProvider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(dataProvider),
              let name = cgFont.postScriptName as String?
        else { return nil }
        postScriptNames[fileName] = name
        return name
    }

    /// A font that can render `language`'s script at `size`.
    ///
    /// Falls back to the system face when a script font is missing — a PDF in the
    /// wrong typeface is far better than a PDF of empty boxes or no PDF at all.
    static func font(for language: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        guard let fileName = fileName(for: language) else {
            return .systemFont(ofSize: size, weight: weight)
        }
        register(fileName)
        if let psName = postScriptName(for: fileName), let font = UIFont(name: psName, size: size) {
            return font
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    /// Latin text inside a translated document still uses the system face; only
    /// translated strings need the script font.
    static func latin(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }
}
