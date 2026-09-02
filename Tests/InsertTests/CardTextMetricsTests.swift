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
/// nothing — is arithmetic over four separate call sites; the last two tests
/// here lay the text out for real and compare, because reading them is exactly
/// how the off-by-one they guard against survived being written down.
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
}
