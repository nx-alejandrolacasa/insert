import SwiftUI

// MARK: - Tint

/// A soft pastel accent used by note types (and available when creating custom
/// ones). Each tint provides a saturated `accent` and a very subtle `soft`
/// background wash that reads on both light and dark backgrounds.
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

    /// The vivid accent color (used for dots, borders, selected states).
    var accent: Color {
        switch self {
        case .gray:   Color(red: 0.63, green: 0.59, blue: 0.53)
        case .yellow: Color(red: 0.95, green: 0.77, blue: 0.29)
        case .purple: Color(red: 0.60, green: 0.45, blue: 0.95)
        case .green:  Color(red: 0.35, green: 0.78, blue: 0.55)
        case .blue:   Color(red: 0.30, green: 0.62, blue: 0.98)
        case .orange: Color(red: 0.98, green: 0.62, blue: 0.30)
        case .pink:   Color(red: 0.96, green: 0.52, blue: 0.72)
        case .teal:   Color(red: 0.30, green: 0.78, blue: 0.80)
        case .red:    Color(red: 0.96, green: 0.42, blue: 0.42)
        }
    }

    /// A deepened partner to `accent`, for the places where white text sits on
    /// top of the colour. The pastel accents are tuned to read as a *wash*, so
    /// filling a pill with one and writing on it leaves the label barely
    /// legible — yellow and orange worst of all. Same hues, taken down to a
    /// depth that carries white type.
    var deep: Color {
        switch self {
        case .gray:   Color(red: 0.44, green: 0.41, blue: 0.35)
        case .yellow: Color(red: 0.76, green: 0.55, blue: 0.07)
        case .purple: Color(red: 0.45, green: 0.29, blue: 0.85)
        case .green:  Color(red: 0.16, green: 0.57, blue: 0.36)
        case .blue:   Color(red: 0.13, green: 0.45, blue: 0.88)
        case .orange: Color(red: 0.84, green: 0.45, blue: 0.09)
        case .pink:   Color(red: 0.83, green: 0.31, blue: 0.54)
        case .teal:   Color(red: 0.09, green: 0.54, blue: 0.57)
        case .red:    Color(red: 0.84, green: 0.24, blue: 0.24)
        }
    }

    /// A subtle background wash for note "islands" of this type.
    var soft: Color { accent.opacity(0.14) }

    /// A slightly stronger fill for pills/chips.
    var chip: Color { accent.opacity(0.20) }
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

    static let minSidebarWidth: CGFloat = 260
    static let idealSidebarWidth: CGFloat = 340
    static let maxSidebarWidth: CGFloat = 460
}

// MARK: - Filter pill

/// A capsule filter pill, shared by the notes type filter and the tasks
/// state filter so both columns read as one system. The fill never changes — it's
/// the tint's soft wash whatever the state — so selecting something doesn't put a
/// louder block of colour on screen. Selection shows in the *border*, drawn in a
/// softened `deep` shade — `accent` is tuned as a wash, so a yellow or orange
/// outline in it reads weaker than a blue one, while full-strength `deep` drew a
/// hard ring around the pill — plus a heavier label. Grey always means "All".
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
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.chip))
            .overlay(
                Capsule().strokeBorder(
                    selected ? tint.deep.opacity(0.45) : Stone.line,
                    lineWidth: selected ? 1 : 0.5
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A compact row of tappable color swatches (one per `Tint`). Reports the chosen
/// tint upward via a closure so both the edit rows and the add form can share it.
struct TintPicker: View {
    let selection: Tint
    let onSelect: (Tint) -> Void

    var body: some View {
        HStack(spacing: 4) {
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
                }
                .buttonStyle(.plain)
                .help(tint.name)
            }
        }
    }
}

// MARK: - Card surface

extension View {
    /// Wraps content in the app's standard rounded "island" — a *flat* fill, not
    /// Liquid Glass. Glass islands each cast their own drop shadow, which the
    /// columns' scroll views clipped at their edges and which pooled into a grubby
    /// band wherever cards stacked. A note takes its type's colour wash; anything
    /// untinted (a task row, the composer) takes the warm `Stone` neutral.
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
            .background { shape.fill(tint?.soft ?? Stone.surface) }
            // A hairline keeps the card's edge readable now that there's no
            // shadow separating it from the background.
            .overlay { shape.strokeBorder(Stone.line, lineWidth: 0.5) }
    }
}
