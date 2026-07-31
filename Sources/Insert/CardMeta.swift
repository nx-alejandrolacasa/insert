import AppKit
import SwiftUI

/// The refresh's note-card anatomy (docs/plans/ decisions 2 and 3): the card
/// face is white, and a note's type is expressed twice — a highlighter stroke
/// behind the title, and a small-caps label leading the meta row. The pieces
/// live here because both cards borrow from them and neither owns them.

// MARK: - Marker title

/// A card title wearing its type's highlighter stroke: a band in the type's
/// `marker` colour covering the bottom ~34% of each line box, drawn *behind*
/// the glyphs — the title's own colour and contrast are untouched.
///
/// The band is per **line**, not per text block, which is the part SwiftUI
/// doesn't give away: a single bottom-aligned background under a two-line
/// title would stroke only the last line. So the text's height is measured,
/// divided by the face's line height into a line count, and one band drawn per
/// line. The bands span the text frame's width — for a wrapped title that is
/// the widest line, so a shorter second line's band can overhang it by a few
/// points, which at marker strength reads as the stroke running on rather
/// than as an error. Mapping each line's true width would need the title
/// laid out by hand; not worth it for a two-line limit.
struct MarkerTitle: View {
    let text: String
    let marker: Color

    @State private var height: CGFloat = 0

    var body: some View {
        // The face's own metrics, so a serif or monospaced card folds its
        // marker at its own rhythm — the `CollapsibleMarkdown` rule.
        let font = Card.nsFont(.title3, weight: .bold)
        let lineHeight = font.ascender - font.descender + font.leading

        Text(text)
            .font(Card.font(.title3, weight: .bold))
            .lineLimit(2)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .background(alignment: .topLeading) {
                let lines = max(1, Int((height / lineHeight).rounded()))
                VStack(spacing: 0) {
                    ForEach(0..<lines, id: \.self) { _ in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            marker
                                .frame(height: lineHeight * 0.34)
                        }
                        .frame(height: lineHeight)
                    }
                }
                // The stroke runs a couple of points past the glyphs at each
                // end, the way a real highlighter overshoots.
                .padding(.horizontal, -2)
            }
    }
}

// MARK: - Type label

/// The small-caps type name leading a card's meta row — "MEETING", "NOTE" —
/// in the type's `ink`, which is already solved at 4.5:1 on the card faces.
struct TypeCapsLabel: View {
    let type: NoteType

    var body: some View {
        Text(type.name.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(type.tint.ink)
            .lineLimit(1)
            // The uppercase is presentation; VoiceOver should say "Meeting",
            // not spell out an initialism.
            .accessibilityLabel("Type: \(type.name)")
    }
}

// MARK: - Project dot chips

/// A read-only project chip: colour dot + name on neutral ground. The dot is
/// the only place project colour appears on a card (docs/plans/ decision 4).
struct ProjectDotChip: View {
    let name: String
    let dot: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(name)
        }
        .font(.caption)
        .foregroundStyle(Stone.metaText)
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
/// space the note's own text should have (docs/plans/ decision 3).
///
/// The overflow chip is a **click popover** naming what it hides — chosen over
/// a hover popover or a tooltip because a click is the platform's standard
/// disclosure and the only one of the three that keyboard and VoiceOver users
/// can reach.
struct ProjectChipsRow: View {
    let projects: [Project]

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
                // of card colour so neighbouring dots stay separable.
                HStack(spacing: -3) {
                    ForEach(hidden.prefix(3)) { project in
                        Circle()
                            .fill(project.tint.accent)
                            .frame(width: 6, height: 6)
                            .padding(1)
                            .background(Circle().fill(Color(nsColor: .textBackgroundColor)))
                    }
                }
                Text("+\(hidden.count)")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Stone.metaText)
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
