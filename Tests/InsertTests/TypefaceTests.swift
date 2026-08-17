import AppKit
import CoreText
import XCTest
@testable import Insert

/// Pins what each `Typeface` actually resolves to, and pins it by *name and
/// glyph* rather than by eye.
///
/// Two things here fail silently rather than loudly, which is the reason this
/// file exists. A system font asked for the wrong way is **substituted**: the
/// serif is New York, a hidden system font, and requesting it by PostScript name
/// hands back Times New Roman without erroring — so "the serif option works" and
/// "the serif option draws New York" are different claims. And a stylistic
/// alternate applies during *shaping*, not when a font is created, so a
/// descriptor that carries the wrong feature makes an identical-looking `NSFont`
/// and only differs once text is laid out. Both are checked below the way they
/// have to be checked: names for the first, shaped glyph ids for the second.
final class TypefaceTests: XCTestCase {

    /// The glyph ids a string shapes to in a given font — which is where feature
    /// settings take effect. `CTFontGetGlyphsForCharacters` would *not* show
    /// this: it's a plain cmap lookup and ignores features entirely.
    private func glyphs(_ font: NSFont, _ text: String) -> [CGGlyph] {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: font])
        )
        var out: [CGGlyph] = []
        for run in (CTLineGetGlyphRuns(line) as? [CTRun] ?? []) {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            out += glyphs
        }
        return out
    }

    // MARK: Which face each option resolves to

    func testStandardIsThePlainSystemFont() {
        let font = Card.nsFont(.body, typeface: .standard)
        XCTAssertEqual(font.fontName, NSFont.preferredFont(forTextStyle: .body).fontName)
    }

    func testRoundedIsTheRoundedDesign() {
        let name = Card.nsFont(.body, typeface: .rounded).fontName
        XCTAssertTrue(name.contains("Rounded"), "expected a rounded face, got \(name)")
    }

    /// Matched on "Mono" rather than a full name on purpose: the same design
    /// resolves to `.SFNSMono-Regular` from a `preferredFont` base and
    /// `.AppleSystemUIFontMonospaced-Regular` from a `systemFont` one. Both are SF
    /// Mono, so the *name* is not the stable part and pinning one spelling would
    /// break on a base-font change that changed nothing a user could see.
    func testMonospacedIsTheMonospacedDesign() {
        let name = Card.nsFont(.body, typeface: .monospaced).fontName
        XCTAssertTrue(name.contains("Mono"), "expected a monospaced face, got \(name)")
    }

    /// The one that can go wrong quietly: New York ships with macOS but only the
    /// design API reaches it. If this ever comes back Times, the serif option is
    /// drawing a fallback and nothing else will say so.
    func testSerifIsNewYorkAndNotASubstitute() {
        let name = Card.nsFont(.body, typeface: .serif).fontName
        XCTAssertTrue(name.contains("NewYork"), "expected New York, got \(name)")
        XCTAssertFalse(name.lowercased().contains("times"), "substituted a fallback: \(name)")
    }

    /// The bundled face, and the one option that can be missing *entirely*
    /// rather than substituted: it lives in a resource bundle, so a build that
    /// forgot to copy it resolves to the system font and looks like nothing
    /// happened. Grotesk is the default for a new install, which makes that the
    /// whole app quietly wearing the wrong face.
    func testGroteskIsTheBundledSpaceGrotesk() {
        XCTAssertTrue(BundledFonts.register(), "the bundled fonts did not register")
        let font = Card.nsFont(.body, typeface: .grotesk)
        XCTAssertEqual(font.familyName, BundledFonts.grotesk, "got \(font.fontName)")
        XCTAssertNotEqual(font.fontName, NSFont.preferredFont(forTextStyle: .body).fontName)
    }

    /// Why the *variable* file ships rather than the four statics: the statics
    /// are Light / Regular / Medium / Bold with no SemiBold, and SemiBold is the
    /// weight the card titles ask for. Through the `wght` axis it has to be a
    /// real instance — distinct from both neighbours, not silently rounded to
    /// Bold, which is exactly what the `.traits`/`.weight` route did.
    func testGroteskResolvesEveryWeightIncludingSemibold() {
        let weights: [NSFont.Weight] = [.regular, .medium, .semibold, .bold]
        let names = weights.map { Card.nsFont(.title3, weight: $0, typeface: .grotesk).fontName }
        XCTAssertEqual(Set(names).count, weights.count, "weights collapsed: \(names)")
    }

    /// The trap the variable font sets, and the reason `BundledFonts.font` has
    /// three routes to a weight instead of one: a descriptor carrying an
    /// explicit `wght` variation answers `withSymbolicTraits(.bold)` with **the
    /// same face again**, no error. Since that trait lookup is how
    /// `MarkdownText` resolves `**bold**`, pinning the axis at 400 for the body
    /// face made every bold run in a Grotesk card render as body text. Pinned
    /// here rather than left to `testBoldItalicKeepsItsWeight`, which only found
    /// it by accident.
    func testSymbolicBoldStillReachesAHeavierGroteskFace() {
        let body = Card.nsFont(.body, typeface: .grotesk)
        let bolded = NSFont(
            descriptor: body.fontDescriptor.withSymbolicTraits(
                body.fontDescriptor.symbolicTraits.union(.bold)),
            size: body.pointSize
        )
        XCTAssertNotNil(bolded)
        XCTAssertNotEqual(
            bolded?.fontName, body.fontName,
            "the body face is pinned against the bold trait: **bold** would draw as regular"
        )
    }

    /// Space Grotesk is Latin-only. Nothing in the app handles that — CoreText's
    /// own cascade substitutes per glyph — so this pins the assumption rather
    /// than a behaviour: if the family ever *did* claim Cyrillic, a title in it
    /// would start rendering in a face nobody chose.
    func testGroteskLeavesNonLatinToTheSystemCascade() {
        let font = Card.nsFont(.body, typeface: .grotesk)
        XCTAssertTrue(font.coveredCharacterSet.contains("A"))
        XCTAssertFalse(font.coveredCharacterSet.contains("д"))
    }

    // MARK: The numeral and label face

    /// `Mono` draws the bands' counts, the cards' timestamps and the type
    /// labels, and it must really be Plex Mono rather than the proportional
    /// system font — a count that isn't tabular is the thing this exists to
    /// prevent.
    func testMonoIsTheBundledPlexMono() {
        XCTAssertTrue(BundledFonts.register())
        for typeface in Typeface.allCases where typeface != .monospaced {
            let font = Mono.nsFont(.caption2, typeface: typeface)
            XCTAssertEqual(
                font.familyName, BundledFonts.mono,
                "\(typeface.label) resolved \(font.fontName) for the numeral face"
            )
        }
    }

    /// The one opt-out: under Monospace the card's own face is already SF Mono,
    /// and two monospaced faces on one card would be two voices. So it defers to
    /// the body face there instead of adding a second.
    func testMonoDefersToTheCardFaceUnderMonospace() {
        let mono = Mono.nsFont(.caption2, typeface: .monospaced)
        XCTAssertEqual(mono.fontName, Card.nsFont(.caption2, weight: .medium, typeface: .monospaced).fontName)
        XCTAssertNotEqual(mono.familyName, BundledFonts.mono)
    }

    /// Same point size as the style it is asked for, whichever typeface is
    /// selected: the footer sits in a line of the card's own metrics, and a
    /// numeral face a point out of step shifts the row it is in.
    func testMonoMatchesTheTextStyleSize() {
        for style in [NSFont.TextStyle.caption2, .caption1, .body] {
            let expected = NSFont.preferredFont(forTextStyle: style).pointSize
            for typeface in Typeface.allCases {
                XCTAssertEqual(
                    Mono.nsFont(style, typeface: typeface).pointSize, expected,
                    "\(typeface.label) at \(style.rawValue)"
                )
            }
        }
    }

    /// The OFL obliges Insert to distribute the licence with the fonts, so an
    /// empty string here is a licensing failure and not a cosmetic one — the
    /// Settings sheet reads exactly this.
    func testBothLicencesAreBundledAndReadable() {
        for licence in ["SpaceGrotesk-OFL", "IBMPlexMono-OFL"] {
            let text = BundledFonts.licence(licence)
            XCTAssertTrue(
                text.contains("SIL OPEN FONT LICENSE"),
                "\(licence) is missing or not the OFL (\(text.count) characters)"
            )
        }
    }

    // MARK: The one-storey `a`

    /// Rounded asks for the alternate, so the `a`s must shape to different glyphs
    /// than the same design without it. This is the assertion the whole
    /// `featureSettings` dance exists to satisfy.
    func testRoundedUsesTheOneStoreyA() {
        let card = Card.nsFont(.body, typeface: .rounded)
        let plain = NSFont(
            descriptor: NSFont.preferredFont(forTextStyle: .body).fontDescriptor
                .withDesign(.rounded)!,
            size: card.pointSize
        )!
        XCTAssertNotEqual(glyphs(card, "banana"), glyphs(plain, "banana"))
    }

    /// Standard asks for the alternate too — the Notes look on the plain SF
    /// design. It first shipped without it, to stay glyph-identical to the
    /// chrome; that was reversed by request, so Standard now differs from the
    /// system font in exactly this one glyph.
    func testStandardUsesTheOneStoreyA() {
        let card = Card.nsFont(.body, typeface: .standard)
        let system = NSFont.preferredFont(forTextStyle: .body)
        XCTAssertNotEqual(glyphs(card, "banana"), glyphs(system, "banana"))
    }

    /// The serif and the monospaced face don't list the selector, and asking for
    /// it anyway resolves to the same glyphs — no fallback, no substitution. So
    /// `prefersOneStoreyA` naming the two SF designs is a statement of intent,
    /// not a workaround for something that would otherwise break.
    func testTheAlternateIsInertOnTheOtherDesigns() {
        for typeface in [Typeface.serif, .monospaced] {
            let design = typeface.design!
            let base = NSFont.preferredFont(forTextStyle: .body).fontDescriptor
                .withDesign(design)!
            let plain = NSFont(descriptor: base, size: 13)!
            let asked = NSFont(
                descriptor: base.addingAttributes([
                    .featureSettings: [[
                        NSFontDescriptor.FeatureKey.typeIdentifier: 35,
                        .selectorIdentifier: 14,
                    ]]
                ]),
                size: 13
            )!
            XCTAssertEqual(
                glyphs(plain, "banana"), glyphs(asked, "banana"),
                "\(typeface.label) unexpectedly substitutes for stylistic set 7"
            )
        }
    }

    // MARK: The italic partner

    /// The point of `Card.italic(_:)`: whatever the typeface, an italic run has to
    /// come out *visibly* slanted. Before this, a rounded card silently drew
    /// `*emphasis*` upright, because the trait lookup found no italic face and fell
    /// back to the one it was given.
    func testEveryTypefaceHasAVisibleItalic() {
        for typeface in Typeface.allCases {
            let upright = Card.nsFont(.body, typeface: typeface)
            let italic = Card.italic(upright)
            let slanted = italic.fontName != upright.fontName
                || CTFontGetMatrix(italic as CTFont).c != 0
            XCTAssertTrue(slanted, "\(typeface.label) italic is not slanted: \(italic.fontName)")
        }
    }

    /// The three designs that ship a real italic must use it rather than a
    /// synthesis — a drawn oblique next to an available true italic would be a
    /// worse rendering of the same span.
    func testRealItalicFacesArePreferred() {
        for typeface in [Typeface.standard, .serif, .monospaced] {
            let italic = Card.italic(Card.nsFont(.body, typeface: typeface))
            XCTAssertTrue(
                italic.fontName.contains("Italic"),
                "\(typeface.label) should use its real italic face, got \(italic.fontName)"
            )
            XCTAssertEqual(
                CTFontGetMatrix(italic as CTFont).c, 0, accuracy: 0.0001,
                "\(typeface.label) has a real italic and should not be sheared"
            )
        }
    }

    /// Rounded has none, so it is the synthesised case: same face, sheared through
    /// the font matrix at the system italic's own angle.
    func testRoundedItalicIsSynthesised() {
        let upright = Card.nsFont(.body, typeface: .rounded)
        let italic = Card.italic(upright)
        XCTAssertEqual(italic.fontName, upright.fontName)
        let skew = CTFontGetMatrix(italic as CTFont).c
        XCTAssertEqual(skew, CGFloat(tan(12.5 * .pi / 180)), accuracy: 0.001)
    }

    /// `***bold italic***` has to keep its weight *and* its slant. Asking for the
    /// italic trait on its own would replace the bold rather than add to it, which
    /// is how this lost both at once.
    func testBoldItalicKeepsItsWeight() {
        for typeface in Typeface.allCases {
            let regular = Card.nsFont(.body, typeface: typeface)
            let bold = NSFont(
                descriptor: regular.fontDescriptor.withSymbolicTraits(
                    regular.fontDescriptor.symbolicTraits.union(.bold)
                ),
                size: regular.pointSize
            )!
            let boldItalic = Card.italic(bold)
            XCTAssertNotEqual(
                boldItalic.fontName, Card.italic(regular).fontName,
                "\(typeface.label) bold-italic resolved to the same face as plain italic"
            )
        }
    }

    // MARK: Weight and size survive the design swap

    /// Weight is baked into the descriptor, not added afterwards — every option
    /// has to honour it, or a card title stops being bold under one of them.
    func testWeightIsCarriedByEveryTypeface() {
        for typeface in Typeface.allCases {
            let bold = Card.nsFont(.title3, weight: .bold, typeface: typeface)
            let regular = Card.nsFont(.title3, typeface: typeface)
            XCTAssertNotEqual(
                bold.fontName, regular.fontName,
                "\(typeface.label) dropped the requested weight"
            )
        }
    }

    /// A card's height is measured from this font, so the point size has to be the
    /// text style's own whichever design is chosen.
    func testSizeMatchesTheTextStyleForEveryTypeface() {
        for style in [NSFont.TextStyle.body, .callout, .title3] {
            let expected = NSFont.preferredFont(forTextStyle: style).pointSize
            for typeface in Typeface.allCases {
                XCTAssertEqual(
                    Card.nsFont(style, typeface: typeface).pointSize, expected,
                    "\(typeface.label) at \(style.rawValue)"
                )
            }
        }
    }
}
