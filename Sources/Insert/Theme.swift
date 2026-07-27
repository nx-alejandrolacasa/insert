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

    /// The vivid accent colour (dots, swatches, decorative strokes, washes).
    var accent: Color { ramp.accent.color }

    /// A solid fill that carries white type at 4.5:1 or better. Doesn't change
    /// between Light and Dark — white-on-fill contrast doesn't depend on what's
    /// behind the fill — but it does deepen when Increase Contrast is on.
    var deep: Color {
        dynamic(light: ramp.fill, dark: ramp.fill,
                lightHC: ramp.fillHC, darkHC: ramp.fillHC)
    }

    /// The tint as a foreground, at 4.5:1 or better against the island, chip and
    /// window surfaces it's drawn on — deepened in Light, brightened in Dark.
    var ink: Color {
        dynamic(light: ramp.inkLight, dark: ramp.inkDark,
                lightHC: ramp.inkLightHC, darkHC: ramp.inkDarkHC)
    }

    /// A subtle background wash for note "islands" of this type.
    var soft: Color { accent.opacity(0.14) }

    /// A slightly stronger fill for pills/chips.
    var chip: Color { accent.opacity(0.20) }
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

private extension Tint {
    var ramp: Ramp {
        switch self {
        case .gray: Ramp(
            accent:     RGB(r: 0.63, g: 0.59, b: 0.53),
            fill:       RGB(r: 0.44, g: 0.41, b: 0.35),
            fillHC:     RGB(r: 0.37, g: 0.34, b: 0.29),
            inkLight:   RGB(r: 0.41, g: 0.39, b: 0.33),
            inkDark:    RGB(r: 0.63, g: 0.59, b: 0.53),
            inkLightHC: RGB(r: 0.29, g: 0.27, b: 0.23),
            inkDarkHC:  RGB(r: 0.76, g: 0.71, b: 0.64))
        case .yellow: Ramp(
            accent:     RGB(r: 0.95, g: 0.77, b: 0.29),
            fill:       RGB(r: 0.60, g: 0.43, b: 0.06),
            fillHC:     RGB(r: 0.45, g: 0.32, b: 0.04),
            inkLight:   RGB(r: 0.50, g: 0.36, b: 0.05),
            inkDark:    RGB(r: 0.95, g: 0.77, b: 0.29),
            inkLightHC: RGB(r: 0.36, g: 0.26, b: 0.03),
            inkDarkHC:  RGB(r: 0.95, g: 0.77, b: 0.29))
        case .purple: Ramp(
            accent:     RGB(r: 0.60, g: 0.45, b: 0.95),
            fill:       RGB(r: 0.45, g: 0.29, b: 0.85),
            fillHC:     RGB(r: 0.39, g: 0.25, b: 0.74),
            inkLight:   RGB(r: 0.44, g: 0.28, b: 0.82),
            inkDark:    RGB(r: 0.63, g: 0.47, b: 1.00),
            inkLightHC: RGB(r: 0.31, g: 0.20, b: 0.59),
            inkDarkHC:  RGB(r: 0.83, g: 0.63, b: 1.00))
        case .green: Ramp(
            accent:     RGB(r: 0.35, g: 0.78, b: 0.55),
            fill:       RGB(r: 0.15, g: 0.52, b: 0.33),
            fillHC:     RGB(r: 0.11, g: 0.39, b: 0.25),
            inkLight:   RGB(r: 0.12, g: 0.44, b: 0.28),
            inkDark:    RGB(r: 0.35, g: 0.78, b: 0.55),
            inkLightHC: RGB(r: 0.09, g: 0.32, b: 0.20),
            inkDarkHC:  RGB(r: 0.35, g: 0.79, b: 0.56))
        case .blue: Ramp(
            accent:     RGB(r: 0.30, g: 0.62, b: 0.98),
            fill:       RGB(r: 0.13, g: 0.45, b: 0.88),
            fillHC:     RGB(r: 0.10, g: 0.34, b: 0.67),
            inkLight:   RGB(r: 0.11, g: 0.38, b: 0.75),
            inkDark:    RGB(r: 0.30, g: 0.62, b: 0.98),
            inkLightHC: RGB(r: 0.08, g: 0.27, b: 0.54),
            inkDarkHC:  RGB(r: 0.36, g: 0.75, b: 1.00))
        case .orange: Ramp(
            accent:     RGB(r: 0.98, g: 0.62, b: 0.30),
            fill:       RGB(r: 0.70, g: 0.37, b: 0.07),
            fillHC:     RGB(r: 0.53, g: 0.28, b: 0.06),
            inkLight:   RGB(r: 0.59, g: 0.32, b: 0.06),
            inkDark:    RGB(r: 0.98, g: 0.62, b: 0.30),
            inkLightHC: RGB(r: 0.42, g: 0.23, b: 0.05),
            inkDarkHC:  RGB(r: 0.99, g: 0.63, b: 0.30))
        case .pink: Ramp(
            accent:     RGB(r: 0.96, g: 0.52, b: 0.72),
            fill:       RGB(r: 0.76, g: 0.29, b: 0.50),
            fillHC:     RGB(r: 0.58, g: 0.22, b: 0.38),
            inkLight:   RGB(r: 0.65, g: 0.24, b: 0.42),
            inkDark:    RGB(r: 0.96, g: 0.52, b: 0.72),
            inkLightHC: RGB(r: 0.46, g: 0.17, b: 0.30),
            inkDarkHC:  RGB(r: 1.00, g: 0.58, b: 0.80))
        case .teal: Ramp(
            accent:     RGB(r: 0.30, g: 0.78, b: 0.80),
            fill:       RGB(r: 0.09, g: 0.51, b: 0.54),
            fillHC:     RGB(r: 0.06, g: 0.38, b: 0.40),
            inkLight:   RGB(r: 0.07, g: 0.43, b: 0.46),
            inkDark:    RGB(r: 0.30, g: 0.78, b: 0.80),
            inkLightHC: RGB(r: 0.05, g: 0.31, b: 0.33),
            inkDarkHC:  RGB(r: 0.30, g: 0.78, b: 0.80))
        case .red: Ramp(
            accent:     RGB(r: 0.96, g: 0.42, b: 0.42),
            fill:       RGB(r: 0.84, g: 0.24, b: 0.24),
            fillHC:     RGB(r: 0.64, g: 0.18, b: 0.18),
            inkLight:   RGB(r: 0.71, g: 0.20, b: 0.20),
            inkDark:    RGB(r: 0.96, g: 0.42, b: 0.42),
            inkLightHC: RGB(r: 0.51, g: 0.15, b: 0.15),
            inkDarkHC:  RGB(r: 1.00, g: 0.60, b: 0.60))
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
        let isHighContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let rgb = switch (isDark, isHighContrast) {
        case (false, false): light
        case (false, true): lightHC
        case (true, false): dark
        case (true, true): darkHC
        }
        return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    })
}

// MARK: - Stone

/// The app's neutral. Plain grey read cold and a little clinical beside the
/// pastel type tints, so every neutral surface — task rows, chips, hairlines —
/// is this barely-there warm stone instead. It's a mid-tone laid on at low
/// opacity rather than a fixed colour, so it warms whatever sits behind it and
/// needs no separate light/dark variants.
enum Stone {
    private static let base = Color(red: 0.52, green: 0.47, blue: 0.39)

    /// Card and row fills.
    static let surface = base.opacity(0.10)
    /// Chips and small capsules — a shade firmer than `surface`.
    static let chip = base.opacity(0.15)
    /// Hairline borders.
    static let line = base.opacity(0.18)
}

// MARK: - Design tokens

/// Shared spacing / radius constants so panels feel like one system.
enum Metrics {
    static let panelPadding: CGFloat = 14
    /// Gap between a panel header and the first content below it. Shared so the
    /// notes and tasks columns line up exactly.
    static let headerGap: CGFloat = 10
    static let islandRadius: CGFloat = 16
    static let rowRadius: CGFloat = 10
    static let cardSpacing: CGFloat = 12
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
    /// point here is one the notes and tasks columns don't get. Neither value
    /// survives a *stale* autosaved column width on its own — see
    /// `AppDelegate.sanitizeSidebarWidth()`.
    static let minSidebarWidth: CGFloat = 200
    static let idealSidebarWidth: CGFloat = 200
    static let maxSidebarWidth: CGFloat = 460
}

// MARK: - Filter pill

/// A capsule filter pill, shared by the notes type filter, the notes type picker
/// and the tasks state filter, so all three read as one system. Grey always means
/// "All".
///
/// Selection is a **filled** pill: `deep` behind white type, against the tint's
/// soft wash behind `.primary` when unselected. This used to keep a constant wash
/// and show selection in the border instead, deliberately, so that picking
/// something didn't put a louder block of colour on screen. Measurement retired
/// that: `deep` and `chip` are the same hue, so an outline drawn from one against
/// the other lands between 1.44:1 and 3.36:1 — under the 3:1 a state indicator
/// needs, in one appearance or the other, for *every* tint at *any* opacity. No
/// border taken from the tint family can carry this, so the fill does.
struct FilterPill: View {
    let label: String
    var symbol: String? = nil
    let tint: Tint
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol, !symbol.isEmpty { Image(systemName: symbol) }
                Text(label)
            }
            .font(.caption.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(selected ? AnyShapeStyle(tint.deep) : AnyShapeStyle(tint.chip)))
            // The hairline is decoration on an unselected pill; a filled one
            // needs no outline at all.
            .overlay {
                if !selected {
                    Capsule().strokeBorder(Stone.line, lineWidth: 0.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

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
/// colour in the window drawn from neither `Tint` nor a `Backdrop`, so it was the
/// loudest thing on screen and fought whatever gradient sat behind it. Plain
/// `.buttonStyle(.glass)` then went because **Liquid Glass draws its own drop
/// shadow** and there is no API to turn it off: with the window otherwise
/// shadowless, these were the only things left casting light. Nothing in the app's
/// own code passes `.shadow(…)` any more, and this is where the last of it would
/// have crept back in.
///
/// So: `Stone.chip` and `Stone.line`, exactly what the filter pills use, and what
/// `AppDelegate`'s `FlatToolbarCapsule` paints behind the search field — the flat
/// world's version of "these surfaces are one material". Hover is a `.primary`
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
                    shape.fill(Stone.chip)
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
    /// A column's primary action.
    static var actionCapsule: Self { .init(shape: Capsule(), sizing: .padded) }
}

extension ButtonStyle where Self == FlatButtonStyle<Circle> {
    /// A lone toolbar glyph, at the diameter AppKit rounds one to.
    static var toolbarGlyph: Self { .init(shape: Circle(), sizing: .square(28)) }
}

// MARK: - Card surface

extension View {
    /// Wraps content in the app's standard rounded "island" — a *flat* fill, not
    /// Liquid Glass. Glass islands each cast their own drop shadow, which the
    /// columns' scroll views clipped at their edges and which pooled into a grubby
    /// band wherever cards stacked.
    ///
    /// A tint gives the card that colour's wash over an opaque base. **No tint is
    /// plain paper** — `textBackgroundColor`, white in Light and near-black in
    /// Dark. That's the untinted task row, and it's neither of the two things it
    /// has been before: not the warm `Stone` neutral, which made the tasks column
    /// a stack of faintly grey slabs, and not transparent, which let the backdrop
    /// gradient run under the text. Opaque and *neutral* — the card is white, the
    /// colour is the backdrop's job.
    func island(radius: CGFloat = Metrics.islandRadius, tint: Tint? = nil) -> some View {
        modifier(IslandSurface(radius: radius, tint: tint))
    }
}

private struct IslandSurface: ViewModifier {
    let radius: CGFloat
    let tint: Tint?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            // A tinted card gets two stacked fills. `tint.soft` is a
            // *translucent* wash — it's meant to tint whatever is behind it — so
            // over a `Backdrop` gradient it stopped being a card and became a
            // slightly tinted window onto the wash, with the gradient running
            // through the text. The opaque base under it stops that.
            // `windowBackgroundColor` specifically, because that is exactly what
            // sits behind an island when no backdrop is set, so a tinted card is
            // pixel-identical there and needs no branching on the setting.
            //
            // The base is listed first so the wash paints *over* it. Chaining two
            // `.background` modifiers instead would put the wash further back
            // than the base and hide it.
            .background {
                if let tint {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                    shape.fill(tint.soft)
                } else {
                    // Paper, not the window's grey: `textBackgroundColor` is the
                    // white a document surface uses, and it flips to near-black in
                    // Dark on its own.
                    shape.fill(Color(nsColor: .textBackgroundColor))
                }
            }
            // A hairline keeps the card's edge readable now that there's no
            // shadow separating it from the background.
            .overlay { shape.strokeBorder(Stone.line, lineWidth: 0.5) }
    }
}
