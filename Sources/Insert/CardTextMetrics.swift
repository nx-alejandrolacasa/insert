import AppKit
import SwiftUI

// MARK: - The two reading metrics

/// The point size a note's **body** is read at — Settings → Appearance, beside
/// the typeface it is set in.
///
/// Stored as the body's own size in points rather than as a multiplier, because
/// that is the number a reader can think about: 13 is what macOS calls `.body`
/// and so what the cards have always been. Everything else on a card is a *text
/// style* — a title is `.title3`, a task's notes `.callout`, a heading
/// `.title2` — and each of those keeps its own ratio to the body, so one number
/// moves the whole card and nothing inside it changes proportion. That is what
/// `scale(_:)` is: the factor `Card` multiplies every preferred size by.
///
/// Scope is the **card**, not the window. The typeface reaches three pieces of
/// chrome as well (the column headings and the sidebar's project names, which
/// are authored text set in the reading face) and the size deliberately does
/// not: those sit in rows whose height is the window's business, and a reader
/// asking for larger notes is not asking for a larger sidebar. `Card.chrome(_:)`
/// is the opt-out they use.
///
/// The bounds are the range where a card still reads as a card. Below 11 the
/// metadata under the body — a caption at the same ratio — stops being legible;
/// above 22 a title is 26pt and two of them fill the column. Both are wider than
/// anyone is likely to want, which is the point of a floor and a ceiling.
enum CardTextSize {
    static let range: ClosedRange<Int> = 11...22

    /// macOS's own `.body` — 13pt — and so the default. Read rather than
    /// written down, so a system that ships a different body size still has
    /// "the size the cards have always been" as its starting point.
    static var system: Int {
        Int(NSFont.preferredFont(forTextStyle: .body).pointSize.rounded())
    }

    static func clamped(_ size: Int) -> Int {
        min(max(size, range.lowerBound), range.upperBound)
    }

    /// What `Card` multiplies a text style's preferred size by. Exactly 1 at the
    /// system's own size, so an install that never touches the setting resolves
    /// the very fonts it did before — the same `NSFont`, not a rounded copy.
    static func scale(_ size: Int) -> CGFloat {
        let body = NSFont.preferredFont(forTextStyle: .body).pointSize
        guard body > 0 else { return 1 }
        return CGFloat(clamped(size)) / body
    }
}

/// How far apart a body's lines sit, as a multiple of the font's own line
/// height — Settings → Appearance, under the size.
///
/// A multiple rather than a point value because the thing being spaced is the
/// font's line, and the font is a setting of its own: 1.4 means the same
/// looseness in 11pt Grotesk and 22pt New York, where "5pt between lines" means
/// two different textures.
///
/// **1.0 is the floor, and it is the font's own leading rather than a tight
/// setting** — the value every card has always been drawn at. Going below it is
/// possible in AppKit (a negative `lineSpacing`) and is not offered: the two
/// faces with real descenders start colliding, and nothing about a Markdown note
/// wants to be tighter than the type designer set it. 2.0 is double-spaced,
/// which is as far as a body is worth loosening before it stops reading as a
/// paragraph.
///
/// The step is a tenth, so the whole range is eleven presses of a stepper.
enum CardLineHeight {
    static let range: ClosedRange<Double> = 1.0...2.0
    static let step = 0.1
    /// The font's own leading, and the default.
    static let standard = 1.0

    /// Clamped into range and snapped onto the step, so a value saved by an
    /// earlier build — or a hand-edited default — lands on one of the eleven
    /// the stepper can reach. Idempotent on a value already on the step: it runs
    /// every launch, and a snap that drifted would walk the setting a tenth at a
    /// time.
    static func snapped(_ value: Double) -> Double {
        // Snapped first and clamped second, not the other way round: a tenth is
        // not representable in binary, so `20 × 0.1` lands a hair *above* 2.0 —
        // and a value a hair outside its own range would leave the stepper's
        // "+" enabled at the top of it.
        let snapped = (value / step).rounded() * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    /// One decimal, always — "1.0" rather than "1", so the column doesn't change
    /// width as the value crosses a whole number. Not locale-formatted: the app
    /// is English throughout, and this is a number the UI writes, not a date.
    static func label(_ value: Double) -> String {
        String(format: "%.1f", snapped(value))
    }
}

// MARK: - The stepper

/// The `−  value  +` control the two settings above are driven by: one pill,
/// two glyph buttons, the value between them.
///
/// A plain `Stepper` was the obvious thing and is the wrong shape here — its
/// AppKit control is the little up/down chevron pair, which is a *spinner*
/// beside the value rather than a control you can aim at, and it wears the
/// system's chrome rather than the window's. This is `FlatButtonStyle`'s
/// construction (`Stone.control` under a hover wash, `Stone.line` hairline, no
/// shadow) drawn once around all three parts, so the pill reads as one control
/// and each half still answers a hover of its own.
///
/// The value is set in `Mono` — IBM Plex Mono, the app's numeral face — for the
/// reason the bands' counts and the cards' timestamps are: it is read as a
/// value, and a proportional face makes it jitter sideways as it changes. The
/// column is pinned to the width of the widest value the caller can reach, so
/// the two glyphs never move either.
///
/// Accessibility is a real `Stepper`'s: the whole pill is one adjustable
/// element, so VoiceOver reads "Font size, 13" and the arrow keys work on it,
/// rather than announcing three unrelated children.
struct ValueStepper: View {
    /// What the value reads as — already formatted, since only the caller knows
    /// whether it is a count or a multiple.
    let value: String
    /// The widest value the caller can show, for the pinned column. Formatted
    /// the same way as `value`.
    let widest: String
    var canDecrease = true
    var canIncrease = true
    /// What each glyph does, said in words — the two buttons are a `−` and a
    /// `+`, which name themselves to nobody using VoiceOver.
    let decreaseLabel: String
    let increaseLabel: String
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    private static let height: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: canDecrease, label: decreaseLabel, action: onDecrease)

            Text(value)
                .font(Mono.font(.callout, weight: .medium))
                .foregroundStyle(.primary)
                // Pinned to the widest value rather than sized to this one, so
                // the glyphs either side hold still as the number changes —
                // the mono face keeps the digits from jittering, this keeps
                // the control from doing it.
                .frame(minWidth: valueWidth)
                .accessibilityHidden(true)

            button("plus", enabled: canIncrease, label: increaseLabel, action: onIncrease)
        }
        .frame(height: Self.height)
        .background(Stone.control, in: Capsule())
        .overlay { Capsule().strokeBorder(Stone.line, lineWidth: 0.5) }
        // One adjustable element, not three views: the two buttons are how a
        // pointer reaches the value, and a keyboard reaches it through this.
        .accessibilityElement(children: .ignore)
        .accessibilityValue(value)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrease { onIncrease() }
            case .decrement: if canDecrease { onDecrease() }
            @unknown default: break
            }
        }
    }

    /// Measured off the numeral face rather than counted in characters: "1.0"
    /// and "22" are different widths, and the caller's widest value is the only
    /// thing that knows which it is.
    @MainActor
    private var valueWidth: CGFloat {
        let font = Mono.nsFont(.callout, weight: .medium)
        let measured = NSAttributedString(string: widest, attributes: [.font: font]).size().width
        return measured.rounded(.up) + 12
    }

    private func button(
        _ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: Self.height, height: Self.height)
                .contentShape(Capsule())
        }
        .buttonStyle(StepperGlyphStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The two glyphs' own hover and press states, drawn *inside* the pill the
/// stepper already owns — `FlatButtonStyle`'s washes without its fill and
/// hairline, which belong to the whole control rather than to each half.
private struct StepperGlyphStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration)
    }

    /// A view rather than the style itself, `FlatButtonStyle`'s reason: a
    /// `ButtonStyle` is not a `View`, so `@State` on one is never tracked and
    /// hover would silently do nothing.
    private struct Surface: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .background(Capsule().fill(.primary.opacity(wash)))
                .animation(.easeInOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }

        private var wash: Double {
            guard isEnabled else { return 0 }
            if configuration.isPressed { return 0.12 }
            return hovering ? 0.06 : 0
        }
    }
}
