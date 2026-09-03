import AppKit
import SwiftUI

/// The themed slab at the top of the notes and tasks columns — the one surface
/// in the window a theme paints, and where all of Insert's colour now lives.
///
/// It replaced a plain heading row plus a loose filter row, and the move is the
/// whole point of the theme system: with the window's flat tint gone and note
/// type reduced to a dot, nothing carried the app's identity, and the two places
/// colour *had* been (the window surface, the title's highlighter stroke) were
/// the two places it worked least — a low-chroma wash reads as nothing, and
/// pigment behind glyphs fights them. A band is neither: it is never behind body
/// text, so its contrast is verified once per theme instead of everywhere, and it
/// gives the filter track's glass indicator a coloured ground to actually refract.
///
/// Two rows inside one band — heading and filters — and **no radius of its own**:
/// it spans the full column width and the window's corner clips it, which is what
/// makes two adjacent bands read as one strip rather than as two cards. And no
/// hairline under it either — see the `.background` below.
///
/// The heading is drawn in the **card face**, not the system font — the one place
/// the typeface setting reaches outside a card. That is a deliberate widening of
/// the rule that chrome stays on the default design: the band is the app's
/// identity surface now, and Grotesk being the default is most of what a new
/// install's character *is*. Everything else in the chrome — chips, pills, the
/// due badge, panel content — is unchanged.
struct ColumnHeaderBand<Filters: View>: View {
    let title: String
    /// The column's "new" glyph, right after the heading: what it creates, the
    /// tooltip (which names the shortcut) and the action.
    let addLabel: String
    let addHelp: String
    let addAction: () -> Void
    @ViewBuilder let filters: Filters

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        let band = settings.theme.band

        VStack(spacing: Metrics.bandRowGap) {
            HStack(spacing: 10) {
                Text(title)
                    // `.title2` (17pt), the size the loose heading already
                    // used — the plan's 19pt is indicative, and this app's ramp
                    // is the thing to convert it into. `.title3` would be 15pt
                    // here, the note *title's* size, which would leave a column
                    // heading no larger than the cards under it.
                    .font(Card.chrome(.title2, weight: .bold))
                    // Tight tracking: a 17pt bold heading opens up a little in
                    // both the bundled and the system faces.
                    .tracking(-0.2)
                    .foregroundStyle(band.text)
                    .lineLimit(1)

                // A bare "+" in the sidebar header's own style, beside the
                // heading rather than pushed to the trailing edge. (The row
                // count sat between the two until September 2026; it is in the
                // filter track's selected segment now — see `SegmentedFilter`.) It was a filled
                // accent pill there until September 2026 — the loudest thing in
                // a header that now melts into the page — and then briefly a
                // toolbar glyph beside search, where it read as belonging to
                // neither column. `plus` alone, since the heading it sits under
                // already says what it creates.
                Button(action: addAction) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.headerAddGlyph)
                .help(addHelp)
                .accessibilityLabel(addLabel)

                Spacer(minLength: 0)
            }

            filters
        }
        .padding(.horizontal, Metrics.panelPadding)
        .padding(.top, Metrics.bandTopPadding)
        .padding(.bottom, Metrics.bandBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // EXPERIMENT (September 2026, at the maintainer's request): the band
        // paints the **page ground** instead of its own fill, so the header
        // melts into the column behind it in every theme. The band's fill and
        // everything derived from it stay in `AppTheme` untouched — restore
        // `.background(band.fill)` to end the experiment.
        .background(settings.theme.windowFill)
        // **No hairline on the bottom edge**, in any theme. A light band used to
        // take one — a dark band separates from the cards on its own — and it read
        // as a rule *drawn under* the header rather than as the edge of a surface,
        // which in a window with no shadows anywhere is the one thing that looks
        // like a border. The band's own colour against the page is the boundary.
        // The band is chrome for the column under it; VoiceOver should reach
        // the heading and the "+", not a container named "band".
        .accessibilityElement(children: .contain)
    }
}
