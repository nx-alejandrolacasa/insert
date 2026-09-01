import AppKit
import SwiftUI

// MARK: - AppTheme

/// One of six named themes — Settings → Appearance → Theme. A theme is **three
/// grounds and one accent**, and those two are the rules: a theme that breaks
/// either reads as a *setting* rather than as a theme, which is exactly what the
/// first set did.
///
/// 1. **Three grounds — band, page, card.** The band is the surface behind a
///    column heading (`ColumnHeaderBand`); the page (`windowFill`, and so the
///    sidebar, which is see-through to it) and the card (`cardFace`) carry the
///    same hue family. So the window belongs to the theme instead of being a
///    coloured strip on neutral grey. The glass track on the band derives from
///    the band and is not a token set of its own.
/// 2. **One accent, for action only** — `primary`: "New Note" / "New Task",
///    focus rings, selected states (CLAUDE.md decision 4).
/// 3. **Text is not themed, except metadata and links.** `titleText` and
///    `bodyText` are `labelColor` in every theme. (Dracula, the one theme that
///    named its own, is gone.)
/// 4. **The count chip carries a second hue from the palette** — not the accent,
///    which is the button's, and the hue itself rather than a wash of it: the
///    chip's *fill* under a **white** numeral in Light, the numeral on a tinted
///    fill in Dark. System is excluded: a theme whose whole claim is that it adds
///    no colour of its own cannot colour the chip.
///
/// **A note type's colour is not one of a theme's values, and two of the plan's
/// rules went with that.** Types were briefly a per-theme palette — four hues
/// authored against each band, kept 25° clear of its accent and re-levelled into a
/// greyscale ladder. It is `Tint.ink` again, one palette for all six; the
/// note-type section below has the whole trade, including what the two retired
/// rules were insurance against.
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
/// its case: **verbatim** for grounds, card edges, links and accents;
/// **deepened** where an accent's label could not clear 4.5:1; **derived** where
/// a palette's comment grey failed on a card; and **desaturated** in two,
/// Kanagawa's Lotus grounds and Dark Owl's light band. (A fifth kind of change, re-levelling each palette's
/// four note-type hues, went with the per-theme type palettes.)
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
    /// link each step down until they clear 4.5:1. It authored four type hues of
    /// its own for a while — the system teal / orange / purple / green — and gave
    /// them up with every other theme's, see the note-type section.
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
    /// light background and nothing else. The count chip is the theme's `blue`
    /// `#7aa2f7`, the second hue everyone knows Tokyo Night by, deliberately not
    /// the magenta `#bb9af7` — which is Dracula's accent to within a couple of
    /// steps. Light takes the palette's own deep `blue0` `#3d59a1` so the numeral
    /// can be white.
    case tokyoNight

    /// The app's own — sourced from the maintainer's six-stop gradient rather
    /// than an upstream project, which makes it the set's one palette whose
    /// source is this repo: `#C9DBD5 → #A6C3C3 → #88AAB5 → #7290A7 → #667595 →
    /// #63597D`, sage through steel blue into dusky violet. **Only the first
    /// four stops are used** — the violet end is deliberately left out, by
    /// request, so nothing in the theme tends to purple. The band is the first
    /// stop `#C9DBD5` (the icon tile's own sage); the accent is `#B4CECE`, a
    /// pale tone between the first two stops, chosen by request — pale enough
    /// that its button wears a **dark** label in both appearances, and the
    /// light ring deepens in-hue to `#689797` since `#B4CECE` on a white card
    /// is 1.66:1; the count chip is the sage-teal `#88AAB5` — deepened for a
    /// white numeral in Light, lightened as the numeral in Dark. Light grounds
    /// stay in the sage family with white cards (the icon's paper is white
    /// too); Dark takes the gradient's steel blue down to a slate-blue ink,
    /// which is the "Tokyo" in the name.
    case nuevoTokyo

    /// `rebelot/kanagawa.nvim` → `lua/kanagawa/colors.lua`. Dark is Wave, Light
    /// is Lotus: warm cream on cold ink, and the set's one warm theme.
    ///
    /// **Orange is removed from the note types**, project dots included, so the
    /// only orange on screen is the button (`surimiOrange`). Lotus's own
    /// `#f2ecbc` page is too yellow to carry a window, so the page and cards are
    /// derived *above* the band and the band is the only saturated surface. The
    /// count chip is `springGreen` `#98bb6c` — a cold second voice against a warm
    /// accent, and the one Wave colour with enough chroma to read as a colour on
    /// Lotus paper: `waveAqua2`, the first choice, measures 0.05 C, half of what
    /// every other chip in the set carries.
    case kanagawa

    /// `hmseeb/dark-owl` → `theme/dark-owl.json`. Teal-navy grounds, violet
    /// action, spring-green links.
    ///
    /// The accent is the theme's own `button.background` at **full opacity**: the
    /// shipped `cc` alpha drops the white label under 4.5:1. Its light link is a
    /// deep jade rather than the theme's `#00ff9f`, which measures 1.4:1 on white.
    /// The count chip is the cyan — Night Owl's signature colour, and the one
    /// bright in the palette that is neither the violet action nor next to the
    /// spring-green link. It is `alexlafroscia/night-owl-palette`'s **normal**
    /// `cyan` `#94d8ca`, at full brightness in both halves, which makes Dark Owl
    /// the second theme after Rosé Pine to keep its bright hue as the Light fill
    /// and take a dark numeral: deepened to `#1c8374` for a white numeral it landed
    /// at `L` 0.55, where a cyan reads as a green — which is how it was reported —
    /// and the hue is too pale for anything else to be the colour. It replaced the
    /// coral `#f78c6c` before that, by request: the coral was the theme's strings
    /// colour and cleared every floor, but a warm chip in a cold theme read as a
    /// stray rather than as the palette's second voice.
    case darkOwl

    /// `rose-pine/palette`. Dark is main, Light is Dawn — plum and rose, on
    /// Dawn's pink-cream paper.
    ///
    /// It used to carry a recorded exception to the 25° rule — `love` at 343°
    /// against a blush Feedback mark at 2° — which is moot now that the types are
    /// one shared palette and that rule is gone. Worth keeping only for what it
    /// showed: the pairing was fine on screen, because the button is a saturated
    /// mid-tone where a mark is a pale blush, and the two never sit adjacent.
    ///
    /// The count chip is `gold`, and it is the **main** palette's `#f6c177` in both
    /// halves rather than Dawn's own `#ea9d34` — and now at full brightness on both
    /// sides, so Light is the one chip in the set that keeps the bright hue as its
    /// *fill* and takes a dark numeral. It is the exception the white-on-deep rule
    /// is stated against; see `Band.countFill`.
    case rosePine

    // Dracula was the sixth — the original of the set, and the theme the
    // sourced five were built to match. **Removed September 2026** at the
    // maintainer's request; the count-chip construction the whole set uses (a
    // vivid palette hue swapping roles per appearance) was found there before
    // it went. A saved `"dracula"` migrates to Dark Owl, the remaining dark
    // theme with a violet action — see `migrated(theme:tint:accent:)`.

    var id: Self { self }

    /// What a new install opens wearing. **The first case, unlike the previous
    /// set**, where the picker's order and the default were two different things.
    static let `default`: AppTheme = .system

    var label: String {
        switch self {
        case .system: "System"
        // Renamed from "Tokyo Night" in September 2026 — the label only. The
        // case and its raw value stay `tokyoNight`, because the raw value is
        // what the `theme` default holds and renaming it would silently reset
        // every install that had picked it.
        case .tokyoNight: "Neon"
        case .nuevoTokyo: "Nuevo Tokyo"
        case .kanagawa: "Kanagawa"
        case .darkOwl: "Dark Owl"
        case .rosePine: "Rosé Pine"
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
    /// **A saved `"dracula"` lands on Dark Owl** since the theme's September
    /// 2026 removal — the remaining dark theme with a violet action, which is
    /// the closest thing to what that install chose. (While Dracula existed the
    /// rule was the opposite: nobody *arrived* at it, because an identity has
    /// to be picked.)
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
        case "indigo", "dracula": return .darkOwl
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
    /// **Nuevo Tokyo's light ring is the one value in the set deepened here
    /// rather than sourced**: its pale `#B4CECE` accent is 1.66:1 on a white
    /// card — under the 3:1 an indicator needs — so the ring is the same hue at
    /// `#689797`, 3.25:1. Note the previous set's rule that a ring must differ
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
    /// `bodyText` are the system's in every theme for that reason.
    ///
    /// Its Increase Contrast pair steps most of the way to the label colour, the
    /// same move `Stone.metaText` makes — and for the same reason, that the solved
    /// values barely move under that switch and it has to look like it did
    /// something.
    var metaText: Color { resolved.metaText }

    /// A card's **title** colour, and the plainest statement of the rule above:
    /// it is `labelColor` — the system's, full contrast, unthemed — in every
    /// theme. If these ever start differing per theme, a theme is reaching
    /// further than the plan allows; `ThemePaletteTests` asserts exactly that.
    var titleText: Color { resolved.titleText }

    /// A card's **body** colour, on the same terms as `titleText`. The two stay
    /// separate values because Dracula's body was a step softer than its title
    /// while it existed, and a future text-palette theme would want the split.
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
    /// a new project. Only the *auto-assigned* default follows the theme: a
    /// colour the user picked is data, and switching theme must never rewrite
    /// it. Kanagawa is the one reorder left (Dracula led with its own five
    /// until its removal); the rest keep the app's own dot order.
    var projectTintOrder: [Tint] {
        switch self {
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

    // MARK: Note-type colour

    // **A note type's colour is not a theme value.** It is `Tint.ink` — the mark
    // beside a title, the dot in the notes filter track and the small-caps label
    // in the meta row, all in the one value, as they were before this file
    // existed. `typeMark(_:)` and `typeLabel(_:)` are gone with the table behind
    // them; call sites read `type.tint.ink`.
    //
    // That retires the plan's "its own note-type palette" rule and, with it, two
    // more of its acceptance criteria, so here is the whole trade. What the
    // per-theme palettes bought was four hues tuned to each band, and 6 × 4 × 2
    // authored values to keep consistent. What they cost was more: the four types
    // are the *same four* in every theme, so a user learning "blue is a Note"
    // should not have them shift under a colour preference — and tuned to sit
    // quietly beside a band, they read **muted** against the rest of the app's
    // colour, which is how this was reported ("the notes colours are off in all
    // themes; the ones for tasks stay vibrant and crisp"). A maintainer's call,
    // taken knowing what goes with it:
    //
    // - **The 25° accent-vs-type-hue rule can no longer hold.** One palette against
    //   six accents means some theme's accent lands on some type's hue, and two
    //   do: Dark Owl's violet and Dracula's lavender both sit within a couple of
    //   degrees of the purple a Feedback note wears. The rule's *point* — that
    //   "action" reads as action — is carried by the accent being the only thing
    //   that fills a pill, and by nothing else on a card wearing it.
    // - **The greyscale ladder goes too.** The app's four tints don't
    //   form one, and levelling them apart would mean re-authoring the palette
    //   the whole app shares to solve a problem inside one card's meta row. The
    //   type's name is spelled out beside its mark, which is what the ladder was
    //   insurance for.
    //
    // What stays is the part that can fail silently, and it got *stricter*: the
    // one palette is measured against **every theme's** card face and filter
    // track rather than against the six it was authored for (see `Tint.ink`).

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
    /// The count chip's fill: **a second hue from the theme's own palette**, and
    /// the one place a theme spends a colour that is not its accent.
    ///
    /// It has been three things. White at 12% was a value with no opinion, which
    /// left the one number in the band reading as chrome. The **accent** at low
    /// alpha over the band fixed that on paper and not on screen: composited into
    /// a pale band it came out a wash of the button beside it — `L` above 0.90 in
    /// all four sourced themes — so the chip still read as chrome while Dracula's,
    /// which was never a wash, read as the theme. So every sourced theme now does
    /// what Dracula does: a **vivid** hue, taken from its palette and named in its
    /// case (Tokyo Night's `blue`, Kanagawa's `springGreen`, Dark Owl's cyan,
    /// Rosé Pine's `gold`, Dracula's pink), and never the accent — the button owns
    /// that, and a chip repeating it is what made the wash look like chrome.
    ///
    /// **The hue swaps roles per appearance**, because it cannot carry both ways:
    /// in Light it is the chip's *fill*, since a hue bright enough to read as text
    /// on a pale band does not exist in these palettes; in Dark it is the numeral
    /// itself, on that hue at 20% over the band, composited offline so nothing
    /// layers alpha at draw time — lightened in-hue only where the floor needs it,
    /// which is Tokyo Night's blue and Kanagawa's green. Dracula's Dark fill is the
    /// one that is *recessed* below its band rather than tinted above it; that is
    /// its own value, kept.
    ///
    /// **The Light numeral is white, and the fill is deepened to carry it** — with
    /// **Rosé Pine and Dark Owl the two exceptions** — by request in every
    /// direction, which is
    /// worth reading as one decision rather than as a rule and a lapse. The bright
    /// hue under a near-black numeral was the first cut of this and read muddy
    /// everywhere it was tried but the gold. White needs the fill at `L` ≈ 0.55 or
    /// below to clear 4.5:1, so each one is the palette's own deep member of that
    /// hue where it publishes one (Tokyo Night's `blue0` `#3d59a1`, verbatim) and
    /// the hue deepened in oklch at constant chroma and hue where it doesn't
    /// (Kanagawa's `lotusGreen` → `#637c42`, Dracula's pink → `#b02a72`, which is
    /// the same deepening the plan derived for
    /// its light pink). It is the "deepen and invert to white-on-deep" move
    /// Kanagawa's and Rosé Pine's primary buttons already make, spent here on the
    /// chip; the cost is that a light chip reads heavier than the bright pill it
    /// replaced, which is the trade that was asked for.
    ///
    /// **Rosé Pine keeps `gold` `#f6c177` itself in Light**, under the band's own
    /// dark plum: at `L` 0.84 it is far too light for a white numeral, and it is the
    /// one hue in the set bright enough that deepening it was the thing that read
    /// wrong. So the floor is met from the other side — a dark numeral on a bright
    /// fill, 5.98:1 — and the rule the other three follow is what the chip does when
    /// its hue *can't* carry that.
    ///
    /// **Dark Owl does the same with its cyan `#94d8ca`**, for the other reason a
    /// bright hue survives here: deepened to `L` 0.55 it read as a *green* rather
    /// than as Night Owl's cyan, which is the one thing the chip is there to say. At
    /// `L` 0.83 it takes the band's own navy at 9.55:1. Two exceptions out of five
    /// is where the rule stands: white-on-deep is what a hue does when it can carry
    /// a white numeral **and** still reads as itself once it can.
    ///
    /// **System keeps a neutral chip**, because a theme whose claim is that it adds
    /// no colour cannot spend one here. Both directions are measured on the
    /// composited value rather than on the raw fill, which is the check that caught
    /// the most defects in design.
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

    init(_ theme: AppTheme) {
        let tones = theme.tones
        band = BandColors(tones)
        let grounds = theme.grounds
        window = grounds.window.color
        card = grounds.card.color
        border = grounds.border.color
        metaText = theme.metaTones.color
        // `labelColor`, unthemed, for every theme — the writing's contrast is
        // the system's business (Dracula, the one exception, is gone).
        titleText = Color(nsColor: .labelColor)
        bodyText = Color(nsColor: .labelColor)
        link = theme.linkTones.color
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
    /// hairline, the accent and the chip's hue come from the source — the chip's
    /// being a *second* palette colour, never the accent; the track and the
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
        // chip is the one neutral one in the set, which is rule 4's exclusion.
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
        // white card. The chip is the `blue` in both halves at the palette's own two
        // depths: `blue0` as the light fill, and `blue` lightened in-hue as the dark
        // numeral — `#7aa2f7` itself is 4.04:1 on its own composited fill.
        case .tokyoNight: Tones(
            light: Band(
                fill: RGB(r: 0.902, g: 0.906, b: 0.929),
                text: RGB(r: 0.169, g: 0.188, b: 0.286),
                countFill: RGB(r: 0.239, g: 0.349, b: 0.631),
                countText: RGB(r: 1.000, g: 1.000, b: 1.000),
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
                countFill: RGB(r: 0.209, g: 0.253, b: 0.379),
                countText: RGB(r: 0.663, g: 0.757, b: 0.984),
                primary: RGB(r: 0.451, g: 0.855, b: 0.792),
                primaryLabel: RGB(r: 0.102, g: 0.106, b: 0.149),
                ring: RGB(r: 0.451, g: 0.855, b: 0.792),
                trackFill: RGB(r: 0.227, g: 0.241, b: 0.308),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.803, g: 0.828, b: 0.927),
                segmentFill: RGB(r: 0.881, g: 0.905, b: 1.000),
                segmentLabelSelected: RGB(r: 0.141, g: 0.157, b: 0.231)))
        // The gradient's sage half (see the case): band `#C9DBD5`, accent
        // `#B4CECE` — pale by request, so the button carries the band's own dark
        // ink as its label in both appearances (7.9:1 light, 10.7:1 dark) and
        // only the light ring deepens, to `#689797` at 3.25:1 on the white card.
        // The chip is `#88AAB5` deepened to `#2F5D6B` as the light fill under a
        // white numeral and lightened to `#8FCADC` as the dark numeral — the
        // published teal is 0.040 C, the quietest chip hue in the set, so the
        // numeral is saturated a step with the lightness. Track and segments
        // derived from the band's hue by the rules on `Band`.
        case .nuevoTokyo: Tones(
            light: Band(
                fill: RGB(r: 0.788, g: 0.859, b: 0.835),
                text: RGB(r: 0.165, g: 0.196, b: 0.220),
                countFill: RGB(r: 0.184, g: 0.365, b: 0.420),
                countText: RGB(r: 1.000, g: 1.000, b: 1.000),
                primary: RGB(r: 0.706, g: 0.808, b: 0.808),
                primaryLabel: RGB(r: 0.165, g: 0.196, b: 0.220),
                ring: RGB(r: 0.408, g: 0.592, b: 0.592),
                trackFill: RGB(r: 0.863, g: 0.906, b: 0.886),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.306, g: 0.353, b: 0.333),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.165, g: 0.196, b: 0.220)),
            dark: Band(
                fill: RGB(r: 0.149, g: 0.184, b: 0.212),
                text: RGB(r: 0.769, g: 0.824, b: 0.847),
                countFill: RGB(r: 0.226, g: 0.281, b: 0.312),
                countText: RGB(r: 0.561, g: 0.792, b: 0.863),
                primary: RGB(r: 0.706, g: 0.808, b: 0.808),
                primaryLabel: RGB(r: 0.078, g: 0.098, b: 0.114),
                ring: RGB(r: 0.706, g: 0.808, b: 0.808),
                trackFill: RGB(r: 0.234, g: 0.266, b: 0.291),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.784, g: 0.839, b: 0.863),
                segmentFill: RGB(r: 0.847, g: 0.894, b: 0.914),
                segmentLabelSelected: RGB(r: 0.149, g: 0.184, b: 0.212)))
        // Wave's `sumiInk5` band over `sumiInk3`, and Lotus's `lotusWhite2` over a
        // page derived above it — **at half Lotus's chroma**, by request: the
        // published `lotusWhite2` is 0.060 C, which is more than twice any other
        // band in the set and read as a khaki slab rather than as warm paper. Hue
        // and lightness are the palette's; only the saturation is ours, and the
        // page and card were eased with it so the three grounds stay one family.
        // The chip's green follows the halves the rest of the theme does: Wave's
        // `springGreen` in Dark, lightened in-hue for the numeral since the palette
        // has no lighter green; Lotus's `lotusGreen` in Light, deepened to `#637c42`
        // so a white numeral clears the floor — `lotusGreen` itself is 3.91:1.
        // The Lotus accent is the orange **deepened to
        // carry a white label** — `surimiOrange` is 1.96:1 on Lotus paper, so
        // Light inverts to white-on-deep while Dark keeps the bright original
        // under a `sumiInk3` label.
        case .kanagawa: Tones(
            light: Band(
                fill: RGB(r: 0.878, g: 0.867, b: 0.773),
                text: RGB(r: 0.329, g: 0.329, b: 0.392),
                countFill: RGB(r: 0.388, g: 0.488, b: 0.259),
                countText: RGB(r: 1.000, g: 1.000, b: 1.000),
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
                countFill: RGB(r: 0.289, g: 0.316, b: 0.304),
                countText: RGB(r: 0.690, g: 0.812, b: 0.541),
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
        // the white label under 4.5:1 — and the dark ring is its lifted violet. The
        // cyan chip is the palette's normal `cyan` **verbatim in both halves** — the
        // dark numeral, and the light *fill* under the band's own navy at 9.55:1.
        // The light band is the plan's hue at **half its chroma**, by request: at
        // 0.018 C it read as a blue slab rather than as a header over blue-white
        // paper, so the hue and lightness stand and only the saturation is ours.
        // Its track and segment label are re-derived from it, as they are derived
        // from every band's hue.
        case .darkOwl: Tones(
            light: Band(
                fill: RGB(r: 0.921, g: 0.945, b: 0.963),
                text: RGB(r: 0.060, g: 0.147, b: 0.232),
                countFill: RGB(r: 0.580, g: 0.847, b: 0.792),
                countText: RGB(r: 0.060, g: 0.147, b: 0.232),
                primary: RGB(r: 0.494, g: 0.341, b: 0.761),
                primaryLabel: RGB(r: 1.000, g: 1.000, b: 1.000),
                ring: RGB(r: 0.494, g: 0.341, b: 0.761),
                trackFill: RGB(r: 0.876, g: 0.900, b: 0.918),
                trackHighlight: false,
                segmentLabel: RGB(r: 0.286, g: 0.305, b: 0.320),
                segmentFill: RGB(r: 1.000, g: 1.000, b: 1.000),
                segmentLabelSelected: RGB(r: 0.060, g: 0.147, b: 0.232)),
            dark: Band(
                fill: RGB(r: 0.043, g: 0.161, b: 0.259),
                text: RGB(r: 0.902, g: 0.929, b: 0.961),
                countFill: RGB(r: 0.151, g: 0.298, b: 0.366),
                countText: RGB(r: 0.580, g: 0.847, b: 0.792),
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
        // under a near-black one. The chip is `gold` `#f6c177` **verbatim in both
        // halves** — the dark numeral, and the light *fill* — which makes it the one
        // light chip in the set that is not deepened for a white numeral. It carried
        // `#9b6b1a` under white until it was asked for at full brightness; the
        // numeral there is the band's own text rather than black, since the band had
        // already solved a dark plum for gold and it clears 5.98:1.
        case .rosePine: Tones(
            light: Band(
                fill: RGB(r: 0.949, g: 0.914, b: 0.882),
                text: RGB(r: 0.271, g: 0.247, b: 0.388),
                countFill: RGB(r: 0.965, g: 0.757, b: 0.467),
                countText: RGB(r: 0.271, g: 0.247, b: 0.388),
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
                countFill: RGB(r: 0.312, g: 0.261, b: 0.275),
                countText: RGB(r: 0.965, g: 0.757, b: 0.467),
                primary: RGB(r: 0.922, g: 0.435, b: 0.573),
                primaryLabel: RGB(r: 0.169, g: 0.102, b: 0.141),
                ring: RGB(r: 0.922, g: 0.435, b: 0.573),
                trackFill: RGB(r: 0.234, g: 0.224, b: 0.305),
                trackHighlight: true,
                segmentLabel: RGB(r: 0.827, g: 0.817, b: 0.937),
                segmentFill: RGB(r: 0.904, g: 0.896, b: 1.000),
                segmentLabelSelected: RGB(r: 0.149, g: 0.137, b: 0.227)))
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
        // A pale sage page under white cards in Light, and the gradient's steel
        // blue taken down to a slate-blue ink in Dark, with the edge white at
        // 8% over the card, composited here like every other dark edge.
        case .nuevoTokyo: Grounds(
            window: DynamicRGB(light: RGB(r: 0.937, g: 0.957, b: 0.949), dark: RGB(r: 0.078, g: 0.098, b: 0.114)),
            card: DynamicRGB(light: RGB(r: 1.000, g: 1.000, b: 1.000), dark: RGB(r: 0.106, g: 0.133, b: 0.157)),
            border: DynamicRGB(light: RGB(r: 0.761, g: 0.831, b: 0.816), dark: RGB(r: 0.178, g: 0.202, b: 0.224)))
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
        }
    }

    /// Metadata type, per theme, and the value most likely to fail: it is the one
    /// themed *text* colour, and it lands on the card rather than on the band.
    ///
    /// Neon's `#565f89` (6.2:1 on white) and Rosé Pine's `subtle` in Dark are
    /// their palette's own comment grey, verbatim. The rest are derived, because
    /// the published grey failed on the card: Rosé Pine's `subtle` measures
    /// 4.3:1 on Dawn's paper, and `secondaryLabel` at its shipping opacity is
    /// ~3.4:1.
    var metaTones: DynamicRGB {
        switch self {
        case .system: DynamicRGB(
            light: RGB(r: 0.388, g: 0.388, b: 0.400), dark: RGB(r: 0.596, g: 0.596, b: 0.616),
            lightHC: RGB(r: 0.296, g: 0.296, b: 0.307), darkHC: RGB(r: 0.699, g: 0.699, b: 0.720))
        case .tokyoNight: DynamicRGB(
            light: RGB(r: 0.337, g: 0.373, b: 0.537), dark: RGB(r: 0.545, g: 0.576, b: 0.722),
            lightHC: RGB(r: 0.248, g: 0.280, b: 0.437), darkHC: RGB(r: 0.647, g: 0.680, b: 0.829))
        case .nuevoTokyo: DynamicRGB(
            light: RGB(r: 0.361, g: 0.408, b: 0.439), dark: RGB(r: 0.576, g: 0.651, b: 0.690),
            lightHC: RGB(r: 0.275, g: 0.316, b: 0.345), darkHC: RGB(r: 0.700, g: 0.760, b: 0.790))
        case .kanagawa: DynamicRGB(
            light: RGB(r: 0.427, g: 0.408, b: 0.529), dark: RGB(r: 0.604, g: 0.592, b: 0.549),
            lightHC: RGB(r: 0.334, g: 0.314, b: 0.431), darkHC: RGB(r: 0.732, g: 0.720, b: 0.675))
        case .darkOwl: DynamicRGB(
            light: RGB(r: 0.356, g: 0.420, b: 0.476), dark: RGB(r: 0.490, g: 0.576, b: 0.659),
            lightHC: RGB(r: 0.265, g: 0.326, b: 0.380), darkHC: RGB(r: 0.591, g: 0.679, b: 0.764))
        case .rosePine: DynamicRGB(
            light: RGB(r: 0.427, g: 0.408, b: 0.529), dark: RGB(r: 0.565, g: 0.549, b: 0.667),
            lightHC: RGB(r: 0.334, g: 0.314, b: 0.431), darkHC: RGB(r: 0.667, g: 0.651, b: 0.773))
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
        case .nuevoTokyo: DynamicRGB(
            light: RGB(r: 0.200, g: 0.376, b: 0.498), dark: RGB(r: 0.561, g: 0.757, b: 0.878),
            lightHC: RGB(r: 0.149, g: 0.286, b: 0.373), darkHC: RGB(r: 0.780, g: 0.880, b: 0.949))
        case .kanagawa: DynamicRGB(
            light: RGB(r: 0.179, g: 0.485, b: 0.596), dark: RGB(r: 0.498, g: 0.706, b: 0.792),
            lightHC: RGB(r: 0.000, g: 0.370, b: 0.476), darkHC: RGB(r: 0.602, g: 0.813, b: 0.901))
        case .darkOwl: DynamicRGB(
            light: RGB(r: 0.000, g: 0.459, b: 0.306), dark: RGB(r: 0.000, g: 1.000, b: 0.624),
            lightHC: RGB(r: 0.000, g: 0.351, b: 0.230), darkHC: RGB(r: 0.845, g: 1.000, b: 0.901))
        case .rosePine: DynamicRGB(
            light: RGB(r: 0.157, g: 0.412, b: 0.514), dark: RGB(r: 0.420, g: 0.663, b: 0.769),
            lightHC: RGB(r: 0.021, g: 0.317, b: 0.415), darkHC: RGB(r: 0.523, g: 0.769, b: 0.877))
        }
    }

    // `writingTones` is gone with Dracula, which was the one theme naming its
    // own title and body — the writing is `labelColor` in all six now, with no
    // exception left to plumb for. Every palette in the set *does* publish a
    // title and a body; declining them is rule 3, not an omission.
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
