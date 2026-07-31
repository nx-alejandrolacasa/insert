import AppKit
import SwiftUI

// MARK: - Backdrop

/// The optional flat tint behind the main window — the app's one piece of pure
/// decoration, and the only setting that exists purely to make Insert feel like
/// *yours*.
///
/// Seven tints plus "Plain" for the untinted window background, which stays
/// the default so an install that never opens Settings looks exactly as it
/// always has. These replaced five *gradients* (Cloud, Stone, Dawn, Dusk,
/// Grove) in the July 2026 visual refresh (CLAUDE.md decision 1), for a
/// measured reason: a gradient was legible only in the outer margins and the
/// sidebar, and each one needed its Light and Dark ends solved for contrast
/// separately per region. A flat tint means text contrast is identical
/// everywhere in the window, so it is verified once per theme. A saved gradient
/// is migrated to its nearest tint by family (see `migratedFromGradient`), so a
/// chosen backdrop stays a chosen backdrop.
///
/// **Every tint is one lightness and one chroma; hue is the only variable.**
/// Light values sit at oklch L 97.5% / C 0.014–0.016 (the refresh's spec), so
/// switching tint never changes contrast. The dark values are derived, not yet
/// designed by hand: the same rule at a fixed dark lightness (L 23.5% for the
/// window, 26.5% for the sidebar), chosen to sit within a couple of points of
/// `windowBackgroundColor`'s own dark value so a tinted dark window reads as
/// the system's dark window, warmed — not as a new colour. Keep that constraint
/// if a tint is ever added: same L/C as the six here, new hue only.
///
/// A tint paints **two strengths**: the window's base surface at ~55% of the
/// tint's chroma (near-white, so cards keep their edge) and the sidebar at
/// ~90% (where the tint actually reads). The Settings swatch runs to ~125%,
/// the tint's *identity* rather than either surface — a 52pt swatch of the
/// base colour previews nothing. Those fractions started at 30/62/100 and were
/// raised by request ("the tints are almost invisible"); if they move again,
/// regenerate the whole table from the oklch spec rather than nudging one
/// entry, or the set stops being one lightness and chroma.
enum Backdrop: String, CaseIterable, Identifiable {
    /// The plain window background. Spelled `plain` rather than `none` so
    /// `Backdrop?` can't quietly mean two things at a call site.
    case plain
    /// Warm straw (hue 85) — the palest warm one, paper left in the sun.
    case linen
    /// Terracotta warmth (hue 45).
    case clay
    /// Pink warmth (hue 25) — the refresh mock's own tint.
    case blush
    /// Soft green (hue 145), kept at the set's low chroma so it reads as
    /// scenery rather than as the status green the due badge owns.
    case sage
    /// Pale teal (hue 190) — added to fill the set's one empty hue family:
    /// the wheel's widest gap sat between Sage and Mist, and at this chroma a
    /// cyan reads as its own thing where a yellow-green (~110) goes sickly
    /// and a magenta (~335) reads as a second Blush.
    case seafoam
    /// Soft blue (hue 245), the same rule against the app's status blue.
    case mist
    /// Pale violet (hue 300).
    case lilac

    var id: Self { self }

    var label: String {
        switch self {
        case .plain: "Plain"
        case .linen: "Linen"
        case .clay: "Clay"
        case .blush: "Blush"
        case .sage: "Sage"
        case .seafoam: "Seafoam"
        case .mist: "Mist"
        case .lilac: "Lilac"
        }
    }

    /// The nearest tint for a gradient saved before the refresh, by family:
    /// the cool near-white and the sky-into-sage go to the cool tints, the
    /// warm ones to the warm tints. `nil` for anything unrecognised.
    static func migratedFromGradient(_ raw: String) -> Backdrop? {
        switch raw {
        case "cloud": .mist
        case "stone": .linen
        case "dawn": .blush
        case "dusk": .clay
        case "grove": .sage
        default: nil
        }
    }

    /// The window's base surface, or `nil` for the plain background.
    var color: Color? { roles?.base.color }

    /// What the window paints behind everything. `.windowBackground` for
    /// "Plain", so the setting can be applied *unconditionally* — branching on
    /// it in the view builder instead would give the two cases different
    /// identities and tear down `NavigationSplitView` (and with it the
    /// autosaved column widths) every time the picker moved.
    var windowStyle: AnyShapeStyle {
        color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.windowBackground)
    }

    /// The sidebar's stronger cut of the tint, or `nil` for "Plain", which
    /// leaves AppKit's own sidebar material (and its desktop translucency)
    /// untouched. A flat fill rather than the Liquid Glass the gradients wore:
    /// glass earned its place by *refracting* a gradient's travel, and a flat
    /// tint has none — the mock's sidebar is simply the tint at a higher
    /// strength, which a fill is and a glass layer over the base colour isn't.
    var sidebarColor: Color? { roles?.sidebar.color }

    /// The Settings swatch fill: the tint at full identity strength.
    var swatchColor: Color {
        roles?.swatch.color ?? Color(nsColor: .windowBackgroundColor)
    }

    /// The three strengths a tint is used at, each in its two appearances.
    /// Values are oklch converted to sRGB offline — this type's header is the
    /// spec now that the refresh handoff is gone, so regenerate from the L/C
    /// and the per-case hues above rather than from a table elsewhere. Light
    /// rows are L 99 / 97.4 / 97.5, dark rows L 23.5 / 26.5 / 27, chroma
    /// scaled per role as the header describes.
    private var roles: Roles? {
        switch self {
        case .plain: nil
        case .linen: Roles(
            base: DynamicRGB(light: RGB(r: 0.997, g: 0.986, b: 0.965), dark: RGB(r: 0.124, g: 0.117, b: 0.102)),
            sidebar: DynamicRGB(light: RGB(r: 0.982, g: 0.965, b: 0.930), dark: RGB(r: 0.158, g: 0.144, b: 0.117)),
            swatch: DynamicRGB(light: RGB(r: 0.989, g: 0.965, b: 0.917), dark: RGB(r: 0.166, g: 0.149, b: 0.113)))
        case .clay: Roles(
            base: DynamicRGB(light: RGB(r: 1.000, g: 0.981, b: 0.968), dark: RGB(r: 0.133, g: 0.113, b: 0.105)),
            sidebar: DynamicRGB(light: RGB(r: 1.000, g: 0.956, b: 0.936), dark: RGB(r: 0.172, g: 0.137, b: 0.122)),
            swatch: DynamicRGB(light: RGB(r: 1.000, g: 0.953, b: 0.925), dark: RGB(r: 0.184, g: 0.139, b: 0.119)))
        case .blush: Roles(
            base: DynamicRGB(light: RGB(r: 1.000, g: 0.979, b: 0.975), dark: RGB(r: 0.134, g: 0.112, b: 0.110)),
            sidebar: DynamicRGB(light: RGB(r: 1.000, g: 0.953, b: 0.947), dark: RGB(r: 0.174, g: 0.135, b: 0.131)),
            swatch: DynamicRGB(light: RGB(r: 1.000, g: 0.949, b: 0.941), dark: RGB(r: 0.187, g: 0.136, b: 0.131)))
        case .sage: Roles(
            base: DynamicRGB(light: RGB(r: 0.975, g: 0.993, b: 0.975), dark: RGB(r: 0.109, g: 0.122, b: 0.109)),
            sidebar: DynamicRGB(light: RGB(r: 0.947, g: 0.976, b: 0.946), dark: RGB(r: 0.131, g: 0.153, b: 0.131)),
            swatch: DynamicRGB(light: RGB(r: 0.941, g: 0.981, b: 0.940), dark: RGB(r: 0.130, g: 0.160, b: 0.130)))
        case .seafoam: Roles(
            base: DynamicRGB(light: RGB(r: 0.966, g: 0.994, b: 0.991), dark: RGB(r: 0.102, g: 0.123, b: 0.121)),
            sidebar: DynamicRGB(light: RGB(r: 0.931, g: 0.978, b: 0.973), dark: RGB(r: 0.118, g: 0.154, b: 0.151)),
            swatch: DynamicRGB(light: RGB(r: 0.919, g: 0.984, b: 0.978), dark: RGB(r: 0.112, g: 0.162, b: 0.158)))
        case .mist: Roles(
            base: DynamicRGB(light: RGB(r: 0.971, g: 0.990, b: 1.000), dark: RGB(r: 0.106, g: 0.120, b: 0.132)),
            sidebar: DynamicRGB(light: RGB(r: 0.940, g: 0.971, b: 0.999), dark: RGB(r: 0.125, g: 0.149, b: 0.170)),
            swatch: DynamicRGB(light: RGB(r: 0.931, g: 0.974, b: 1.000), dark: RGB(r: 0.123, g: 0.155, b: 0.183)))
        case .lilac: Roles(
            base: DynamicRGB(light: RGB(r: 0.990, g: 0.982, b: 1.000), dark: RGB(r: 0.120, g: 0.114, b: 0.132)),
            sidebar: DynamicRGB(light: RGB(r: 0.971, g: 0.959, b: 1.000), dark: RGB(r: 0.150, g: 0.140, b: 0.171)),
            swatch: DynamicRGB(light: RGB(r: 0.975, g: 0.957, b: 1.000), dark: RGB(r: 0.156, g: 0.142, b: 0.184)))
        }
    }
}

/// One tint's three strengths: the window base, the sidebar, the swatch.
private struct Roles {
    let base: DynamicRGB
    let sidebar: DynamicRGB
    let swatch: DynamicRGB
}

/// One colour, in its two appearances.
///
/// A thinner `dynamic(light:dark:lightHC:darkHC:)` than `Tint`'s: there are no
/// Increase Contrast variants to carry, because both values already clear AAA
/// against the text drawn on them (black on the light rows lands past 19:1,
/// white on the dark rows past 13:1).
private struct DynamicRGB {
    let light: RGB
    let dark: RGB

    var color: Color {
        Color(nsColor: NSColor(name: nil) { [light, dark] appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
        })
    }
}

// MARK: - Picker

/// A grid of tint swatches, one per `Backdrop`, each captioned with its name.
///
/// Deliberately not a `Picker`: the whole point of choosing a tint is seeing
/// it, and a menu of the words "Blush" and "Sage" tells you nothing. The
/// swatches paint the same dynamic colour the window reads, so they also answer
/// the question the names can't — what the *current* theme's version of each
/// one looks like.
struct BackdropPicker: View {
    let selection: Backdrop
    let onSelect: (Backdrop) -> Void

    private static let swatchWidth: CGFloat = 52
    private static let swatchHeight: CGFloat = 34
    /// 9pt, not the controls' full capsule: a swatch is a preview of a surface,
    /// not a button — "round means pressable" (CLAUDE.md decision 6).
    private static let radius: CGFloat = 9

    var body: some View {
        // A grid, not the single row the gradients had: past six entries a
        // 52pt row outgrows the Settings pane, which is exactly the "seven is
        // where it stops fitting" line the old row documented — and the answer
        // it prescribed is this, four columns (an exact 4×2 with Plain plus
        // the seven tints), not smaller swatches: below about 46pt a swatch
        // stops previewing anything.
        //
        // 10pt gaps so the selection ring, which sits outside its swatch, has
        // room either side and can't touch its neighbours.
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(Self.swatchWidth), spacing: 10), count: 4),
            alignment: .trailing,
            spacing: 10
        ) {
            ForEach(Backdrop.allCases) { backdrop in
                swatch(backdrop)
            }
        }
        // The selection ring overhangs its swatch; give it somewhere to go
        // rather than letting the Form row clip it.
        .padding(.vertical, 4)
    }

    private func swatch(_ backdrop: Backdrop) -> some View {
        let selected = backdrop == selection
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)

        return Button {
            onSelect(backdrop)
        } label: {
            VStack(spacing: 6) {
                shape
                    .fill(backdrop.swatchColor)
                    .frame(width: Self.swatchWidth, height: Self.swatchHeight)
                    // The same hairline `.island()` uses, so a pale swatch on a
                    // pale Form row still has an edge.
                    .overlay { shape.strokeBorder(Stone.line, lineWidth: 0.5) }
                    // The accent ring the refresh gives every picker: selection
                    // is the accent's job (CLAUDE.md decision 4), and on this
                    // neutral ground — unlike the tint-on-tint case `Tint`
                    // documents — an outline can carry the 3:1 an indicator
                    // needs. The caption below going `.primary` is the second
                    // cue.
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.radius + 2, style: .continuous)
                            .strokeBorder(SettingsStore.shared.accent.color, lineWidth: 1.5)
                            .padding(-3)
                            .opacity(selected ? 1 : 0)
                    }

                Text(backdrop.label)
                    .font(.caption)
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    // Held to the swatch's width: every label is one short word,
                    // so none of them needs more, and pinning it means a longer
                    // name added later widens its own column rather than
                    // silently knocking the whole grid out of step.
                    .multilineTextAlignment(.center)
                    .frame(width: Self.swatchWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(backdrop.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
