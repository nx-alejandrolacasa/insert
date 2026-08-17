import AppKit
import CoreText
import SwiftUI

// MARK: - Registration

/// The two typefaces Insert **bundles**, and the only files in the app that
/// aren't Apple's.
///
/// This is a knowing departure from "no third-party dependencies — system
/// frameworks only": the rule was about *code*, and these are two SIL Open Font
/// License 1.1 font files with no build step, no package manager and nothing
/// executable in them. They ship inside the bundle and are registered
/// **`.process`**-scoped, so they exist for this app and are never installed on
/// the user's Mac. The licences travel with them (`SpaceGrotesk-OFL.txt`,
/// `IBMPlexMono-OFL.txt`, shown in Settings → General → "Font licences") because
/// the OFL requires the copyright notice and licence to be distributed with the
/// fonts.
///
/// - **Space Grotesk** is the user-selectable "Grotesk" face (`Typeface`) and
///   the default for new installs. Shipped as the **variable** file rather than
///   four statics: the four static instances Florian Karsten publishes are
///   Light / Regular / Medium / Bold, with **no SemiBold**, which is the weight
///   the plan's 16pt titles want. The variable font's `wght` axis runs 300–700
///   continuously, so asking for 600 through
///   `kCTFontVariationAttribute` gets a real SemiBold instance
///   (verified: it resolves to a distinct face, `SpaceGrotesk-Light_wght2580000`,
///   not to Bold) — one 137KB file instead of four totalling 460KB, and a weight
///   the statics can't give at all.
/// - **IBM Plex Mono** is *not* a body option. It is the app's numeral and label
///   face: the column bands' counts, the cards' timestamps and the uppercase
///   type labels. Three statics, Regular / Medium / SemiBold.
///
/// Space Grotesk is **Latin-only** (measured: no Cyrillic, Greek or CJK), and
/// nothing special is needed for that — CoreText's own cascade substitutes
/// per glyph, so a Cyrillic title under Grotesk falls through to the system face
/// a character at a time rather than switching the whole string.
enum BundledFonts {
    /// The families, by the names CoreText publishes once the files are
    /// registered — *not* the PostScript names, which are worth a warning. The
    /// variable file's members come back as `SpaceGrotesk-Light_Regular` and
    /// friends (an artifact of its default instance being Light), and Plex
    /// Mono's are abbreviated — `IBMPlexMono-Medm`, `IBMPlexMono-SmBld`. So
    /// `NSFont(name: "SpaceGrotesk-SemiBold")` and
    /// `NSFont(name: "IBMPlexMono-Medium")` are both **nil**. Everything below
    /// goes through the family plus a weight instead, which is stable.
    static let grotesk = "Space Grotesk"
    static let mono = "IBM Plex Mono"

    /// Registers the bundled files once, for this process only.
    ///
    /// A lazy `static let` rather than a guarded function: the initialiser runs
    /// exactly once and is thread-safe by language rule, and every resolver
    /// below touches it, so nothing can resolve a bundled face before the files
    /// are in. `AppDelegate` also touches it at launch, which is what keeps the
    /// first frame from measuring in a fallback face.
    @discardableResult
    static func register() -> Bool { registered }

    private static let registered: Bool = {
        guard let directory = Bundle.module.url(forResource: "Fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return false }
        let fonts = files.filter { $0.pathExtension.lowercased() == "ttf" }
        guard !fonts.isEmpty else { return false }
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, false, nil)
        return true
    }()

    /// The text of one bundled licence, for the Settings sheet. Read from the
    /// bundle rather than pasted into a Swift literal so the file shipped and
    /// the text shown can't drift apart.
    static func licence(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: "Fonts/\(name)", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }

    // MARK: Resolution

    /// A bundled face at a point size and weight, or `nil` if the family isn't
    /// registered — which is the case worth handling rather than asserting: a
    /// bundle assembled without the resource bundle (a bare `swift run`, say)
    /// should fall back to a system face, not draw nothing.
    ///
    /// Three routes to a weight, and the split is measured rather than tidy —
    /// **pinning the variable axis freezes the weight against every later
    /// symbolic trait**, which is a silent one. A descriptor carrying
    /// `wght: 400` answers `withSymbolicTraits(.bold)` with *the regular face
    /// again*, no error, so `**bold**` in a Grotesk card body would have
    /// rendered as body text — and `MarkdownText` leans on exactly that trait
    /// lookup, as the italic synthesis already documents. So:
    ///
    /// - **Regular** (or no weight asked for) gets the family **alone**, no
    ///   traits and no variation, which leaves a later `.bold` free to resolve.
    ///   The family's default instance is Regular, despite the file naming it
    ///   `SpaceGrotesk-Light_Regular` after its Light origin.
    /// - **Semibold on Grotesk** is the one case that needs the axis: the
    ///   variable file's *named* instances are Light / Regular / Medium / Bold,
    ///   so the trait route rounds 600 up to Bold. `wght: 600` gets the real
    ///   instance. A face resolved this way can't be bolded further, which is
    ///   fine — nothing asks a semibold title to become bold.
    /// - **Everything else** uses the ordinary weight trait, which lands on a
    ///   named instance for Grotesk and on the right static for Plex Mono.
    static func font(family: String, size: CGFloat, weight: NSFont.Weight?) -> NSFont? {
        register()
        var attributes: [NSFontDescriptor.AttributeName: Any] = [.family: family]
        if let weight, weight != .regular {
            if family == grotesk, weight == .semibold {
                attributes[Self.variation] = [Self.wghtAxis: 600]
            } else {
                attributes[.traits] = [NSFontDescriptor.TraitKey.weight: weight.rawValue]
            }
        }
        return NSFont(descriptor: NSFontDescriptor(fontAttributes: attributes), size: size)
    }

    private static let variation = NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String)
    /// `'wght'` as the four-character code CoreText wants. The axis runs
    /// 300–700 on this file.
    private static let wghtAxis = 0x77676874
}

// MARK: - The numeral and label face

/// IBM Plex Mono, at the app's own text styles — the counts in a column band,
/// the cards' timestamps, and the small-caps type labels.
///
/// Why a mono face for those three and nothing else: they are the parts of a card
/// that are read as *values* rather than as prose. A count and a timestamp change
/// under you, and a proportional face makes them jitter sideways as they do
/// (`11:59` is narrower than `12:00` in SF); a tabular mono holds the column
/// still. The uppercase type label joins them because it is a tag, not a word.
///
/// **Except under the Monospace typeface**, where the card's own face is already
/// SF Mono: a second monospaced face on the same card would be two mono voices
/// saying different things, so the body face covers it instead. That is the one
/// place this reads the typeface setting, and it reads it the way `Card` does —
/// inside a view update, so the `@Observable` access registers and a change in
/// Settings re-renders.
enum Mono {
    @MainActor
    static func nsFont(_ style: NSFont.TextStyle, weight: NSFont.Weight = .medium) -> NSFont {
        nsFont(style, weight: weight, typeface: SettingsStore.shared.typeface)
    }

    static func nsFont(
        _ style: NSFont.TextStyle,
        weight: NSFont.Weight = .medium,
        typeface: Typeface
    ) -> NSFont {
        let size = NSFont.preferredFont(forTextStyle: style).pointSize
        if typeface == .monospaced {
            return Card.nsFont(style, weight: weight, typeface: typeface)
        }
        return BundledFonts.font(family: BundledFonts.mono, size: size, weight: weight)
            // Not the proportional system font: if Plex Mono is missing the
            // point is still that these read as values, so SF Mono is the
            // right degradation.
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    @MainActor
    static func font(_ style: NSFont.TextStyle, weight: NSFont.Weight = .medium) -> Font {
        Font(nsFont(style, weight: weight))
    }

    static func font(
        _ style: NSFont.TextStyle,
        weight: NSFont.Weight = .medium,
        typeface: Typeface
    ) -> Font {
        Font(nsFont(style, weight: weight, typeface: typeface))
    }

    /// A fixed point size, for the two places that aren't on a text style: the
    /// band's count pill (11pt) and the type label (10.5pt), both of which the
    /// plan specifies as sizes because they sit between `.caption` and
    /// `.caption2`.
    @MainActor
    static func font(size: CGFloat, weight: NSFont.Weight = .medium) -> Font {
        let typeface = SettingsStore.shared.typeface
        if typeface == .monospaced {
            return Font(Card.nsFont(.caption1, weight: weight, typeface: typeface))
        }
        let resolved = BundledFonts.font(family: BundledFonts.mono, size: size, weight: weight)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        return Font(resolved)
    }
}
