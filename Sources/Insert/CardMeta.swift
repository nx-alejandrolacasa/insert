import AppKit
import SwiftUI

/// The note card's anatomy: the card face is plain paper, and a note's type is
/// expressed twice — a capsule mark before the title, and a small-caps label
/// leading the meta row. The pieces live here because both cards borrow from
/// them and neither owns them.

// MARK: - Marked title

/// A card title with its type's mark: a 3×16pt capsule in the type's colour,
/// then the title at full contrast.
///
/// This replaced `MarkerTitle`, which drew the type as a **highlighter stroke
/// behind the glyphs** — the July 2026 refresh's decision 2, and the one part of
/// it that had to be undone rather than tuned. A coloured band under letters
/// fights them at any opacity; the strength had already come down from the
/// handoff's 60% to 45% because a saturated type crowded its own title, and the
/// remaining problem wasn't the number. It also forced every title onto a tinted
/// ground, so the title's contrast had to be argued per type instead of being
/// the one thing on a card that never varies.
///
/// Beside the title, the type's colour costs the words nothing: the mark is a
/// graphic, so it is solved at 3:1 (`AppTheme.typeMark`) and can stay bright
/// enough to see, where the label naming the same type in the meta row is text
/// and takes a darker value of it (`AppTheme.typeLabel`).
///
/// Two details. The mark is **fixed at 16pt tall** and top-aligned to the title's
/// first line rather than stretched to the text's height, so a title that wraps
/// to two lines doesn't grow a 40pt bar — it marks the card, it isn't a rule down
/// the side (that treatment was mocked as a 3px left rule and rejected as
/// generic). And it declares its own baseline through `centredOnTextCap`, because
/// the title row is `.firstTextBaseline`-aligned and a shape has no baseline of
/// its own: without that the capsule sat a couple of points low against the
/// capitals it marks.
struct TypeMarkTitle: View {
    let text: String
    let mark: Color

    @Environment(SettingsStore.self) private var settings

    /// 3×16 at a 2pt radius, from the plan. A hair narrower than a hairline is
    /// thick, so it reads as a mark rather than as a border.
    private static let markWidth: CGFloat = 3
    private static let markHeight: CGFloat = 16
    private static let markRadius: CGFloat = 2

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            RoundedRectangle(cornerRadius: Self.markRadius, style: .continuous)
                .fill(mark)
                .frame(width: Self.markWidth, height: Self.markHeight)
                .centredOnTextCap()
                // Decoration: the meta row's label names the type in words, and
                // spelling a colour out loud helps nobody.
                .accessibilityHidden(true)

            Text(text)
                .font(Card.font(.title3, weight: .semibold))
                .tracking(-0.1)
                // `labelColor` in five of the six themes — only Dracula names a
                // title colour of its own (`AppTheme.titleText`).
                .foregroundStyle(settings.theme.titleText)
                .lineLimit(2)
        }
    }
}

// MARK: - Type label

/// The small-caps type name leading a card's meta row — "MEETING", "NOTE" — in
/// the type's themed **label** colour, solved at 4.5:1 on the card faces its
/// theme paints. A few points darker than the capsule mark beside the title, and
/// that difference is the point: text carries a floor a graphic doesn't.
///
/// Mono, and uppercase, because it is a **tag rather than a word**: it labels the
/// card the way the count pill labels a column, and the same face draws both (see
/// `Mono`). At 10.5pt with 0.06em of tracking it also stops competing with the
/// project chips beside it, which are proportional and sentence-case.
struct TypeCapsLabel: View {
    let type: NoteType

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Text(type.name.uppercased())
            .font(Mono.font(size: 10.5, weight: .semibold))
            // 0.06em at 10.5pt.
            .tracking(0.63)
            .foregroundStyle(settings.theme.typeLabel(type.tint))
            .lineLimit(1)
            // The uppercase is presentation; VoiceOver should say "Meeting",
            // not spell out an initialism.
            .accessibilityLabel("Type: \(type.name)")
    }
}

// MARK: - Project dot chips

/// A read-only project chip: colour dot + name on neutral ground. The dot is
/// the only place project colour appears on a card (CLAUDE.md decision 4).
struct ProjectDotChip: View {
    let name: String
    let dot: Color

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(name)
        }
        .font(.caption)
        .foregroundStyle(settings.theme.metaText)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .chipHeight()
        .background(Capsule().fill(Stone.chip))
    }
}

/// A note's project chips, held to a fixed card height: the first two show in
/// full, everything past them collapses into one overflow chip — the hidden
/// projects' dots, overlapped, and a `+N` — because a note nearly always has
/// one project, two at most, and a card that grows a row per project spends
/// space the note's own text should have (CLAUDE.md decision 3).
///
/// The overflow chip is a **click popover** naming what it hides — chosen over
/// a hover popover or a tooltip because a click is the platform's standard
/// disclosure and the only one of the three that keyboard and VoiceOver users
/// can reach.
struct ProjectChipsRow: View {
    let projects: [Project]

    @Environment(SettingsStore.self) private var settings
    @State private var showingOverflow = false

    private static let shown = 2

    var body: some View {
        let visible = projects.prefix(Self.shown)
        let hidden = Array(projects.dropFirst(Self.shown))

        ForEach(visible) { project in
            ProjectDotChip(name: project.name, dot: project.tint.accent)
        }
        if !hidden.isEmpty {
            overflowChip(hidden)
        }
    }

    private func overflowChip(_ hidden: [Project]) -> some View {
        Button {
            showingOverflow = true
        } label: {
            HStack(spacing: 3) {
                // The hidden projects' own dots, overlapped, each on a sliver
                // of the card's own ground so neighbouring dots stay separable
                // — the theme's face, not a nominal white, or the slivers would
                // be the one light thing on a dark card.
                HStack(spacing: -3) {
                    ForEach(hidden.prefix(3)) { project in
                        Circle()
                            .fill(project.tint.accent)
                            .frame(width: 6, height: 6)
                            .padding(1)
                            .background(Circle().fill(settings.theme.cardFace))
                    }
                }
                Text("+\(hidden.count)")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(settings.theme.metaText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .chipHeight()
            .background(Capsule().fill(Stone.chip))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show all projects")
        .accessibilityLabel("\(hidden.count) more projects")
        .popover(isPresented: $showingOverflow, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(hidden) { project in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(project.tint.accent)
                            .frame(width: 7, height: 7)
                        Text(project.name)
                            .lineLimit(1)
                    }
                }
            }
            .font(.callout)
            .padding(12)
            .opaquePopoverWhenTransparencyReduced()
        }
    }
}
