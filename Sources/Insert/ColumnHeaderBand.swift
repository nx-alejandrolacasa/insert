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
    /// How many rows the column is currently showing, in a mono pill beside the
    /// heading. The *filtered* count, deliberately: it is a label for the list
    /// under it, so it has to agree with what you can see.
    let count: Int
    let primaryTitle: String
    let primarySymbol: String
    let primaryHelp: String
    let primaryAction: () -> Void
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

                CountPill(count: count, band: band)

                Spacer(minLength: 8)

                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: primarySymbol)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.accentCapsule)
                .controlSize(.large)
                .help(primaryHelp)
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
        // the heading, the count and the button, not a container named "band".
        .accessibilityElement(children: .contain)
    }
}

/// The row count, in a mono pill in the band's own count tones.
///
/// Mono because the number changes under you: a proportional face makes a count
/// jump sideways going from 9 to 10, where a tabular one holds still. See `Mono`
/// for why the same face draws the timestamps and the type labels, and for the
/// one setting that opts out of it.
private struct CountPill: View {
    let count: Int
    let band: BandColors

    var body: some View {
        // Through the app's own locale, not the system's: a count past 999 gets
        // a group separator, and a Spanish Mac would draw "1.000" in an
        // otherwise English window (the `Formatting.locale` rule, which is
        // usually about dates but is the same rule).
        Text(count, format: .number.locale(Formatting.locale))
            // `font`, not `card`: the band is chrome, and its height is the
            // window's business — a reader asking for larger notes is not asking
            // for a taller header (`Card.chrome(_:)`'s line). The cards' own
            // timestamps and type labels take `Mono.card` for the same reason
            // read the other way.
            .font(Mono.font(size: 11, weight: .semibold))
            // Digits of one width, so the pill doesn't breathe as the count
            // changes. Free with a mono face for the glyphs themselves; this
            // covers the case where the fallback isn't one.
            .monospacedDigit()
            .foregroundStyle(band.countText)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(band.countFill))
            // Spoken as a sentence: "12" alone, read out after the heading,
            // says nothing about what there are twelve of.
            .accessibilityLabel("\(count) shown")
    }
}
