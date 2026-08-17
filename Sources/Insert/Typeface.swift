import AppKit
import SwiftUI

/// The face note and task **cards** read and write in — Settings → General.
/// Chrome is not affected; see `Card`, which is the only thing that resolves
/// this.
///
/// Four of the five are *system designs* (`NSFontDescriptor.withDesign(_:)`), so
/// they cost no resource. **Grotesk is the exception** — Space Grotesk, bundled,
/// and the default for a new install (see `BundledFonts` for what the bundling
/// costs and why the rule bends for two font files). Existing installs keep
/// whatever they had, since a saved value wins over the default.
///
/// Being a system design is also the only
/// way to reach two of the four: the serif is **New York**, which ships with macOS at
/// `/System/Library/Fonts/NewYork.ttf` but is a hidden system font — asking for
/// `.NewYork-Regular` by name returns nil and asking for the PostScript name
/// hands back *Times New Roman*, which CoreText logs as a substitution. The
/// "New York" / "New York Small…ExtraLarge" families that appear in Font Book on
/// a developer's Mac are Apple's optional download in `/Library/Fonts` and are
/// **not** on a clean install, so they can't be named either.
///
/// Two things come free with the serif and are worth knowing before anyone tries
/// to add them by hand. The system copy is variable and CoreText tracks its
/// optical-size axis to the point size (`opsz` came back 12/15/20/34 at those
/// sizes), so there is nothing to select. And it has a **true italic**
/// (`.NewYork-RegularItalic`), where `.rounded` asked for `.italic` resolves
/// straight back to the upright — so `*italic*` in a card body only really slants
/// under this option.
enum Typeface: String, CaseIterable, Identifiable {
    case standard
    case rounded
    case grotesk
    case serif
    case monospaced

    var id: Self { self }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .rounded: "Rounded"
        case .grotesk: "Grotesk"
        case .serif: "Serif"
        case .monospaced: "Monospace"
        }
    }

    /// `nil` for Standard — the plain system font, the same face the window's
    /// chrome is drawn in. (Not quite the same *glyphs*: Standard also asks for
    /// the one-storey `a` — see `prefersOneStoreyA`.) Also `nil` for Grotesk,
    /// which isn't a system design at all — `bundledFamily` is what resolves it.
    var design: NSFontDescriptor.SystemDesign? {
        switch self {
        case .standard, .grotesk: nil
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }

    /// The bundled family this option is, or `nil` for the four system designs.
    /// `Card` branches on this before it touches a descriptor, because a
    /// bundled family is reached by name and a system design by
    /// `withDesign(_:)` — two different resolutions, not two arguments to one.
    var bundledFamily: String? {
        self == .grotesk ? BundledFonts.grotesk : nil
    }

    /// Whether to ask for the round single-storey `a` (see `Card.oneStoreyA`).
    ///
    /// Standard and Rounded — the two SF designs, the two that offer the
    /// alternate. Standard first shipped *without* it, to keep the cards
    /// glyph-identical to the chrome beside them, and that was reversed by
    /// request: Apple Notes sets its plain SF body with the one-storey `a`, and
    /// that is the look this option is for. So Standard now differs from the
    /// chrome in exactly one glyph — a decision, not a drift. The serif and the
    /// monospaced face don't list the selector at all, and asking anyway is a
    /// genuine no-op there: shaping the same word with and without it produced
    /// identical glyph ids, no fallback and no substitution. So this could be
    /// `true` for every case and behave the same; it names the designs the
    /// alternate actually exists in. Grotesk is `false` for a different reason:
    /// its `a` is single-storey as drawn, so there is nothing to select.
    var prefersOneStoreyA: Bool {
        switch self {
        case .standard, .rounded: true
        case .grotesk, .serif, .monospaced: false
        }
    }
}

// MARK: - Picker

/// A row of specimens, one per `Typeface` — 52pt swatches with the hairline
/// and selection ring `ThemePicker` beside it uses, because the
/// two sit in the same pane and a font choice is as visual as a theme. A
/// `Picker` would have to name the faces without showing them, and the names
/// are the least useful thing about them.
///
/// The swatches are **capsules** where the tint swatches keep a 9pt radius — a
/// deliberate exception to "round means pressable applies to controls only"
/// (CLAUDE.md decision 6 left this open; the maintainer chose the pills).
///
/// The specimen is **"Aa"**, which is not a filler string: the capital shows the
/// terminals and the serifs, and the lowercase `a` shows the round single-storey
/// alternate the two SF designs carry against the serif's and the mono's
/// two-storey one. Each swatch draws in *its own* face rather than the selected
/// one, which is what `Card.font(_:weight:typeface:)` exists for.
///
/// Five 62pt columns plus 10pt gaps is 350pt against the pane's ~420, which is
/// where the row it had room to grow into stops: a sixth face would have to
/// become a grid, as `ThemePicker` already is.
struct TypefacePicker: View {
    let selection: Typeface
    let onSelect: (Typeface) -> Void

    private static let swatchWidth: CGFloat = 52
    private static let swatchHeight: CGFloat = 34
    /// The column is as wide as the widest *label*, not as the swatch: "Monospace"
    /// measures 55.6pt at caption size against the swatch's 52, so held to the
    /// swatch it hyphen-wrapped to "Mono-/space" and left this row a line taller
    /// than the theme grid beside it. Widening the column instead keeps the
    /// swatch itself at 52pt.
    private static let columnWidth: CGFloat = 62

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Typeface.allCases) { typeface in
                swatch(typeface)
            }
        }
        // The selection ring sits outside its swatch; give it somewhere to go
        // rather than letting the Form row clip it.
        .padding(.vertical, 4)
    }

    private func swatch(_ typeface: Typeface) -> some View {
        let selected = typeface == selection
        let shape = Capsule()

        return Button {
            onSelect(typeface)
        } label: {
            VStack(spacing: 6) {
                Text(verbatim: "Aa")
                    .font(Card.font(.title3, typeface: typeface))
                    .frame(width: Self.swatchWidth, height: Self.swatchHeight)
                    .background(Stone.chip, in: shape)
                    .overlay { shape.strokeBorder(Stone.line, lineWidth: 0.5) }
                    // The theme's primary, ringing every picker in this pane;
                    // the caption below going `.primary` when selected is the
                    // second cue.
                    .overlay {
                        Capsule()
                            .strokeBorder(SettingsStore.shared.theme.primary, lineWidth: 1.5)
                            .padding(-3)
                            .opacity(selected ? 1 : 0)
                    }

                Text(typeface.label)
                    .font(.caption)
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    // Pinned rather than free, so a longer name added later widens
                    // its own column instead of silently knocking the row out of
                    // step — and centred, so it stays under its swatch.
                    .multilineTextAlignment(.center)
                    .frame(width: Self.columnWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(typeface.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
