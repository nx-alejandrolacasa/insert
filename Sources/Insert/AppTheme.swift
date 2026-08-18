import AppKit
import SwiftUI

// MARK: - AppTheme

/// One of six named themes — Settings → Appearance → Theme. A theme is **three
/// grounds, one accent and its own note-type palette**, and those three are the
/// rules: a theme that breaks any of them reads as a *setting* rather than as a
/// theme, which is exactly what the first set did.
///
/// 1. **Three grounds — band, page, card.** The band is the surface behind a
///    column heading (`ColumnHeaderBand`); the page (`windowFill`, and so the
///    sidebar, which is see-through to it) and the card (`cardFace`) carry the
///    same hue family. So the window belongs to the theme instead of being a
///    coloured strip on neutral grey. The glass track on the band derives from
///    the band and is not a token set of its own.
/// 2. **One accent, for action only** — `primary`: "New Note" / "New Task",
///    focus rings, selected states (CLAUDE.md decision 4). It may not sit within
///    25° of a hue from the theme's own note-type palette, which is why Kanagawa
///    has no orange in its types: the only orange thing on screen is the button.
/// 3. **Its own note-type palette.** Authored per theme rather than shared, and
///    most of what makes a theme feel designed.
/// 4. **The four marks form a lightness ladder**, so they are told apart in
///    greyscale as well as by hue. Every source palette puts three or four of its
///    hues at one lightness; each theme's four are re-levelled apart. One
///    documented exception, Dracula — see its case.
/// 5. **Text is not themed, except metadata.** `titleText` and `bodyText` are
///    `labelColor` in five of the six; only Dracula names its own, and it earns
///    that by being a text palette by origin.
/// 6. **The count chip is accented** — the accent at low alpha, composited over
///    the band, under a legible tint of itself. System is excluded: a theme whose
///    whole claim is that it adds no colour of its own cannot colour the chip.
///
/// **This is the second set of six, and the swap is the interesting part.** The
/// first (Bone, Moss, Ember, Rosewood, Indigo, plus Dracula) obeyed all of the
/// rules above and still came out as a *preference*, because every hue in it was
/// one somebody picked: a set of chosen hues has nothing to be faithful to, so
/// there is no answer to "why this green" beyond taste, and the only theme in it
/// that read as an identity was the one borrowed from somewhere else. So five of
/// the six are now **sourced palettes**, read from the upstream project rather
/// than designed here (each case names the repo and file it came from),
/// and the sixth is the platform's own. What we changed, per theme, is stated in
/// its case: **verbatim** for grounds, hairlines, links and accents;
/// **deepened** where an accent's label could not clear 4.5:1; **derived** where
/// a palette's comment grey failed on a card; and **re-levelled**, always, for
/// the four marks.
///
/// The band-is-where-colour-goes finding the first set was built on is unchanged,
/// and so is everything in the July 2026 refresh it carried forward — including
/// the **retired highlighter stroke** behind note titles (a coloured band under
/// glyphs fights the letters at any opacity, so a type's mark is a 3pt capsule
/// *beside* the title; see `TypeMarkTitle`). What was wrong was picking the hues.
///
/// **Two rules of the previous set are deliberately reversed here.** Light cards
/// are no longer pure white in all six — Kanagawa's Lotus paper is `#fffdf0` and
/// Rosé Pine's Dawn `surface` is `#fffaf3`, because a sourced palette's own paper
/// is part of what it is — so the contrast floor is measured against **the card
/// actually painted** rather than verified once against white. And a theme's
/// `ring` no longer has to differ from its `primary`: it is the accent, deepened
/// only where the accent itself lands under 3:1 on the card it outlines.
///
/// **Every value is measured.** The plan's oklch spec is converted to sRGB
/// offline, with the track and the raised segment derived from the band's own hue
/// by the rules in the comments below. Each theme's worst *text* pairing, in
/// either appearance, clears the refresh's 4.5:1 floor for text under 14px
/// (CLAUDE.md decision 5), and the pairings checked are: band text on the band,
/// count text on the count chip, primary label on the primary fill, an unselected
/// segment label on the track, a selected one on the raised pill, the metadata
/// colour on the card, a link on the card, and each of the four type labels on
/// the card. Graphics — the type marks, the filter track's dots and the selection
/// ring — are checked at 3:1 and clear it (worst 3.03:1, and the three values
/// that had to be stepped to get there are named where they are declared).
enum AppTheme: String, CaseIterable, Identifiable {
    // Declaration order **is** the order of the picker, and unlike the previous
    // set the default is the first case rather than a different one: System
    // leads because it is what a new install opens wearing, and the five that
    // follow run cool → warm → cool → identity.

    /// The platform. No colours of our own — the one theme in the set that is
    /// not a borrowed palette, and the **default**.
    ///
    /// Its blues are the system's, *deepened*: `systemBlue` measures ~4.0:1 as a
    /// white-label fill and as link text on white, so the button and the light
    /// link each step down until they clear 4.5:1. Its four type marks are the
    /// system teal / orange / purple / green, deepened into rule 4's ladder,
    /// because the shipping four resolve to nearly one lightness.
    ///
    /// **It is written down rather than read from semantic tokens, and that was
    /// measured rather than assumed.** The plan asks for the tokens themselves,
    /// on the sound argument that they resolve per appearance and contrast
    /// setting; the obstacle is that its names are UIKit's, and the AppKit pair
    /// that would stand in for page and card — `windowBackgroundColor` and
    /// `controlBackgroundColor` — resolve to **the same value** on macOS 26
    /// (`#ffffff` Light, `#1e1e1e` Dark), so a card would vanish into the page it
    /// is meant to sit forward of. There is no macOS token for `systemGray5` or
    /// `tertiarySystemBackground` either, and the band's derived tones have to be
    /// composited offline against a concrete band. So the grounds are written
    /// down — the plan's grouped ladder in Dark, and in Light a **white page under
    /// a grey band**, which is that ladder with its two lightest steps swapped and
    /// is what `windowBackgroundColor` really resolves to today. The writing is still the platform's, through
    /// `labelColor` — which is what `titleText` and `bodyText` hand back for five
    /// of the six themes anyway.
    case system

    /// `tokyonight.org/palette` (upstream `tokyo-night/tokyo-night-vscode-theme`).
    /// Indigo-slate grounds, **mint** action.
    ///
    /// The accent is the mint `#73daca` and not the red `#f7768e`, which is Tokyo
    /// Night's *errors* colour: spending it on the primary button would leave the
    /// app with no red for `Semantic.overdue`. Because it isn't a button here,
    /// this is the one theme in the set where overdue needs no special case at
    /// all. Its light-mode foregrounds are all derived — the source publishes a
    /// light background and nothing else.
    case tokyoNight

    /// `rebelot/kanagawa.nvim` → `lua/kanagawa/colors.lua`. Dark is Wave, Light
    /// is Lotus: warm cream on cold ink, and the set's one warm theme.
    ///
    /// **Orange is removed from the note types**, project dots included, so the
    /// only orange on screen is the button (`surimiOrange`). Lotus's own
    /// `#f2ecbc` page is too yellow to carry a window, so the page and cards are
    /// derived *above* the band and the band is the only saturated surface.
    case kanagawa

    /// `hmseeb/dark-owl` → `theme/dark-owl.json`. Teal-navy grounds, violet
    /// action, spring-green links.
    ///
    /// The accent is the theme's own `button.background` at **full opacity**: the
    /// shipped `cc` alpha drops the white label under 4.5:1. Its light link is a
    /// deep jade rather than the theme's `#00ff9f`, which measures 1.4:1 on white.
    case darkOwl

    /// `rose-pine/palette`. Dark is main, Light is Dawn — plum and rose, on
    /// Dawn's pink-cream paper.
    ///
    /// **A recorded exception to rule 2**: `love` (343°) and the blush Feedback
    /// mark (2°) are 19° apart in Light and 17° in Dark, inside the 25° the rule
    /// asks for. The palette is built on that pairing, the button is a saturated
    /// mid-tone where the mark is a pale blush, and the two never sit adjacent.
    /// `ThemePaletteTests` records it by name rather than relaxing the rule; do
    /// not "fix" it.
    case rosePine

    /// The original of the set, and now the theme the other five were built to
    /// match — it was the only one in the first cut that read as an identity
    /// rather than as a shade, which is the observation this whole set came from.
    /// Unchanged in structure, with two changes of its own.
    ///
    /// **Pink and purple are swapped.** The accent is the lavender `#bd93f9` and
    /// Feedback takes the pink `#ff79c6`, because with Rosé Pine in the set a
    /// rose-pink button on a plum ground made two themes read as the same idea.
    /// The bright pink moves onto the **count chip**, where it works differently
    /// per appearance because it cannot carry both ways: a pink numeral on a
    /// recessed fill in Dark, and the reverse in Light — a pink *fill* under a
    /// dark numeral, since bright pink as text on a pale band fails badly.
    ///
    /// **A recorded exception to rule 4.** Its cyan Note `#8be9fd` and green
    /// Staffing `#50fa7b` sit at one lightness in both appearances and collapse in
    /// greyscale — the exact thing every other theme was re-levelled to avoid. It
    /// keeps them because levelling four bright pastels is what would stop it
    /// looking like Dracula, and because the mark is never the sole carrier: the
    /// mono type label spells the type out beside it. If the exception is ever
    /// rejected, the lever is deepening the cyan to `#4fc8e8` and leaving the
    /// other three alone.
    case dracula

    var id: Self { self }

    /// What a new install opens wearing. **The first case, unlike the previous
    /// set**, where the picker's order and the default were two different things.
    static let `default`: AppTheme = .system

    var label: String {
        switch self {
        case .system: "System"
        case .tokyoNight: "Tokyo Night"
        case .kanagawa: "Kanagawa"
        case .darkOwl: "Dark Owl"
        case .rosePine: "Rosé Pine"
        case .dracula: "Dracula"
        }
    }

    /// The theme an older install lands on, mapped from whatever colour setting it
    /// has. Run once from `SettingsStore.init`, which then writes the answer to
    /// the `theme` key and **deletes the two retired ones**, so none of this is
    /// read again.
    ///
    /// Three generations of setting arrive here, and they are tried in the order
    /// of how deliberate a choice each was:
    ///
    /// 1. A **saved theme from the first set**, which is a name this enum no
    ///    longer has. It maps by what the new set replaces:
    ///    the neutrals to System, Moss and Pine to Tokyo Night, the warm ones to
    ///    Kanagawa, Indigo to Dark Owl, Rosewood to Rosé Pine. This is the one
    ///    that would otherwise reset silently — a decoded `theme` key that fails
    ///    `init(rawValue:)` looks exactly like an install that never had one.
    /// 2. The retired **tint** (Background → Tint), by family.
    /// 3. The retired **accent** (Accent → Highlight colour), which decides only
    ///    where the tint was Plain, since that was then the only colour chosen.
    ///
    /// **Nobody arrives at Dracula.** It is an identity rather than a shade, so it
    /// has to be picked — and a saved `"dracula"` never reaches this function,
    /// because that raw value still decodes.
    ///
    /// One row is worth naming: a stored **blue** accent goes to Dark Owl, which
    /// the plan asks for and which is a change of mind from the previous
    /// migration, where blue was read as "the accent's own default, so it says
    /// nothing". An install that never chose an accent has no key at all and lands
    /// on the default instead, so the two cases still separate — but they separate
    /// on the key's *presence*, which is worth knowing if it ever looks wrong.
    static func migrated(theme: String, tint: String, accent: String) -> AppTheme {
        switch theme {
        case "bone", "slate", "graphite": return .system
        case "moss", "pine": return .tokyoNight
        case "ember", "amber": return .kanagawa
        case "indigo": return .darkOwl
        case "rosewood": return .rosePine
        default: break
        }
        switch tint {
        case "mist": return .system
        case "linen", "clay": return .kanagawa
        case "blush": return .rosePine
        // "seafoam" postdates the plan's table; its family is green, so it
        // follows sage rather than the cool near-whites it was added beside.
        case "sage", "seafoam": return .tokyoNight
        case "lilac": return .darkOwl
        // "plain" and anything unrecognised fall through to the accent.
        default: break
        }
        switch accent {
        case "green": return .tokyoNight
        case "orange": return .kanagawa
        case "blue", "lilac": return .darkOwl
        case "gray", "graphite", "lightGray": return .system
        // An install that never chose either setting.
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

    /// What type on `primary` wears — white where the accent is a deep fill, the
    /// palette's own near-black where it is a bright one. Solved at 4.5:1 on the
    /// fill in both appearances, which is what deepened Kanagawa's Lotus orange
    /// and Rosé Pine's Dawn `love`.
    var primaryLabel: Color { band.primaryLabel }

    /// The ring an open card wears. It is the accent in most themes, and where it
    /// isn't, the palette usually says so: Tokyo Night publishes a deepened jade
    /// for Light (its mint is 1.67:1 on white) and Dark Owl a lifted violet for
    /// Dark.
    ///
    /// **Dracula's light ring is the one value in the set deepened here rather
    /// than sourced.** The table repeats the lavender in both appearances, and on
    /// a white card that is 2.41:1 — under the 3:1 an indicator needs — so it
    /// steps down to 3.08:1. Note the previous set's rule that a ring must differ
    /// from the button beside it is *gone*: the ring follows the accent, and only
    /// contrast moves it.
    var ring: Color { band.ring }

    // MARK: Grounds

    /// What the window paints behind everything — the page ground. The sidebar
    /// gets it for free: `SidebarVibrancy` leaves the panel see-through, so the
    /// column shows the desktop rather than this, and the two detail columns are
    /// what carry it (see `RootView`).
    ///
    /// This is the part the first theme set didn't have, and the reason it read
    /// as a preference: a themed band over the system's grey window is a coloured
    /// strip on somebody else's surface.
    var windowFill: Color { resolved.window }

    /// The card face — the paper a note or a task is written on.
    ///
    /// **No longer pure white in every theme in Light**, which reverses the
    /// previous set's rule: Kanagawa's cards are Lotus cream and Rosé Pine's are
    /// Dawn's `surface`, because a sourced palette's paper is part of what it is.
    /// The cost is that body-text contrast can no longer be verified once against
    /// white — it is measured against the face actually painted, which is the
    /// third of the refresh's contrast rules (CLAUDE.md decision 5) and is what
    /// `ThemePaletteTests` does for every value that lands on a card.
    var cardFace: Color { resolved.card }

    /// The card's hairline, paired with `cardFace` — the palette's own edge where
    /// it publishes one, and white at 8% over the dark card where it doesn't,
    /// composited offline. `Stone`'s warm wash over a themed card face reads as a
    /// smudge rather than an edge, which is why this is themed at all.
    var cardBorder: Color { resolved.border }

    /// Metadata type on a card — timestamps, chip names, the resting due badge,
    /// the `···` menu. Each palette's own comment grey where it clears 4.5:1 on
    /// the card, and derived from the page's hue where it doesn't.
    ///
    /// **Text is not themed except here**, and the exception is about kind rather
    /// than degree: a card's title and its body are the writing, read at length,
    /// so their contrast must not become a function of a colour preference, while
    /// metadata is already deliberately quiet and a tinted grey is what makes it
    /// read as part of the theme instead of as leftover chrome. `titleText` and
    /// `bodyText` are the system's in five of the six for that reason — Dracula
    /// is the one exception, and it earns it by being a text palette by origin.
    ///
    /// Its Increase Contrast pair steps most of the way to the label colour, the
    /// same move `Stone.metaText` makes — and for the same reason, that the solved
    /// values barely move under that switch and it has to look like it did
    /// something.
    var metaText: Color { resolved.metaText }

    /// A card's **title** colour, and the plainest statement of the rule above:
    /// it is `labelColor` — the system's, full contrast, unthemed — for five of
    /// the six themes, and only Dracula returns something else. If these ever
    /// start differing per theme, a theme is reaching further than the plan
    /// allows; `ThemePaletteTests` asserts exactly that.
    var titleText: Color { resolved.titleText }

    /// A card's **body** colour, on the same terms as `titleText`. Dracula's is a
    /// step softer than its title (`#cfd2e0` on dark, `#463d63` on light), which
    /// is the paragraph-versus-heading contrast its palette is built around — and
    /// the reason the two are separate values rather than one "text".
    var bodyText: Color { resolved.bodyText }

    /// A link inside a card's body. The palette's own link colour, deepened in
    /// Light where the published one is a dark-mode value on paper — Dark Owl's
    /// `#00ff9f` measures 1.4:1 on white, and Kanagawa publishes none for Lotus
    /// at all, so that one is `springBlue`'s hue taken down until it clears.
    ///
    /// It is applied as a `.tint()` on the rendered body (`MarkdownText`), because
    /// that is the colour SwiftUI draws a link in; without it a link inherited the
    /// app-wide tint, which is `primary` — a lavender or a mint link on a white
    /// card, at 2.4:1 and 1.6:1.
    var link: Color { resolved.link }

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
        case .kanagawa:
            // Kanagawa's rule is "the only orange on screen is the button", and
            // the plan says project dots are included in it — so orange goes to
            // the **end** rather than out of the list. A tenth project still
            // needs a colour, and the alternative, a theme that can run out of
            // dots, is worse than a tenth dot that shares the button's hue.
            return Tint.allCases.filter { $0 != .orange } + [.orange]
        default:
            return Tint.allCases
        }
    }

    // MARK: Note-type palette

    /// The colour a note type's **mark** draws in: its 3pt capsule before the
    /// title, and its dot in the notes filter track. A graphic, so it is solved
    /// at 3:1 — against both the card and the track, since the dot sits on the
    /// band, and the track is the tighter of the two.
    func typeMark(_ tint: Tint) -> Color { resolved.marks[tint] ?? tint.ink }

    /// The colour a note type's **label** draws in — the small-caps name leading
    /// the meta row. Text under 14px, so 4.5:1, which is why it is a separate
    /// value from the mark rather than the same one twice: a label sits a few
    /// points under the mark it belongs to, and that difference is exactly what
    /// lets the mark stay bright enough to see.
    ///
    /// One value per appearance in Dark, where the palettes give a single tone and
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

/// One band's twelve colours, in one appearance.
///
/// **There is no hairline along the bottom edge any more**, in any theme. Light
/// bands used to take one, on the argument that a pale band needs an edge where a
/// dark band separates from the cards on its own — and on screen it read as a
/// *rule drawn under the header*, a line the eye follows instead of a boundary it
/// stops at, which is the last thing a shadowless window wants (see "No shadows"
/// in CLAUDE.md). The band's own value against the page is the boundary now, so a
/// light theme's strip is quieter than it was and that is the intent.
///
/// Eight of the twelve are the plan's own tokens; the four that make the filter
/// track are **derived from the band's hue**, which is what keeps a new theme a hue
/// rather than a design:
///
/// - `trackFill` is white at 10% over the band in Dark, composited offline to an
///   opaque value so nothing layers alpha at draw time, and the band's hue at
///   92% L in Light.
/// - `segmentLabel` is that hue at 87% L (dark) / 42% L (light), and the raised
///   `segmentFill` at 93% L (dark) or pure white (light).
/// - `segmentLabelSelected` is the band's **text** in Light, where the raised
///   pill is pure white, and the band's own **fill** in Dark, where the pill is
///   near-white and the label reads as the band inverted. That is the trick the
///   raised pill turns: neither is a value that had to be solved on its own.
///
/// `countFill` and `countText` are **not** derived any more — see `Band.countFill`.
struct Band {
    let fill: RGB
    let text: RGB
    /// The count chip's fill: the theme's **accent at low alpha over the band**,
    /// composited offline. It used to be white at 12%, a value with no opinion,
    /// which left the one number in the band reading as chrome.
    ///
    /// Two of the six do something else. **System** keeps a neutral chip, because
    /// a theme whose claim is that it adds no colour cannot spend the accent here.
    /// And **Dracula inverts per appearance**: its bright pink is the chip's
    /// numeral on a recessed black fill in Dark, and the chip's *fill* under a
    /// dark numeral in Light, since bright pink as text on a pale band fails
    /// badly. Both directions are measured on the composited value rather than on
    /// the raw fill, which is the check that caught the most defects in design.
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

/// The two bands, both appearances of the page and card grounds, the metadata and
/// link colours and the type palette — resolved into `Color`s once per theme.
private struct Resolved {
    let band: BandColors
    let window: Color
    let card: Color
    let border: Color
    let metaText: Color
    let titleText: Color
    let bodyText: Color
    let link: Color
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
        link = theme.linkTones.color
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
/// already clears the floor with room to spare and the switch's visible work
/// there would be nothing. It is filled in for the values that *are* near the
/// floor: the note-type marks and labels, the metadata colour and the link.
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
    /// Generated from each palette's own values rather than typed by hand, and
    /// regenerate it the same way if a theme is added: the band, its text, the
    /// hairline, the accent and the chip come from the source; the track and the
    /// raised segment are derived from the band's hue by the rules on `Band`; and
    /// the accent has to clear 4.5:1 under its label in both appearances — if it
    /// can't, deepen it and invert to white-on-deep, which is what Kanagawa's
    /// Lotus orange and Rosé Pine's Dawn `love` do.
    var tones: Tones {
        switch self {
        // The band greys are written down rather than read from tokens (see `case
        // system`): `#F2F2F7` in Light — the grey the *page* used to wear, swapped
        // with it so the sheet under the cards is white, which is what
        // `windowBackgroundColor` resolves to on macOS 26 — and
        // `tertiarySystemBackground`'s `#2C2C2E` in Dark. The band's own text is
        // the set's rule, 26% L at the band's hue, rather than `label`, so a column
        // heading reads as a heading in all six themes. The blues are `systemBlue`
        // **deepened**: as shipped it is ~4.0:1 under a white label. And the count
        // chip is the one neutral one in the set, which is rule 6's exclusion.
        case .system: Tones(
            light: Band(
                fill: RGB(r: 0.949, g: 0.949, b: 0.969),
                text: RGB(r: 0.140, g: 0.139, b: 0.154),
                countFill: RGB(r: 0.863, g: 0.863, b: 0.882),
                countText: RGB(r: 0.235, g: 0.235, b: 0.263),
                primary: RGB(r: 0.000, g: 0.412, b: 0.851),
                primaryLabel: RGB(r: 1.000, g: 1.000, b: 1.000),
                ring: RGB(r: 0.000, g: 0.412, b: 0.851),
                trackFill: RGB(r: 0.894, g: 0.894, b: 0.913),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.300, g: 0.300, b: 0.316),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.140, g: 0.139, b: 0.154)),
            dark: Band(
                fill: RGB(r: 0.173, g: 0.173, b: 0.180),
                text: RGB(r: 0.940, g: 0.940, b: 0.951),
                countFill: RGB(r: 0.272, g: 0.272, b: 0.279),
                countText: RGB(r: 0.773, g: 0.773, b: 0.792),
                primary: RGB(r: 0.039, g: 0.431, b: 0.851),
                primaryLabel: RGB(r: 1.000, g: 1.000, b: 1.000),
                ring: RGB(r: 0.039, g: 0.518, b: 1.000),
                trackFill: RGB(r: 0.255, g: 0.255, b: 0.262),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.830, g: 0.830, b: 0.841),
                segmentFill: RGB(r: 0.907, g: 0.908, b: 0.918),
                segmentLabelSelected: RGB(r: 0.173, g: 0.173, b: 0.180)))
        // Storm as the band over Night as the page, and the accent is the mint
        // rather than the red — see the case. Light is derived throughout: the
        // source publishes a light *background* and nothing else. The light ring
        // is the palette's deepened jade, because the mint itself is 1.67:1 on a
        // white card.
        case .tokyoNight: Tones(
            light: Band(
                fill: RGB(r: 0.902, g: 0.906, b: 0.929),
                text: RGB(r: 0.169, g: 0.188, b: 0.286),
                countFill: RGB(r: 0.847, g: 0.949, b: 0.925),
                countText: RGB(r: 0.082, g: 0.384, b: 0.329),
                primary: RGB(r: 0.451, g: 0.855, b: 0.792),
                primaryLabel: RGB(r: 0.102, g: 0.106, b: 0.149),
                ring: RGB(r: 0.122, g: 0.616, b: 0.537),
                trackFill: RGB(r: 0.890, g: 0.894, b: 0.918),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.297, g: 0.301, b: 0.320),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.169, g: 0.188, b: 0.286)),
            dark: Band(
                fill: RGB(r: 0.141, g: 0.157, b: 0.231),
                text: RGB(r: 0.753, g: 0.792, b: 0.961),
                countFill: RGB(r: 0.203, g: 0.296, b: 0.344),
                countText: RGB(r: 0.604, g: 0.902, b: 0.847),
                primary: RGB(r: 0.451, g: 0.855, b: 0.792),
                primaryLabel: RGB(r: 0.102, g: 0.106, b: 0.149),
                ring: RGB(r: 0.451, g: 0.855, b: 0.792),
                trackFill: RGB(r: 0.227, g: 0.241, b: 0.308),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.803, g: 0.828, b: 0.927),
                segmentFill: RGB(r: 0.881, g: 0.905, b: 1.000),
                segmentLabelSelected: RGB(r: 0.141, g: 0.157, b: 0.231)))
        // Wave's `sumiInk5` band over `sumiInk3`, and Lotus's `lotusWhite2` over a
        // page derived above it — **at half Lotus's chroma**, by request: the
        // published `lotusWhite2` is 0.060 C, which is more than twice any other
        // band in the set and read as a khaki slab rather than as warm paper. Hue
        // and lightness are the palette's; only the saturation is ours, and the
        // page and card were eased with it so the three grounds stay one family.
        // The Lotus accent is the orange **deepened to
        // carry a white label** — `surimiOrange` is 1.96:1 on Lotus paper, so
        // Light inverts to white-on-deep while Dark keeps the bright original
        // under a `sumiInk3` label.
        case .kanagawa: Tones(
            light: Band(
                fill: RGB(r: 0.878, g: 0.867, b: 0.773),
                text: RGB(r: 0.329, g: 0.329, b: 0.392),
                countFill: RGB(r: 0.941, g: 0.875, b: 0.784),
                countText: RGB(r: 0.541, g: 0.310, b: 0.000),
                primary: RGB(r: 0.659, g: 0.345, b: 0.000),
                primaryLabel: RGB(r: 1.000, g: 1.000, b: 1.000),
                ring: RGB(r: 0.659, g: 0.345, b: 0.000),
                trackFill: RGB(r: 0.913, g: 0.901, b: 0.806),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.316, g: 0.305, b: 0.225),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.329, g: 0.329, b: 0.392)),
            dark: Band(
                fill: RGB(r: 0.212, g: 0.212, b: 0.275),
                text: RGB(r: 0.863, g: 0.843, b: 0.729),
                countFill: RGB(r: 0.369, g: 0.295, b: 0.300),
                countText: RGB(r: 1.000, g: 0.788, b: 0.647),
                primary: RGB(r: 1.000, g: 0.627, b: 0.400),
                primaryLabel: RGB(r: 0.122, g: 0.122, b: 0.157),
                ring: RGB(r: 1.000, g: 0.627, b: 0.400),
                trackFill: RGB(r: 0.291, g: 0.291, b: 0.347),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.822, g: 0.824, b: 0.904),
                segmentFill: RGB(r: 0.899, g: 0.901, b: 0.982),
                segmentLabelSelected: RGB(r: 0.212, g: 0.212, b: 0.275)))
        // `editor.background` and `tab.activeBackground` in Dark; Light is the
        // plan's oklch spec at the same hue, since the source is a dark theme and
        // publishes no light half. The accent is the theme's own
        // `button.background` at **full opacity** — the shipped `cc` alpha drops
        // the white label under 4.5:1 — and the dark ring is its lifted violet.
        case .darkOwl: Tones(
            light: Band(
                fill: RGB(r: 0.908, g: 0.956, b: 0.992),
                text: RGB(r: 0.060, g: 0.147, b: 0.232),
                countFill: RGB(r: 0.902, g: 0.863, b: 0.969),
                countText: RGB(r: 0.357, g: 0.227, b: 0.620),
                primary: RGB(r: 0.494, g: 0.341, b: 0.761),
                primaryLabel: RGB(r: 1.000, g: 1.000, b: 1.000),
                ring: RGB(r: 0.494, g: 0.341, b: 0.761),
                trackFill: RGB(r: 0.856, g: 0.904, b: 0.940),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.269, g: 0.308, b: 0.338),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.060, g: 0.147, b: 0.232)),
            dark: Band(
                fill: RGB(r: 0.043, g: 0.161, b: 0.259),
                text: RGB(r: 0.902, g: 0.929, b: 0.961),
                countFill: RGB(r: 0.178, g: 0.215, b: 0.409),
                countText: RGB(r: 0.769, g: 0.663, b: 0.941),
                primary: RGB(r: 0.494, g: 0.341, b: 0.761),
                primaryLabel: RGB(r: 1.000, g: 1.000, b: 1.000),
                ring: RGB(r: 0.604, g: 0.463, b: 0.910),
                trackFill: RGB(r: 0.139, g: 0.245, b: 0.333),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.715, g: 0.849, b: 0.978),
                segmentFill: RGB(r: 0.838, g: 0.921, b: 1.000),
                segmentLabelSelected: RGB(r: 0.043, g: 0.161, b: 0.259)))
        // `overlay` / `base` / `surface` in both halves, verbatim. Dawn's accent is
        // `love` **deepened**: the original is 2.8:1 on Dawn's paper, so Light
        // takes a white label on a deeper rose while Dark keeps `love` itself
        // under a near-black one.
        case .rosePine: Tones(
            light: Band(
                fill: RGB(r: 0.949, g: 0.914, b: 0.882),
                text: RGB(r: 0.271, g: 0.247, b: 0.388),
                countFill: RGB(r: 0.961, g: 0.867, b: 0.890),
                countText: RGB(r: 0.561, g: 0.267, b: 0.349),
                primary: RGB(r: 0.659, g: 0.333, b: 0.427),
                primaryLabel: RGB(r: 1.000, g: 1.000, b: 1.000),
                ring: RGB(r: 0.659, g: 0.333, b: 0.427),
                trackFill: RGB(r: 0.924, g: 0.889, b: 0.858),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.325, g: 0.296, b: 0.271),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.271, g: 0.247, b: 0.388)),
            dark: Band(
                fill: RGB(r: 0.149, g: 0.137, b: 0.227),
                text: RGB(r: 0.878, g: 0.871, b: 0.957),
                countFill: RGB(r: 0.319, g: 0.203, b: 0.303),
                countText: RGB(r: 0.941, g: 0.639, b: 0.722),
                primary: RGB(r: 0.922, g: 0.435, b: 0.573),
                primaryLabel: RGB(r: 0.169, g: 0.102, b: 0.141),
                ring: RGB(r: 0.922, g: 0.435, b: 0.573),
                trackFill: RGB(r: 0.234, g: 0.224, b: 0.305),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.827, g: 0.817, b: 0.937),
                segmentFill: RGB(r: 0.904, g: 0.896, b: 1.000),
                segmentLabelSelected: RGB(r: 0.149, g: 0.137, b: 0.227)))
        // Unchanged from the theme's first appearance in the app apart from the two
        // swaps in its case: the accent is the lavender rather than the pink, and
        // the pink moves onto the count chip — a numeral on a recessed black fill
        // in Dark, the chip's own fill under a dark numeral in Light. The light
        // ring is the lavender deepened, the one ring in the set this
        // implementation solved rather than sourced.
        case .dracula: Tones(
            light: Band(
                fill: RGB(r: 0.941, g: 0.910, b: 0.992),
                text: RGB(r: 0.235, g: 0.165, b: 0.388),
                countFill: RGB(r: 1.000, g: 0.475, b: 0.776),
                countText: RGB(r: 0.290, g: 0.122, b: 0.235),
                primary: RGB(r: 0.741, g: 0.576, b: 0.976),
                primaryLabel: RGB(r: 0.290, g: 0.122, b: 0.235),
                ring: RGB(r: 0.661, g: 0.497, b: 0.890),
                trackFill: RGB(r: 0.911, g: 0.880, b: 0.961),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.314, g: 0.288, b: 0.355),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.235, g: 0.165, b: 0.388)),
            dark: Band(
                fill: RGB(r: 0.227, g: 0.184, b: 0.369),
                text: RGB(r: 0.973, g: 0.973, b: 0.949),
                countFill: RGB(r: 0.187, g: 0.151, b: 0.302),
                countText: RGB(r: 1.000, g: 0.475, b: 0.776),
                primary: RGB(r: 0.741, g: 0.576, b: 0.976),
                primaryLabel: RGB(r: 0.169, g: 0.129, b: 0.212),
                ring: RGB(r: 0.741, g: 0.576, b: 0.976),
                trackFill: RGB(r: 0.305, g: 0.266, b: 0.432),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.834, g: 0.802, b: 1.000),
                segmentFill: RGB(r: 0.909, g: 0.894, b: 1.000),
                segmentLabelSelected: RGB(r: 0.227, g: 0.184, b: 0.369)))
        }
    }

    /// The page and card grounds, and the card's hairline. Verbatim from each
    /// palette where it publishes them; Kanagawa's are derived *above* the band,
    /// because Lotus's own page is too yellow to carry a window, and System's are
    /// the plan's grouped ladder rather than semantic tokens (see `case system`).
    /// A dark edge with no published value is white at 8% over the card,
    /// composited here rather than layered at draw time.
    var grounds: Grounds {
        switch self {
        // **System's Light page is white and its band is the grey the page used to
        // be**, which is a swap rather than a new pair of values: on macOS 26
        // `windowBackgroundColor` resolves to `#ffffff` in Light, so a white sheet
        // under a grey header strip is the platform's own arrangement, and System
        // is the one theme with a reason to be literal about it.
        //
        // One consequence is deliberate: **System's light card *is* its page**,
        // both pure white, so the card's hairline is the whole of the separation —
        // which is how a stack of white cards on white paper reads in the
        // platform's own apps. `ThemePaletteTests` names that exception rather than
        // loosening the check that catches an accidental collapse.
        case .system: Grounds(
            window: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.000, g: 0.000, b: 0.000)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.110, g: 0.110, b: 0.118)),
            border: DynamicRGB(light: RGB(r: 0.847, g: 0.847, b: 0.863), dark: RGB(r: 0.220, g: 0.220, b: 0.227)))
        case .tokyoNight: Grounds(
            window: DynamicRGB(light: RGB(r: 0.949, g: 0.953, b: 0.969), dark: RGB(r: 0.102, g: 0.106, b: 0.149)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.118, g: 0.125, b: 0.188)),
            border: DynamicRGB(light: RGB(r: 0.875, g: 0.882, b: 0.918), dark: RGB(r: 0.188, g: 0.195, b: 0.253)))
        // Lotus's own `#f2ecbc` page is too yellow to carry a window, so the page
        // and cards are derived *above* the band and the band stays the only
        // saturated surface. The cream card is one of the two in the set that
        // isn't white — see `cardFace`.
        case .kanagawa: Grounds(
            window: DynamicRGB(light: RGB(r: 0.976, g: 0.973, b: 0.937), dark: RGB(r: 0.122, g: 0.122, b: 0.157)),
            card: DynamicRGB(light: RGB(r: 0.996, g: 0.992, b: 0.973), dark: RGB(r: 0.165, g: 0.165, b: 0.216)),
            border: DynamicRGB(light: RGB(r: 0.886, g: 0.878, b: 0.820), dark: RGB(r: 0.329, g: 0.329, b: 0.427)))
        case .darkOwl: Grounds(
            window: DynamicRGB(light: RGB(r: 0.967, g: 0.983, b: 0.995), dark: RGB(r: 0.004, g: 0.086, b: 0.153)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.039, g: 0.125, b: 0.208)),
            border: DynamicRGB(light: RGB(r: 0.857, g: 0.888, b: 0.912), dark: RGB(r: 0.116, g: 0.195, b: 0.271)))
        // `base` / `surface` / `highlightMed` verbatim in both halves, which is
        // what makes Dawn's paper pink-cream rather than white.
        case .rosePine: Grounds(
            window: DynamicRGB(light: RGB(r: 0.980, g: 0.957, b: 0.929), dark: RGB(r: 0.098, g: 0.090, b: 0.141)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 0.980, b: 0.953), dark: RGB(r: 0.122, g: 0.114, b: 0.180)),
            border: DynamicRGB(light: RGB(r: 0.925, g: 0.886, b: 0.847), dark: RGB(r: 0.251, g: 0.239, b: 0.322)))
        case .dracula: Grounds(
            window: DynamicRGB(light: RGB(r: 0.980, g: 0.969, b: 1.000), dark: RGB(r: 0.157, g: 0.165, b: 0.212)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.184, g: 0.192, b: 0.247)),
            border: DynamicRGB(light: RGB(r: 0.906, g: 0.867, b: 0.969), dark: RGB(r: 0.247, g: 0.259, b: 0.337)))
        }
    }

    /// Metadata type, per theme, and the value most likely to fail: it is the one
    /// themed *text* colour, and it lands on the card rather than on the band.
    ///
    /// Three of the six are their palette's own comment grey, verbatim — Tokyo
    /// Night's `#565f89` (6.2:1 on white), Rosé Pine's `subtle` in Dark, Dracula's
    /// own pair. The rest are derived, because the published grey failed on the
    /// card: Rosé Pine's `subtle` measures 4.3:1 on Dawn's paper, and
    /// `secondaryLabel` at its shipping opacity is ~3.4:1. Dracula's Dark value
    /// is the tightest text pairing in the file at 4.52:1 — it clears the floor
    /// and it is the palette's own, so it stands, but it has no room left and a
    /// card face nudged lighter would take it under.
    var metaTones: DynamicRGB {
        switch self {
        case .system: DynamicRGB(
            light: RGB(r: 0.388, g: 0.388, b: 0.400), dark: RGB(r: 0.596, g: 0.596, b: 0.616),
            lightHC: RGB(r: 0.296, g: 0.296, b: 0.307), darkHC: RGB(r: 0.699, g: 0.699, b: 0.720))
        case .tokyoNight: DynamicRGB(
            light: RGB(r: 0.337, g: 0.373, b: 0.537), dark: RGB(r: 0.545, g: 0.576, b: 0.722),
            lightHC: RGB(r: 0.248, g: 0.280, b: 0.437), darkHC: RGB(r: 0.647, g: 0.680, b: 0.829))
        case .kanagawa: DynamicRGB(
            light: RGB(r: 0.427, g: 0.408, b: 0.529), dark: RGB(r: 0.604, g: 0.592, b: 0.549),
            lightHC: RGB(r: 0.334, g: 0.314, b: 0.431), darkHC: RGB(r: 0.732, g: 0.720, b: 0.675))
        case .darkOwl: DynamicRGB(
            light: RGB(r: 0.356, g: 0.420, b: 0.476), dark: RGB(r: 0.490, g: 0.576, b: 0.659),
            lightHC: RGB(r: 0.265, g: 0.326, b: 0.380), darkHC: RGB(r: 0.591, g: 0.679, b: 0.764))
        case .rosePine: DynamicRGB(
            light: RGB(r: 0.427, g: 0.408, b: 0.529), dark: RGB(r: 0.565, g: 0.549, b: 0.667),
            lightHC: RGB(r: 0.334, g: 0.314, b: 0.431), darkHC: RGB(r: 0.667, g: 0.651, b: 0.773))
        case .dracula: DynamicRGB(
            light: RGB(r: 0.420, g: 0.384, b: 0.533), dark: RGB(r: 0.565, g: 0.596, b: 0.722),
            lightHC: RGB(r: 0.327, g: 0.291, b: 0.434), darkHC: RGB(r: 0.716, g: 0.749, b: 0.880))
        }
    }

    /// A link in a card's body. Verbatim from the palette in Dark, where every
    /// source publishes one it means; deepened or derived in Light, where two of
    /// them publish a dark-mode value that cannot sit on paper (Dark Owl's
    /// `#00ff9f` is 1.4:1 on white) and Kanagawa publishes nothing for Lotus at
    /// all.
    var linkTones: DynamicRGB {
        switch self {
        case .system: DynamicRGB(
            light: RGB(r: 0.000, g: 0.384, b: 0.800), dark: RGB(r: 0.039, g: 0.518, b: 1.000),
            lightHC: RGB(r: 0.000, g: 0.295, b: 0.627), darkHC: RGB(r: 0.405, g: 0.665, b: 1.000))
        case .tokyoNight: DynamicRGB(
            light: RGB(r: 0.090, g: 0.412, b: 0.561), dark: RGB(r: 0.490, g: 0.812, b: 1.000),
            lightHC: RGB(r: 0.000, g: 0.315, b: 0.443), darkHC: RGB(r: 0.747, g: 0.902, b: 1.000))
        case .kanagawa: DynamicRGB(
            light: RGB(r: 0.179, g: 0.485, b: 0.596), dark: RGB(r: 0.498, g: 0.706, b: 0.792),
            lightHC: RGB(r: 0.000, g: 0.370, b: 0.476), darkHC: RGB(r: 0.602, g: 0.813, b: 0.901))
        case .darkOwl: DynamicRGB(
            light: RGB(r: 0.000, g: 0.459, b: 0.306), dark: RGB(r: 0.000, g: 1.000, b: 0.624),
            lightHC: RGB(r: 0.000, g: 0.351, b: 0.230), darkHC: RGB(r: 0.845, g: 1.000, b: 0.901))
        case .rosePine: DynamicRGB(
            light: RGB(r: 0.157, g: 0.412, b: 0.514), dark: RGB(r: 0.420, g: 0.663, b: 0.769),
            lightHC: RGB(r: 0.021, g: 0.317, b: 0.415), darkHC: RGB(r: 0.523, g: 0.769, b: 0.877))
        case .dracula: DynamicRGB(
            light: RGB(r: 0.482, g: 0.247, b: 0.722), dark: RGB(r: 0.545, g: 0.914, b: 0.992),
            lightHC: RGB(r: 0.387, g: 0.134, b: 0.612), darkHC: RGB(r: 0.883, g: 0.978, b: 1.000))
        }
    }

    /// The title and body colours, for the **one** theme that is a text palette
    /// by origin. `nil` everywhere else, and that is rule 5 rather than an
    /// omission: five of the six leave the writing on `labelColor`, so a card's
    /// paragraph reads at the system's own contrast whatever theme is on. The
    /// other five palettes *do* publish a title and a body — this is the one
    /// place the set deliberately declines a sourced value.
    ///
    /// Dracula's four are its palette's own (`#f8f8f2` / `#cfd2e0` dark,
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
    /// Each set is read from its palette's own syntax colours — the source and the
    /// file are named on each `case` above — then held to two rules. **No mark's
    /// hue sits within 25° of the theme's accent** (rule 2, automated by
    /// `ThemePaletteTests`), which is what keeps "action" legible as action: it
    /// is why Kanagawa has no orange type, why Tokyo Night's Staffing is a
    /// yellow-green rather than a mint, and why Dracula's Feedback is the pink
    /// now that the lavender is the button. And **the four are re-levelled into a
    /// lightness ladder** (rule 4), because every source palette puts three or
    /// four of its hues at one lightness and they collapse in greyscale; the
    /// worst gap in the set is 0.03 of oklch lightness, and Dracula is the one
    /// documented exception.
    ///
    /// Two kinds of value here are ours rather than the palette's, and both are
    /// named where they occur. **Light labels** are a step under their mark
    /// (Kanagawa's are derived outright, since Lotus publishes one value per
    /// hue). And the **Increase Contrast variants** are derived, not solved:
    /// ±8.5 points of lightness at the same hue, stepped further only where that
    /// didn't reach 7:1 on the card. Stepping lightness is the one move that
    /// can't change which colour a type *is*.
    var typePalette: [Tint: TypeTone] {
        switch self {
        // The system's teal / orange / purple / green, **deepened into rule 4's
        // ladder**: as shipped they resolve to nearly one lightness. The dark
        // Feedback purple is a point brighter than `systemPurple` — verbatim it is
        // 2.89:1 as a dot on the dark filter track, and a dot is held to 3:1.
        case .system: [
            // Note
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.051, g: 0.263, b: 0.318), dark: RGB(r: 0.541, g: 0.871, b: 1.000),
                                 lightHC: RGB(r: 0.000, g: 0.173, b: 0.216), darkHC: RGB(r: 0.831, g: 0.950, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.039, g: 0.212, b: 0.255), dark: RGB(r: 0.541, g: 0.871, b: 1.000),
                                  lightHC: RGB(r: 0.000, g: 0.125, b: 0.158), darkHC: RGB(r: 0.831, g: 0.950, b: 1.000))),
            // Meeting
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.659, g: 0.373, b: 0.000), dark: RGB(r: 0.878, g: 0.541, b: 0.031),
                                 lightHC: RGB(r: 0.525, g: 0.293, b: 0.000), darkHC: RGB(r: 0.993, g: 0.647, b: 0.226)),
                label: DynamicRGB(light: RGB(r: 0.561, g: 0.314, b: 0.000), dark: RGB(r: 0.878, g: 0.541, b: 0.031),
                                  lightHC: RGB(r: 0.432, g: 0.236, b: 0.000), darkHC: RGB(r: 0.993, g: 0.647, b: 0.226))),
            // Feedback
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.490, g: 0.165, b: 0.659), dark: RGB(r: 0.768, g: 0.373, b: 0.969),
                                 lightHC: RGB(r: 0.392, g: 0.000, b: 0.551), darkHC: RGB(r: 0.837, g: 0.545, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.420, g: 0.137, b: 0.569), dark: RGB(r: 0.768, g: 0.373, b: 0.969),
                                  lightHC: RGB(r: 0.322, g: 0.000, b: 0.458), darkHC: RGB(r: 0.837, g: 0.545, b: 1.000))),
            // Staffing
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.078, g: 0.329, b: 0.122), dark: RGB(r: 0.188, g: 0.820, b: 0.345),
                                 lightHC: RGB(r: 0.000, g: 0.233, b: 0.051), darkHC: RGB(r: 0.338, g: 0.932, b: 0.453)),
                label: DynamicRGB(light: RGB(r: 0.059, g: 0.247, b: 0.094), dark: RGB(r: 0.188, g: 0.820, b: 0.345),
                                  lightHC: RGB(r: 0.000, g: 0.156, b: 0.029), darkHC: RGB(r: 0.338, g: 0.932, b: 0.453))),
        ]
        // Tokyo Night's blue / orange / purple / green, with Staffing kept a
        // yellow-green rather than the palette's mint so it can't be read as the
        // button (rule 2).
        case .tokyoNight: [
            // Note
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.122, g: 0.310, b: 0.659), dark: RGB(r: 0.416, g: 0.565, b: 0.902),
                                 lightHC: RGB(r: 0.019, g: 0.210, b: 0.551), darkHC: RGB(r: 0.523, g: 0.671, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.102, g: 0.259, b: 0.565), dark: RGB(r: 0.416, g: 0.565, b: 0.902),
                                  lightHC: RGB(r: 0.011, g: 0.161, b: 0.460), darkHC: RGB(r: 0.523, g: 0.671, b: 1.000))),
            // Meeting
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.698, g: 0.376, b: 0.094), dark: RGB(r: 1.000, g: 0.671, b: 0.471),
                                 lightHC: RGB(r: 0.573, g: 0.290, b: 0.000), darkHC: RGB(r: 1.000, g: 0.826, b: 0.726)),
                label: DynamicRGB(light: RGB(r: 0.604, g: 0.325, b: 0.075), dark: RGB(r: 1.000, g: 0.671, b: 0.471),
                                  lightHC: RGB(r: 0.481, g: 0.242, b: 0.000), darkHC: RGB(r: 1.000, g: 0.826, b: 0.726))),
            // Feedback
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.306, g: 0.184, b: 0.471), dark: RGB(r: 0.702, g: 0.580, b: 0.949),
                                 lightHC: RGB(r: 0.219, g: 0.088, b: 0.370), darkHC: RGB(r: 0.797, g: 0.706, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.247, g: 0.145, b: 0.388), dark: RGB(r: 0.702, g: 0.580, b: 0.949),
                                  lightHC: RGB(r: 0.164, g: 0.051, b: 0.292), darkHC: RGB(r: 0.797, g: 0.706, b: 1.000))),
            // Staffing
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.255, g: 0.427, b: 0.122), dark: RGB(r: 0.765, g: 0.906, b: 0.608),
                                 lightHC: RGB(r: 0.167, g: 0.330, b: 0.000), darkHC: RGB(r: 0.902, g: 1.000, b: 0.800)),
                label: DynamicRGB(light: RGB(r: 0.216, g: 0.361, b: 0.102), dark: RGB(r: 0.765, g: 0.906, b: 0.608),
                                  lightHC: RGB(r: 0.132, g: 0.267, b: 0.000), darkHC: RGB(r: 0.902, g: 1.000, b: 0.800))),
        ]
        // Lotus and Wave's own hues, and the one palette here with **no orange**:
        // that belongs to the button alone. Meeting is `sakuraPink` in Dark, which
        // the plan asks for verbatim and which lands at 2.97:1 as a dot on
        // Kanagawa's track — the lightest dark band in the set — so it is stepped
        // one point of lightness to clear 3:1. The light labels are derived rather
        // than sourced: Lotus publishes one value per hue, and a label carries the
        // tighter floor.
        case .kanagawa: [
            // Note
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.322, g: 0.439, b: 0.624), dark: RGB(r: 0.576, g: 0.682, b: 0.894),
                                 lightHC: RGB(r: 0.230, g: 0.343, b: 0.520), darkHC: RGB(r: 0.683, g: 0.789, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.257, g: 0.371, b: 0.550), dark: RGB(r: 0.576, g: 0.682, b: 0.894),
                                  lightHC: RGB(r: 0.168, g: 0.277, b: 0.449), darkHC: RGB(r: 0.683, g: 0.789, b: 1.000))),
            // Meeting
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.490, g: 0.188, b: 0.286), dark: RGB(r: 0.830, g: 0.500, b: 0.606),
                                 lightHC: RGB(r: 0.386, g: 0.090, b: 0.199), darkHC: RGB(r: 0.943, g: 0.603, b: 0.710)),
                label: DynamicRGB(light: RGB(r: 0.416, g: 0.120, b: 0.224), dark: RGB(r: 0.830, g: 0.500, b: 0.606),
                                  lightHC: RGB(r: 0.314, g: 0.009, b: 0.141), darkHC: RGB(r: 0.964, g: 0.621, b: 0.728))),
            // Feedback
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.275, g: 0.196, b: 0.373), dark: RGB(r: 0.788, g: 0.722, b: 0.894),
                                 lightHC: RGB(r: 0.189, g: 0.110, b: 0.278), darkHC: RGB(r: 0.895, g: 0.830, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.213, g: 0.135, b: 0.306), dark: RGB(r: 0.788, g: 0.722, b: 0.894),
                                  lightHC: RGB(r: 0.132, g: 0.050, b: 0.214), darkHC: RGB(r: 0.895, g: 0.830, b: 1.000))),
            // Staffing
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.337, g: 0.420, b: 0.200), dark: RGB(r: 0.812, g: 0.894, b: 0.706),
                                 lightHC: RGB(r: 0.247, g: 0.325, b: 0.103), darkHC: RGB(r: 0.928, g: 1.000, b: 0.838)),
                label: DynamicRGB(light: RGB(r: 0.273, g: 0.352, b: 0.132), dark: RGB(r: 0.812, g: 0.894, b: 0.706),
                                  lightHC: RGB(r: 0.187, g: 0.260, b: 0.024), darkHC: RGB(r: 0.928, g: 1.000, b: 0.838))),
        ]
        // Dark Owl's syntax colours: functions, types, variables, operators.
        case .darkOwl: [
            // Note
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.071, g: 0.290, b: 0.541), dark: RGB(r: 0.333, g: 0.647, b: 0.910),
                                 lightHC: RGB(r: 0.000, g: 0.200, b: 0.415), darkHC: RGB(r: 0.469, g: 0.753, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.063, g: 0.239, b: 0.439), dark: RGB(r: 0.333, g: 0.647, b: 0.910),
                                  lightHC: RGB(r: 0.000, g: 0.152, b: 0.321), darkHC: RGB(r: 0.469, g: 0.753, b: 1.000))),
            // Meeting
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.541, g: 0.361, b: 0.020), dark: RGB(r: 0.933, g: 0.694, b: 0.290),
                                 lightHC: RGB(r: 0.422, g: 0.276, b: 0.000), darkHC: RGB(r: 1.000, g: 0.817, b: 0.538)),
                label: DynamicRGB(light: RGB(r: 0.435, g: 0.290, b: 0.016), dark: RGB(r: 0.933, g: 0.694, b: 0.290),
                                  lightHC: RGB(r: 0.321, g: 0.208, b: 0.000), darkHC: RGB(r: 1.000, g: 0.817, b: 0.538))),
            // Feedback
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.431, g: 0.071, b: 0.149), dark: RGB(r: 0.937, g: 0.322, b: 0.400),
                                 lightHC: RGB(r: 0.306, g: 0.000, b: 0.081), darkHC: RGB(r: 1.000, g: 0.490, b: 0.530)),
                label: DynamicRGB(light: RGB(r: 0.361, g: 0.059, b: 0.122), dark: RGB(r: 0.937, g: 0.322, b: 0.400),
                                  lightHC: RGB(r: 0.240, g: 0.000, b: 0.056), darkHC: RGB(r: 1.000, g: 0.526, b: 0.559))),
            // Staffing
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.051, g: 0.498, b: 0.612), dark: RGB(r: 0.490, g: 0.933, b: 1.000),
                                 lightHC: RGB(r: 0.000, g: 0.395, b: 0.490), darkHC: RGB(r: 0.896, g: 0.986, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.039, g: 0.420, b: 0.518), dark: RGB(r: 0.490, g: 0.933, b: 1.000),
                                  lightHC: RGB(r: 0.000, g: 0.320, b: 0.399), darkHC: RGB(r: 0.896, g: 0.986, b: 1.000))),
        ]
        // `foam` / `gold` / `rose` / `iris`. Rose against `love` is the recorded
        // 25-degree exception — see the case.
        case .rosePine: [
            // Note
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.137, g: 0.412, b: 0.478), dark: RGB(r: 0.557, g: 0.765, b: 0.804),
                                 lightHC: RGB(r: 0.000, g: 0.316, b: 0.380), darkHC: RGB(r: 0.662, g: 0.873, b: 0.913)),
                label: DynamicRGB(light: RGB(r: 0.110, g: 0.357, b: 0.416), dark: RGB(r: 0.557, g: 0.765, b: 0.804),
                                  lightHC: RGB(r: 0.000, g: 0.263, b: 0.317), darkHC: RGB(r: 0.662, g: 0.873, b: 0.913))),
            // Meeting
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.604, g: 0.416, b: 0.071), dark: RGB(r: 0.984, g: 0.847, b: 0.600),
                                 lightHC: RGB(r: 0.487, g: 0.326, b: 0.000), darkHC: RGB(r: 1.000, g: 0.974, b: 0.929)),
                label: DynamicRGB(light: RGB(r: 0.522, g: 0.349, b: 0.059), dark: RGB(r: 0.984, g: 0.847, b: 0.600),
                                  lightHC: RGB(r: 0.407, g: 0.262, b: 0.000), darkHC: RGB(r: 1.000, g: 0.974, b: 0.929))),
            // Feedback
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.420, g: 0.141, b: 0.149), dark: RGB(r: 0.867, g: 0.569, b: 0.561),
                                 lightHC: RGB(r: 0.317, g: 0.038, b: 0.066), darkHC: RGB(r: 0.980, g: 0.673, b: 0.663)),
                label: DynamicRGB(light: RGB(r: 0.353, g: 0.114, b: 0.122), dark: RGB(r: 0.867, g: 0.569, b: 0.561),
                                  lightHC: RGB(r: 0.254, g: 0.016, b: 0.042), darkHC: RGB(r: 0.980, g: 0.673, b: 0.663))),
            // Staffing
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.384, g: 0.286, b: 0.498), dark: RGB(r: 0.639, g: 0.510, b: 0.804),
                                 lightHC: RGB(r: 0.293, g: 0.196, b: 0.399), darkHC: RGB(r: 0.744, g: 0.612, b: 0.915)),
                label: DynamicRGB(light: RGB(r: 0.325, g: 0.239, b: 0.427), dark: RGB(r: 0.639, g: 0.510, b: 0.804),
                                  lightHC: RGB(r: 0.237, g: 0.151, b: 0.331), darkHC: RGB(r: 0.744, g: 0.612, b: 0.915))),
        ]
        // The real Dracula hues in Dark. **Feedback is the pink now** — the swap
        // that freed the lavender for the button — and in Light each is the
        // palette darkened in oklch until it clears its floor on white, since the
        // published light values land at 4.1–4.3:1: fine for a capsule, short for
        // the label beside it.
        case .dracula: [
            // Note
            .blue: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.090, g: 0.525, b: 0.612), dark: RGB(r: 0.545, g: 0.914, b: 0.992),
                                 lightHC: RGB(r: 0.000, g: 0.422, b: 0.496), darkHC: RGB(r: 0.883, g: 0.978, b: 1.000)),
                label: DynamicRGB(light: RGB(r: 0.086, g: 0.467, b: 0.541), dark: RGB(r: 0.545, g: 0.914, b: 0.992),
                                  lightHC: RGB(r: 0.000, g: 0.365, b: 0.429), darkHC: RGB(r: 0.883, g: 0.978, b: 1.000))),
            // Meeting
            .yellow: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.706, g: 0.404, b: 0.039), dark: RGB(r: 1.000, g: 0.722, b: 0.424),
                                 lightHC: RGB(r: 0.575, g: 0.320, b: 0.000), darkHC: RGB(r: 1.000, g: 0.869, b: 0.740)),
                label: DynamicRGB(light: RGB(r: 0.639, g: 0.373, b: 0.031), dark: RGB(r: 1.000, g: 0.722, b: 0.424),
                                  lightHC: RGB(r: 0.511, g: 0.290, b: 0.000), darkHC: RGB(r: 1.000, g: 0.869, b: 0.740))),
            // Feedback
            .purple: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.690, g: 0.165, b: 0.447), dark: RGB(r: 1.000, g: 0.475, b: 0.776),
                                 lightHC: RGB(r: 0.574, g: 0.000, b: 0.352), darkHC: RGB(r: 1.000, g: 0.680, b: 0.849)),
                label: DynamicRGB(light: RGB(r: 0.612, g: 0.141, b: 0.392), dark: RGB(r: 1.000, g: 0.475, b: 0.776),
                                  lightHC: RGB(r: 0.495, g: 0.000, b: 0.299), darkHC: RGB(r: 1.000, g: 0.680, b: 0.849))),
            // Staffing
            .green: TypeTone(
                mark: DynamicRGB(light: RGB(r: 0.102, g: 0.561, b: 0.290), dark: RGB(r: 0.314, g: 0.980, b: 0.482),
                                 lightHC: RGB(r: 0.000, g: 0.453, b: 0.216), darkHC: RGB(r: 0.814, g: 1.000, b: 0.835)),
                label: DynamicRGB(light: RGB(r: 0.094, g: 0.498, b: 0.259), dark: RGB(r: 0.314, g: 0.980, b: 0.482),
                                  lightHC: RGB(r: 0.000, g: 0.393, b: 0.186), darkHC: RGB(r: 0.814, g: 1.000, b: 0.835))),
        ]
        }
    }
}

// MARK: - Picker

/// The Theme row's six swatches (Settings → Appearance). Each one is a **miniature
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
/// Mode decides which you see" — which is a sentence doing a job no
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
