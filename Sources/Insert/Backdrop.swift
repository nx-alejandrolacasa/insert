import AppKit
import SwiftUI

// MARK: - Backdrop

/// The optional gradient wash behind the main window — the app's one piece of
/// pure decoration, and the only setting that exists purely to make Insert feel
/// like *yours*.
///
/// Five gradients, plus "None" for the plain window background, which stays the
/// default so an install that never opens Settings looks exactly as it always
/// has. `dawn` and `dusk` are drawn from the icon's warm family (see
/// `tools/IconGenerator.swift`) and `grove` is their cool counterpart, so the
/// set isn't only variations on a sunset; `cloud` and `stone` are borrowed from a
/// CSS gradient gallery, hex values intact, with only their Dark halves inferred
/// here. The row runs quietest-first: the two near-white neutrals, the warm pair,
/// then `grove`, the only cool one left.
///
/// Seven candidates were cut on sight, and they're the brief for a sixth — a
/// Honey and a Dune too close to the pale warm end of Dawn, an Orchid that ended
/// on the very lilac Dawn begins with, a Neon simply too loud for a surface you
/// look at all day, a Rare Wind, a linear near-white-into-sand that gave its name
/// to `stone`, and a Soft grass too bright at its deep end. **A new gradient
/// earns its place by not being reachable from an existing one** — and by being
/// quiet enough to sit behind text all day. Sharing a hue family is fine; sharing
/// a *stop* is what makes two entries feel like one mirrored, and the gradient
/// that wins the swatch row is usually the one you turn off within the hour.
/// Five of the seven cuts were for one of those two reasons.
///
/// **Each gradient is one gradient, not two.** A backdrop names a pair of hues;
/// what changes between Light and Dark is the *value* those hues are rendered
/// at, never the hues themselves — Dawn is lilac-into-apricot in both, pale in
/// Light and deep in Dark. That's why the stops are declared as light/dark pairs
/// and resolved through a dynamic `NSColor`, exactly as `Tint` does: the whole
/// palette then follows Settings → General → Theme with nothing to re-apply, and
/// no view has to read `colorScheme` to draw a swatch.
///
/// Both halves of every pair are solved for legibility against the text that
/// sits on them. The pale stops land between 14:1 and 21:1 for black, the deep
/// stops between 13:1 and 18:1 for white — comfortably past the 7:1 that AAA
/// asks and the 7:1 the `Tint` ramps reserve for Increase Contrast, which is why
/// there is no separate high-contrast variant here. Content still sits on
/// `.island()` surfaces on top of this, so the backdrop is never the only thing
/// carrying a glyph; keep it that way and keep any new pair inside those bands.
enum Backdrop: String, CaseIterable, Identifiable {
    /// The plain window background. Spelled `plain` rather than `none` so
    /// `Backdrop?` can't quietly mean two things at a call site.
    case plain
    /// Near-white into pale cool grey (`#fdfbfb` → `#ebedee`) — overcast light.
    /// The only achromatic member, and by a distance the quietest: it reads as
    /// paper rather than as a colour, which is the point. Note the two ends lean
    /// opposite ways — the light one is faintly *warm* (red highest), the pale
    /// one faintly *cool* (blue highest) — and that half-percent disagreement is
    /// the whole gradient. Flatten it to one neutral and there's nothing left.
    case cloud
    /// Warm off-white with a soft bloom out of the centre — the one **radial**
    /// backdrop, and the reason `Ramp` has a shape at all. `cloud`'s warm twin:
    /// the same near-white idea, one cool and flat, this one warm and lit.
    ///
    /// The source is two stacked CSS radials blended with `screen`: a near-flat
    /// `#EADFDF → #ECE2DF` base, and over it an ellipse running white at 50%
    /// alpha to black at 50% alpha. That blend is resolved here rather than
    /// reproduced, because `screen` against those two ends is arithmetic with a
    /// known answer: screening with black is the identity, so the outer stop is
    /// just the base's `#ECE2DF`, and screening with white at half alpha lands
    /// halfway to white, so the centre is `0.5 + 0.5 × #EADFDF`. Two stops, no
    /// blend mode, no second layer — and nothing for SwiftUI to composite
    /// per-frame.
    ///
    /// Faithful to the source, that came out at a ~12% swing in luminance, and
    /// **12% is not a gradient** — it read as a flat colour in the window and as
    /// nothing whatsoever in a 52pt swatch, which is the one job the Settings
    /// preview has. So the outer stop is deepened well past `#ECE2DF`, to about a
    /// 30% swing. The centre is still the resolved blend; only the edge moved. If a
    /// borrowed gradient's own stops are 1% apart, copying them exactly is the
    /// wrong kind of faithful.
    ///
    /// Unrelated to the `Stone` palette in `Theme.swift`, which is the app's
    /// neutral for chips and hairlines. Same word, different job — no call site
    /// can confuse them (`Backdrop.stone` against the `Stone` enum), but don't
    /// wire one to the other on the strength of the name. This case also inherits
    /// the name from a *different* gradient: a linear near-white-into-sand that
    /// was cut, so a saved `"stone"` from before now selects the radial.
    case stone
    /// Pale lilac into pale apricot — the icon's own gradient, toned well down
    /// from it. The lilac end is what carries the name; the apricot end is nearly
    /// white.
    case dawn
    /// Pale apricot into pale coral rose. The coral end carries the name.
    ///
    /// Dusk's first stop and `dawn`'s last are near-identical pale apricots, so by
    /// the rule in this file's header the two share a stop. They get away with it
    /// where a mirrored pair wouldn't, because they *chain* rather than reflect —
    /// Dawn runs lilac → apricot and Dusk apricot → coral, so each still reads as
    /// the colour at its own far end and the two never resolve to the same
    /// impression. Toning both down narrowed that margin; narrowing it further is
    /// how they'd finally collapse into one another.
    case dusk
    /// Soft sky into sage leaf — kept low in saturation on purpose: green and
    /// blue at pastel strength read as scenery, and at anything more they read
    /// as a status colour, which every other green and blue in the app already
    /// means (a due-today badge, the base Note type).
    case grove

    var id: Self { self }

    var label: String {
        switch self {
        case .plain: "None"
        case .cloud: "Cloud"
        case .stone: "Stone"
        case .dawn: "Dawn"
        case .dusk: "Dusk"
        case .grove: "Grove"
        }
    }

    /// The wash itself, or `nil` for the plain background. Type-erased because
    /// the two ramp shapes are different `ShapeStyle`s, and every call site only
    /// ever hands this straight to `.fill` or `.containerBackground`.
    ///
    /// The linear ones run **diagonally**, corner to corner. A window is much
    /// wider than it is tall, so the icon's top-to-bottom ramp would put both
    /// stops in narrow bands at the very top and bottom and leave the middle —
    /// where all the content is — a flat mid-tone. Corner to corner is the flat
    /// `.icns`'s direction, and it keeps some travel across the whole surface.
    var gradient: AnyShapeStyle? {
        switch ramp {
        case .none:
            nil
        case .linear(let stops):
            AnyShapeStyle(LinearGradient(
                colors: stops.map(\.color),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        // Centre-out, and the radius runs past the frame: the CSS this came from
        // sizes its ellipse at 147% of the box height, so the outer stop is only
        // ever reached in the corners. Clamping it to the edge instead would ring
        // the window with the dark stop and lose the point of the shape.
        case .elliptical(let stops):
            AnyShapeStyle(EllipticalGradient(
                colors: stops.map(\.color),
                center: .center,
                startRadiusFraction: 0,
                endRadiusFraction: 0.85
            ))
        }
    }

    /// What the window paints behind everything. `.windowBackground` for "None",
    /// so the setting can be applied *unconditionally* — branching on it in the
    /// view builder instead would give the two cases different identities and
    /// tear down `NavigationSplitView` (and with it the autosaved column widths)
    /// every time the picker moved.
    var windowStyle: AnyShapeStyle {
        gradient ?? AnyShapeStyle(.windowBackground)
    }

    /// Whether the projects sidebar frosts the backdrop itself, instead of
    /// leaving AppKit's own sidebar material to it.
    ///
    /// It has to, for anything but "None". AppKit's sidebar material blends
    /// **behind the window**: it frosts the desktop and is blind to everything
    /// Insert draws, so the gradient would simply not be there. What goes over it
    /// is **Liquid Glass** (see `ProjectsSidebar`), not a `Material` — a
    /// `.thinMaterial` was the first attempt and it reads as a flat grey panel
    /// laid over the design, because a material only blurs and dims what's behind
    /// it. Glass also *refracts* and picks up the backdrop's own light, which is
    /// what makes the column look like it belongs to the gradient rather than
    /// sitting on top of it — and it matches the toolbar's search field, the one
    /// other large glass surface in the window.
    ///
    /// False for "None", which leaves the AppKit material untouched, so a default
    /// install keeps the desktop translucency it has always had.
    var frostsSidebar: Bool { self != .plain }

    /// The shape and the stops, each stop in its two appearances. Reused by the
    /// gradient and by the Settings swatches, so a preview can't drift from the
    /// thing it previews.
    ///
    /// Stops are an array rather than a `start`/`end` pair: every member happens
    /// to be two stops today, but a three-stop sweep is the natural way to build
    /// a gradient that travels across more than one hue, and the shape costs
    /// nothing to keep.
    ///
    /// Declared in `allCases` order, which is the order the Settings grid shows:
    /// the two near-white neutrals (`cloud`, `stone`), the app's own
    /// warm pair (`dawn`, `dusk`), then `grove`.
    private var ramp: Ramp? {
        switch self {
        case .plain:
            nil
        // Dark is inferred, not measured off a source: the same two ends turned
        // over. Near-black keeping the light end's faint warmth, into a lifted
        // cool grey for the pale end — so an overcast day becomes an overcast
        // night rather than a grey card, and the warm/cool split that carries
        // the light version survives at the only strength that reads down here.
        case .cloud: .linear([
            DynamicRGB(light: RGB(r: 0.992, g: 0.984, b: 0.984), dark: RGB(r: 0.105, g: 0.102, b: 0.102)),
            DynamicRGB(light: RGB(r: 0.922, g: 0.929, b: 0.933), dark: RGB(r: 0.165, g: 0.172, b: 0.178))])
        // Centre first, edge second — the order an `EllipticalGradient` reads, and
        // the opposite of how the CSS lists its stops.
        //
        // The centre is the resolved screen blend (see the case). The **edge is
        // deepened past what the source gives**, and that's a deliberate departure:
        // the CSS's own two stops are `#EADFDF → #ECE2DF`, a 1% step, and even with
        // the white bloom screened over it the whole thing came to a ~12% swing in
        // luminance — which reads as a flat colour, not a gradient, and reads as
        // *nothing at all* in a 52pt swatch. This edge takes it to ~30%, enough to
        // see the falloff while keeping the character: still a warm off-white lit
        // from the middle, and the palest member of the set after `cloud`.
        case .stone: .elliptical([
            DynamicRGB(light: RGB(r: 0.959, g: 0.937, b: 0.937), dark: RGB(r: 0.185, g: 0.170, b: 0.168)),
            DynamicRGB(light: RGB(r: 0.872, g: 0.828, b: 0.815), dark: RGB(r: 0.108, g: 0.100, b: 0.098))])
        // Both of these were toned down: they were the two most saturated members
        // and sat oddly beside the near-white borrowed ones. Every stop keeps its
        // hue and its *lead* channel — the identity of each is which channel wins,
        // not by how much — and only loses chroma. Deliberately the pale ends kept
        // more of their colour than the middle, since that's where each one's name
        // actually lives: Dawn's lilac and Dusk's coral.
        case .dawn: .linear([
            DynamicRGB(light: RGB(r: 0.925, g: 0.910, b: 0.985), dark: RGB(r: 0.150, g: 0.145, b: 0.190)),
            DynamicRGB(light: RGB(r: 0.990, g: 0.955, b: 0.915), dark: RGB(r: 0.195, g: 0.175, b: 0.155))])
        case .dusk: .linear([
            DynamicRGB(light: RGB(r: 0.995, g: 0.950, b: 0.905), dark: RGB(r: 0.200, g: 0.175, b: 0.150)),
            DynamicRGB(light: RGB(r: 0.980, g: 0.895, b: 0.885), dark: RGB(r: 0.205, g: 0.165, b: 0.163))])
        // Sky first, sage second — inverted from how this was first written, so the
        // gradient runs blue at the top-leading corner down into green, the way
        // the thing it's named after is actually arranged.
        case .grove: .linear([
            DynamicRGB(light: RGB(r: 0.84, g: 0.92, b: 0.95), dark: RGB(r: 0.11, g: 0.17, b: 0.21)),
            DynamicRGB(light: RGB(r: 0.90, g: 0.95, b: 0.89), dark: RGB(r: 0.13, g: 0.19, b: 0.15))])
        }
    }
}

/// A backdrop's ramp: the stops, plus the shape they're laid out in.
///
/// Two shapes because `stone` is radial where every other member is a
/// diagonal linear ramp. Kept as an enum rather than, say, a `startPoint`/
/// `endPoint` pair on every case, so a linear backdrop can't accidentally be
/// given a centre and a radial one can't be given a direction.
private enum Ramp {
    /// Corner to corner, stops in reading order.
    case linear([DynamicRGB])
    /// Centre outwards, first stop at the centre.
    case elliptical([DynamicRGB])
}

/// One gradient stop, in its two appearances.
///
/// A thinner `dynamic(light:dark:lightHC:darkHC:)` than `Tint`'s: there are no
/// Increase Contrast variants to carry, because both values already clear AAA
/// against the text drawn on them (see `Backdrop`).
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

/// A grid of gradient swatches, one per `Backdrop`, each captioned with its name.
///
/// Deliberately not a `Picker`: the whole point of choosing a background is
/// seeing it, and a menu of the words "Dawn" and "Stone" tells you nothing.
/// The swatches paint from the very same `gradient` the window does, so they also
/// answer the question the names can't — what the *current* theme's version of
/// each one looks like, radial ones included.
struct BackdropPicker: View {
    let selection: Backdrop
    let onSelect: (Backdrop) -> Void

    private static let swatchWidth: CGFloat = 52
    private static let swatchHeight: CGFloat = 34
    private static let radius: CGFloat = 7

    var body: some View {
        // One row. Six entries at 52pt plus 10pt gaps is 362pt against the
        // Settings pane's ~420 (a fixed 700pt window, less its sidebar and the
        // Form's insets), so it fits with room to spare. **Seven is where it stops
        // fitting** — 424pt — and the answer then is a `LazyVGrid` of four
        // columns, not smaller swatches: below about 46pt a gradient preview stops
        // previewing anything, which defeats the point of not using a `Picker`.
        //
        // 10pt apart so the selection ring, which sits outside its swatch, has
        // room either side and can't touch its neighbours.
        HStack(alignment: .top, spacing: 10) {
            ForEach(Backdrop.allCases) { backdrop in
                swatch(backdrop)
            }
        }
        // The selection ring overhangs its swatch; give it somewhere to go rather
        // than letting the Form row clip it.
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
                    .fill(backdrop.gradient ?? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)))
                    .frame(width: Self.swatchWidth, height: Self.swatchHeight)
                    // The same hairline `.island()` uses, so a pale swatch on a
                    // pale Form row still has an edge.
                    .overlay { shape.strokeBorder(Stone.line, lineWidth: 0.5) }
                    // `.secondary`, not `.primary`: a full-strength label-coloured
                    // ring is the loudest thing in the pane and fights the very
                    // gradients it's meant to be pointing at. Softening it does
                    // give up contrast — a knowing trade, and the reason the
                    // caption below still goes `.primary` when selected, so the
                    // state is carried by two cues rather than by this ring alone.
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.radius + 2, style: .continuous)
                            .strokeBorder(.secondary, lineWidth: 2)
                            .padding(-3)
                            .opacity(selected ? 1 : 0)
                    }

                Text(backdrop.label)
                    .font(.caption)
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    // Centred in its grid column, which is wider than the swatch
                    // Held to the swatch's width: every label is one short word, so
                    // none of them needs more, and pinning it means a longer name
                    // added later widens its own column rather than silently
                    // knocking the whole row out of step.
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
