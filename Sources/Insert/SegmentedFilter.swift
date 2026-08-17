import SwiftUI

/// The filter rows' segmented control (CLAUDE.md decision 7): a recessed
/// capsule track holding one segment per option, with the selection carried by
/// a **Liquid Glass pill that travels** between segments rather than a colour
/// that cross-fades.
///
/// It replaced the row of separate `FilterPill`s, which read as disconnected
/// chips and whose selected state was a filled colour block. Here the track
/// says "one of these, always" the way a radio does, and the glass indicator is
/// the platform's own current material — the intent is that this feels
/// indistinguishable from a system segmented control, so everything about the
/// indicator comes from the platform: `glassEffect` for the material (no
/// hand-rolled blur or rims), the default spring for the travel, and the two
/// accessibility fallbacks HIG asks for — **Reduce Transparency** swaps the
/// glass for an opaque raised pill, and **Reduce Motion** cuts straight to the
/// new segment instead of travelling.
///
/// A segment can carry a **dot**: the notes row gives every type segment its
/// type's colour, tying the filter to the capsule mark on the cards it
/// selects; the tasks row gives every state its long-standing colour (grey
/// All, orange Pending, green Done — `TaskFilter.tint`). Dots ride the label
/// layer, above the glass, so they keep their colour over it.
///
/// It now lives **on the column header band**, which is what finally makes the
/// glass worth having: an indicator refracts what is under it, and under a
/// neutral panel there was nothing to refract. So the track and both label
/// states come from the band's own tones (`BandColors`) rather than from
/// `Stone`, each solved against the band it is painted on — the third of the
/// refresh's contrast rules, verified against the surface actually painted
/// (CLAUDE.md decision 5). Every unselected label clears 6.1:1 on its track and
/// every selected one 10.9:1 on the raised pill.
///
/// Selection is reported through a callback rather than a binding, matching
/// how the panels drive their `AppState` filters.
struct SegmentedFilter<ID: Hashable>: View {
    struct Segment: Identifiable {
        let id: ID
        let label: String
        var dot: Color? = nil
    }

    let segments: [Segment]
    let selection: ID
    let onSelect: (ID) -> Void

    @Namespace private var indicatorSpace
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // Each system switch OR-ed with its in-app twin (the Accessibility menu):
    // the environment keys are read-only, so the pairing happens at the read.
    private var motionReduced: Bool { reduceMotion || settings.appReduceMotion }
    private var transparencyReduced: Bool { reduceTransparency || settings.appReduceTransparency }

    /// The band's tones, since that is what the track is painted on.
    private var band: BandColors { settings.theme.band }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(3)
        // The recess: quiet on purpose, so it can't compete with the glass
        // indicator inside it. The band's hue at ~92% L in Light, the band
        // itself lifted 10% toward white in Dark.
        .background(Capsule().fill(band.trackFill))
        .overlay {
            // Dark mode only: a recess in a dark band needs an upper lip to
            // read as one, and the same highlight on a light band is invisible.
            if band.trackHighlight {
                Capsule()
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                    // The lip is the *top* edge; masking the stroke to the
                    // upper half is what keeps it from becoming an outline.
                    .mask(alignment: .top) {
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom)
                    }
            }
        }
    }

    private func segmentButton(_ segment: Segment) -> some View {
        let selected = segment.id == selection
        return Button {
            guard !selected else { return }
            // The travel: matched geometry between the old segment's indicator
            // and the new one's, on the platform's default spring. Reduce
            // Motion drops the animation, so the pill cuts.
            withAnimation(motionReduced ? nil : .smooth(duration: 0.28)) {
                onSelect(segment.id)
            }
        } label: {
            HStack(spacing: 5) {
                if let dot = segment.dot {
                    Circle()
                        .fill(dot)
                        .frame(width: 6, height: 6)
                }
                Text(segment.label)
            }
            .font(.caption.weight(selected ? .semibold : .regular))
            // Not `.primary`: a label on a themed track has to be solved
            // against that track, and the selected one sits on a near-white
            // pill where the band's own fill is what reads.
            .foregroundStyle(selected ? band.segmentLabelSelected : band.segmentLabel)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            // The pills' floor, less the track's own 3pt padding, so the whole
            // control lines up with the chips and menus beside it.
            .frame(minHeight: Metrics.chipHeight - 6)
            .background {
                if selected {
                    indicator
                        .matchedGeometryEffect(id: "selection", in: indicatorSpace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// The moving selection. Glass, so it refracts the track and the tint
    /// under it — or, with Reduce Transparency on, plain opaque paper with the
    /// standard hairline.
    ///
    /// The clip is load-bearing: **Liquid Glass paints its own drop shadow**
    /// (the search-field lesson — it lives inside the glass renderer, with no
    /// API to turn it off), and here it was drawn from the indicator's
    /// *rectangular* bounds, so a square shadow leaked past the capsule onto
    /// the track and the panel. The window is deliberately shadowless, so the
    /// rendering is clipped to the capsule — a point proud of the shape, which
    /// keeps the rim's own lighting while everything the shadow painted
    /// outside it goes.
    @ViewBuilder
    private var indicator: some View {
        if transparencyReduced {
            // The opaque raised pill the plan specifies as the fallback: the
            // band's own `segmentFill` — pure white in Light, the band's hue at
            // 97% L in Dark — which is what the glass approximates anyway, so
            // the two states read as the same control.
            Capsule()
                .fill(band.segmentFill)
                .overlay(Capsule().strokeBorder(Stone.line, lineWidth: 0.5))
        } else {
            Color.clear
                .glassEffect(.regular, in: Capsule())
                .clipShape(Capsule().inset(by: -1))
        }
    }
}
