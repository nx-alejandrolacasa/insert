import AppKit
import SwiftUI

// MARK: - Tint

/// A soft pastel accent used by note types and projects (and available when
/// creating custom ones).
///
/// Each tint exposes its colours by *role* rather than by shade, because the same
/// hue needs a different value depending on what sits against it:
///
/// - `accent` — the vivid colour. Only ever a wash behind `.primary` text or a
///   decorative stroke, so it never has to carry legibility by itself.
/// - `deep` — a solid fill that **white** text sits on: the sidebar's selection
///   pill, a selected filter pill, the calendar's selected day.
/// - `ink` — the tint as a **foreground**: glyphs drawn on the app's own
///   surfaces (an island, a chip capsule, the window).
/// - `soft` / `chip` — translucent washes, derived from `accent`.
///
/// `deep` and `ink` pull in opposite directions in Dark Mode: a fill carrying
/// white type has to stay dark, while a glyph on a dark island has to get
/// *lighter*. They were a single "deep" value until measurement put purple's
/// glyph-on-dark-island at 2.54:1 — no one colour can do both jobs, hence two
/// roles. Every value below is solved against WCAG AA (4.5:1 for type, and 7:1
/// for the Increase Contrast variants).
enum Tint: String, CaseIterable, Identifiable, Codable {
    case gray
    case yellow
    case purple
    case green
    case blue
    case orange
    case pink
    case teal
    case red

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    /// The vivid accent colour, and **the app's one dot colour**: a project's chip
    /// dot and its sidebar wash, the tasks track's Pending and Done dots, the type
    /// swatches in Settings, and a note type's own two graphics — its 3×16pt capsule
    /// mark beside the title and its dot in the notes filter track.
    ///
    /// **It is held to no contrast floor, and that is the deliberate half of the
    /// split with `ink`.** These are bright values by design: yellow measures
    /// 1.58:1 as a dot on Rosé Pine's
    /// paper, which would fail the 3:1 a *required* graphic is held to. Nothing here
    /// is required — every dot and mark in the app sits beside the name of the thing
    /// it marks, so the colour is a second voice rather than the only one, and the
    /// text beside it carries the floor. The note-type mark was briefly `ink`
    /// instead, on the reasoning that a bar is big enough to be worth solving, and
    /// it was reversed on sight: against project dots and the tasks track — both
    /// `accent` all along — the deeper value read as *muted*, which is how it was
    /// reported ("the tones in the settings are nice, but the ones shown in the UI
    /// not"). One dot colour, everywhere.
    var accent: Color { palette.accent }

    /// A solid fill that carries white type at 4.5:1 or better. Doesn't change
    /// between Light and Dark — white-on-fill contrast doesn't depend on what's
    /// behind the fill — but it does deepen when Increase Contrast is on.
    var deep: Color { palette.deep }

    /// The tint as a foreground, at 4.5:1 or better against the surfaces it's drawn
    /// on — deepened in Light, brightened in Dark.
    ///
    /// **This is a note type's label colour again** — the small-caps type name
    /// leading a card's meta row — as it was before the theme system gave every
    /// theme a palette of its own. Six themes × four types × two appearances was a
    /// lot of decisions to keep consistent, and what it bought — hues tuned to each
    /// band — cost the thing that mattered more: the four types are the *same four*
    /// whatever theme is on, so they should look it. See `AppTheme` for the two
    /// rules that retires.
    ///
    /// The type's two *graphics* — the capsule mark and the filter dot — are
    /// `accent`, not this: text carries a floor, decoration doesn't.
    ///
    /// Which is why the surfaces it is solved against are now **every theme's**:
    /// the twelve card faces, plus the sidebar and popover grounds it already
    /// served. That re-solve moved four base values and eight Increase Contrast
    /// ones, all by a few points of lightness at the same hue — the themed dark
    /// cards are *lighter* than the flat near-black island these were first measured
    /// on, which is what took dark purple under the floor. Worst pairing in the set
    /// is now 4.65:1 on a card; `ThemePaletteTests` measures all of it.
    var ink: Color { palette.ink }

    /// A subtle background wash for note "islands" of this type.
    var soft: Color { palette.soft }

    /// A slightly stronger fill for pills/chips.
    var chip: Color { palette.chip }
}

// The `marker` role — the highlighter band a note title used to wear (the July
// 2026 refresh's decision 2) — lived here and is gone, along with `MarkerTitle`.
// It was the refresh's answer to "where does a note's type show", and the
// answer was wrong in a way no value fixed: a coloured band behind the glyphs
// fights the letters at any opacity, and it forced every title onto a tinted
// ground. The strength had already been walked from the handoff's 60% down to
// 45% for exactly that reason and it was still the wrong shape. A note's type is
// now a 3pt capsule mark *beside* the title (`TypeMarkTitle`) in the type's
// `accent`, which costs the title nothing.

// `AccentColor` and `AccentPicker` — Settings → General → Accent ("Highlight
// colour"), five swatches, blue by default — lived here. Both are gone: the
// accent is no longer chosen beside the window's colour, it *is* the window's
// colour, one of the six `AppTheme`s setting its band and its primary
// together. What the accent got right survives in `AppTheme.primary`: one hue,
// for interactive and selected state only (CLAUDE.md decision 4). What it got
// wrong is that it had no relationship to the tint it sat next to, so two
// separate settings could be combined into something neither had been solved
// for. A saved accent still decides the migration where a saved tint doesn't —
// see `AppTheme.migrated(tint:accent:)`.

// MARK: - Semantic colours

/// The one place red is allowed: a genuinely overdue task's date. Everything
/// else a date can be — today, upcoming, "created at" — is grey, so that when
/// this fires it means exactly one thing (CLAUDE.md decision 4).
///
/// oklch 50% 0.16 32 in Light (6.5:1 on the white card), brightened to 72% in
/// Dark (6.3:1 on the dark card) — the `Tint.ink` move, solved against the
/// refresh's AA floor for sub-14px text rather than borrowed from `Tint.red`,
/// whose hue is pinker than the overdue token's vermilion.
enum Semantic {
    static let overdue: Color = dynamic(
        light: RGB(r: 0.672, g: 0.200, b: 0.122),
        dark: RGB(r: 0.937, g: 0.504, b: 0.421),
        lightHC: RGB(r: 0.560, g: 0.150, b: 0.080),
        darkHC: RGB(r: 0.965, g: 0.560, b: 0.480))
}

// MARK: - Palette

/// A plain sRGB triple. Spelled out rather than stored as a `Color` so the table
/// below stays readable as *data*, and so one value can feed several appearances.
struct RGB {
    let r, g, b: Double
    var color: Color { Color(red: r, green: g, blue: b) }
}

/// Every legibility-critical value for one tint.
///
/// Written as explicit literals rather than derived from `accent` by a scale
/// factor: the factor needed to clear 4.5:1 differs per hue — yellow had to come
/// down by 21%, teal by only 5% — so there is no single function to apply. A
/// palette whose whole purpose is measured contrast is also easier to trust when
/// you can read the numbers off it.
private struct Ramp {
    let accent: RGB
    /// Solid fill under white type: ≥4.5:1, and ≥7:1 for `fillHC`.
    let fill: RGB, fillHC: RGB
    /// Foreground on app surfaces, per appearance: ≥4.5:1, ≥7:1 for the HC pair.
    let inkLight: RGB, inkDark: RGB
    let inkLightHC: RGB, inkDarkHC: RGB
}

/// One tint's five role colours, materialised **once**.
///
/// The roles were computed properties, and every access built a fresh dynamic
/// `NSColor` — a new provider closure wrapped in a new `Color`. Two of those
/// never compare equal, so any view holding one compared unequal to its
/// predecessor on every pass and SwiftUI could not skip an unchanged card; the
/// dots, chips and labels also allocated per item, per render. One instance per
/// role is the same move `Stone`'s `static let`s and `AppTheme`'s resolved table
/// already make. The providers still resolve per appearance, so Light/Dark and
/// Increase Contrast behave exactly as before.
private struct TintPalette {
    let accent, deep, ink, soft, chip: Color
}

private extension Tint {
    var palette: TintPalette { Self.palettes[self]! }

    static let palettes: [Tint: TintPalette] = Dictionary(
        uniqueKeysWithValues: allCases.map { tint in
            let ramp = tint.ramp
            let accent = ramp.accent.color
            return (tint, TintPalette(
                accent: accent,
                deep: dynamic(light: ramp.fill, dark: ramp.fill,
                              lightHC: ramp.fillHC, darkHC: ramp.fillHC),
                ink: dynamic(light: ramp.inkLight, dark: ramp.inkDark,
                             lightHC: ramp.inkLightHC, darkHC: ramp.inkDarkHC),
                soft: accent.opacity(0.14),
                chip: accent.opacity(0.20)))
        })

    var ramp: Ramp {
        switch self {
        case .gray: Ramp(
            accent:     RGB(r: 0.63, g: 0.59, b: 0.53),
            fill:       RGB(r: 0.44, g: 0.41, b: 0.35),
            fillHC:     RGB(r: 0.37, g: 0.34, b: 0.29),
            inkLight:   RGB(r: 0.41, g: 0.39, b: 0.33),
            inkDark:    RGB(r: 0.65, g: 0.61, b: 0.55),
            inkLightHC: RGB(r: 0.29, g: 0.27, b: 0.23),
            inkDarkHC:  RGB(r: 0.80, g: 0.75, b: 0.68))
        // Yellow's dark halves are the one aesthetic judgment in this table:
        // any yellow at 4.5:1 goes brown, and the first values leaned olive —
        // "that brown/gold-ish shade is ugly". These sit at the floor's edge
        // (4.55:1, 7.2:1 HC) with the green pulled up and the blue pulled out,
        // which reads as amber rather than mud. They can't get brighter
        // without giving up AA; if they still look wrong, the lever is hue,
        // not lightness.
        case .yellow: Ramp(
            accent:     RGB(r: 0.95, g: 0.77, b: 0.29),
            fill:       RGB(r: 0.63, g: 0.42, b: 0.00),
            fillHC:     RGB(r: 0.47, g: 0.31, b: 0.00),
            inkLight:   RGB(r: 0.61, g: 0.40, b: 0.00),
            inkDark:    RGB(r: 0.95, g: 0.77, b: 0.29),
            inkLightHC: RGB(r: 0.46, g: 0.31, b: 0.00),
            inkDarkHC:  RGB(r: 0.95, g: 0.77, b: 0.29))
        case .purple: Ramp(
            accent:     RGB(r: 0.60, g: 0.45, b: 0.95),
            fill:       RGB(r: 0.45, g: 0.29, b: 0.85),
            fillHC:     RGB(r: 0.39, g: 0.25, b: 0.74),
            inkLight:   RGB(r: 0.44, g: 0.28, b: 0.82),
            inkDark:    RGB(r: 0.66, g: 0.53, b: 1.00),
            inkLightHC: RGB(r: 0.31, g: 0.20, b: 0.59),
            inkDarkHC:  RGB(r: 0.85, g: 0.69, b: 1.00))
        case .green: Ramp(
            accent:     RGB(r: 0.35, g: 0.78, b: 0.55),
            fill:       RGB(r: 0.15, g: 0.52, b: 0.33),
            fillHC:     RGB(r: 0.11, g: 0.39, b: 0.25),
            inkLight:   RGB(r: 0.12, g: 0.44, b: 0.28),
            inkDark:    RGB(r: 0.35, g: 0.78, b: 0.55),
            inkLightHC: RGB(r: 0.09, g: 0.32, b: 0.20),
            inkDarkHC:  RGB(r: 0.40, g: 0.84, b: 0.61))
        case .blue: Ramp(
            accent:     RGB(r: 0.30, g: 0.62, b: 0.98),
            fill:       RGB(r: 0.13, g: 0.45, b: 0.88),
            fillHC:     RGB(r: 0.10, g: 0.34, b: 0.67),
            inkLight:   RGB(r: 0.11, g: 0.38, b: 0.75),
            inkDark:    RGB(r: 0.30, g: 0.62, b: 0.98),
            inkLightHC: RGB(r: 0.08, g: 0.27, b: 0.54),
            inkDarkHC:  RGB(r: 0.48, g: 0.79, b: 1.00))
        case .orange: Ramp(
            accent:     RGB(r: 0.98, g: 0.62, b: 0.30),
            fill:       RGB(r: 0.70, g: 0.37, b: 0.07),
            fillHC:     RGB(r: 0.53, g: 0.28, b: 0.06),
            inkLight:   RGB(r: 0.59, g: 0.32, b: 0.06),
            inkDark:    RGB(r: 0.98, g: 0.62, b: 0.30),
            inkLightHC: RGB(r: 0.42, g: 0.23, b: 0.05),
            inkDarkHC:  RGB(r: 1.00, g: 0.68, b: 0.41))
        case .pink: Ramp(
            accent:     RGB(r: 0.96, g: 0.52, b: 0.72),
            fill:       RGB(r: 0.76, g: 0.29, b: 0.50),
            fillHC:     RGB(r: 0.58, g: 0.22, b: 0.38),
            inkLight:   RGB(r: 0.65, g: 0.24, b: 0.42),
            inkDark:    RGB(r: 0.96, g: 0.52, b: 0.72),
            inkLightHC: RGB(r: 0.46, g: 0.17, b: 0.30),
            inkDarkHC:  RGB(r: 1.00, g: 0.65, b: 0.83))
        case .teal: Ramp(
            accent:     RGB(r: 0.30, g: 0.78, b: 0.80),
            fill:       RGB(r: 0.09, g: 0.51, b: 0.54),
            fillHC:     RGB(r: 0.06, g: 0.38, b: 0.40),
            inkLight:   RGB(r: 0.07, g: 0.43, b: 0.46),
            inkDark:    RGB(r: 0.30, g: 0.78, b: 0.80),
            inkLightHC: RGB(r: 0.05, g: 0.31, b: 0.33),
            inkDarkHC:  RGB(r: 0.34, g: 0.82, b: 0.84))
        case .red: Ramp(
            accent:     RGB(r: 0.96, g: 0.42, b: 0.42),
            fill:       RGB(r: 0.84, g: 0.24, b: 0.24),
            fillHC:     RGB(r: 0.64, g: 0.18, b: 0.18),
            inkLight:   RGB(r: 0.71, g: 0.20, b: 0.20),
            inkDark:    RGB(r: 0.98, g: 0.44, b: 0.44),
            inkLightHC: RGB(r: 0.51, g: 0.15, b: 0.15),
            inkDarkHC:  RGB(r: 1.00, g: 0.66, b: 0.66))
        }
    }
}

/// Wraps four explicit variants in one appearance-reactive colour, so no view has
/// to read `colorScheme` / `colorSchemeContrast` itself and every `tint.deep` and
/// `tint.ink` call site stays a plain `Color`.
///
/// The two axes have to be read from different places, which is not obvious:
///
/// - **Light vs Dark** comes from the appearance AppKit hands the provider.
/// - **Increase Contrast** does *not*. It would be natural to ask the appearance
///   — macOS does swap in `accessibilityHighContrastAqua` when the setting is on
///   — but that appearance reports its `name` as plain `NSAppearanceNameAqua`,
///   so `bestMatch(from:)` and a direct `name ==` comparison both collapse it
///   onto the base appearance and the high-contrast variants never fire. The
///   setting has to be read from `NSWorkspace` instead. Toggling it changes the
///   effective appearance, which is what re-invokes this provider.
private func dynamic(light: RGB, dark: RGB, lightHC: RGB, darkHC: RGB) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let isHighContrast = AccessibilityOverride.increaseContrast
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let rgb = switch (isDark, isHighContrast) {
        case (false, false): light
        case (false, true): lightHC
        case (true, false): dark
        case (true, true): darkHC
        }
        return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    })
}

/// The Accessibility menu's in-app "Increase Contrast", mirrored out of
/// `SettingsStore` so the dynamic-colour providers above can read it: those
/// closures are nonisolated and resolve off SwiftUI's schedule, so they can't
/// touch a `@MainActor` store. Written only from the main thread
/// (`SettingsStore` owns it), hence the unsafe opt-out rather than a lock.
/// `SettingsStore.refreshDynamicColors()` is the other half — flipping this
/// changes what the providers *would* answer, and something still has to make
/// AppKit ask them again.
enum AccessibilityOverride {
    nonisolated(unsafe) static var increaseContrast = false
}

// MARK: - Stone

/// The app's neutral. Plain grey read cold and a little clinical beside the
/// pastel type tints, so every neutral surface — task rows, chips, hairlines —
/// is this barely-there warm stone instead. It's a mid-tone laid on at low
/// opacity rather than a fixed colour, so it warms whatever sits behind it and
/// needs no separate light/dark variants.
enum Stone {
    /// One wash at two strengths: the everyday alpha, and a firmer one under
    /// Increase Contrast — most of what that switch *visibly* does lives
    /// here, because the tinted fills were already solved to 7:1 and barely
    /// move, where a hairline going from 0.18 to 0.45 is edges appearing on
    /// every card, chip and button at once.
    private static func wash(_ alpha: Double, hc: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in
            let highContrast = AccessibilityOverride.increaseContrast
                || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            return NSColor(srgbRed: 0.52, green: 0.47, blue: 0.39,
                           alpha: highContrast ? hc : alpha)
        })
    }

    /// Card and row fills.
    static let surface = wash(0.10, hc: 0.16)
    /// Chips and small capsules — a shade firmer than `surface`.
    static let chip = wash(0.15, hc: 0.22)
    /// The buttons' ground — `#F5F4F3` in Light, the maintainer's sampled
    /// control-background colour, with a matching lifted warm dark. **Solid**,
    /// unlike `surface`/`chip`: a button should sit the same on every card and
    /// tint, where the translucent washes take the colour of whatever is
    /// behind them. Worn by `FlatButtonStyle` and the search field's
    /// `FlatToolbarCapsule`, which are meant to read as one material.
    static let control = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.173, green: 0.169, blue: 0.163, alpha: 1)
            : NSColor(srgbRed: 0.961, green: 0.957, blue: 0.953, alpha: 1)
    })
    /// Hairline borders.
    static let line = wash(0.18, hc: 0.45)

    /// Metadata type on the app's **neutral** surfaces — which since the themes
    /// grew their own grounds means the `@project` dropdown, and nothing on a
    /// card: a card's metadata is `AppTheme.metaText`, the page hue at 50% L,
    /// solved on the face its theme paints.
    ///
    /// Not `.secondary`: `secondaryLabelColor` is an alpha of the label colour
    /// that lands around 3.9:1 on a white card, under the refresh's 4.5:1
    /// floor for text below 14px (CLAUDE.md decision 5). This is a solid
    /// grey solved against the card faces instead — 7.4:1 in Light, 6.7:1 in
    /// Dark — so metadata is quiet by being grey, not by being faint. Under
    /// Increase Contrast it steps most of the way to the label colour, and
    /// `AppTheme.metaText`'s own HC pair makes the same move for the same reason.
    static let metaText = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let highContrast = AccessibilityOverride.increaseContrast
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        return switch (dark, highContrast) {
        case (false, false): NSColor(srgbRed: 0.323, green: 0.335, blue: 0.352, alpha: 1)
        case (false, true): NSColor(srgbRed: 0.13, green: 0.14, blue: 0.15, alpha: 1)
        case (true, false): NSColor(srgbRed: 0.632, green: 0.647, blue: 0.665, alpha: 1)
        case (true, true): NSColor(srgbRed: 0.85, green: 0.86, blue: 0.88, alpha: 1)
        }
    })
}

// MARK: - The reading typeface

/// The typeface note and task **cards** read and write in — one of the five
/// `Typeface` options, Grotesk on a new install and Rounded on an existing one.
///
/// Four of the five are *system designs* — `Font.system(_:design:)` and
/// `NSFontDescriptor.withDesign(_:)` — so they cost no resource and track the
/// system's own weights and sizes. Grotesk is the bundled Space Grotesk, reached
/// by family name instead (`Typeface.bundledFamily` → `BundledFonts`), which is
/// the one branch below.
///
/// Scope is *nearly* the **content** of a card, meaning its title and its
/// body, in both the rendered and the source view — the exception being the
/// column header bands' headings, which the theme system brought into it because
/// the band is the app's identity surface and Grotesk being the default is most
/// of what a new install's character is. The rest of the chrome — panel
/// headers, chips, pills, the due badge, the metadata footer — stays on the
/// default design, so the rounded face reads as "this is the writing" rather
/// than as a restyle of the app.
///
/// Both halves matter and must agree. `Card.font` is what SwiftUI draws with;
/// `Card.nsFont` is the same face as AppKit, which is what `MarkdownText`
/// measures its spacing from and what the cards' hidden sizing proxies are laid
/// out in. Take one and not the other and the card's height stops matching its
/// text.
enum Card {
    /// `Alternative Stylistic Sets` → `One storey a`, read off the font's own
    /// feature table (`CTFontCopyFeatures`) rather than guessed. SF ships the
    /// round single-storey `a` as an alternate glyph, so it costs nothing but
    /// asking — and the rounded *design* alone doesn't give it, which is the
    /// thing that's easy to get wrong here: SF Pro Rounded softens the terminals
    /// and keeps the two-storey `a`. Asked for by the two SF designs, the ones
    /// that have it (`Typeface.prefersOneStoreyA`).
    private static let oneStoreyA: [NSFontDescriptor.FeatureKey: Int] = [
        .typeIdentifier: 35,     // kStylisticAlternativesType
        .selectorIdentifier: 14, // stylistic set 7 "on" — "One storey a"
    ]

    /// The face the cards are currently set in, **at the size they are read
    /// at** — `Typeface` and `CardTextSize`, the two settings that between them
    /// say what a card's writing looks like.
    ///
    /// Reading them *here* rather than passing them down is what keeps the call
    /// sites honest: there are a dozen of them across the two panels, they all
    /// sit in a view body, and an `@Observable` read during a body evaluation
    /// registers as a dependency — so changing either option in Settings
    /// re-renders every card with no notification, no re-apply step and nothing
    /// to remember to thread through. `@MainActor` for the same reason: this is
    /// only ever called during a view update.
    ///
    /// The size is deliberately *not* what `chrome(_:weight:)` hands out — see
    /// there for the line between a card and the window around it.
    @MainActor
    static func nsFont(_ style: NSFont.TextStyle, weight: NSFont.Weight? = nil) -> NSFont {
        let settings = SettingsStore.shared
        return nsFont(style, weight: weight, typeface: settings.typeface,
                      scale: CardTextSize.scale(settings.cardFontSize))
    }

    /// The card's *face* at the **system's own size** — the three pieces of
    /// chrome that borrow the reading typeface but must not follow the reading
    /// size: the column headings, the sidebar's "Projects" and the project names
    /// under it. All three are authored text, which is why they take the face;
    /// all three sit in rows whose height belongs to the window, which is why a
    /// reader asking for larger notes doesn't get a larger sidebar.
    @MainActor
    static func chrome(_ style: NSFont.TextStyle, weight: NSFont.Weight? = nil) -> Font {
        font(style, weight: weight, typeface: SettingsStore.shared.typeface)
    }

    /// Text styles are `NSFont.TextStyle` throughout, not SwiftUI's, because the
    /// alternate can only be asked for through a font descriptor — so the AppKit
    /// font is the real one and the SwiftUI `Font` is derived from it. Weight is
    /// baked in for the same reason: `.weight()`/`.fontWeight()` applied *after*
    /// a descriptor-built font is a different font, and would drop the alternate.
    ///
    /// The explicit `typeface:` is for `TypefacePicker`, whose specimens each have
    /// to draw in their own face rather than in the selected one. The explicit
    /// `scale:` is for the render and highlight passes, which are handed one in a
    /// `Config` built on the main actor because they run nonisolated — and, at
    /// its default of 1, for everything that must stay at the system's size.
    static func nsFont(
        _ style: NSFont.TextStyle,
        weight: NSFont.Weight? = nil,
        typeface: Typeface,
        scale: CGFloat = 1
    ) -> NSFont {
        let base = NSFont.preferredFont(forTextStyle: style)
        return nsFont(size: base.pointSize * scale, weight: weight, typeface: typeface, base: base)
    }

    /// The same face at an **explicit point size**, for the one caller that has a
    /// size rather than a text style: `AppDelegate.restyleWindowTitle()`, which
    /// re-fonts a title AppKit has already sized and must not resize it.
    ///
    /// `base` is the font to start from when the typeface is a system design —
    /// the style's `preferredFont` where there is one, so a card keeps tracking
    /// Dynamic Type, and the plain system font at this size otherwise.
    static func nsFont(
        size: CGFloat,
        weight: NSFont.Weight? = nil,
        typeface: Typeface,
        base: NSFont? = nil
    ) -> NSFont {
        // Memoised: the descriptor work below is a CoreText match, and this is
        // asked per card per render — and per event by
        // `AppDelegate.restyleWindowTitle()`. `base` only ever contributes its
        // face (a `preferredFont` or the titlebar's own field font), so its name
        // plus the explicit size identifies it.
        let key = FontKey(size: size, weight: weight?.rawValue,
                          typeface: typeface, base: base?.fontName)
        return resolvedFonts.value(for: key) {
            // A bundled family is reached by name at the requested point size, not by
            // transforming the system font's descriptor — `withDesign(_:)` has no
            // idea Space Grotesk exists. Falls through to the system face if the
            // resource bundle isn't there, which is the one way this can be asked
            // for a family that isn't registered.
            if let family = typeface.bundledFamily,
               let bundled = BundledFonts.font(family: family, size: size, weight: weight) {
                return bundled
            }
            let start = base ?? NSFont.systemFont(ofSize: size)
            let sized = weight.map { NSFont.systemFont(ofSize: size, weight: $0) } ?? start
            var descriptor = sized.fontDescriptor
            if let design = typeface.design, let styled = descriptor.withDesign(design) {
                descriptor = styled
            }
            if typeface.prefersOneStoreyA {
                descriptor = descriptor.addingAttributes([.featureSettings: [oneStoreyA]])
            }
            return NSFont(descriptor: descriptor, size: size) ?? sized
        }
    }

    private struct FontKey: Hashable {
        let size: CGFloat
        let weight: CGFloat?
        let typeface: Typeface
        let base: String?
    }

    private struct ItalicKey: Hashable {
        let name: String
        let size: CGFloat
    }

    private static let resolvedFonts = MemoCache<FontKey, NSFont>()
    private static let italicFonts = MemoCache<ItalicKey, NSFont>()

    /// The face the cards are set in, at an explicit size — the `@MainActor`
    /// partner of the overload above, reading the setting the way `nsFont(_:)`
    /// does.
    @MainActor
    static func nsFont(size: CGFloat, weight: NSFont.Weight? = nil) -> NSFont {
        nsFont(size: size, weight: weight, typeface: SettingsStore.shared.typeface)
    }

    /// The italic partner of a card font: the design's real italic face where it
    /// has one, and a **synthesised oblique** where it doesn't.
    ///
    /// The synthesis is not a nicety. Standard, Serif and Monospace each ship a
    /// true italic (`.SFNS-RegularItalic`, `.NewYork-RegularItalic`,
    /// `.SFNSMono-RegularItalic`), but **SF Rounded has none** — asking a rounded
    /// descriptor for `.italic` hands back the upright face, silently, so
    /// `*emphasis*` in a body drew as plain text under the app's *default*
    /// typeface. A quote and its attribution is where that shows: the attribution
    /// is the italic line, and it wasn't one.
    ///
    /// So a face with no italic gets sheared instead, at the angle SF's own italic
    /// slants at — read off that face (`italicAngle`, 12.5°) rather than picked, so
    /// a synthesised oblique leans exactly as far as a real one beside it. The
    /// shear is applied through the *font matrix*, which is the only way to ask for
    /// it: `withSymbolicTraits(.italic)` can only select a face that exists.
    /// Because it goes through `font`'s own descriptor, the one-storey `a` and the
    /// weight come along with it.
    /// The trait is **added** to whatever the font already carries, never set on its
    /// own: `withSymbolicTraits(.italic)` replaces the whole set, so on a bold base
    /// it quietly dropped the weight — and then the "did we get a real italic?"
    /// check below saw a differently-named face and believed it, which is how
    /// `***bold italic***` came out neither bold nor italic. Unioning also makes
    /// that check honest, since both names then come from the same descriptor and
    /// differ only if an italic face was really found.
    static func italic(_ font: NSFont) -> NSFont {
        // Memoised for `MarkdownText`, which asks once per italic run per render.
        italicFonts.value(for: ItalicKey(name: font.fontName, size: font.pointSize)) {
            let traits = font.fontDescriptor.symbolicTraits
            let italicised = font.fontDescriptor.withSymbolicTraits(traits.union(.italic))
            if let real = NSFont(descriptor: italicised, size: font.pointSize),
               real.fontName != font.fontName {
                return real
            }
            var skew = CGAffineTransform(a: 1, b: 0, c: obliqueSkew, d: 1, tx: 0, ty: 0)
            let sheared = CTFontCreateWithFontDescriptor(
                font.fontDescriptor as CTFontDescriptor, font.pointSize, &skew
            )
            return sheared as NSFont
        }
    }

    /// `tan` of the system italic's own angle, so the shear matches it.
    private static let obliqueSkew: CGFloat = {
        let system = NSFont.systemFont(ofSize: 13)
        let italic = NSFont(descriptor: system.fontDescriptor.withSymbolicTraits(.italic), size: 13)
        return CGFloat(tan((italic?.italicAngle ?? 12.5) * .pi / 180))
    }()

    @MainActor
    static func font(_ style: NSFont.TextStyle, weight: NSFont.Weight? = nil) -> Font {
        Font(nsFont(style, weight: weight))
    }

    static func font(
        _ style: NSFont.TextStyle,
        weight: NSFont.Weight? = nil,
        typeface: Typeface,
        scale: CGFloat = 1
    ) -> Font {
        Font(nsFont(style, weight: weight, typeface: typeface, scale: scale))
    }
}

// MARK: - Design tokens

/// Shared spacing / radius constants so panels feel like one system.
enum Metrics {
    static let panelPadding: CGFloat = 14
    /// Gap between a column's header band and the first card below it. Shared so
    /// the notes and tasks columns line up exactly — and applied **inside** each
    /// column's scroller, so it travels with the content rather than holding a
    /// strip of window colour under the band for good.
    static let headerGap: CGFloat = 10
    /// The column header band's two rows and their gap (`ColumnHeaderBand`).
    /// The band is the one surface a theme paints in the window, so its
    /// vertical rhythm is stated here rather than at the two call sites: the
    /// notes and tasks bands must be the same height to the point, or their
    /// first cards sit on different lines.
    ///
    /// The top inset and the row gap are the values the loose header and filter
    /// rows used before the band enclosed them — `panelPadding` and 8 — because
    /// the sidebar's own "Projects" heading is inset to match, and all three
    /// column titles share one baseline. Only the bottom is new: a slab needs
    /// room under its last row, where a loose filter row only needed the gap to
    /// the first card (which is still `headerGap`, now inside the scroller).
    static let bandRowGap: CGFloat = 8
    static let bandTopPadding: CGFloat = panelPadding
    static let bandBottomPadding: CGFloat = 12
    /// 12pt, down from 16: the refresh puts every container in the 10–12pt
    /// band (CLAUDE.md decision 6 — "round means pressable", and a card is
    /// not pressable-shaped). Task rows were already there at `rowRadius`.
    static let islandRadius: CGFloat = 12
    static let rowRadius: CGFloat = 10
    static let cardSpacing: CGFloat = 12
    /// How long a card takes to grow into edit mode, or shrink out of it. Shared
    /// by the notes and tasks cards.
    static let cardModeDuration: Double = 0.22
    /// The height every capsule in the content layer settles at — filter pills,
    /// the note type dropdown, project chips, the due badge. They used to be
    /// three heights: a caption line is 13pt, so 5pt of padding gave 23 and 3pt
    /// gave 19, and a pill whose SF Symbol is a two-person glyph (Meeting,
    /// Staffing) measures 14pt rather than 13 and so came out 24 while the
    /// text-only "All" beside it stayed 23. 24 is that tallest case, pinned:
    /// applied as a **floor** rather than by equalising the paddings, because a
    /// chip's 8pt of horizontal padding is right where a pill's 11pt is right,
    /// and this way a chip's height stops depending on which glyph it carries.
    static let chipHeight: CGFloat = 24
    /// A card's title row, floored at the height of the tallest thing it can carry:
    /// the **Done** capsule, 26pt at `.actionCapsule` / `.controlSize(.small)`,
    /// against a 16pt title line. Measured, not chosen.
    ///
    /// Applied in **both** modes, because Done only exists in one of them. Without
    /// it the task row's title row was 16pt collapsed and 26pt open, and since the
    /// row is baseline-aligned the extra 10pt landed 5pt above the title and 5pt
    /// below it — so opening a card slid the title down 5pt and the body down 10pt,
    /// out from under the cursor that had just clicked it. The note card needs the
    /// same floor since its type glyph (a 26pt symbol well that used to set this
    /// height as a side effect) was removed with the type symbols.
    static let cardTitleRowHeight: CGFloat = 26
    /// The narrowest either the notes or the tasks column may be dragged —
    /// generous on purpose, so a stray drag can't leave a 90pt sliver where
    /// every card truncates to nothing.
    static let minPanelWidth: CGFloat = 320
    // The sidebar has to fit a project name plus its "X notes · Y tasks"
    // subtitle without crowding, so it opens comfortably wide by default.
    /// Height of the window's title-bar row, which the sidebar header sits in.
    static let titlebarHeight: CGFloat = 52
    /// Leading inset that clears the close/minimise/zoom buttons.
    static let trafficLightInset: CGFloat = 80
    /// Height of the plain glyph buttons in the sidebar's title-bar row (＋ and
    /// the collapse control), used to centre them on the traffic lights.
    static let headerButtonSize: CGFloat = 22
    /// Width of the Settings window's toolbar header (chevrons + pane name). Fixed
    /// so the chevrons don't slide about as the pane name changes length.
    static let settingsHeaderWidth: CGFloat = 240
    /// Leading inset that lines text up with the labels in a `.sidebar` List.
    static let sidebarTextInset: CGFloat = 20

    /// The sidebar's resize range. 200pt is both the width a window opens at and
    /// the narrowest it can be dragged: enough for a project row's name and its
    /// `X notes · Y tasks` subtitle to read in full, and no wider, because every
    /// point here is one the notes and tasks columns don't get. 460 is the widest
    /// worth having: past it the sidebar is taking space from the columns the work
    /// is in.
    ///
    /// **None of the three is enforced by passing it to
    /// `navigationSplitViewColumnWidth`.** A stale autosaved width outlives the
    /// minimum (`AppDelegate.sanitizeSidebarWidth()`), and a dragged divider outlives
    /// both bounds (`AppDelegate.constrainSidebarWidth()`); the modifier is what sets
    /// the ideal and nothing more.
    static let minSidebarWidth: CGFloat = 200
    static let idealSidebarWidth: CGFloat = 200
    static let maxSidebarWidth: CGFloat = 460
}

// MARK: - Aligning controls with text

extension View {
    /// Centres a fixed-size control on the **cap height** of the body text it
    /// sits beside, in a row aligned `.firstTextBaseline`.
    ///
    /// `.center` is the obvious alignment and it's wrong here, twice over. A
    /// glyph padded out to a comfortable click target — a 17pt circle in a 28pt
    /// box — centres the *box*, which drops the glyph 14pt from the row's top
    /// while a 13pt title's capitals start 4.6pt from theirs: on the task row
    /// that put the checkbox 7pt below the title it belongs to. And text is not
    /// centred on its own frame either, since the frame carries a descender the
    /// title may not use. So the control declares where its centre sits relative
    /// to the *baseline*, which is the one line both share, and the row aligns on
    /// that. `d.height` is measured, so a control that brings its own chrome (a
    /// `Menu`, say) needs no allowance made for it.
    /// `style` is the text the control sits beside — `.body` for a card's title
    /// row, `.callout` for a task's notes, since the cap height it centres on comes
    /// from that font.
    func centredOnTextCap(_ style: NSFont.TextStyle = .body) -> some View {
        alignmentGuide(.firstTextBaseline) { d in
            d.height / 2 + NSFont.preferredFont(forTextStyle: style).capHeight / 2
        }
    }
}

// MARK: - Chips

extension View {
    /// Floors a chip's height at `Metrics.chipHeight`. Goes on the *padded
    /// label*, before the capsule is drawn behind it, so the capsule grows with
    /// it and the padding still sets the width.
    func chipHeight() -> some View {
        frame(minHeight: Metrics.chipHeight)
    }
}

// `FilterPill` — the tinted capsule the filter rows wore before the refresh —
// lived here. The rows are one `SegmentedFilter` track each now; a note of the
// pill's own lesson survives because it still binds: selection drawn as an
// *outline* in the tint family measured under the 3:1 a state indicator needs
// (`deep` against `chip`, 1.44–3.36:1), which is why selection anywhere in the
// tint family is a fill, and why the pickers' accent rings sit on neutral
// ground instead.

/// A compact row of tappable color swatches (one per `Tint`). Reports the chosen
/// tint upward via a closure so both the edit rows and the add form can share it.
struct TintPicker: View {
    let selection: Tint
    let onSelect: (Tint) -> Void

    var body: some View {
        // No spacing: the 22pt hit areas below already leave the dots visually
        // apart, and butting them up keeps the row about as wide as it was when
        // the targets were only as big as the swatches.
        HStack(spacing: 0) {
            ForEach(Tint.allCases) { tint in
                Button {
                    onSelect(tint)
                } label: {
                    Circle()
                        .fill(tint.accent)
                        .frame(width: 14, height: 14)
                        .overlay {
                            // A ring marks the current selection.
                            Circle()
                                .strokeBorder(.primary, lineWidth: tint == selection ? 2 : 0)
                        }
                        // A 14pt swatch is far below a comfortable click target,
                        // so the hit area is padded out to 22pt while the dot
                        // stays the size the row is designed around.
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(tint.name)
                .accessibilityLabel(tint.name)
                .accessibilityAddTraits(tint == selection ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Flat controls

/// The app's stand-in for Liquid Glass on a button — a flat fill and a hairline, no
/// material and **no drop shadow**. Two shapes use it: the capsule each column's
/// primary action wears ("New Note", "New Task") and the toolbar's circular
/// show-sidebar glyph.
///
/// The capsules are on their third look, and the reason for each change is worth
/// keeping. `.glassProminent` went because it paints the *system accent*, the one
/// colour in the window drawn from neither `Tint` nor the theme, so it was the
/// loudest thing on screen and fought whatever gradient sat behind it. Plain
/// `.buttonStyle(.glass)` then went because **Liquid Glass draws its own drop
/// shadow** and there is no API to turn it off: with the window otherwise
/// shadowless, these were the only things left casting light. Nothing in the app's
/// own code passes `.shadow(…)` any more, and this is where the last of it would
/// have crept back in.
///
/// So: `Stone.control` and `Stone.line`, exactly what `AppDelegate`'s
/// `FlatToolbarCapsule` paints behind the search field — the flat world's
/// version of "these surfaces are one material". Hover is a `.primary`
/// wash — the state plain glass never gave them, and `.primary` rather than the
/// accent for the `.glassProminent` reason above. A press deepens that wash instead
/// of scaling: with no material left to respond, the fill is the only thing that
/// can answer.
struct FlatButtonStyle<S: InsettableShape>: ButtonStyle {
    /// How the label is sized. `padded` follows `.controlSize`, so the column
    /// headers' `.large` capsules and the empty states' default-size ones keep the
    /// difference they had under `.glass`; `square` pins both axes, which is what a
    /// lone glyph needs — padded, the toolbar's circle came out an oval.
    enum Sizing {
        case padded
        case square(CGFloat)
    }

    let shape: S
    let sizing: Sizing

    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, shape: shape, sizing: sizing)
    }

    /// A view, not the style itself: `ButtonStyle` isn't a `View`, so `@State`
    /// declared on it is never tracked and hover would silently do nothing.
    private struct Surface: View {
        let configuration: Configuration
        let shape: S
        let sizing: Sizing

        @Environment(\.controlSize) private var controlSize
        @State private var hovering = false

        var body: some View {
            configuration.label
                .padding(.horizontal, insets.width)
                .padding(.vertical, insets.height)
                // `nil` on both axes for the padded case, where it's a no-op.
                .frame(width: side, height: side)
                .background {
                    shape.fill(Stone.control)
                    shape.fill(.primary.opacity(wash))
                }
                .overlay { shape.strokeBorder(Stone.line, lineWidth: 0.5) }
                .contentShape(shape)
                .animation(.easeInOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }

        private var insets: CGSize {
            switch sizing {
            case .padded:
                let large = controlSize >= .large
                return CGSize(width: large ? 14 : 11, height: large ? 8 : 6)
            case .square:
                return .zero
            }
        }

        private var side: CGFloat? {
            switch sizing {
            case .padded: nil
            case .square(let side): side
            }
        }

        private var wash: Double {
            if configuration.isPressed { return 0.14 }
            return hovering ? 0.07 : 0
        }
    }
}

extension ButtonStyle where Self == FlatButtonStyle<Capsule> {
    /// A flat neutral capsule — secondary actions ("Done" on an open card).
    static var actionCapsule: Self { .init(shape: Capsule(), sizing: .padded) }
}

/// The capsule each column's primary action wears ("New Note", "New Task") —
/// the theme's `primary` fill under its `primaryLabel`.
///
/// This *reverses* the earlier retreat from `.glassProminent`, knowingly. The
/// prominence went because system blue was drawn from neither `Tint` nor the
/// window's own colour and fought whatever gradient sat behind it; the theme
/// system makes the fill *the theme's*, solved against the band the button sits
/// on (≥5:1 for every label, both appearances) — and one filled pill per column
/// is exactly the ration `.glassProminent` was held to. Flat rather
/// than glass for the standing reason: glass casts a drop shadow and the window
/// doesn't. Hover and press deepen the fill with a black wash, since a label
/// that may be white rules out the `.primary` wash `FlatButtonStyle` uses.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration)
    }

    private struct Surface: View {
        let configuration: Configuration

        @Environment(\.controlSize) private var controlSize
        @State private var hovering = false

        var body: some View {
            let large = controlSize >= .large
            // Read here, in a view body, so the `@Observable` access
            // registers and every button follows a Settings change.
            let theme = SettingsStore.shared.theme
            configuration.label
                .foregroundStyle(theme.primaryLabel)
                .padding(.horizontal, large ? 14 : 11)
                .padding(.vertical, large ? 8 : 6)
                .background {
                    Capsule().fill(theme.primary)
                    Capsule().fill(.black.opacity(wash))
                }
                // The hairline every flat control wears (`FlatButtonStyle`,
                // the chips, the search capsule). On the deep primaries it
                // disappears into the fill's own edge; it earns its place on
                // the bright ones (Tokyo Night's mint, Kanagawa's surimiOrange),
                // where a
                // borderless pill on a pale band read as a different material
                // from the bordered controls beside it.
                .overlay(Capsule().strokeBorder(Stone.line, lineWidth: 0.5))
                .contentShape(Capsule())
                .animation(.easeInOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }

        private var wash: Double {
            if configuration.isPressed { return 0.22 }
            return hovering ? 0.12 : 0
        }
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    /// A column's primary action.
    static var accentCapsule: Self { .init() }
}

extension ButtonStyle where Self == FlatButtonStyle<Circle> {
    /// A lone toolbar glyph, at the diameter AppKit rounds one to.
    static var toolbarGlyph: Self { .init(shape: Circle(), sizing: .square(28)) }
}

// MARK: - Popover surface

extension View {
    /// Goes on a popover's *content*: swaps the system popover material for an
    /// opaque window-coloured background while transparency is reduced —
    /// system switch or Settings → Accessibility's. The material's faint
    /// see-through is the system's own doing and only the system switch would
    /// otherwise touch it; this is the in-app switch keeping the same promise
    /// on the surfaces Insert presents.
    func opaquePopoverWhenTransparencyReduced() -> some View {
        modifier(PopoverSurface())
    }
}

private struct PopoverSurface: ViewModifier {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    func body(content: Content) -> some View {
        if systemReduceTransparency || settings.appReduceTransparency {
            // The theme's page ground, for the reason the `@project` dropdown's
            // own fallback gives: the opaque stand-in should be the colour of
            // the window it covers.
            content.presentationBackground(settings.theme.windowFill)
        } else {
            content
        }
    }
}

// MARK: - Card surface

extension View {
    /// Wraps content in the app's standard rounded "island" — a *flat* fill, not
    /// Liquid Glass. Glass islands each cast their own drop shadow, which the
    /// columns' scroll views clipped at their edges and which pooled into a grubby
    /// band wherever cards stacked.
    ///
    /// Every island is the **theme's card ground** (`AppTheme.cardFace`) — pure
    /// white in Light for all six themes, the theme's own hue at ~25% L in Dark.
    /// Opaque, deliberately: not translucent, which would let the window's colour
    /// run under the text, and never a *type* wash. Colour arrives here only as
    /// the page ground's hue, and the type is the title's capsule mark. (A
    /// `tint:` parameter used to layer a translucent wash over an opaque base
    /// here — first for the note types, then only for the "Color tasks by due
    /// date" row wash — and left when that feature did: with due badges gone
    /// grey, a setting named after their colours no longer described anything.)
    ///
    /// The hairline is the theme's too, for the reason Dracula's was when it was
    /// the only themed face: `Stone`'s warm wash over a tinted card reads as a
    /// smudge rather than as an edge.
    func island(radius: CGFloat = Metrics.islandRadius) -> some View {
        modifier(IslandSurface(radius: radius))
    }
}

private struct IslandSurface: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Read in a view body, like `Card`'s typeface, so the `@Observable`
        // access registers and every card repaints on a theme change with
        // nothing to thread through.
        let theme = SettingsStore.shared.theme
        return content
            .background(shape.fill(theme.cardFace))
            // A hairline keeps the card's edge readable now that there's no
            // shadow separating it from the background.
            .overlay { shape.strokeBorder(theme.cardBorder, lineWidth: 0.5) }
    }
}
