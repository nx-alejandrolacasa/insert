import AppKit
import SwiftUI

// MARK: - AppTheme

/// One of six named themes — Settings → General → Theme. A theme is **three
/// grounds, one accent and its own note-type palette**, and those three are the
/// rules: a theme that breaks any of them reads as a *setting* rather than as a
/// theme, which is exactly what the first set did.
///
/// 1. **Three grounds — band, page, card.** The band is the surface behind a
///    column heading (`ColumnHeaderBand`); the page (`windowFill`, and so the
///    sidebar, which is see-through to it) and the card (`cardFace`) carry the
///    *same hue* at 0.005–0.028 chroma. So the window belongs to the theme
///    instead of being a coloured strip on neutral grey. The glass track on the
///    band derives from the band and is not a token set of its own.
/// 2. **One accent, for action only** — `primary`: "New Note" / "New Task",
///    focus rings, selected states (CLAUDE.md decision 4). It may not repeat a
///    hue from the theme's own note-type palette, which is why Moss has no green
///    in its types: the only lime thing on screen is the button.
/// 3. **Its own note-type palette.** Authored per theme rather than shared, and
///    most of what makes a theme feel designed.
///
/// It replaced two separate settings — Background → Tint (Plain plus seven flat
/// tints) and Accent → Highlight colour (four swatches) — because between them
/// they had put the app's colour in the two places that made it least useful. The
/// tint washed the window *surface*, where a low-chroma flat colour reads as
/// almost nothing; the accent was one hue with no relationship to it. A saved
/// tint (and, failing that, a saved accent) maps onto its nearest theme once —
/// see `migrated(tint:accent:)`.
///
/// The same move retired the **highlighter stroke behind note titles** (the July
/// 2026 refresh's decision 2). A coloured band under the glyphs fights the letters
/// at any opacity — the strength had already been walked down from the handoff's
/// 60% to 45% and it was still the wrong shape of solution — so a note's type is
/// now a 3pt capsule mark *beside* the title, where it costs the title nothing.
/// See `TypeMarkTitle`.
///
/// **The set is on its second cut, and the reason is the interesting part.** The
/// first six (Slate, Graphite, Pine, Amber, Indigo, Dracula) were one hue poured
/// over neutral grey: the band was themed and everything under it wasn't, so five
/// of the six read as a preference and only Dracula read as a theme — because
/// Dracula was the only one bringing its own grounds and its own type hues. The
/// fix was to hold every theme to what Dracula was already doing, which is the
/// three rules above. Bone, Moss, Ember and Rosewood are new; Indigo was
/// re-solved; Dracula is unchanged apart from the metadata colour below.
///
/// **Every value is measured.** The plan's oklch spec is converted to sRGB
/// offline, with the track and the raised segment derived from the band's own hue
/// by the rules in the comments below. Each theme's worst *text* pairing, in
/// either appearance, is ≥5.0:1 — well past the refresh's 4.5:1 floor for text
/// under 14px (CLAUDE.md decision 5) — and the pairings checked are: band text on
/// the band, count text on the count chip, primary label on the primary fill, an
/// unselected segment label on the track, a selected one on the raised pill, the
/// metadata colour on the card, and each of the four type labels on the card.
/// Graphics — the type marks and the filter track's dots — are checked at 3:1 and
/// clear it (worst 3.24:1, Dracula's Staffing dot on its light track).
enum AppTheme: String, CaseIterable, Identifiable {
    // Declaration order **is** the order of the picker, and it runs muted →
    // hued → identity: the two quiet ones first, then the three that are a
    // colour, then Dracula, which is an identity rather than a shade and belongs
    // at the end of a list you scan for a hue.
    //
    // Unlike the first set, the first swatch is *not* the default — `default` is
    // Indigo, by the plan. That is a deliberate trade: a new install should open
    // wearing the theme with the most point of view, and the picker should still
    // read from quietest to loudest. Both are pinned by `ThemeMigrationTests`,
    // since either could be moved silently by a reordering done for some other
    // reason.

    /// Warm near-neutral band, and an accent that is **ink** rather than a hue —
    /// near-black on light, near-white on dark. The quietest of the six: its four
    /// type dots are the only colour in the window.
    case bone
    /// Olive band, chartreuse primary. **No green in its type palette** —
    /// Staffing goes teal and Feedback mauve — so the one lime thing on screen is
    /// the button (rule 2, and the clearest illustration of it).
    case moss
    /// Warm near-black band (cream in Light) with an amber primary — the one warm
    /// theme. Its Meeting type shifts off amber to a gold-olive so the type and
    /// the action aren't the same colour.
    case ember
    /// Deep wine band, coral primary (deepened to white-on-coral in Light, where
    /// the bright coral can't carry a label). Meeting warms to gold, Staffing to
    /// jade; nothing sits near the primary.
    case rosewood
    /// Violet band, periwinkle primary (deepened to white-on-violet in Light).
    /// Its Feedback type is pushed to rose so it separates from the primary.
    /// **The default for a new install.**
    case indigo
    /// The Dracula palette, shipped in both appearances. Dark-first by origin,
    /// and the theme the other five were rebuilt to match: its own grounds, its
    /// own note-type hues, one saturated colour kept for action.
    case dracula

    var id: Self { self }

    /// Where an install that has never chosen lands, and what an unrecognised
    /// saved value falls back to. Not `allCases.first` — see the note on the
    /// declaration order above.
    static let `default`: AppTheme = .indigo

    var label: String {
        switch self {
        case .bone: "Bone"
        case .moss: "Moss"
        case .ember: "Ember"
        case .rosewood: "Rosewood"
        case .indigo: "Indigo"
        case .dracula: "Dracula"
        }
    }

    /// The theme a pre-theme install lands on, mapped from whichever of the two
    /// retired settings it had. Run once from `SettingsStore.init`, after which
    /// the old keys are never read again.
    ///
    /// The tint decides it where there was one, by family: the near-neutrals go
    /// to Bone, the warm ones to Ember, pink to Rosewood, green to Moss, violet
    /// to Indigo. With the tint left at Plain the *accent* decides instead, since
    /// that was then the only colour the user had chosen. **Nobody arrives at
    /// Dracula by migration** — it is an identity, not a shade, so it has to be
    /// picked.
    ///
    /// Two rows are worth naming. A **grey** accent goes to Bone, which is the
    /// nearest thing the set still has to a monochrome theme now that the grey
    /// one is gone — Bone's own accent is ink rather than a hue, so "I chose no
    /// colour" is answered by the theme that has none. And a **blue** accent goes
    /// to Indigo, the default, rather than to the theme whose band is bluest:
    /// blue was the accent's own default, so an install holding it may never have
    /// chosen anything at all.
    static func migrated(tint: String, accent: String) -> AppTheme {
        switch tint {
        case "mist": return .bone
        case "linen", "clay": return .ember
        case "blush": return .rosewood
        // "seafoam" postdates the plan's table; its family is green, so it
        // follows sage rather than the cool near-whites it was added beside.
        case "sage", "seafoam": return .moss
        case "lilac": return .indigo
        // "plain" and anything unrecognised fall through to the accent.
        default: break
        }
        switch accent {
        case "green": return .moss
        case "orange": return .ember
        case "lilac": return .indigo
        case "gray", "graphite", "lightGray": return .bone
        // Blue, and an install that never chose either setting.
        default: return .default
        }
    }

    // MARK: Band

    /// The band's tones for the current appearance. Every member is a dynamic
    /// `NSColor` under the hood, so a view reads one plain `Color` and the
    /// Light/Dark switch costs nothing — the same trick `Tint` uses.
    ///
    /// **Built once per theme, not per read**, which is the `DateCoding` lesson
    /// in a new place: this is called from view bodies — `ColumnHeaderBand`, and
    /// `SegmentedFilter` once per segment per render — and building one allocates
    /// a dozen `NSColor` providers, so a five-segment track mid-animation would
    /// have made scores of them a frame to say the same thing. There are six
    /// themes and the values are constants, so every theme is resolved up front
    /// and handed out.
    var band: BandColors { resolved.band }

    // MARK: Primary

    /// The interactive colour: `AccentButtonStyle`'s fill, the pickers'
    /// selection rings, the tasks column's active date pill, a ticked
    /// checkbox. One hue, for interactive and selected state only (CLAUDE.md
    /// decision 4) — the difference from the retired `AccentColor` is that
    /// this one comes with the band it has to sit beside.
    var primary: Color { band.primary }

    /// What type on `primary` wears. White for the two themes whose primary is a
    /// deep fill (Rosewood, Indigo in Light), a near-black of the band's own hue
    /// for the ones whose primary is a bright one.
    var primaryLabel: Color { band.primaryLabel }

    /// The ring an open card wears. Follows `primary` except where a pale accent
    /// drawn as a 1.5pt outline would read as the *edge of a button* rather than
    /// as a selection: **Ember**, **Moss** and **Bone** each deepen a step in
    /// Light, and **Dracula** swaps its pink for its purple in both appearances,
    /// because a ring the same colour as the button beside it says nothing.
    var ring: Color { band.ring }

    // MARK: Grounds

    /// What the window paints behind everything — the page ground, at the band's
    /// hue and a fraction of its chroma. The sidebar gets it for free:
    /// `SidebarVibrancy` blends `.withinWindow`, so the panel is see-through to
    /// this.
    ///
    /// This is the part the first theme set didn't have, and the reason it read
    /// as a preference: a themed band over the system's grey window is a coloured
    /// strip on somebody else's surface. At 0.005–0.028 chroma the page is barely
    /// a colour on its own, which is the point — it is what stops the band from
    /// being the only themed thing in the window.
    var windowFill: Color { resolved.window }

    /// The card face. **Pure white in Light for every theme** — the tint lives in
    /// the window behind the cards, not on them, so body-text contrast is
    /// identical in all six — and the page hue at ~25% L in Dark.
    var cardFace: Color { resolved.card }

    /// The card's hairline, paired with `cardFace`: white at 7% over the dark
    /// card, composited offline. `Stone`'s warm wash over a themed card face
    /// reads as a smudge rather than an edge, which is why this is themed at all.
    var cardBorder: Color { resolved.border }

    /// Metadata type on a card — timestamps, chip names, the resting due badge,
    /// the `···` menu. The page ground's hue at 50% L in Light and 70% in Dark,
    /// so the quietest text in the window belongs to the theme rather than
    /// sitting on it.
    ///
    /// **Text is not themed except here**, and the exception is about kind rather
    /// than degree: a card's title and its body are the writing, read at length,
    /// so their contrast must not become a function of a colour preference, while
    /// metadata is already deliberately quiet and a tinted grey is what makes it
    /// read as part of the theme instead of as leftover chrome. `titleText` and
    /// `bodyText` are the same colour in five of the six themes for that reason —
    /// Dracula is the one exception, and it earns it by being a text palette by
    /// origin.
    ///
    /// Solved on the card face it is actually drawn on rather than on a nominal
    /// white, which is the third of the refresh's contrast rules: ~6.0:1 for the
    /// five derived values, and 5.6:1 / 4.5:1 for Dracula's two named ones, which
    /// are the tightest text pairings in the file. Its Increase Contrast pair
    /// steps most of the way to the label colour, the same move `Stone.metaText`
    /// makes — and for the same reason, that the solved values barely move under
    /// that switch and it has to look like it did something.
    var metaText: Color { resolved.metaText }

    /// A card's **title** colour, and the plainest statement of the rule above:
    /// it is `labelColor` — the system's, full contrast, unthemed — for five of
    /// the six themes, and only Dracula returns something else. If these ever
    /// start differing per theme, a theme is reaching further than the plan
    /// allows; `ThemePaletteTests` asserts exactly that.
    var titleText: Color { resolved.titleText }

    /// A card's **body** colour, on the same terms as `titleText`. Dracula's is a
    /// step softer than its title (`#cfd2e0` on dark, `#463d63` on light, 8.6:1
    /// and 10.0:1 on its cards), which is the paragraph-versus-heading contrast
    /// its palette is built around — and the reason the two are separate values
    /// rather than one "text".
    var bodyText: Color { resolved.bodyText }

    /// The order `Library.leastUsedTint()` walks when auto-assigning a colour to
    /// a new project, so a Dracula install's projects come out in Dracula's own
    /// hues. Only the *auto-assigned* default follows the theme: a colour the
    /// user picked is data, and switching theme must never rewrite it. The other
    /// five keep the app's own dot order.
    var projectTintOrder: [Tint] {
        switch self {
        case .dracula:
            // Dracula's five: red, yellow, cyan (the app's `blue`), purple,
            // orange — then the rest of the palette, so the order is still
            // total and a tenth project still gets a colour.
            let preferred: [Tint] = [.red, .yellow, .blue, .purple, .orange]
            return preferred + Tint.allCases.filter { !preferred.contains($0) }
        default:
            return Tint.allCases
        }
    }

    // MARK: Note-type palette

    /// The colour a note type's **mark** draws in: its 3pt capsule before the
    /// title, and its dot in the notes filter track. A graphic, so it is solved
    /// at 3:1 — against both the card and the track, since the dot sits on the
    /// band.
    func typeMark(_ tint: Tint) -> Color { resolved.marks[tint] ?? tint.ink }

    /// The colour a note type's **label** draws in — the small-caps name leading
    /// the meta row. Text under 14px, so 4.5:1, which is why it is a separate
    /// value from the mark rather than the same one twice: the plan gives the
    /// label 5–8 points less lightness than the mark it belongs to, and that
    /// difference is exactly what lets the mark stay bright enough to see.
    ///
    /// One value per appearance in Dark, where the plan gives a single tone and
    /// mark and label share it.
    func typeLabel(_ tint: Tint) -> Color { resolved.labels[tint] ?? tint.ink }

    // The picker needs no values of its own: its swatch draws `band.fill` and
    // `band.primary`, the dynamic pair the window itself uses, so it shows the
    // appearance in effect. A `ThemePreview` of flat light-and-dark sRGB lived
    // here while the swatch stacked both halves — see `ThemePicker` for why that
    // went.

    // MARK: Resolution

    private var resolved: Resolved { Self.table[self] ?? Resolved(self) }

    private static let table: [AppTheme: Resolved] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, Resolved($0)) })
}

// MARK: - Band tones

/// One band's thirteen colours, in one appearance.
///
/// Seven of them are the plan's own tokens; the rest are **derived from the
/// band's hue**, which is what keeps a new theme a hue rather than a design:
///
/// - `countFill` (dark) and `trackFill` (dark) are white at 12% and 10% over
///   the band, composited offline to opaque values so nothing layers alpha at
///   draw time.
/// - `trackFill` (light) is the band's hue at 92% L, `segmentLabel` at 87% L
///   (dark) / 42% L (light), and the raised `segmentFill` at 93% L (dark) or
///   pure white (light).
/// - `segmentLabelSelected` is the band's **text** in Light, where the raised
///   pill is pure white, and the band's own **fill** in Dark, where the pill is
///   near-white and the label reads as the band inverted. That is the trick the
///   raised pill turns: neither is a value that had to be solved on its own.
struct Band {
    let fill: RGB
    /// Light bands take a 1pt hairline on their bottom edge; a dark band
    /// separates from the cards below it on its own.
    let hairline: RGB?
    let text: RGB
    let countFill: RGB
    let countText: RGB
    let primary: RGB
    let primaryLabel: RGB
    let ring: RGB
    let trackFill: RGB
    /// A 1pt inset highlight along the track's top edge, dark mode only — the
    /// recess needs an upper lip to read as one against a dark band, and on a
    /// light band the same highlight is invisible.
    let trackHighlight: Bool
    let segmentLabel: RGB
    let segmentFill: RGB
    let segmentLabelSelected: RGB
}

/// A band's colours as `Color`s that follow the appearance on their own, so a
/// view never reads `colorScheme`.
struct BandColors {
    let fill: Color
    let hairline: Color?
    let text: Color
    let countFill: Color
    let countText: Color
    let primary: Color
    let primaryLabel: Color
    let ring: Color
    let trackFill: Color
    let trackHighlight: Bool
    let segmentLabel: Color
    let segmentFill: Color
    let segmentLabelSelected: Color

    fileprivate init(_ tones: Tones) {
        func pair(_ get: (Band) -> RGB) -> Color {
            DynamicRGB(light: get(tones.light), dark: get(tones.dark)).color
        }
        fill = pair(\.fill)
        hairline = tones.light.hairline.map {
            // Only the light band has one; in Dark this resolves to the band's
            // own fill, which draws nothing. A `nil` here would mean "no
            // hairline in either appearance" and lose the light one.
            DynamicRGB(light: $0, dark: tones.dark.fill).color
        }
        text = pair(\.text)
        countFill = pair(\.countFill)
        countText = pair(\.countText)
        primary = pair(\.primary)
        primaryLabel = pair(\.primaryLabel)
        ring = pair(\.ring)
        trackFill = pair(\.trackFill)
        trackHighlight = tones.dark.trackHighlight
        segmentLabel = pair(\.segmentLabel)
        segmentFill = pair(\.segmentFill)
        segmentLabelSelected = pair(\.segmentLabelSelected)
    }
}

/// The two bands, both appearances of the page and card grounds, the metadata
/// colour and the type palette — resolved into `Color`s once per theme.
private struct Resolved {
    let band: BandColors
    let window: Color
    let card: Color
    let border: Color
    let metaText: Color
    let titleText: Color
    let bodyText: Color
    let marks: [Tint: Color]
    let labels: [Tint: Color]

    init(_ theme: AppTheme) {
        let tones = theme.tones
        band = BandColors(tones)
        let grounds = theme.grounds
        window = grounds.window.color
        card = grounds.card.color
        border = grounds.border.color
        metaText = theme.metaTones.color
        // `labelColor` unless a theme names its own, which today means Dracula
        // alone — and the fall-through is the point: the writing's contrast is
        // the system's business in five of the six.
        titleText = theme.writingTones?.title.color ?? Color(nsColor: .labelColor)
        bodyText = theme.writingTones?.body.color ?? Color(nsColor: .labelColor)
        let palette = theme.typePalette
        marks = palette.mapValues(\.mark.color)
        labels = palette.mapValues(\.label.color)
    }
}

private struct Tones {
    let light: Band
    let dark: Band
}

/// The page and card grounds — rule 1's other two thirds.
private struct Grounds {
    let window: DynamicRGB
    let card: DynamicRGB
    let border: DynamicRGB
}

/// One note type's two values: the mark it is drawn with and the label that
/// names it. Separate because they carry different floors — see `typeLabel`.
private struct TypeTone {
    let mark: DynamicRGB
    let label: DynamicRGB
}

/// A theme's title and body colours, for the one theme that names them.
private struct WritingTones {
    let title: DynamicRGB
    let body: DynamicRGB
}

/// One colour in its two appearances, and optionally its two Increase Contrast
/// variants.
///
/// The HC pair is `nil` for every band tone, because each band's worst pairing
/// already clears 5:1 — well past the 4.5:1 floor — and the switch's visible
/// work there would be nothing. It is filled in for the values that *are* near
/// the floor: the note-type marks and labels, and the metadata colour.
struct DynamicRGB {
    let light: RGB
    let dark: RGB
    var lightHC: RGB? = nil
    var darkHC: RGB? = nil

    /// Increase Contrast is read from `NSWorkspace` rather than the appearance,
    /// for the reason `Theme.swift`'s own `dynamic(…)` gives: the high-contrast
    /// appearance still reports itself as plain Aqua, so `bestMatch(from:)`
    /// collapses it onto the base appearance and the variants never fire.
    var color: Color {
        Color(nsColor: NSColor(name: nil) { [light, dark, lightHC, darkHC] appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let highContrast = AccessibilityOverride.increaseContrast
                || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            let rgb = switch (isDark, highContrast) {
            case (false, false): light
            case (false, true): lightHC ?? light
            case (true, false): dark
            case (true, true): darkHC ?? dark
            }
            return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        })
    }
}

// MARK: - The table

private extension AppTheme {
    /// Generated from the plan's oklch spec rather than typed by hand, and
    /// regenerate it the same way if a theme is added: band `96% L / ≤0.026 C`
    /// in Light and ~20–27% L in Dark, band text `26% L` at the same hue, light
    /// hairline `89% L`, and a primary that clears 4.5:1 against **both** bands
    /// — if it can't, invert it to white-on-deep, which is what Rosewood and
    /// Indigo do in Light.
    var tones: Tones {
        switch self {
        case .bone: Tones(
            light: Band(
                fill: RGB(r: 0.965, g: 0.952, b: 0.924),
                hairline: RGB(r: 0.883, g: 0.868, b: 0.842),
                text: RGB(r: 0.126, g: 0.110, b: 0.094),
                countFill: RGB(r: 0.912, g: 0.894, b: 0.862),
                countText: RGB(r: 0.330, g: 0.309, b: 0.286),
                // Ink, not a hue: Bone's accent is the one that simply flips,
                // near-black on light and near-white on dark. It is what makes
                // Bone the set's quiet option — the button is a step in value,
                // so the four type dots are the only colour in the window.
                // Lifted from 25% L to 33% at the same hue, by request: at
                // near-black the pill read as a hole punched in the band rather
                // than as the quietest of six accents. There is nothing to
                // solve for here — white on it was 15:1 and is now 11.6:1 —
                // so the only constraint is that it stay ink, which 33% does.
                primary: RGB(r: 0.235, g: 0.203, b: 0.171),
                primaryLabel: RGB(r: 0.981, g: 0.973, b: 0.957),
                // Deepened from the near-black primary: an ink ring at full
                // strength round a white card reads as a heavy border rather
                // than as a selection.
                ring: RGB(r: 0.459, g: 0.428, b: 0.396),
                trackFill: RGB(r: 0.908, g: 0.895, b: 0.867),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.312, g: 0.301, b: 0.278),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.126, g: 0.110, b: 0.094)),
            dark: Band(
                fill: RGB(r: 0.096, g: 0.084, b: 0.071),
                hairline: nil,
                text: RGB(r: 0.958, g: 0.947, b: 0.925),
                countFill: RGB(r: 0.205, g: 0.194, b: 0.183),
                countText: RGB(r: 0.833, g: 0.818, b: 0.786),
                primary: RGB(r: 0.936, g: 0.920, b: 0.888),
                primaryLabel: RGB(r: 0.099, g: 0.083, b: 0.068),
                ring: RGB(r: 0.936, g: 0.920, b: 0.888),
                trackFill: RGB(r: 0.187, g: 0.176, b: 0.164),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.846, g: 0.829, b: 0.811),
                segmentFill: RGB(r: 0.924, g: 0.906, b: 0.887),
                segmentLabelSelected: RGB(r: 0.096, g: 0.084, b: 0.071)))
        case .moss: Tones(
            light: Band(
                fill: RGB(r: 0.939, g: 0.964, b: 0.890),
                hairline: RGB(r: 0.845, g: 0.870, b: 0.796),
                text: RGB(r: 0.132, g: 0.178, b: 0.067),
                countFill: RGB(r: 0.868, g: 0.898, b: 0.807),
                countText: RGB(r: 0.280, g: 0.318, b: 0.225),
                // The chartreuse is out of sRGB at the plan's chroma and is
                // gamut-mapped by chroma reduction, which is why blue lands at
                // zero. It keeps its dark-mode value here — bright as it is, it
                // still carries a near-black label on a pale band at 8.2:1.
                primary: RGB(r: 0.706, g: 0.801, b: 0.000),
                primaryLabel: RGB(r: 0.121, g: 0.171, b: 0.000),
                ring: RGB(r: 0.484, g: 0.572, b: 0.000),
                trackFill: RGB(r: 0.884, g: 0.908, b: 0.834),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.292, g: 0.312, b: 0.250),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.132, g: 0.178, b: 0.067)),
            dark: Band(
                fill: RGB(r: 0.125, g: 0.167, b: 0.069),
                hairline: nil,
                text: RGB(r: 0.939, g: 0.958, b: 0.894),
                countFill: RGB(r: 0.230, g: 0.267, b: 0.181),
                countText: RGB(r: 0.805, g: 0.833, b: 0.749),
                primary: RGB(r: 0.781, g: 0.878, b: 0.242),
                primaryLabel: RGB(r: 0.124, g: 0.169, b: 0.022),
                ring: RGB(r: 0.781, g: 0.878, b: 0.242),
                trackFill: RGB(r: 0.213, g: 0.250, b: 0.162),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.798, g: 0.856, b: 0.734),
                segmentFill: RGB(r: 0.875, g: 0.934, b: 0.810),
                segmentLabelSelected: RGB(r: 0.125, g: 0.167, b: 0.069)))
        case .ember: Tones(
            light: Band(
                fill: RGB(r: 0.997, g: 0.942, b: 0.887),
                hairline: RGB(r: 0.899, g: 0.848, b: 0.800),
                text: RGB(r: 0.189, g: 0.124, b: 0.091),
                countFill: RGB(r: 0.938, g: 0.871, b: 0.803),
                countText: RGB(r: 0.354, g: 0.286, b: 0.242),
                primary: RGB(r: 0.977, g: 0.632, b: 0.160),
                primaryLabel: RGB(r: 0.216, g: 0.110, b: 0.047),
                // The original of the deepened-ring rule: an amber this bright
                // drawn as a 1.5pt outline round a card reads as the edge of a
                // button, so the ring steps down a level in Light.
                ring: RGB(r: 0.755, g: 0.437, b: 0.040),
                trackFill: RGB(r: 0.940, g: 0.886, b: 0.832),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.338, g: 0.294, b: 0.248),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.189, g: 0.124, b: 0.091)),
            dark: Band(
                fill: RGB(r: 0.150, g: 0.086, b: 0.058),
                hairline: nil,
                text: RGB(r: 0.980, g: 0.941, b: 0.899),
                countFill: RGB(r: 0.252, g: 0.196, b: 0.171),
                countText: RGB(r: 0.853, g: 0.812, b: 0.765),
                primary: RGB(r: 1.000, g: 0.659, b: 0.219),
                primaryLabel: RGB(r: 0.205, g: 0.101, b: 0.037),
                // No deepening in Dark: a bright ring on a dark card is what an
                // outline wants there.
                ring: RGB(r: 1.000, g: 0.659, b: 0.219),
                trackFill: RGB(r: 0.235, g: 0.178, b: 0.152),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.903, g: 0.810, b: 0.770),
                segmentFill: RGB(r: 0.981, g: 0.887, b: 0.846),
                segmentLabelSelected: RGB(r: 0.150, g: 0.086, b: 0.058)))
        case .rosewood: Tones(
            light: Band(
                fill: RGB(r: 1.000, g: 0.932, b: 0.932),
                hairline: RGB(r: 0.914, g: 0.836, b: 0.836),
                text: RGB(r: 0.233, g: 0.108, b: 0.114),
                countFill: RGB(r: 0.955, g: 0.856, b: 0.856),
                countText: RGB(r: 0.392, g: 0.279, b: 0.280),
                // Inverted, per the rule above: the dark theme's coral can't
                // carry a label on a pale ground, so Light gets a deeper red
                // and a white one — and a ring needs no deepening, because the
                // fill is already a deep one.
                primary: RGB(r: 0.756, g: 0.239, b: 0.203),
                primaryLabel: RGB(r: 1.000, g: 1.000, b: 1.000),
                ring: RGB(r: 0.756, g: 0.239, b: 0.203),
                trackFill: RGB(r: 0.945, g: 0.878, b: 0.878),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.341, g: 0.287, b: 0.287),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.233, g: 0.108, b: 0.114)),
            dark: Band(
                fill: RGB(r: 0.198, g: 0.081, b: 0.093),
                hairline: nil,
                text: RGB(r: 0.985, g: 0.934, b: 0.933),
                countFill: RGB(r: 0.294, g: 0.192, b: 0.202),
                countText: RGB(r: 0.870, g: 0.800, b: 0.798),
                primary: RGB(r: 1.000, g: 0.630, b: 0.581),
                primaryLabel: RGB(r: 0.225, g: 0.077, b: 0.084),
                ring: RGB(r: 1.000, g: 0.630, b: 0.581),
                trackFill: RGB(r: 0.278, g: 0.173, b: 0.184),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.950, g: 0.785, b: 0.792),
                segmentFill: RGB(r: 1.000, g: 0.874, b: 0.879),
                segmentLabelSelected: RGB(r: 0.198, g: 0.081, b: 0.093)))
        case .indigo: Tones(
            light: Band(
                fill: RGB(r: 0.941, g: 0.942, b: 1.000),
                hairline: RGB(r: 0.849, g: 0.850, b: 0.925),
                text: RGB(r: 0.152, g: 0.152, b: 0.283),
                countFill: RGB(r: 0.872, g: 0.874, b: 0.966),
                countText: RGB(r: 0.307, g: 0.306, b: 0.450),
                primary: RGB(r: 0.431, g: 0.324, b: 0.832),
                primaryLabel: RGB(r: 1.000, g: 1.000, b: 1.000),
                ring: RGB(r: 0.431, g: 0.324, b: 0.832),
                trackFill: RGB(r: 0.889, g: 0.890, b: 0.947),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.297, g: 0.297, b: 0.344),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.152, g: 0.152, b: 0.283)),
            dark: Band(
                fill: RGB(r: 0.100, g: 0.109, b: 0.223),
                hairline: nil,
                text: RGB(r: 0.945, g: 0.943, b: 0.984),
                countFill: RGB(r: 0.208, g: 0.216, b: 0.316),
                countText: RGB(r: 0.813, g: 0.809, b: 0.895),
                primary: RGB(r: 0.715, g: 0.666, b: 1.000),
                primaryLabel: RGB(r: 0.113, g: 0.102, b: 0.228),
                ring: RGB(r: 0.715, g: 0.666, b: 1.000),
                trackFill: RGB(r: 0.190, g: 0.198, b: 0.300),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.797, g: 0.821, b: 0.976),
                segmentFill: RGB(r: 0.886, g: 0.903, b: 1.000),
                segmentLabelSelected: RGB(r: 0.100, g: 0.109, b: 0.223)))
        case .dracula: Tones(
            light: Band(
                fill: RGB(r: 0.941, g: 0.910, b: 0.992),
                hairline: RGB(r: 0.871, g: 0.816, b: 0.965),
                text: RGB(r: 0.235, g: 0.165, b: 0.388),
                countFill: RGB(r: 0.882, g: 0.824, b: 0.980),
                countText: RGB(r: 0.357, g: 0.271, b: 0.549),
                // The pink survives the move to a pale band, which is why
                // Dracula keeps one primary across both appearances where
                // Rosewood and Indigo don't.
                primary: RGB(r: 1.000, g: 0.475, b: 0.776),
                primaryLabel: RGB(r: 0.290, g: 0.122, b: 0.235),
                // Dracula's purple, not its pink, in both appearances: the pink
                // is the primary, and a ring in the same colour as the button
                // beside it stops meaning "selected".
                ring: RGB(r: 0.741, g: 0.576, b: 0.976),
                trackFill: RGB(r: 0.911, g: 0.880, b: 0.961),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.314, g: 0.288, b: 0.355),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.235, g: 0.165, b: 0.388)),
            dark: Band(
                fill: RGB(r: 0.227, g: 0.184, b: 0.369),
                hairline: nil,
                text: RGB(r: 0.973, g: 0.973, b: 0.949),
                countFill: RGB(r: 0.320, g: 0.282, b: 0.444),
                countText: RGB(r: 0.839, g: 0.812, b: 0.980),
                primary: RGB(r: 1.000, g: 0.475, b: 0.776),
                primaryLabel: RGB(r: 0.169, g: 0.129, b: 0.212),
                ring: RGB(r: 0.741, g: 0.576, b: 0.976),
                trackFill: RGB(r: 0.305, g: 0.266, b: 0.432),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.834, g: 0.802, b: 1.000),
                segmentFill: RGB(r: 0.909, g: 0.894, b: 1.000),
                segmentLabelSelected: RGB(r: 0.227, g: 0.184, b: 0.369)))
        }
    }

    /// The page and card grounds. Light cards are pure white in every theme; the
    /// dark card edge is white at 7% over the dark card, composited here rather
    /// than layered at draw time.
    var grounds: Grounds {
        switch self {
        case .bone: Grounds(
            window: DynamicRGB(light: RGB(r: 0.985, g: 0.978, b: 0.965), dark: RGB(r: 0.105, g: 0.093, b: 0.080)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.144, g: 0.129, b: 0.112)),
            border: DynamicRGB(light: RGB(r: 0.900, g: 0.888, b: 0.867), dark: RGB(r: 0.204, g: 0.190, b: 0.174)))
        case .moss: Grounds(
            window: DynamicRGB(light: RGB(r: 0.979, g: 0.985, b: 0.962), dark: RGB(r: 0.087, g: 0.101, b: 0.070)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.120, g: 0.140, b: 0.096)),
            border: DynamicRGB(light: RGB(r: 0.877, g: 0.889, b: 0.855), dark: RGB(r: 0.181, g: 0.200, b: 0.159)))
        case .ember: Grounds(
            window: DynamicRGB(light: RGB(r: 0.996, g: 0.979, b: 0.960), dark: RGB(r: 0.103, g: 0.068, b: 0.056)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.156, g: 0.111, b: 0.093)),
            border: DynamicRGB(light: RGB(r: 0.901, g: 0.879, b: 0.856), dark: RGB(r: 0.215, g: 0.173, b: 0.157)))
        case .rosewood: Grounds(
            window: DynamicRGB(light: RGB(r: 0.999, g: 0.974, b: 0.973), dark: RGB(r: 0.121, g: 0.070, b: 0.076)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.176, g: 0.112, b: 0.117)),
            border: DynamicRGB(light: RGB(r: 0.914, g: 0.872, b: 0.871), dark: RGB(r: 0.234, g: 0.174, b: 0.179)))
        case .indigo: Grounds(
            window: DynamicRGB(light: RGB(r: 0.978, g: 0.978, b: 1.000), dark: RGB(r: 0.078, g: 0.082, b: 0.129)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.123, g: 0.126, b: 0.184)),
            border: DynamicRGB(light: RGB(r: 0.878, g: 0.879, b: 0.920), dark: RGB(r: 0.184, g: 0.187, b: 0.241)))
        // The only theme whose grounds are named rather than derived — the
        // Dracula palette's own window, card and edge.
        case .dracula: Grounds(
            window: DynamicRGB(light: RGB(r: 0.980, g: 0.969, b: 1.000), dark: RGB(r: 0.157, g: 0.165, b: 0.212)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.184, g: 0.192, b: 0.247)),
            border: DynamicRGB(light: RGB(r: 0.906, g: 0.867, b: 0.969), dark: RGB(r: 0.247, g: 0.259, b: 0.337)))
        }
    }

    /// Metadata type, per theme: the page hue at 50% L in Light and 70% in Dark,
    /// with the Increase Contrast pair at 26% / 88%.
    ///
    /// **Dracula's is named rather than derived** (`#6b6288` / `#9098b8`, from its
    /// own palette), which is also why it is the tightest text pairing in the
    /// file: 5.6:1 in Light and **4.52:1** in Dark against its card, where the
    /// five derived values all land near 6:1. It clears the 4.5:1 floor and it is
    /// the palette's own value, so it stands — but it is the one entry here with
    /// no room left, and a card face nudged lighter would take it under. Its HC
    /// pair follows the same 26% / 88% rule at its own hue.
    var metaTones: DynamicRGB {
        switch self {
        case .bone: DynamicRGB(
            light: RGB(r: 0.399, g: 0.388, b: 0.364), dark: RGB(r: 0.638, g: 0.617, b: 0.596),
            lightHC: RGB(r: 0.150, g: 0.140, b: 0.120), darkHC: RGB(r: 0.863, g: 0.841, b: 0.818))
        case .moss: DynamicRGB(
            light: RGB(r: 0.385, g: 0.393, b: 0.368), dark: RGB(r: 0.609, g: 0.629, b: 0.588),
            lightHC: RGB(r: 0.138, g: 0.144, b: 0.123), darkHC: RGB(r: 0.832, g: 0.853, b: 0.810))
        case .ember: DynamicRGB(
            light: RGB(r: 0.404, g: 0.386, b: 0.365), dark: RGB(r: 0.658, g: 0.609, b: 0.592),
            lightHC: RGB(r: 0.154, g: 0.138, b: 0.121), darkHC: RGB(r: 0.884, g: 0.832, b: 0.814))
        case .rosewood: DynamicRGB(
            light: RGB(r: 0.411, g: 0.381, b: 0.380), dark: RGB(r: 0.673, g: 0.600, b: 0.606),
            lightHC: RGB(r: 0.160, g: 0.134, b: 0.133), darkHC: RGB(r: 0.900, g: 0.823, b: 0.829))
        case .indigo: DynamicRGB(
            light: RGB(r: 0.386, g: 0.386, b: 0.411), dark: RGB(r: 0.608, g: 0.616, b: 0.681),
            lightHC: RGB(r: 0.139, g: 0.139, b: 0.160), darkHC: RGB(r: 0.831, g: 0.840, b: 0.908))
        case .dracula: DynamicRGB(
            light: RGB(r: 0.420, g: 0.384, b: 0.533), dark: RGB(r: 0.565, g: 0.596, b: 0.722),
            lightHC: RGB(r: 0.151, g: 0.114, b: 0.242), darkHC: RGB(r: 0.805, g: 0.839, b: 0.973))
        }
    }

    /// The title and body colours, for the **one** theme that is a text palette
    /// by origin. `nil` everywhere else, and that is the rule rather than an
    /// omission: five of the six leave the writing on `labelColor`, so a card's
    /// paragraph reads at the system's own contrast whatever theme is on.
    ///
    /// Dracula's four values are its palette's own (`#f8f8f2` / `#cfd2e0` dark,
    /// `#2c2145` / `#463d63` light) and need no Increase Contrast variants: the
    /// softest of them is the dark body at 8.6:1 on its card, already past the
    /// 7:1 that switch promises.
    var writingTones: WritingTones? {
        switch self {
        case .dracula: WritingTones(
            title: DynamicRGB(
                light: RGB(r: 0.173, g: 0.129, b: 0.271),
                dark: RGB(r: 0.973, g: 0.973, b: 0.949)),
            body: DynamicRGB(
                light: RGB(r: 0.275, g: 0.239, b: 0.388),
                dark: RGB(r: 0.812, g: 0.824, b: 0.878)))
        default: nil
        }
    }

    /// The four note types' marks and labels, per theme — rule 3, and the part
    /// that costs the most rows for the least code.
    ///
    /// Keyed by **`Tint`**, not by note-type id, and that is what makes it work
    /// with a user-extensible list of types: the four defaults wear blue, yellow,
    /// purple and green (Note, Meeting, Feedback, Staffing), so a theme overrides
    /// those four and a custom type on any other tint falls through to
    /// `Tint.ink`, the app's own solved foreground. A table keyed by the four
    /// built-in ids would have left a custom type with no themed mark at all —
    /// and a type whose tint the user *changed* would have kept a colour naming
    /// the type it no longer matches.
    ///
    /// The hues are authored per theme rather than shared, and each set is
    /// arranged around its own primary: **no type hue is within 25° of the
    /// theme's accent** (`ThemePaletteTests`), which is what keeps "action"
    /// legible as action. Ember is where that bites — the plan puts its Meeting
    /// at hue 92 against an amber primary at 68, which is 24° and fails the
    /// plan's own rule by one degree, so Meeting sits at 95 here. Three degrees
    /// is invisible; a type that reads as the button is not.
    ///
    /// The Increase Contrast variants are **derived**, not solved: ±8–9 points of
    /// lightness at the same hue and chroma, which takes every one of them past
    /// 7:1 on the card it is drawn on (worst 7.18:1, Dracula's Meeting label).
    /// The plan gives no HC values, and stepping lightness is the one move that
    /// can't change which colour a type *is*.
    ///
    /// **One acceptance criterion is measured and not met, and it is not fixed
    /// here.** The plan asks that a theme's four marks be "mutually
    /// distinguishable in greyscale as well as in colour (they differ in
    /// lightness, not only hue)" — but its own tables put three of the four at
    /// essentially one lightness (50 / 56 / 50 / 49 in Bone's light set, and much
    /// the same in the others), so the worst pair in every theme is 1.00–1.07:1
    /// by luminance. Meeting is the only one that separates. Spreading the four
    /// apart would mean re-authoring the palettes rather than converting them,
    /// which is a design decision and not a conversion, so the tables are
    /// implemented as given and the gap is recorded here. If it is taken up, the
    /// lever is lightness at fixed hue, and `ThemePaletteTests` is where the
    /// check would go.
    var typePalette: [Tint: TypeTone] {
        switch self {
        case .bone: [
            // Note
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.182, g: 0.404, b: 0.601), dark: RGB(r: 0.465, g: 0.692, b: 0.906),
                                 lightHC: RGB(r: 0.065, g: 0.303, b: 0.492), darkHC: RGB(r: 0.575, g: 0.792, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.141, g: 0.336, b: 0.508), dark: RGB(r: 0.465, g: 0.692, b: 0.906),
                                  lightHC: RGB(r: 0.020, g: 0.238, b: 0.402), darkHC: RGB(r: 0.575, g: 0.792, b: 1.000))),
            // Meeting
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.674, g: 0.360, b: 0.182), dark: RGB(r: 0.946, g: 0.633, b: 0.472),
                                 lightHC: RGB(r: 0.559, g: 0.256, b: 0.056), darkHC: RGB(r: 1.000, g: 0.758, b: 0.635)),
                label: DynamicRGB(light: RGB(r: 0.557, g: 0.279, b: 0.116), dark: RGB(r: 0.946, g: 0.633, b: 0.472),
                                  lightHC: RGB(r: 0.441, g: 0.183, b: 0.000), darkHC: RGB(r: 1.000, g: 0.758, b: 0.635))),
            // Feedback
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.447, g: 0.319, b: 0.585), dark: RGB(r: 0.727, g: 0.607, b: 0.870),
                                 lightHC: RGB(r: 0.347, g: 0.219, b: 0.476), darkHC: RGB(r: 0.828, g: 0.705, b: 0.975)),
                label: DynamicRGB(light: RGB(r: 0.386, g: 0.272, b: 0.507), dark: RGB(r: 0.727, g: 0.607, b: 0.870),
                                  lightHC: RGB(r: 0.288, g: 0.175, b: 0.402), darkHC: RGB(r: 0.828, g: 0.705, b: 0.975))),
            // Staffing
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.169, g: 0.438, b: 0.300), dark: RGB(r: 0.472, g: 0.739, b: 0.585),
                                 lightHC: RGB(r: 0.030, g: 0.336, b: 0.205), darkHC: RGB(r: 0.570, g: 0.840, b: 0.682)),
                label: DynamicRGB(light: RGB(r: 0.101, g: 0.381, b: 0.247), dark: RGB(r: 0.472, g: 0.739, b: 0.585),
                                  lightHC: RGB(r: 0.000, g: 0.278, b: 0.162), darkHC: RGB(r: 0.570, g: 0.840, b: 0.682))),
        ]
        case .moss: [
            // Note
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.000, g: 0.416, b: 0.617), dark: RGB(r: 0.444, g: 0.789, b: 0.982),
                                 lightHC: RGB(r: 0.000, g: 0.312, b: 0.470), darkHC: RGB(r: 0.672, g: 0.877, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.007, g: 0.346, b: 0.516), dark: RGB(r: 0.444, g: 0.789, b: 0.982),
                                  lightHC: RGB(r: 0.000, g: 0.246, b: 0.376), darkHC: RGB(r: 0.672, g: 0.877, b: 1.000))),
            // Meeting
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.710, g: 0.331, b: 0.132), dark: RGB(r: 0.987, g: 0.609, b: 0.435),
                                 lightHC: RGB(r: 0.584, g: 0.232, b: 0.000), darkHC: RGB(r: 1.000, g: 0.756, b: 0.648)),
                label: DynamicRGB(light: RGB(r: 0.576, g: 0.263, b: 0.099), dark: RGB(r: 0.987, g: 0.609, b: 0.435),
                                  lightHC: RGB(r: 0.452, g: 0.172, b: 0.000), darkHC: RGB(r: 1.000, g: 0.756, b: 0.648))),
            // Feedback — mauve, not the app's violet: Moss's palette moves it
            // away from the greens it has given up.
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.535, g: 0.310, b: 0.571), dark: RGB(r: 0.838, g: 0.636, b: 0.869),
                                 lightHC: RGB(r: 0.429, g: 0.209, b: 0.463), darkHC: RGB(r: 0.943, g: 0.735, b: 0.974)),
                label: DynamicRGB(light: RGB(r: 0.455, g: 0.254, b: 0.486), dark: RGB(r: 0.838, g: 0.636, b: 0.869),
                                  lightHC: RGB(r: 0.351, g: 0.156, b: 0.382), darkHC: RGB(r: 0.943, g: 0.735, b: 0.974))),
            // Staffing — teal. This is rule 2 in one value: the theme's accent
            // is chartreuse, so its type palette has no green in it at all.
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.000, g: 0.442, b: 0.480), dark: RGB(r: 0.443, g: 0.814, b: 0.833),
                                 lightHC: RGB(r: 0.000, g: 0.333, b: 0.362), darkHC: RGB(r: 0.547, g: 0.917, b: 0.937)),
                label: DynamicRGB(light: RGB(r: 0.000, g: 0.369, b: 0.401), dark: RGB(r: 0.443, g: 0.814, b: 0.833),
                                  lightHC: RGB(r: 0.000, g: 0.264, b: 0.287), darkHC: RGB(r: 0.547, g: 0.917, b: 0.937))),
        ]
        case .ember: [
            // Note
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.000, g: 0.421, b: 0.596), dark: RGB(r: 0.377, g: 0.742, b: 0.921),
                                 lightHC: RGB(r: 0.000, g: 0.316, b: 0.453), darkHC: RGB(r: 0.528, g: 0.840, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.000, g: 0.350, b: 0.500), dark: RGB(r: 0.377, g: 0.742, b: 0.921),
                                  lightHC: RGB(r: 0.000, g: 0.250, b: 0.362), darkHC: RGB(r: 0.528, g: 0.840, b: 1.000))),
            // Meeting — gold-olive at hue 95, three degrees past the plan's 92,
            // which is what puts it 27° clear of the amber primary.
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.567, g: 0.473, b: 0.000), dark: RGB(r: 0.898, g: 0.790, b: 0.370),
                                 lightHC: RGB(r: 0.449, g: 0.372, b: 0.000), darkHC: RGB(r: 1.000, g: 0.894, b: 0.488)),
                label: DynamicRGB(light: RGB(r: 0.436, g: 0.361, b: 0.000), dark: RGB(r: 0.898, g: 0.790, b: 0.370),
                                  lightHC: RGB(r: 0.324, g: 0.266, b: 0.000), darkHC: RGB(r: 1.000, g: 0.894, b: 0.488))),
            // Feedback
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.559, g: 0.301, b: 0.539), dark: RGB(r: 0.850, g: 0.593, b: 0.825),
                                 lightHC: RGB(r: 0.450, g: 0.200, b: 0.433), darkHC: RGB(r: 0.955, g: 0.692, b: 0.929)),
                label: DynamicRGB(light: RGB(r: 0.476, g: 0.246, b: 0.458), dark: RGB(r: 0.850, g: 0.593, b: 0.825),
                                  lightHC: RGB(r: 0.370, g: 0.147, b: 0.356), darkHC: RGB(r: 0.955, g: 0.692, b: 0.929))),
            // Staffing
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.068, g: 0.458, b: 0.332), dark: RGB(r: 0.460, g: 0.800, b: 0.657),
                                 lightHC: RGB(r: 0.000, g: 0.348, b: 0.245), darkHC: RGB(r: 0.562, g: 0.903, b: 0.756)),
                label: DynamicRGB(light: RGB(r: 0.028, g: 0.383, b: 0.274), dark: RGB(r: 0.460, g: 0.800, b: 0.657),
                                  lightHC: RGB(r: 0.000, g: 0.276, b: 0.191), darkHC: RGB(r: 0.562, g: 0.903, b: 0.756))),
        ]
        case .rosewood: [
            // Note
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.000, g: 0.425, b: 0.577), dark: RGB(r: 0.425, g: 0.769, b: 0.917),
                                 lightHC: RGB(r: 0.000, g: 0.319, b: 0.438), darkHC: RGB(r: 0.568, g: 0.867, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.000, g: 0.354, b: 0.483), dark: RGB(r: 0.425, g: 0.769, b: 0.917),
                                  lightHC: RGB(r: 0.000, g: 0.252, b: 0.350), darkHC: RGB(r: 0.568, g: 0.867, b: 1.000))),
            // Meeting — gold, warmed away from the coral primary.
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.588, g: 0.425, b: 0.000), dark: RGB(r: 0.921, g: 0.738, b: 0.388),
                                 lightHC: RGB(r: 0.461, g: 0.330, b: 0.000), darkHC: RGB(r: 1.000, g: 0.848, b: 0.568)),
                label: DynamicRGB(light: RGB(r: 0.475, g: 0.341, b: 0.000), dark: RGB(r: 0.921, g: 0.738, b: 0.388),
                                  lightHC: RGB(r: 0.354, g: 0.250, b: 0.000), darkHC: RGB(r: 1.000, g: 0.848, b: 0.568))),
            // Feedback
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.512, g: 0.319, b: 0.596), dark: RGB(r: 0.798, g: 0.610, b: 0.883),
                                 lightHC: RGB(r: 0.408, g: 0.218, b: 0.487), darkHC: RGB(r: 0.901, g: 0.709, b: 0.989)),
                label: DynamicRGB(light: RGB(r: 0.434, g: 0.262, b: 0.509), dark: RGB(r: 0.798, g: 0.610, b: 0.883),
                                  lightHC: RGB(r: 0.333, g: 0.164, b: 0.403), darkHC: RGB(r: 0.901, g: 0.709, b: 0.989))),
            // Staffing — jade.
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.000, g: 0.459, b: 0.355), dark: RGB(r: 0.464, g: 0.827, b: 0.705),
                                 lightHC: RGB(r: 0.000, g: 0.346, b: 0.265), darkHC: RGB(r: 0.567, g: 0.930, b: 0.806)),
                label: DynamicRGB(light: RGB(r: 0.000, g: 0.383, b: 0.294), dark: RGB(r: 0.464, g: 0.827, b: 0.705),
                                  lightHC: RGB(r: 0.000, g: 0.274, b: 0.207), darkHC: RGB(r: 0.567, g: 0.930, b: 0.806))),
        ]
        case .indigo: [
            // Note
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.000, g: 0.408, b: 0.507), dark: RGB(r: 0.369, g: 0.811, b: 0.928),
                                 lightHC: RGB(r: 0.000, g: 0.303, b: 0.379), darkHC: RGB(r: 0.565, g: 0.903, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.000, g: 0.349, b: 0.435), dark: RGB(r: 0.369, g: 0.811, b: 0.928),
                                  lightHC: RGB(r: 0.000, g: 0.246, b: 0.310), darkHC: RGB(r: 0.565, g: 0.903, b: 1.000))),
            // Meeting
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.624, g: 0.403, b: 0.000), dark: RGB(r: 0.958, g: 0.718, b: 0.406),
                                 lightHC: RGB(r: 0.490, g: 0.313, b: 0.000), darkHC: RGB(r: 1.000, g: 0.840, b: 0.646)),
                label: DynamicRGB(light: RGB(r: 0.505, g: 0.323, b: 0.000), dark: RGB(r: 0.958, g: 0.718, b: 0.406),
                                  lightHC: RGB(r: 0.377, g: 0.236, b: 0.000), darkHC: RGB(r: 1.000, g: 0.840, b: 0.646))),
            // Feedback — rose, pushed off violet so it can't be mistaken for
            // the periwinkle primary.
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.609, g: 0.263, b: 0.509), dark: RGB(r: 0.894, g: 0.573, b: 0.788),
                                 lightHC: RGB(r: 0.496, g: 0.157, b: 0.405), darkHC: RGB(r: 1.000, g: 0.672, b: 0.890)),
                label: DynamicRGB(light: RGB(r: 0.510, g: 0.224, b: 0.427), dark: RGB(r: 0.894, g: 0.573, b: 0.788),
                                  lightHC: RGB(r: 0.401, g: 0.121, b: 0.326), darkHC: RGB(r: 1.000, g: 0.672, b: 0.890))),
            // Staffing
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.079, g: 0.461, b: 0.291), dark: RGB(r: 0.484, g: 0.862, b: 0.652),
                                 lightHC: RGB(r: 0.000, g: 0.351, b: 0.210), darkHC: RGB(r: 0.587, g: 0.967, b: 0.752)),
                label: DynamicRGB(light: RGB(r: 0.030, g: 0.386, b: 0.237), dark: RGB(r: 0.484, g: 0.862, b: 0.652),
                                  lightHC: RGB(r: 0.000, g: 0.278, b: 0.162), darkHC: RGB(r: 0.587, g: 0.967, b: 0.752))),
        ]
        // The real Dracula hues in Dark. In Light they are the palette darkened
        // in oklch until each clears its floor on white: the plan's own light
        // values land at 4.1–4.3:1, which is fine for a capsule and short for
        // the label beside it.
        case .dracula: [
            // Note — cyan.
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.090, g: 0.525, b: 0.612), dark: RGB(r: 0.545, g: 0.914, b: 0.992),
                                 lightHC: RGB(r: 0.000, g: 0.416, b: 0.489), darkHC: RGB(r: 0.865, g: 0.975, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.086, g: 0.467, b: 0.541), dark: RGB(r: 0.545, g: 0.914, b: 0.992),
                                  lightHC: RGB(r: 0.000, g: 0.360, b: 0.423), darkHC: RGB(r: 0.865, g: 0.975, b: 1.000))),
            // Meeting — orange.
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.706, g: 0.404, b: 0.039), dark: RGB(r: 1.000, g: 0.722, b: 0.424),
                                 lightHC: RGB(r: 0.567, g: 0.316, b: 0.000), darkHC: RGB(r: 1.000, g: 0.861, b: 0.723)),
                label: DynamicRGB(light: RGB(r: 0.639, g: 0.373, b: 0.031), dark: RGB(r: 1.000, g: 0.722, b: 0.424),
                                  lightHC: RGB(r: 0.504, g: 0.285, b: 0.000), darkHC: RGB(r: 1.000, g: 0.861, b: 0.723))),
            // Feedback — purple.
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.498, g: 0.271, b: 0.878), dark: RGB(r: 0.741, g: 0.576, b: 0.976),
                                 lightHC: RGB(r: 0.401, g: 0.135, b: 0.757), darkHC: RGB(r: 0.821, g: 0.707, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.478, g: 0.247, b: 0.847), dark: RGB(r: 0.741, g: 0.576, b: 0.976),
                                  lightHC: RGB(r: 0.382, g: 0.104, b: 0.726), darkHC: RGB(r: 0.821, g: 0.707, b: 1.000))),
            // Staffing — green.
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.102, g: 0.561, b: 0.290), dark: RGB(r: 0.314, g: 0.980, b: 0.482),
                                 lightHC: RGB(r: 0.000, g: 0.446, b: 0.212), darkHC: RGB(r: 0.790, g: 1.000, b: 0.815)),
                label: DynamicRGB(light: RGB(r: 0.094, g: 0.498, b: 0.259), dark: RGB(r: 0.314, g: 0.980, b: 0.482),
                                  lightHC: RGB(r: 0.000, g: 0.386, b: 0.182), darkHC: RGB(r: 0.790, g: 1.000, b: 0.815))),
        ]
        }
    }
}

// MARK: - Picker

/// The Theme row's six swatches (Settings → General). Each one is a **miniature
/// of the thing it changes** rather than a dot of the primary alone, because the
/// band is most of what a theme is and a single colour chip couldn't say which of
/// the two it stood for.
///
/// It shows **one half — the appearance you are actually in**, through the same
/// dynamic colours the window draws with, so the swatch and the band agree. The
/// light and dark halves were briefly stacked in one swatch, on the argument that
/// a theme carries both values and previewing one hides half of what is being
/// chosen; at 74pt wide that read as two slabs bolted together rather than as one
/// preview, and it was reversed on sight. The caption under the row is where the
/// other half is explained instead — "Light and dark values are built in —
/// Appearance decides which you see" — which is a sentence doing a job no
/// 22pt-tall rectangle could.
///
/// **Two shapes, not three.** The swatch drew a short capsule for the heading as
/// well, standing in for the column title, and at 20×3pt it read as a stray line
/// rather than as text. What the picker has to answer is "which colours is this",
/// and a band plus a pill answers it at the proportions those two really have.
///
/// A grid of three columns, not a row of six: at the width the miniature needs to
/// read as a band-plus-button, six across overflow the pane — the line the tint
/// picker this replaced had already hit at seven 52pt swatches, and the answer is
/// the same one, a grid rather than smaller swatches, because below about 46pt a
/// swatch stops previewing anything.
struct ThemePicker: View {
    let selection: AppTheme
    let onSelect: (AppTheme) -> Void

    private static let swatchWidth: CGFloat = 74
    private static let swatchHeight: CGFloat = 38
    /// 9pt, matching the tint swatches this replaced: a swatch previews a
    /// surface, so it is not a capsule ("round means pressable", CLAUDE.md
    /// decision 6).
    private static let radius: CGFloat = 9

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(Self.swatchWidth), spacing: 10), count: 3),
            alignment: .trailing,
            spacing: 10
        ) {
            ForEach(AppTheme.allCases) { theme in
                swatch(theme)
            }
        }
        // The selection ring overhangs its swatch; give it room rather than
        // letting the Form row clip it.
        .padding(.vertical, 4)
    }

    private func swatch(_ theme: AppTheme) -> some View {
        let selected = theme == selection
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let band = theme.band

        return Button {
            onSelect(theme)
        } label: {
            VStack(spacing: 6) {
                shape
                    .fill(band.fill)
                    .frame(width: Self.swatchWidth, height: Self.swatchHeight)
                    .overlay {
                        // The primary as the pill it really is, centred — the
                        // control on the surface, which is the whole theme.
                        Capsule()
                            .fill(band.primary)
                            .frame(width: 30, height: 12)
                    }
                    .overlay { shape.strokeBorder(Stone.line, lineWidth: 0.5) }
                // The selection ring in the theme's *own* primary, which is the
                // only ring in the app that can't be checked once: it sits on
                // the Form row's neutral ground, where an outline carries the
                // 3:1 an indicator needs (the case `Tint` rules out on tinted
                // ground).
                .overlay {
                    RoundedRectangle(cornerRadius: Self.radius + 2, style: .continuous)
                        .strokeBorder(theme.primary, lineWidth: 1.5)
                        .padding(-3)
                        .opacity(selected ? 1 : 0)
                }

                Text(theme.label)
                    .font(.caption)
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    // Held to the swatch's width, so a longer name widens its
                    // own column rather than knocking the grid out of step.
                    .multilineTextAlignment(.center)
                    .frame(width: Self.swatchWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
