import AppKit
import SwiftUI
import XCTest
@testable import Insert

/// Measures every `AppTheme` — the plan's acceptance list, run rather than
/// asserted in a comment.
///
/// This suite exists because the theme table is **data that can only be wrong
/// quietly**. A band tone off by a step, a type label that stops clearing its
/// floor on a card, an accent that drifts into the hue one of its own note types
/// wears: none of those crash, none of them show up in a screenshot of the theme
/// you happen to be using, and there are twelve surfaces (six themes × two
/// appearances) where they could hide. The values are generated from an oklch
/// spec offline, so the thing worth pinning is not the arithmetic that produced
/// them but the properties they were produced to have.
///
/// Colours are resolved the way AppKit will resolve them — through the dynamic
/// `NSColor` under each `Color`, inside an explicit appearance — so what is
/// measured is what gets painted, not the literal in the table.
final class ThemePaletteTests: XCTestCase {
    /// Text under 14px, which is what a type label, a count and a timestamp are
    /// (CLAUDE.md decision 5).
    private let textFloor = 4.5
    /// A mark or a dot: a graphic, and held to the lower floor deliberately —
    /// that is *why* mark and label are two values rather than one.
    private let graphicFloor = 3.0
    /// What Increase Contrast promises.
    private let contrastFloor = 7.0

    // MARK: The bands

    func testEveryBandPairingClearsTheTextFloor() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                let band = theme.band
                assert(band.text, on: band.fill, floor: textFloor,
                       "\(theme.label)/\(mode) band text", mode)
                assert(band.countText, on: band.countFill, floor: textFloor,
                       "\(theme.label)/\(mode) count text", mode)
                assert(band.primaryLabel, on: band.primary, floor: textFloor,
                       "\(theme.label)/\(mode) primary label", mode)
                assert(band.segmentLabel, on: band.trackFill, floor: textFloor,
                       "\(theme.label)/\(mode) unselected segment label", mode)
                assert(band.segmentLabelSelected, on: band.segmentFill, floor: textFloor,
                       "\(theme.label)/\(mode) selected segment label", mode)
                // The tasks column's date dropdown at rest: the band's heading
                // colour on the *track* fill, since it shares the segmented
                // control's ground so the two halves of one filter row read as
                // one material.
                assert(band.text, on: band.trackFill, floor: textFloor,
                       "\(theme.label)/\(mode) date dropdown label", mode)
            }
        }
    }

    /// The band has to read as a *different surface* from the cards below it, or
    /// the column stops having a header at all.
    ///
    /// Deliberately a loose threshold, and worth saying why: this measures
    /// **luminance**, and in Dark the two surfaces are within a point of
    /// lightness by design (band ~20–27% L, card ~25%) with the difference
    /// carried by hue and chroma instead — Rosewood's wine band against its
    /// greyer card is 1.04:1 here and obvious on screen. So what this catches is
    /// a value that has *collapsed onto its neighbour*, not a legibility floor;
    /// the floors are the pairings above.
    func testEachBandIsDistinguishableFromItsOwnCard() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                let ratio = contrast(theme.band.fill, theme.cardFace, mode)
                XCTAssertGreaterThan(
                    ratio, 1.02,
                    "\(theme.label)/\(mode) band is indistinguishable from its card (\(round(ratio)))")
            }
        }
    }

    // MARK: The grounds

    /// Light cards are pure white in every theme: the tint lives in the window
    /// behind them, which is what makes body-text contrast identical in all six
    /// and verifiable once rather than per theme.
    func testLightCardsArePureWhiteInEveryTheme() {
        for theme in AppTheme.allCases {
            let face = srgb(theme.cardFace, .light)
            XCTAssertEqual(face.r, 1, accuracy: 0.002, "\(theme.label) light card is not white")
            XCTAssertEqual(face.g, 1, accuracy: 0.002, "\(theme.label) light card is not white")
            XCTAssertEqual(face.b, 1, accuracy: 0.002, "\(theme.label) light card is not white")
        }
    }

    /// A card has to sit forward of the page it is on, in both appearances —
    /// this is the pair that would silently collapse if a window ground were
    /// nudged toward its card.
    ///
    /// In Light the two are a white card on a 98.5% L page, 1.04:1, and the
    /// separation is really the **hairline's** job (91% L, checked below) — which
    /// is the whole reason `.island()` draws one now that nothing casts a shadow.
    /// So the page check is for collapse, and the edge check is the one with
    /// something to prove.
    func testEveryCardSitsForwardOfItsPage() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                let ratio = contrast(theme.cardFace, theme.windowFill, mode)
                XCTAssertGreaterThan(
                    ratio, 1.02,
                    "\(theme.label)/\(mode) card doesn't separate from its window")
                let edge = contrast(theme.cardBorder, theme.cardFace, mode)
                XCTAssertGreaterThan(
                    edge, 1.05,
                    "\(theme.label)/\(mode) card hairline is invisible on its own card")
            }
        }
    }

    // MARK: Metadata

    /// Metadata is the themed text value and so the one most likely to fail.
    /// The five derived values land near 6:1; Dracula's is its palette's own and
    /// is the tightest pairing in the file at 4.52:1 in Dark, which is why the
    /// floor asserted here is the plan's 4.5 rather than the 5.0 the rest of the
    /// table happens to clear.
    func testMetadataClearsItsFloorOnEveryCard() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                assert(theme.metaText, on: theme.cardFace, floor: textFloor,
                       "\(theme.label)/\(mode) metadata", mode)
            }
        }
    }

    // MARK: The writing

    /// **Title and body colour are identical across the six, Dracula excepted.**
    /// The plan's own words: if they differ, a theme is reaching further than it
    /// allows. This is the check that keeps "text is not themed" true, since the
    /// tempting next step from a themed metadata colour is a themed body — and
    /// nothing on screen would announce it.
    func testTitleAndBodyAreUnthemedExceptInDracula() {
        for mode in Appearances.both {
            let label = srgb(Color(nsColor: .labelColor), mode)
            for theme in AppTheme.allCases where theme != .dracula {
                for (what, colour) in [("title", theme.titleText), ("body", theme.bodyText)] {
                    let resolved = srgb(colour, mode)
                    let message = "\(theme.label)/\(mode) \(what) is not the system label colour"
                    XCTAssertEqual(resolved.r, label.r, accuracy: 0.002, message)
                    XCTAssertEqual(resolved.g, label.g, accuracy: 0.002, message)
                    XCTAssertEqual(resolved.b, label.b, accuracy: 0.002, message)
                }
            }
            // And Dracula really is the exception, rather than quietly resolving
            // to the same thing and making the rule above vacuous.
            let title = srgb(AppTheme.dracula.titleText, mode)
            XCTAssertNotEqual(title.r, label.r, accuracy: 0.002,
                              "Dracula/\(mode) title should be its own value")
            // Leaving the writing unthemed only helps if the *card* can carry it:
            // a themed dark face nudged lighter is how `labelColor` would quietly
            // stop clearing the floor, which is the failure this half catches.
            for theme in AppTheme.allCases {
                assert(theme.titleText, on: theme.cardFace, floor: textFloor,
                       "\(theme.label)/\(mode) title", mode)
                assert(theme.bodyText, on: theme.cardFace, floor: textFloor,
                       "\(theme.label)/\(mode) body", mode)
            }
        }
    }

    /// Dracula's body is a step softer than its title — the paragraph-versus-
    /// heading contrast its palette is built around — and both still clear the
    /// floor on its own cards.
    func testDraculasWritingClearsTheFloorAndKeepsItsHierarchy() {
        for mode in Appearances.both {
            let card = AppTheme.dracula.cardFace
            assert(AppTheme.dracula.titleText, on: card, floor: textFloor,
                   "Dracula/\(mode) title", mode)
            assert(AppTheme.dracula.bodyText, on: card, floor: textFloor,
                   "Dracula/\(mode) body", mode)
            let title = contrast(AppTheme.dracula.titleText, card, mode)
            let body = contrast(AppTheme.dracula.bodyText, card, mode)
            XCTAssertGreaterThan(
                title, body,
                "Dracula/\(mode): the body should be softer than the title, not louder")
            // Its writing needs no Increase Contrast variants — the softest of
            // the four is already past 7:1, which is what that switch promises.
            XCTAssertGreaterThan(body, contrastFloor, "Dracula/\(mode) body under 7:1")
        }
    }

    // MARK: The note-type palettes

    /// Marks at 3:1 on the card *and* on the filter track, since the same value
    /// draws the capsule beside a title and the dot on the band.
    func testEveryTypeMarkClearsTheGraphicFloorOnBothSurfaces() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                for tint in Self.typeTints {
                    let mark = theme.typeMark(tint)
                    assert(mark, on: theme.cardFace, floor: graphicFloor,
                           "\(theme.label)/\(mode) \(tint.name) mark on card", mode)
                    assert(mark, on: theme.band.trackFill, floor: graphicFloor,
                           "\(theme.label)/\(mode) \(tint.name) dot on track", mode)
                }
            }
        }
    }

    func testEveryTypeLabelClearsTheTextFloorOnItsCard() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                for tint in Self.typeTints {
                    assert(theme.typeLabel(tint), on: theme.cardFace, floor: textFloor,
                           "\(theme.label)/\(mode) \(tint.name) label", mode)
                }
            }
        }
    }

    /// The plan's own rule, automated as it asks: **no theme's accent may sit
    /// within 25° of any of its four note-type hues**, because that is what keeps
    /// "action" legible as action rather than as a fifth type.
    ///
    /// A primary under 0.03 chroma is exempt, and Bone is the case that makes the
    /// exemption necessary rather than convenient: its accent is ink, so it has a
    /// nominal hue and no colour, and a hue distance measured against it means
    /// nothing.
    func testNoAccentSitsInAnyOfItsOwnTypeHues() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                let primary = oklch(srgb(theme.primary, mode))
                guard primary.chroma >= 0.03 else { continue }
                for tint in Self.typeTints {
                    let mark = oklch(srgb(theme.typeMark(tint), mode))
                    let apart = hueDistance(primary.hue, mark.hue)
                    XCTAssertGreaterThanOrEqual(
                        apart, 25,
                        """
                        \(theme.label)/\(mode): the accent (h \(Int(primary.hue))) is only \
                        \(Int(apart))° from \(tint.name) (h \(Int(mark.hue)))
                        """)
                }
            }
        }
    }

    /// The label is *not* the mark: the plan gives it 5–8 points less lightness,
    /// and that gap is what lets a mark stay bright enough to see while the text
    /// beside it carries the tighter floor. Pinned because collapsing the two
    /// back into one value is the obvious simplification, and it was the previous
    /// set's mistake.
    func testLabelsAreDarkerThanTheirMarksInLight() {
        for theme in AppTheme.allCases {
            for tint in Self.typeTints {
                let mark = oklch(srgb(theme.typeMark(tint), .light))
                let label = oklch(srgb(theme.typeLabel(tint), .light))
                XCTAssertLessThan(
                    label.lightness, mark.lightness,
                    "\(theme.label) \(tint.name): the label is not darker than its mark")
            }
        }
    }

    /// A type on a tint no theme overrides — Insert's types are user-extensible,
    /// so a custom one can be any `Tint` — falls back to the app's own solved
    /// foreground rather than to nothing.
    func testACustomTypesTintFallsBackToTheAppsOwnInk() {
        for theme in AppTheme.allCases {
            for tint in [Tint.teal, .pink, .red, .gray, .orange] {
                for mode in Appearances.both {
                    let mark = srgb(theme.typeMark(tint), mode)
                    let ink = srgb(tint.ink, mode)
                    let what = "\(theme.label)/\(mode) \(tint.name) should fall back to Tint.ink"
                    XCTAssertEqual(mark.r, ink.r, accuracy: 0.002, what)
                    XCTAssertEqual(mark.g, ink.g, accuracy: 0.002, what)
                    XCTAssertEqual(mark.b, ink.b, accuracy: 0.002, what)
                }
            }
        }
    }

    // MARK: Increase Contrast

    /// The values near the floor — the type labels and the metadata colour — are
    /// the ones with Increase Contrast variants, and the switch has to actually
    /// move them past 7:1. Derived by stepping lightness rather than solved by
    /// hand, so this is the check that the step was far enough.
    func testIncreaseContrastTakesTheNearFloorValuesTo7To1() {
        let wasOn = AccessibilityOverride.increaseContrast
        AccessibilityOverride.increaseContrast = true
        defer { AccessibilityOverride.increaseContrast = wasOn }

        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                assert(theme.metaText, on: theme.cardFace, floor: contrastFloor,
                       "\(theme.label)/\(mode) metadata under Increase Contrast", mode)
                for tint in Self.typeTints {
                    assert(theme.typeLabel(tint), on: theme.cardFace, floor: contrastFloor,
                           "\(theme.label)/\(mode) \(tint.name) label under Increase Contrast", mode)
                }
            }
        }
    }

    // MARK: Dracula

    /// Only Dracula reorders the auto-assigned project colours, and only the
    /// *auto-assigned* ones: the order stays total, so the tenth project still
    /// gets a colour rather than falling off the end of the preferred five.
    func testOnlyDraculaReordersTheProjectDots() {
        for theme in AppTheme.allCases where theme != .dracula {
            XCTAssertEqual(theme.projectTintOrder, Tint.allCases, "\(theme.label)")
        }
        XCTAssertEqual(AppTheme.dracula.projectTintOrder.prefix(5),
                       [.red, .yellow, .blue, .purple, .orange])
        XCTAssertEqual(Set(AppTheme.dracula.projectTintOrder), Set(Tint.allCases))
        XCTAssertEqual(AppTheme.dracula.projectTintOrder.count, Tint.allCases.count)
    }

    // MARK: - Measuring

    /// The four tints the default note types wear, which is what a theme's
    /// palette overrides (`AppTheme.typePalette` is keyed by tint, not by type).
    private static let typeTints: [Tint] = [.blue, .yellow, .purple, .green]

    private func assert(
        _ fg: Color, on bg: Color, floor: Double, _ what: String, _ mode: Appearances,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let ratio = contrast(fg, bg, mode)
        XCTAssertGreaterThanOrEqual(
            ratio, floor, "\(what): \(round(ratio)):1, floor \(floor):1",
            file: file, line: line)
    }

    private func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }

    private func contrast(_ a: Color, _ b: Color, _ mode: Appearances) -> Double {
        let (la, lb) = (luminance(srgb(a, mode)), luminance(srgb(b, mode)))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Resolves a `Color` the way the window will: the dynamic `NSColor` inside
    /// it only answers under a *current* appearance, so asking for one outside
    /// this block would hand back whatever appearance the test process happens to
    /// be running in — which is how a Dark-only mistake gets past a Light-only
    /// test run.
    private func srgb(_ color: Color, _ mode: Appearances) -> RGB {
        var out = RGB(r: 0, g: 0, b: 0)
        NSAppearance(named: mode == .dark ? .darkAqua : .aqua)?
            .performAsCurrentDrawingAppearance {
                guard let resolved = NSColor(color).usingColorSpace(.sRGB) else { return }
                out = RGB(r: Double(resolved.redComponent),
                          g: Double(resolved.greenComponent),
                          b: Double(resolved.blueComponent))
            }
        return out
    }

    private func luminance(_ c: RGB) -> Double {
        func linear(_ u: Double) -> Double {
            u <= 0.04045 ? u / 12.92 : pow((u + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// sRGB → oklch, the inverse of the conversion the table was generated with.
    /// Only lightness, chroma and hue are wanted, and only for the hue rule and
    /// the mark/label ordering — nothing here reproduces the generator.
    private func oklch(_ c: RGB) -> (lightness: Double, chroma: Double, hue: Double) {
        func linear(_ u: Double) -> Double {
            u <= 0.04045 ? u / 12.92 : pow((u + 0.055) / 1.055, 2.4)
        }
        let (r, g, b) = (linear(c.r), linear(c.g), linear(c.b))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let hue = (atan2(bb, a) * 180 / .pi).truncatingRemainder(dividingBy: 360)
        return (lightness, (a * a + bb * bb).squareRoot(), hue < 0 ? hue + 360 : hue)
    }

    /// Degrees apart on the hue circle, the short way round — 350° and 10° are
    /// 20° apart, not 340.
    private func hueDistance(_ a: Double, _ b: Double) -> Double {
        let raw = (a - b).truncatingRemainder(dividingBy: 360)
        return abs(abs(raw) > 180 ? 360 - abs(raw) : raw)
    }

    private enum Appearances: CustomStringConvertible {
        case light, dark

        static let both: [Appearances] = [.light, .dark]

        var description: String { self == .dark ? "dark" : "light" }
    }
}
