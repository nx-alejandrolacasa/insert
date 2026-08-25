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
/// `IBMPlexMono-OFL.txt`, shown in Settings → Appearance → "Font licences") because
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
/// Nothing but a class to ask `Bundle(for:)` about, so `resources` can find the
/// bundle this code was loaded from.
private final class BundleMarker {}

enum BundledFonts {
    /// The SwiftPM resource bundle holding `Fonts/`, found by looking rather than
    /// through **`Bundle.module`** — which is generated, and which *traps*.
    ///
    /// This is what crashed 0.12.0 on launch for everyone who installed the DMG,
    /// and it is worth the paragraph. SwiftPM's generated accessor tries exactly two
    /// paths: `Bundle.main.bundleURL` + `Insert_Insert.bundle` — a **sibling of
    /// `Contents/`**, not inside `Contents/Resources` — and then an absolute
    /// hard-coded path into the `.build` directory of *the machine that compiled it*.
    /// Neither can be right in a shipped app: the first is a place nothing may live
    /// (a file beside `Contents/` is unsealed and breaks the signature), and the
    /// second existed only on the developer's own Mac. Which is exactly why it was
    /// never seen locally — a locally built app fell through to
    /// `/Users/…/insert/.build/…` and worked, while the CI-built app carried
    /// `/Users/runner/work/…` and hit `Swift.fatalError` in
    /// `applicationWillFinishLaunching`, before a window existed.
    ///
    /// So: our own candidates, in the order they can be right, and **`nil` rather
    /// than a trap** when none is. A missing resource bundle is a *font* problem —
    /// `font(family:…)` already answers `nil` and every caller falls back to a
    /// system face — and there is no version of it that should stop the app opening
    /// someone's notes.
    ///
    /// - `Bundle.main.resourceURL` — `Contents/Resources` of the assembled app,
    ///   where `build.sh` puts it and the only correct place in a signed bundle.
    /// - `Bundle.main.bundleURL` — beside the executable, which is what a bare
    ///   `swift run` produces (and what `Bundle.module` looks at for an app).
    /// - the marker's own bundle and its parent — under `swift test` the resource
    ///   bundle sits next to `InsertPackageTests.xctest` in `.build/<triple>/debug`,
    ///   which is neither of the above.
    private static let resources: Bundle? = {
        let marker = Bundle(for: BundleMarker.self)
        let bases = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            marker.resourceURL,
            marker.bundleURL.deletingLastPathComponent(),
        ]
        for base in bases.compactMap(\.self) {
            let url = base.appendingPathComponent("Insert_Insert.bundle")
            if let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }()

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
        guard let directory = resources?.url(forResource: "Fonts", withExtension: nil),
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
        guard let url = resources?.url(forResource: "Fonts/\(name)", withExtension: "txt"),
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
        // Memoised: the family-name descriptor match is the slow form of font
        // resolution, and `Mono` asks for it per count, timestamp and type label,
        // per render. A `nil` (no resource bundle) is cached too — registration
        // is a one-shot `static let`, so the answer can't change mid-process.
        let key = FontKey(family: family, size: size, weight: weight?.rawValue)
        return resolved.value(for: key) {
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
    }

    private struct FontKey: Hashable {
        let family: String
        let size: CGFloat
        let weight: CGFloat?
    }

    private static let resolved = MemoCache<FontKey, NSFont?>()

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
