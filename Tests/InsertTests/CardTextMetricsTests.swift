import AppKit
import SwiftUI
import XCTest
@testable import Insert

/// Pins the two reading settings — the size a card is set at and how far apart
/// its lines sit.
///
/// Both fail *quietly*, which is why they are here. A scale that isn't exactly
/// 1 at the default would re-resolve every font on a machine that never opened
/// the pane, and the only symptom would be cards that look slightly wrong to
/// somebody who changed nothing. And the rhythm rule — that a card's preview and
/// its source are laid out to the same height, so the flip between them moves
/// nothing — is arithmetic over four separate call sites, which is why the tests
/// under "The rhythm" lay both halves out **for real** and compare: reading the
/// arithmetic is exactly how the off-by-ones they guard against survived being
/// written down. `CardTextMetrics.current(for:)` is here for the same reason
/// from the other end — it is the one resolver those four sites now consume, so
/// it is checked against the derivations it replaced rather than trusted.
final class CardTextMetricsTests: XCTestCase {

    // MARK: The size

    func testTheDefaultSizeScalesNothing() {
        // Not "close to 1" — exactly 1, so `Card` asks for the same point size
        // it always did and gets back the same cached `NSFont`.
        XCTAssertEqual(CardTextSize.scale(CardTextSize.system), 1)
        XCTAssertEqual(
            Card.nsFont(.body, typeface: .rounded, scale: CardTextSize.scale(CardTextSize.system)),
            Card.nsFont(.body, typeface: .rounded)
        )
    }

    func testTheSystemBodySizeIsInsideTheRange() {
        // The default has to be reachable by the stepper, or the pane opens on a
        // value it cannot get back to.
        XCTAssertTrue(CardTextSize.range.contains(CardTextSize.system))
    }

    func testSizeIsClampedBothWays() {
        XCTAssertEqual(CardTextSize.clamped(2), CardTextSize.range.lowerBound)
        XCTAssertEqual(CardTextSize.clamped(400), CardTextSize.range.upperBound)
        XCTAssertEqual(CardTextSize.clamped(14), 14)
        // The scale clamps too: a value off the range must never reach a font.
        XCTAssertEqual(CardTextSize.scale(400), CardTextSize.scale(CardTextSize.range.upperBound))
    }

    func testEveryStyleGrowsByTheSameFactor() {
        // One number moves the whole card and nothing inside it changes
        // proportion — the reason the setting is a body size rather than a
        // per-style table.
        let scale = CardTextSize.scale(CardTextSize.range.upperBound)
        for style in [NSFont.TextStyle.body, .callout, .title2, .title3, .headline] {
            let plain = Card.nsFont(style, typeface: .standard).pointSize
            let scaled = Card.nsFont(style, typeface: .standard, scale: scale).pointSize
            XCTAssertEqual(scaled, plain * scale, accuracy: 0.001, "\(style)")
        }
    }

    func testChromeDoesNotFollowTheReadingSize() {
        // The column headings and the sidebar's project names take the reading
        // *face* and not the reading *size*: their rows belong to the window.
        // Asserted through the unscaled overload the three of them call, since
        // `Card.chrome` reads the store and would need the app running.
        for size in [CardTextSize.range.lowerBound, CardTextSize.range.upperBound] {
            let card = Card.nsFont(.title2, weight: .bold, typeface: .grotesk,
                                   scale: CardTextSize.scale(size))
            let chrome = Card.nsFont(.title2, weight: .bold, typeface: .grotesk)
            XCTAssertEqual(chrome.pointSize, NSFont.preferredFont(forTextStyle: .title2).pointSize)
            if size != CardTextSize.system {
                XCTAssertNotEqual(card.pointSize, chrome.pointSize)
            }
            // Same face either way — only the size is withheld.
            XCTAssertEqual(card.familyName, chrome.familyName)
        }
    }

    // MARK: The leading

    func testTheDefaultLineHeightAddsNothing() {
        XCTAssertEqual(CardLineHeight.standard, CardLineHeight.range.lowerBound)
        let font = Card.nsFont(.body, typeface: .rounded)
        XCTAssertEqual(MarkdownText.lineSpacing(font, lineHeight: CardLineHeight.standard), 0)
        // And the block gap is what it has always been: one line, rounded.
        XCTAssertEqual(
            MarkdownText.blankLine(font, lineHeight: CardLineHeight.standard),
            (font.ascender - font.descender + font.leading).rounded()
        )
    }

    func testLineHeightSnapsOntoTheStepAndStaysThere() {
        XCTAssertEqual(CardLineHeight.snapped(0.2), CardLineHeight.range.lowerBound)
        XCTAssertEqual(CardLineHeight.snapped(9), CardLineHeight.range.upperBound)
        // Exactly the bound, not a hair over it: the stepper decides whether "+"
        // is still live by comparing against the bound, and a tenth is not
        // representable in binary.
        XCTAssertFalse(CardLineHeight.snapped(1.99) > CardLineHeight.range.upperBound)
        XCTAssertTrue(CardLineHeight.range.contains(CardLineHeight.snapped(1.99)))
        XCTAssertEqual(CardLineHeight.snapped(1.43), 1.4, accuracy: 0.0001)
        // Idempotent — it runs on every launch, and a snap that drifted would
        // walk somebody's choice a tenth at a time.
        var value = CardLineHeight.range.lowerBound
        while value <= CardLineHeight.range.upperBound + 0.0001 {
            XCTAssertEqual(CardLineHeight.snapped(value), CardLineHeight.snapped(CardLineHeight.snapped(value)),
                           accuracy: 0.0001, "\(value)")
            value += CardLineHeight.step
        }
    }

    func testTheLabelIsAlwaysOneDecimal() {
        // The stepper's value column is pinned to the widest label, so a value
        // that dropped its decimal would change the control's width.
        XCTAssertEqual(CardLineHeight.label(1), "1.0")
        XCTAssertEqual(CardLineHeight.label(2), "2.0")
        XCTAssertEqual(CardLineHeight.label(1.4000001), "1.4")
        XCTAssertEqual(CardLineHeight.label(1.0).count, CardLineHeight.label(2.0).count)
    }

    // MARK: The rhythm

    /// The height `markdown` lays out to as the **editor** shows it: the raw
    /// source, one line per source line, with the base paragraph style the
    /// bridge installs.
    private func sourceHeight(_ markdown: String, font: NSFont, lineHeight: Double) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = MarkdownText.lineSpacing(font, lineHeight: lineHeight)
        return laidOut(NSAttributedString(string: markdown, attributes: [
            .font: font, .paragraphStyle: style,
        ]))
    }

    /// The height an attributed string lays out to at a width nothing wraps at.
    private func laidOut(_ text: NSAttributedString) -> CGFloat {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 4_000, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height
    }

    func testThePreviewAndTheSourceKeepOneRhythm() {
        // The card flips between these two on one frame, which is the one moment
        // they are compared — so two paragraphs, a blank line apart, have to
        // occupy the same height whichever half is showing. Checked at every
        // setting, because the gap is built from three terms and only the
        // default makes two of them zero.
        let markdown = "First paragraph.\n\nSecond paragraph."
        for typeface in Typeface.allCases {
            let font = Card.nsFont(.body, typeface: typeface)
            var lineHeight = CardLineHeight.range.lowerBound
            while lineHeight <= CardLineHeight.range.upperBound + 0.0001 {
                let config = MarkdownRichText.Config(
                    textStyle: .body, typeface: typeface, theme: .system,
                    scale: 1, lineHeight: lineHeight
                )
                let preview = laidOut(MarkdownRichText.render(markdown, config: config).text)
                let source = sourceHeight(markdown, font: font, lineHeight: lineHeight)
                // A point of slack: the preview's blank line is rounded once
                // where the source rounds each of its three fragments.
                XCTAssertEqual(preview, source, accuracy: 1,
                               "\(typeface) at \(CardLineHeight.label(lineHeight))")
                lineHeight += CardLineHeight.step
            }
        }
    }

    func testTheLineSpacingLandsBetweenLinesAndNowhereElse() {
        // The whole reason this is a `lineSpacing` and not a `lineHeightMultiple`
        // (which SwiftUI has no counterpart for): `n` lines gain `n - 1` gaps,
        // never `n`, so a single line is unaffected at every setting. The clamp
        // in `CollapsibleMarkdown` counts them the same way.
        let font = Card.nsFont(.body, typeface: .standard)
        // Measured as the *cost of one more line*, not as `n ×` the first one:
        // AppKit rounds the block's used height up once, so a single line
        // measures a shade taller than each of the lines inside a run of three.
        func perLine(_ lineHeight: Double) -> CGFloat {
            sourceHeight("one\ntwo\nthree", font: font, lineHeight: lineHeight)
                - sourceHeight("one\ntwo", font: font, lineHeight: lineHeight)
        }
        for lineHeight in [1.0, 1.5, 2.0] {
            let spacing = MarkdownText.lineSpacing(font, lineHeight: lineHeight)
            XCTAssertEqual(sourceHeight("one", font: font, lineHeight: lineHeight),
                           sourceHeight("one", font: font, lineHeight: 1), accuracy: 0.001,
                           "a single line gains nothing at \(lineHeight)")
            // Within a point: AppKit rounds a run's used height up, and it does
            // it once for the block rather than once per fragment, so the two
            // measurements are rounded differently. What is being pinned is
            // that an added line costs one gap and not two.
            XCTAssertEqual(perLine(lineHeight) - perLine(1), spacing, accuracy: 1,
                           "one gap per added line at \(lineHeight)")
        }
        XCTAssertEqual(MarkdownText.lineSpacing(font, lineHeight: 2),
                       MarkdownText.naturalLine(font).rounded(), accuracy: 1,
                       "double-spaced is one blank line's worth between every pair")
    }

    // MARK: The store

    /// Both settings sanitise what they are given, and this pins that the
    /// sanitising happens where it can't re-enter. It shipped as a write-back
    /// inside the property's own `didSet` — the ordinary Swift idiom, since a
    /// stored property's `didSet` doesn't fire for a write made within it — and
    /// `@Observable` makes that idiom recursive: the macro rewrites the stored
    /// property into a private one plus a computed façade, so assigning the
    /// façade from the private one's `didSet` runs the `didSet` again. It went
    /// ~74,600 frames deep and hit the stack guard on the first press of "+".
    ///
    /// So this test is really two: the values it asserts, and the fact that it
    /// *returns at all*. A regression doesn't fail an assertion — it takes the
    /// test process down with a segfault, which is the loudest failure there is.
    @MainActor
    func testTheStoreClampsWithoutReenteringItsOwnSetter() {
        let store = SettingsStore.shared
        let size = store.cardFontSize
        let height = store.cardLineHeight
        defer {
            store.cardFontSize = size
            store.cardLineHeight = height
        }

        store.cardFontSize = 999
        XCTAssertEqual(store.cardFontSize, CardTextSize.range.upperBound)
        store.cardFontSize = -3
        XCTAssertEqual(store.cardFontSize, CardTextSize.range.lowerBound)
        store.cardFontSize = CardTextSize.system
        XCTAssertEqual(store.cardFontSize, CardTextSize.system)

        store.cardLineHeight = 9
        XCTAssertEqual(store.cardLineHeight, CardLineHeight.range.upperBound, accuracy: 0.0001)
        store.cardLineHeight = 0
        XCTAssertEqual(store.cardLineHeight, CardLineHeight.range.lowerBound, accuracy: 0.0001)
        // Snapped to the offered tenths, and a value already on one stays put —
        // it runs on every write, so a snap that drifted would walk the setting.
        store.cardLineHeight = 1.44
        XCTAssertEqual(store.cardLineHeight, 1.4, accuracy: 0.0001)
        store.cardLineHeight = store.cardLineHeight
        XCTAssertEqual(store.cardLineHeight, 1.4, accuracy: 0.0001)
    }

    // MARK: The resolver

    /// `CardTextMetrics.current(for:)` replaced four independent derivations of
    /// the same five values — each panel's hidden sizing proxy, the editor's
    /// highlight config and the view-mode render's — and the reason it exists is
    /// that a term derived differently at one of them shows up as the card
    /// **changing shape** on the flip between reading and editing. So this
    /// re-derives all five the long way and compares, at every Text size and
    /// every Line height, in all five faces, for both styles a card body reads
    /// at.
    @MainActor
    func testTheResolverAgreesWithTheDerivationsItReplaced() {
        let store = SettingsStore.shared
        let size = store.cardFontSize
        let height = store.cardLineHeight
        let face = store.typeface
        defer {
            store.cardFontSize = size
            store.cardLineHeight = height
            store.typeface = face
        }

        for typeface in Typeface.allCases {
            store.typeface = typeface
            for points in CardTextSize.range {
                store.cardFontSize = points
                var lineHeight = CardLineHeight.range.lowerBound
                while lineHeight <= CardLineHeight.range.upperBound + 0.0001 {
                    store.cardLineHeight = lineHeight
                    for style in [NSFont.TextStyle.body, .callout] {
                        let metrics = CardTextMetrics.current(for: style, settings: store)
                        let scale = CardTextSize.scale(store.cardFontSize)
                        let nsFont = Card.nsFont(style, typeface: store.typeface, scale: scale)
                        let where_ = "\(typeface) \(style) \(points)pt × \(CardLineHeight.label(lineHeight))"
                        XCTAssertEqual(metrics.typeface, store.typeface, where_)
                        XCTAssertEqual(metrics.scale, scale, where_)
                        XCTAssertEqual(metrics.lineHeight, store.cardLineHeight,
                                       accuracy: 0.0001, where_)
                        XCTAssertEqual(metrics.nsFont, nsFont, where_)
                        XCTAssertEqual(metrics.nsFont.pointSize, nsFont.pointSize, where_)
                        XCTAssertEqual(metrics.font, Font(nsFont), where_)
                        XCTAssertEqual(
                            metrics.lineSpacing,
                            MarkdownText.lineSpacing(nsFont, lineHeight: store.cardLineHeight),
                            where_
                        )
                    }
                    lineHeight += CardLineHeight.step
                }
            }
        }
    }

    // MARK: The rhythm through a heading and a fenced block

    /// The editor's storage, styled exactly as the bridge styles it: the raw
    /// source, the highlighter's attributes, and the one base paragraph style
    /// both halves start from.
    @MainActor
    private func editorSource(
        _ markdown: String, typeface: Typeface, scale: CGFloat, lineHeight: Double
    ) -> NSTextStorage {
        let base = Card.nsFont(.body, typeface: typeface, scale: scale)
        let storage = NSTextStorage(string: markdown)
        MarkdownHighlight.apply(
            to: storage,
            config: MarkdownHighlight.Config(
                base: base,
                typeface: typeface,
                palette: .init(text: .labelColor, marker: .gray,
                               faintMarker: .lightGray, link: .linkColor),
                scale: scale,
                lineHeight: lineHeight
            ),
            paragraphStyle: MarkdownText.paragraphStyle(base: base, lineHeight: lineHeight)
        )
        return storage
    }

    private func previewRender(
        _ markdown: String, typeface: Typeface, scale: CGFloat, lineHeight: Double
    ) -> NSAttributedString {
        MarkdownRichText.render(markdown, config: MarkdownRichText.Config(
            textStyle: .body, typeface: typeface, theme: .system,
            scale: scale, lineHeight: lineHeight
        )).text
    }

    /// A **heading** must cost the two halves the same height, which is the fix
    /// this pins: both renderers opened 2pt above an h1/h2 and the editor —
    /// and its sizing proxy — opened none, so a note with three `##` was 6pt
    /// taller in view mode than the editor it flipped out of.
    ///
    /// Measured as a *difference of differences*, and that is deliberate. The
    /// two halves already sit up to a point apart per block boundary, because
    /// the preview rounds its blank line once where the source rounds each of
    /// its own fragments (the slack the rhythm test above allows for) — which
    /// is the same order as the 2pt being pinned. Replacing the heading with an
    /// ordinary paragraph holds the boundaries, the blank lines and the base
    /// font fixed and leaves only the heading, so the heading's contribution to
    /// the drift is measured on its own and has to be **zero**. Measured: 0 at
    /// every setting with the fix, exactly 2.0 without it.
    @MainActor
    func testAHeadingCostsTheTwoHalvesTheSameHeight() {
        let withHeading = "A paragraph.\n\n## Section\n\nAnother."
        let without = "A paragraph.\n\nSection\n\nAnother."
        for typeface in Typeface.allCases {
            for points in CardTextSize.range {
                let scale = CardTextSize.scale(points)
                var lineHeight = CardLineHeight.range.lowerBound
                while lineHeight <= CardLineHeight.range.upperBound + 0.0001 {
                    func drift(_ markdown: String) -> CGFloat {
                        laidOut(previewRender(markdown, typeface: typeface, scale: scale,
                                              lineHeight: lineHeight))
                            - laidOut(editorSource(markdown, typeface: typeface, scale: scale,
                                                   lineHeight: lineHeight))
                    }
                    XCTAssertEqual(
                        drift(withHeading), drift(without), accuracy: 0.001,
                        "\(typeface) at \(points)pt × \(CardLineHeight.label(lineHeight))"
                    )
                    lineHeight += CardLineHeight.step
                }
            }
        }
    }

    /// And the same air, read straight off both halves' heading paragraphs, at
    /// every level — including the two that get none.
    @MainActor
    func testEveryHeadingLevelOpensTheSameAirInBothHalves() {
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let markdown = "A paragraph.\n\n\(hashes) Section\n\nAnother."
            let preview = previewRender(markdown, typeface: .grotesk, scale: 1, lineHeight: 1)
            let source = editorSource(markdown, typeface: .grotesk, scale: 1, lineHeight: 1)
            func air(_ text: NSAttributedString, at sub: String) -> CGFloat? {
                let at = (text.string as NSString).range(of: sub).location
                return (text.attribute(.paragraphStyle, at: at, effectiveRange: nil)
                    as? NSParagraphStyle)?.paragraphSpacingBefore
            }
            XCTAssertEqual(air(preview, at: "Section"), MarkdownText.headingGap(level), "h\(level)")
            XCTAssertEqual(air(source, at: "\(hashes) Section"),
                           MarkdownText.headingGap(level), "h\(level)")
        }
    }

    /// A **fenced block** is set at its own size — `.callout` scaled, never the
    /// card's base — and the editor sized it off the base, which on a note card
    /// is `.body`: one point bigger, times the reading scale, on every line of
    /// every fenced block. The sizing proxy agreed with the editor, so nothing
    /// caught it.
    ///
    /// Pinned by taking the code line's font out of **both real outputs** and
    /// laying a line out in each. Whole-body equality is not available here and
    /// is not the claim: the preview elides the two fence lines and draws 10pt
    /// of padding above and below the block instead, so the two halves differ
    /// in height for a fenced body by construction. What must not differ is the
    /// size the code itself is set at.
    @MainActor
    func testAFencedBlockIsSetAtOneSizeInBothHalves() {
        let markdown = "```\nlet a = 1\n```"
        // The offset of the code line in the source: past the opening fence and
        // its newline.
        let codeLine = 4
        for typeface in Typeface.allCases {
            for points in CardTextSize.range {
                let scale = CardTextSize.scale(points)
                let where_ = "\(typeface) at \(points)pt"
                let preview = previewRender(markdown, typeface: typeface, scale: scale,
                                            lineHeight: 1)
                let source = editorSource(markdown, typeface: typeface, scale: scale,
                                          lineHeight: 1)
                let previewFont = preview.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                let sourceFont = source.attribute(.font, at: codeLine, effectiveRange: nil) as? NSFont
                XCTAssertEqual(previewFont, MarkdownText.codeFont(scale: scale), where_)
                XCTAssertEqual(sourceFont, previewFont, where_)
                // The measurement, not just the descriptor: one line of code
                // has to occupy the same height whichever half is showing.
                XCTAssertEqual(
                    laidOut(NSAttributedString(string: "let a = 1",
                                               attributes: [.font: previewFont as Any])),
                    laidOut(NSAttributedString(string: "let a = 1",
                                               attributes: [.font: sourceFont as Any])),
                    where_
                )
                // And it is genuinely a different size from the card's base, so
                // the test would have failed before the fix rather than passing
                // by coincidence.
                XCTAssertNotEqual(
                    sourceFont?.pointSize,
                    Card.nsFont(.body, typeface: typeface, scale: scale).pointSize,
                    where_
                )
            }
        }
    }
}
