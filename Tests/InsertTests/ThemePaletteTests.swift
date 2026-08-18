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
    /// **luminance**, and in Dark the two surfaces are close by design, with the
    /// difference carried by hue and chroma instead — Dracula's plum band against
    /// its greyer card is 1.07:1 here and obvious on screen. So what this catches is
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

    /// **Light cards are no longer pure white in every theme**, and this is the
    /// test that keeps the reversal honest rather than letting it rot into an
    /// accident. The previous set made every light card white so body-text
    /// contrast could be verified once; two of the sourced palettes bring their
    /// own paper — Kanagawa's Lotus cream and Rosé Pine's Dawn `surface` — because
    /// a palette's paper is part of what it is.
    ///
    /// So it asserts both halves: those two are *not* white, which is what makes
    /// "measure against the surface actually painted" a real requirement rather
    /// than a formality, and the other four still are, which is what keeps the
    /// exception to two themes instead of a drift across the set.
    func testOnlyTheTwoSourcedPapersAreOffWhiteInLight() {
        let papered: Set<AppTheme> = [.kanagawa, .rosePine]
        for theme in AppTheme.allCases {
            let face = srgb(theme.cardFace, .light)
            let white = face.r >= 0.998 && face.g >= 0.998 && face.b >= 0.998
            if papered.contains(theme) {
                XCTAssertFalse(white, "\(theme.label) light card should be its palette's own paper")
                // Paper, not a tint: it still has to be the lightest thing in the
                // window, or the cards stop reading as cards.
                XCTAssertGreaterThan(luminance(face), 0.9, "\(theme.label) light card is too dark")
            } else {
                XCTAssertTrue(white, "\(theme.label) light card should be pure white")
            }
        }
    }

    /// A card has to sit forward of the page it is on, in both appearances —
    /// this is the pair that would silently collapse if a window ground were
    /// nudged toward its card.
    ///
    /// In Light the two are close by design and the separation is really the
    /// **hairline's** job — which is the whole reason `.island()` draws one now
    /// that nothing casts a shadow. So the page check is for an accidental
    /// collapse, and the edge check is the one with something to prove; the edge
    /// is therefore asserted for **every** theme, including the one exception
    /// below.
    ///
    /// **System in Light is that exception, and it is deliberate**: its page is
    /// white and so is its card, because macOS 26's own window background is white
    /// and a white sheet of hairlined cards is the platform's arrangement. Asserted
    /// as an *equality* rather than skipped, so a value drifting off white — in
    /// either of the two — still fails.
    func testEveryCardSitsForwardOfItsPage() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                let edge = contrast(theme.cardBorder, theme.cardFace, mode)
                XCTAssertGreaterThan(
                    edge, 1.05,
                    "\(theme.label)/\(mode) card hairline is invisible on its own card")
                if theme == .system, mode == .light {
                    assertSame(srgb(theme.cardFace, mode), srgb(theme.windowFill, mode),
                               "System's light card and page are both meant to be white")
                    assertSame(srgb(theme.cardFace, mode), RGB(r: 1, g: 1, b: 1),
                               "System's light card and page are both meant to be white")
                    continue
                }
                let ratio = contrast(theme.cardFace, theme.windowFill, mode)
                XCTAssertGreaterThan(
                    ratio, 1.02,
                    "\(theme.label)/\(mode) card doesn't separate from its window")
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

    // MARK: Links and rings

    /// A link is text on a card, so 4.5:1 — and it is the value most likely to
    /// arrive wrong, because a palette's link is authored for a dark editor. Dark
    /// Owl's `#00ff9f` measures **1.4:1** on white, which is why the light halves
    /// are deepened or derived rather than taken.
    func testEveryLinkClearsTheTextFloorOnItsCard() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                assert(theme.link, on: theme.cardFace, floor: textFloor,
                       "\(theme.label)/\(mode) link", mode)
            }
        }
    }

    /// The ring is a non-text indicator at 3:1 against the card it outlines, and
    /// it is `primary` in most themes — so this is the check that a *table's* own
    /// value was not taken on trust. The plan repeats the accent for Dracula in
    /// both modes, and the lavender on white is 2.41:1; three rings in the set
    /// step away from their accent for exactly this reason.
    func testEveryRingClearsTheGraphicFloorOnItsCard() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                assert(theme.ring, on: theme.cardFace, floor: graphicFloor,
                       "\(theme.label)/\(mode) selection ring", mode)
            }
        }
    }

    // MARK: The count chip

    /// The chip is the accent's, **except in System** — a theme whose whole claim
    /// is that it adds no colour of its own cannot spend the accent on the one
    /// number in the band. Measured as chroma rather than as a hex, since what is
    /// being asserted is "this is a grey" and "this is a colour".
    func testTheCountChipIsAccentedEverywhereButSystem() {
        for mode in Appearances.both {
            XCTAssertLessThan(
                oklch(srgb(AppTheme.system.band.countFill, mode)).chroma, 0.02,
                "System/\(mode) count chip should be neutral")
            for theme in AppTheme.allCases where theme != .system {
                let chip = oklch(srgb(theme.band.countFill, mode))
                let text = oklch(srgb(theme.band.countText, mode))
                XCTAssertGreaterThan(
                    max(chip.chroma, text.chroma), 0.04,
                    "\(theme.label)/\(mode) count chip carries no colour at all")
            }
        }
    }

    /// Dracula's chip **inverts between appearances**, and that is deliberate:
    /// its bright pink cannot carry both ways, so it is the numeral on a recessed
    /// fill in Dark and the *fill* under a dark numeral in Light. Pinned because
    /// the obvious tidy-up — one role in both modes — is what fails the floor.
    func testDraculasCountChipInvertsBetweenAppearances() {
        let pink = RGB(r: 1.0, g: 0x79 / 255.0, b: 0xc6 / 255.0)
        let band = AppTheme.dracula.band
        assertSame(srgb(band.countFill, .light), pink, "Dracula light chip fill is the pink")
        assertSame(srgb(band.countText, .dark), pink, "Dracula dark chip numeral is the pink")
        // And the recessed fill really is recessed, rather than the band again.
        XCTAssertLessThan(
            luminance(srgb(band.countFill, .dark)), luminance(srgb(band.fill, .dark)),
            "Dracula dark chip fill should sit below its band")
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
    /// A primary under 0.03 chroma is exempt, because a hue distance measured
    /// against a grey means nothing. **No theme in the current set is exempt** —
    /// the previous Bone's accent was ink and needed it, and the guard stays for
    /// the next accent that is a value rather than a hue.
    func testNoAccentSitsInAnyOfItsOwnTypeHues() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                let primary = oklch(srgb(theme.primary, mode))
                guard primary.chroma >= 0.03 else { continue }
                for tint in Self.typeTints {
                    // Rosé Pine's `love` and its blush Feedback mark are 19°
                    // apart in Light and 17° in Dark. The palette is built on
                    // that pairing and the plan records it rather than fixing it,
                    // so it is named here rather than lowering the rule.
                    if theme == .rosePine, tint == .purple { continue }
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

    /// **The four marks form a lightness ladder** (rule 4), so a card's type is
    /// legible in greyscale and not by hue alone. Every source palette puts three
    /// or four of its hues at one lightness — that is what "re-levelled" in the
    /// theme comments means, and it is the one thing done to all five sourced
    /// palettes.
    ///
    /// The previous set failed this outright (worst pair 1.00–1.07:1 by
    /// luminance) and recorded it as a known gap; this is that gap closed, which
    /// is why the assertion is on the **gap** rather than on an ordering: what
    /// matters is that no two marks collapse, not which type is darkest.
    ///
    /// **Dracula is the recorded exception**, in both appearances: its cyan Note
    /// and green Staffing sit at one lightness, and levelling four bright pastels
    /// is what would stop it looking like Dracula. The mark is never the sole
    /// carrier — the mono label spells the type out beside it.
    func testTheFourMarksFormALightnessLadder() {
        for theme in AppTheme.allCases where theme != .dracula {
            for mode in Appearances.both {
                let levels = Self.typeTints
                    .map { oklch(srgb(theme.typeMark($0), mode)).lightness }
                    .sorted()
                let gaps = (0..<3).map { levels[$0 + 1] - levels[$0] }
                XCTAssertGreaterThanOrEqual(
                    gaps.min() ?? 0, 0.029,
                    """
                    \(theme.label)/\(mode): two marks collapse in greyscale \
                    (levels \(levels.map { round($0 * 1000) / 1000 }))
                    """)
            }
        }
        // And Dracula really is the exception, rather than quietly passing and
        // making the note above wrong.
        let levels = Self.typeTints
            .map { oklch(srgb(AppTheme.dracula.typeMark($0), .dark)).lightness }
            .sorted()
        XCTAssertLessThan(
            (0..<3).map { levels[$0 + 1] - levels[$0] }.min() ?? 1, 0.029,
            "Dracula's ladder no longer needs its exception — take it out of the docs")
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
                assert(theme.link, on: theme.cardFace, floor: contrastFloor,
                       "\(theme.label)/\(mode) link under Increase Contrast", mode)
                for tint in Self.typeTints {
                    assert(theme.typeLabel(tint), on: theme.cardFace, floor: contrastFloor,
                           "\(theme.label)/\(mode) \(tint.name) label under Increase Contrast", mode)
                }
            }
        }
    }

    // MARK: Dracula

    /// Two themes reorder the auto-assigned project colours, and only the
    /// *auto-assigned* ones — a colour the user picked is data in `Projects.md`,
    /// and switching theme must never rewrite it. Both orders stay **total**, so
    /// the tenth project still gets a colour rather than falling off the end.
    ///
    /// Dracula leads with its own five. Kanagawa pushes orange last instead,
    /// which is its "the only orange on screen is the button" rule reaching the
    /// dots as the plan asks — a demotion rather than a removal, for the totality
    /// reason above.
    func testOnlyDraculaAndKanagawaReorderTheProjectDots() {
        for theme in AppTheme.allCases where theme != .dracula && theme != .kanagawa {
            XCTAssertEqual(theme.projectTintOrder, Tint.allCases, "\(theme.label)")
        }
        XCTAssertEqual(AppTheme.dracula.projectTintOrder.prefix(5),
                       [.red, .yellow, .blue, .purple, .orange])
        XCTAssertEqual(AppTheme.kanagawa.projectTintOrder.last, .orange)
        for theme in [AppTheme.dracula, .kanagawa] {
            XCTAssertEqual(Set(theme.projectTintOrder), Set(Tint.allCases), "\(theme.label)")
            XCTAssertEqual(theme.projectTintOrder.count, Tint.allCases.count, "\(theme.label)")
        }
    }

    // MARK: The one red

    /// `Semantic.overdue` is the app's only red and it is solved on the card, so
    /// **a new set of card faces means re-measuring it** — the plan says so in as
    /// many words ("re-measure; do not assume white"), and two of these faces are
    /// no longer white. It lives in `Theme.swift` and knows nothing about themes,
    /// which is exactly why the check belongs here: nothing else would notice a
    /// card face nudged toward it.
    func testOverdueRedClearsTheTextFloorOnEveryCardFace() {
        for theme in AppTheme.allCases {
            for mode in Appearances.both {
                assert(Semantic.overdue, on: theme.cardFace, floor: textFloor,
                       "\(theme.label)/\(mode) overdue red", mode)
            }
        }
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

    private func assertSame(
        _ a: RGB, _ b: RGB, _ what: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(a.r, b.r, accuracy: 0.004, what, file: file, line: line)
        XCTAssertEqual(a.g, b.g, accuracy: 0.004, what, file: file, line: line)
        XCTAssertEqual(a.b, b.b, accuracy: 0.004, what, file: file, line: line)
    }

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
