import AppKit
import SwiftUI

/// The face note and task **cards** read and write in — Settings → General.
/// Chrome is not affected; see `Card`, which is the only thing that resolves
/// this.
///
/// All four are *system designs* (`NSFontDescriptor.withDesign(_:)`), so nothing
/// is bundled and the no-dependencies rule is untouched. That is also the only
/// way to reach two of them: the serif is **New York**, which ships with macOS at
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
    case serif
    case monospaced

    var id: Self { self }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .monospaced: "Monospace"
        }
    }

    /// `nil` for Standard — the plain system font, deliberately the very same
    /// face the window's chrome is drawn in, so choosing it means "don't set the
    /// writing apart" rather than "set it apart in a fourth way".
    var design: NSFontDescriptor.SystemDesign? {
        switch self {
        case .standard: nil
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }

    /// Whether to ask for the round single-storey `a` (see `Card.oneStoreyA`).
    ///
    /// Rounded only, and each exclusion is a decision rather than a limit. SF's
    /// *default* design offers the alternate too — verified: the feature swaps
    /// glyph ids when the string is shaped — but Standard's whole job is to match
    /// the chrome beside it, which a stylistic alternate would quietly break. The
    /// serif and the monospaced face don't list the selector at all, and asking
    /// anyway is a genuine no-op there: shaping the same word with and without it
    /// produced identical glyph ids, no fallback and no substitution. So this
    /// could be `self != .standard` and behave the same; it names the one design
    /// the alternate is actually *for*.
    var prefersOneStoreyA: Bool { self == .rounded }
}

// MARK: - Picker

/// A row of specimens, one per `Typeface`, in the shape `BackdropPicker` uses —
/// same 52pt swatch, same hairline, same selection ring — because the two sit in
/// the same pane and a font choice is as visual as a gradient. A `Picker` would
/// have to name the faces without showing them, and the names are the least
/// useful thing about them.
///
/// The specimen is **"Aa"**, which is not a filler string: the capital shows the
/// terminals and the serifs, and the lowercase `a` is exactly what separates
/// Standard from Rounded — two-storey against the round single-storey alternate.
/// Each swatch draws in *its own* face rather than the selected one, which is
/// what `Card.font(_:weight:typeface:)` exists for.
///
/// Four 62pt columns plus 10pt gaps is 278pt against the pane's ~420, so unlike
/// the backdrop row this one has room to grow.
struct TypefacePicker: View {
    let selection: Typeface
    let onSelect: (Typeface) -> Void

    private static let swatchWidth: CGFloat = 52
    private static let swatchHeight: CGFloat = 34
    private static let radius: CGFloat = 7
    /// The column is as wide as the widest *label*, not as the swatch: "Monospace"
    /// measures 55.6pt at caption size against the swatch's 52, so held to the
    /// swatch it hyphen-wrapped to "Mono-/space" and left this row a line taller
    /// than the backdrop row beside it. Widening the column instead keeps the
    /// swatch itself at the 52pt both pickers share.
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
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)

        return Button {
            onSelect(typeface)
        } label: {
            VStack(spacing: 6) {
                Text(verbatim: "Aa")
                    .font(Card.font(.title3, typeface: typeface))
                    .frame(width: Self.swatchWidth, height: Self.swatchHeight)
                    .background(Stone.chip, in: shape)
                    .overlay { shape.strokeBorder(Stone.line, lineWidth: 0.5) }
                    // `.secondary` for the same reason the backdrop swatches use
                    // it: a full-strength ring is the loudest thing in the pane.
                    // The caption below going `.primary` when selected is the
                    // second cue that pays for the softer ring.
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.radius + 2, style: .continuous)
                            .strokeBorder(.secondary, lineWidth: 2)
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
