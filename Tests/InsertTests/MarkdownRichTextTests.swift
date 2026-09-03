import AppKit
import SwiftUI
import XCTest
@testable import Insert

/// Pins what the preview's rich text promises: that the formatting a body is
/// written in reaches the pasteboard (bold and italic faces, heading sizes,
/// links, real lists) and that what *shouldn't* travel doesn't — the bullet
/// glyph leaves with its list and the checkbox attachment becomes its plain
/// spelling, no colour leaves
/// (a `labelColor` resolved in Dark Mode is white, invisible on a white page),
/// and no font leaves under a name only this app can resolve.
final class MarkdownRichTextTests: XCTestCase {
    private let config = MarkdownRichText.Config(textStyle: .body, typeface: .rounded, theme: .system)

    private func render(_ markdown: String) -> MarkdownRichText.Rendered {
        MarkdownRichText.render(markdown, config: config)
    }

    private func fonts(in text: NSAttributedString) -> [NSFont] {
        var fonts: [NSFont] = []
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let font = value as? NSFont { fonts.append(font) }
        }
        return fonts
    }

    // MARK: Rendering

    func testInlineMarkersBecomeFacesNotCharacters() {
        let text = render("Ship **it** *now* `fast`").text
        XCTAssertEqual(text.string, "Ship it now fast")
        let faces = fonts(in: text)
        XCTAssertTrue(faces.contains { $0.fontDescriptor.symbolicTraits.contains(.bold) }, "bold run")
        XCTAssertTrue(faces.contains { $0.fontDescriptor.symbolicTraits.contains(.monoSpace) }, "code run")
        // Rounded has no italic face, so the oblique is synthesised through the
        // matrix — the same `Card.italic` the SwiftUI preview uses.
        let upright = Card.nsFont(.body, typeface: .rounded)
        XCTAssertTrue(faces.contains { font in
            CTFontGetMatrix(font as CTFont).c != 0
                || (font.fontDescriptor.symbolicTraits.contains(.italic) && font.fontName != upright.fontName)
        }, "italic run")
    }

    func testHeadingsTakeThePreviewsHeadingFonts() {
        let text = render("# Title\n\nBody").text
        let heading = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(heading, MarkdownText.headingFont(1, typeface: .rounded))
        let body = text.attribute(.font, at: text.length - 1, effectiveRange: nil) as? NSFont
        XCTAssertEqual(body, Card.nsFont(.body, typeface: .rounded))
    }

    func testBlocksAreSeparatedByOneBlankLineOfTheFace() {
        let text = render("One\n\nTwo").text
        let font = Card.nsFont(.body, typeface: .rounded)
        let blank = (font.ascender - font.descender + font.leading).rounded()
        let first = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let second = text.attribute(.paragraphStyle, at: text.length - 1, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(first?.paragraphSpacing, blank)
        XCTAssertEqual(second?.paragraphSpacing, 0, "the last block has nothing under it")
    }

    func testLinksCarryTheirDestination() {
        let text = render("See [the docs](https://example.com/x).").text
        let range = (text.string as NSString).range(of: "the docs")
        XCTAssertEqual(text.attribute(.link, at: range.location, effectiveRange: nil) as? URL,
                       URL(string: "https://example.com/x"))
    }

    /// A body is Markdown from a folder anything can write to, so the render
    /// only draws a destination `MarkdownFormatting.isLinkDestination` names:
    /// `[Report](file:///Applications/Calculator.app)` would otherwise be one
    /// click from launching an application.
    func testOnlyAWebDestinationRendersAsALink() {
        let text = render("A [report](file:///Applications/Calculator.app) and [docs](https://example.com)").text
        XCTAssertEqual(text.string, "A report and docs")
        let string = text.string as NSString
        XCTAssertNil(text.attribute(.link, at: string.range(of: "report").location, effectiveRange: nil),
                     "a file:// destination is the plain words it wraps")
        XCTAssertEqual(text.attribute(.link, at: string.range(of: "docs").location, effectiveRange: nil) as? URL,
                       URL(string: "https://example.com"))
    }

    /// The same check where the click lands, since a `.link` attribute is only
    /// ever one attribute in a storage other code can write to.
    func testTheViewFollowsOnlyADestinationTheRenderWouldHaveDrawn() {
        XCTAssertNil(MarkdownPreviewView.openableDestination(
            URL(string: "file:///Applications/Calculator.app")!))
        XCTAssertNil(MarkdownPreviewView.openableDestination("file:///Applications/Calculator.app"))
        XCTAssertNil(MarkdownPreviewView.openableDestination(42))
        XCTAssertEqual(MarkdownPreviewView.openableDestination(URL(string: "https://example.com")!),
                       URL(string: "https://example.com"))
        XCTAssertEqual(MarkdownPreviewView.openableDestination("mailto:someone@example.com"),
                       URL(string: "mailto:someone@example.com"))
    }

    func testListItemsIndentByLevelAndWrapUnderTheirText() {
        let text = render("- One\n  - Two").text
        let lines = text.string.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        let firstStyle = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let secondStyle = text.attribute(.paragraphStyle, at: text.length - 1, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(firstStyle?.firstLineHeadIndent, MarkdownText.listInset,
                       "the whole list steps in, first level included, as the editor's does")
        XCTAssertEqual(secondStyle?.firstLineHeadIndent, MarkdownText.listInset + 13,
                       "one level is the marker column: 5pt dot + 8pt gap")
        XCTAssertGreaterThan(firstStyle?.headIndent ?? 0, firstStyle?.firstLineHeadIndent ?? 0,
                             "wrapped lines sit under the item's text, not its marker")
        XCTAssertEqual(firstStyle?.tabStops.first?.location, firstStyle?.headIndent)
    }

    /// The gap the editor opens before each list paragraph, so the flip between
    /// the modes moves nothing.
    func testItemsAreSeparatedByHalfALineAndTheListByABlankOne() {
        let base = Card.nsFont(.body, typeface: .rounded)
        let text = render("- One\n- Two\n\nAfter").text
        let one = (text.string as NSString).range(of: "One")
        let two = (text.string as NSString).range(of: "Two")
        let first = text.attribute(.paragraphStyle, at: one.location, effectiveRange: nil) as? NSParagraphStyle
        let last = text.attribute(.paragraphStyle, at: two.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(first?.paragraphSpacing, MarkdownText.listGap(base))
        XCTAssertEqual(last?.paragraphSpacing, (base.ascender - base.descender + base.leading).rounded(),
                       "the last item closes the block, so it takes the blank line")
    }

    func testACheckboxKnowsItsSourceLine() {
        let rendered = render("Intro\n\n- [ ] Open\n- [x] Done")
        let text = rendered.text
        var lines: [Int] = []
        text.enumerateAttribute(.markdownCheckbox, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let line = value as? Int { lines.append(line) }
        }
        XCTAssertEqual(lines, [2, 3])
        let done = (text.string as NSString).range(of: "Done")
        XCTAssertNotNil(text.attribute(.strikethroughStyle, at: done.location, effectiveRange: nil))
    }

    func testQuoteCodeAndRuleAreDecoratedOverTheirOwnRanges() {
        let rendered = render("> Quoted\n> *Author*\n\n```\nlet x = 1\n```\n\n---\n\nEnd")
        let kinds = rendered.decorations.map(\.kind)
        XCTAssertEqual(kinds, [.quote, .code, .rule])
        let string = rendered.text.string as NSString
        let quote = rendered.decorations[0].range
        XCTAssertEqual(string.substring(with: quote), "Quoted\nAuthor")
        let code = rendered.decorations[1].range
        XCTAssertEqual(string.substring(with: code), "let x = 1")
    }

    // MARK: Export

    func testMarkersLeaveAsTheirPlainSpelling() {
        let text = render("- One\n1. Two\n- [ ] Three\n- [x] Four\n\n---").text
        let export = MarkdownRichText.export(text)
        XCTAssertEqual(export.string, "• One\n1. Two\n☐ Three\n☑ Four\n---")
        XCTAssertFalse(export.string.contains("\u{FFFC}"), "no attachment character leaves the view")
        XCTAssertFalse(export.string.contains("\t"), "the marker tab goes with the marker")
    }

    func testListsLeaveAsRealLists() throws {
        let text = render("- One\n- Two\n  1. Sub\n- Three\n\nPara\n\n1. A\n2. B\n\n- [ ] Task").text
        let export = MarkdownRichText.export(text)
        XCTAssertEqual(export.string, "• One\n• Two\n1. Sub\n• Three\nPara\n1. A\n2. B\n☐ Task",
                       "the plain flavour keeps every marker spelled out")
        guard let rtf = export.rtf, let back = NSAttributedString(rtf: rtf, documentAttributes: nil) else {
            return XCTFail("no RTF")
        }
        XCTAssertEqual(back.string, "One\nTwo\nSub\nThree\nPara\nA\nB\n☐ Task",
                       "bullets and numbers are the list's to draw; a checkbox is still a character")
        var lists: [[String]] = []
        back.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: back.length)) { value, _, _ in
            lists.append(((value as? NSParagraphStyle)?.textLists ?? []).map(\.markerFormat.rawValue))
        }
        XCTAssertEqual(lists, [["{disc}"], ["{disc}", "{decimal}"], ["{disc}"], [], ["{decimal}"], ["{decimal}"], []])

        let html = try XCTUnwrap(export.html.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(html.components(separatedBy: "<ul").count - 1, 1)
        XCTAssertEqual(html.components(separatedBy: "<ol").count - 1, 2, "the sub-list and the second list are two lists")
        XCTAssertEqual(html.components(separatedBy: "<li").count - 1, 6)
        XCTAssertFalse(html.contains("•"), "no bullet character in the HTML either")
        XCTAssertTrue(html.contains("☐ Task"))
    }

    func testANumberedRunInterruptedByABulletRestartsItsList() throws {
        let text = render("1. A\n2. B\n- C\n1. D").text
        let html = try XCTUnwrap(MarkdownRichText.export(text).html.flatMap { String(data: $0, encoding: .utf8) })
        XCTAssertEqual(html.components(separatedBy: "<ol").count - 1, 2, "D starts a new numbered list, as the parser counts it")
        XCTAssertEqual(html.components(separatedBy: "<ul").count - 1, 1)
    }

    func testNoColourLeavesTheView() {
        let text = render("Plain **bold** [link](https://example.com)").text
        let export = MarkdownRichText.export(text)
        guard let rtf = export.rtf,
              let back = NSAttributedString(rtf: rtf, documentAttributes: nil) else {
            return XCTFail("no RTF")
        }
        var colours = 0
        back.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: back.length)) { value, _, _ in
            if value != nil { colours += 1 }
        }
        XCTAssertEqual(colours, 0)
        XCTAssertEqual(back.attribute(.link, at: back.length - 1, effectiveRange: nil) as? URL,
                       URL(string: "https://example.com"))
    }

    /// The sanitiser is an **allowlist**, so an attribute the renderer gains
    /// later is dropped by default rather than leaking into a pasted document —
    /// the one failure that is only ever seen in some other application. Pinned
    /// on the attributed string the flavours are written from rather than on
    /// the RTF, which drops attributes of its own and so can't tell "we dropped
    /// it" from "the format never carried it".
    func testExportKeepsOnlyThePortableAttributes() {
        let text = NSMutableAttributedString(
            attributedString: render("Plain **bold** [docs](https://example.com)").text
        )
        let whole = NSRange(location: 0, length: text.length)
        text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: whole)
        text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: whole)
        // Three the allowlist doesn't name: one of the renderer's own, one it
        // could plausibly gain, one it never will.
        text.addAttribute(.markdownCheckbox, value: 0, range: whole)
        text.addAttribute(.kern, value: 4.0, range: whole)
        text.addAttribute(.toolTip, value: "not ours to export", range: whole)

        let rich = MarkdownRichText.portableText(text)
        var keys: Set<NSAttributedString.Key> = []
        rich.enumerateAttributes(in: NSRange(location: 0, length: rich.length)) { attrs, _, _ in
            keys.formUnion(attrs.keys)
        }
        XCTAssertEqual(keys, MarkdownRichText.portableAttributes)
        XCTAssertEqual(keys, [.font, .link, .underlineStyle, .strikethroughStyle, .paragraphStyle],
                       "widening the allowlist is a decision, not a tweak")

        // And each of the five is really carrying its value out.
        let string = rich.string as NSString
        XCTAssertEqual(rich.attribute(.link, at: string.range(of: "docs").location, effectiveRange: nil) as? URL,
                       URL(string: "https://example.com"))
        let font = rich.attribute(.font, at: string.range(of: "bold").location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.familyName, "Helvetica Neue")
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        XCTAssertNotNil(rich.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertNotNil(rich.attribute(.strikethroughStyle, at: 0, effectiveRange: nil))
        XCTAssertNotNil(rich.attribute(.paragraphStyle, at: 0, effectiveRange: nil))
    }

    func testFormattingSurvivesTheRoundTripThroughRTF() {
        let text = render("# Head\n\nSome **bold** and *italic* and `code`").text
        guard let rtf = MarkdownRichText.export(text).rtf,
              let back = NSAttributedString(rtf: rtf, documentAttributes: nil) else {
            return XCTFail("no RTF")
        }
        XCTAssertEqual(back.string, "Head\nSome bold and italic and code")
        let faces = fonts(in: back)
        let body = Card.nsFont(.body, typeface: .rounded).pointSize
        XCTAssertTrue(faces.contains { $0.pointSize > body }, "the heading keeps its size")
        XCTAssertTrue(faces.contains { $0.fontDescriptor.symbolicTraits.contains(.bold) }, "bold survives")
        XCTAssertTrue(faces.contains { $0.fontDescriptor.symbolicTraits.contains(.italic) }, "italic survives")
        XCTAssertTrue(faces.contains { $0.fontDescriptor.symbolicTraits.contains(.monoSpace) }, "code stays monospaced")
        for face in faces {
            XCTAssertFalse(face.fontName.hasPrefix("."), "\(face.fontName) is a hidden system face no other app can name")
        }
    }

    func testPortableFontKeepsSizeAndTraits() {
        let bold = NSFont.boldSystemFont(ofSize: 17)
        let out = MarkdownRichText.portable(bold)
        XCTAssertEqual(out.pointSize, 17)
        XCTAssertTrue(out.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(out.familyName, "Helvetica Neue")
        let mono = MarkdownRichText.portable(.monospacedSystemFont(ofSize: 12, weight: .regular))
        XCTAssertEqual(mono.familyName, "Menlo")
    }

    // MARK: The view

    @MainActor
    func testTheViewMeasuresItsHeightAtTheProposedWidth() {
        let view = MarkdownPreviewView(usingTextLayoutManager: true)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainerInset = .zero
        let short = render("One line").text
        view.textStorage?.setAttributedString(short)
        let oneLine = view.usedSize(forWidth: 300).height
        XCTAssertGreaterThan(oneLine, 0)
        let long = render(String(repeating: "word ", count: 60)).text
        view.textStorage?.setAttributedString(long)
        XCTAssertGreaterThan(view.usedSize(forWidth: 200).height, oneLine * 2,
                             "a long paragraph wraps at the width it is given")
        XCTAssertGreaterThan(view.usedSize(forWidth: 200).height, view.usedSize(forWidth: 400).height,
                             "wider wraps less")
    }

    /// The ideal width is the longest line's, and it is only asked for when no
    /// width is proposed — a **zero** width is the row asking how narrow this
    /// body can go, and answering the natural width there would tell it the
    /// body can never be narrower than one unwrapped line.
    @MainActor
    func testTheNaturalWidthIsWiderThanAnyWrap() {
        let view = MarkdownPreviewView(usingTextLayoutManager: true)
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textStorage?.setAttributedString(render(String(repeating: "word ", count: 40)).text)
        let natural = view.usedSize(forWidth: .greatestFiniteMagnitude)
        let wrapped = view.usedSize(forWidth: 300)
        XCTAssertGreaterThan(natural.width, wrapped.width)
        XCTAssertLessThan(natural.height, wrapped.height, "unwrapped is one line")
        XCTAssertLessThanOrEqual(view.usedSize(forWidth: 300).width, 300)
    }

    /// Only the *width* answered to a zero-width proposal is zero. The height
    /// question a wrap can't answer there: laid out at one point the body
    /// stacks one character per line, a height nothing on screen will ever
    /// have, so it takes the ideal width's height.
    @MainActor
    func testAZeroWidthProposalTakesTheIdealWidthsHeight() throws {
        let body = String(repeating: "word ", count: 40)
        let view = MarkdownPreviewView(usingTextLayoutManager: true)
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textStorage?.setAttributedString(render(body).text)
        view.key = MarkdownPreviewView.Key(markdown: body, config: config)

        let zero = try XCTUnwrap(MarkdownPreview.size(for: ProposedViewSize(width: 0, height: nil), of: view))
        let ideal = try XCTUnwrap(MarkdownPreview.size(for: ProposedViewSize(width: nil, height: nil), of: view))
        let wrapped = try XCTUnwrap(MarkdownPreview.size(for: ProposedViewSize(width: 300, height: nil), of: view))

        XCTAssertEqual(zero.width, 0, "the row is still told the body can go as narrow as it likes")
        XCTAssertEqual(zero.height, ideal.height)
        XCTAssertLessThan(zero.height, wrapped.height, "unwrapped is one line; 300pt is several")
        XCTAssertEqual(wrapped.width, 300)
    }

    // MARK: Clicks

    /// A click in the card's empty space below the body is the card's "open
    /// me", and it stays one for a body whose last character is a marker's tab.
    /// An empty checklist item at the end of a note is exactly that, and the
    /// click used to be read as a flip of its box — which saves.
    @MainActor
    func testAClickBelowABodyEndingInAnEmptyCheckboxIsATap() throws {
        let view = MarkdownPreviewView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.onToggleCheckbox = { _ in }
        view.textStorage?.setAttributedString(render("Intro\n\n- [ ]").text)
        let size = view.usedSize(forWidth: 320)
        // The card is taller than its text, so the click lands under it.
        view.setFrameSize(CGSize(width: 320, height: size.height + 40))

        XCTAssertEqual(view.clickTarget(at: CGPoint(x: 160, y: size.height + 20)), .tap)

        // The mark itself still flips, so the guard hasn't taken the checkbox
        // with it — and that mark is the last run in this body.
        let mark = try XCTUnwrap(view.checkboxRects().last)
        XCTAssertEqual(view.clickTarget(at: CGPoint(x: mark.midX, y: mark.midY)), .checkbox(line: 2))
    }

    // MARK: Cursor

    /// A checkbox is the one run in a body that answers a click of its own —
    /// it flips its source line where everything else only starts a selection —
    /// so it wears the pointing hand. Pinned because the hand is invisible to
    /// every other kind of check: it is a cursor rect over a TextKit 2 segment,
    /// and it going missing looks exactly like a body with no checkbox in it.
    @MainActor
    func testOnlyTheCheckboxMarkersEarnThePointingHand() {
        let view = MarkdownPreviewView(usingTextLayoutManager: true)
        view.isEditable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textStorage?.setAttributedString(render("- [ ] Ship it\n- [x] Shipped\n\nA plain paragraph").text)
        let size = view.usedSize(forWidth: 320)
        view.setFrameSize(CGSize(width: 320, height: size.height))

        // No handler, no promise: a body whose boxes don't flip keeps the I-beam.
        XCTAssertTrue(view.checkboxRects().isEmpty)

        view.onToggleCheckbox = { _ in }
        let rects = view.checkboxRects().sorted { $0.minY < $1.minY }

        XCTAssertEqual(rects.count, 2, "one per item, and none for the paragraph")
        for rect in rects {
            XCTAssertGreaterThan(rect.width, 0)
            XCTAssertGreaterThan(rect.height, 0)
            // The mark and its tab, at the head of the line — not the item.
            XCTAssertLessThan(rect.minX, 20)
            XCTAssertLessThan(rect.width, 80)
        }
        // The view is flipped, so the second item's mark sits below the first's.
        XCTAssertGreaterThan(rects[1].minY, rects[0].minY)
        // And both are above the paragraph that follows them.
        XCTAssertLessThan(rects[1].maxY, size.height)
    }

    /// The hover itself, driven by a synthetic mouse-moved event: over the mark
    /// the view sets the hand, over the words it doesn't. What this *can't*
    /// reach is whether AppKit delivers the event in the real window — that is
    /// the tracking area's job, and the cursor rect it replaced failed exactly
    /// there. So the rule is pinned and the delivery is the thing to try first
    /// if the hand still never shows.
    @MainActor
    func testTheViewSetsTheHandOverTheMarkAndNotOverTheWords() throws {
        let view = MarkdownPreviewView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.onToggleCheckbox = { _ in }
        view.textStorage?.setAttributedString(render("- [ ] Ship it").text)
        let size = view.usedSize(forWidth: 320)
        view.setFrameSize(CGSize(width: 320, height: size.height))
        guard let mark = view.checkboxRects().first else { return XCTFail("no checkbox") }

        func moved(to point: CGPoint) throws -> NSCursor? {
            guard let event = NSEvent.mouseEvent(
                with: .mouseMoved, location: view.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 0, clickCount: 0, pressure: 0
            ) else { throw XCTSkip("no event to send") }
            view.mouseMoved(with: event)
            return NSCursor.current
        }

        XCTAssertEqual(try moved(to: CGPoint(x: mark.midX, y: mark.midY)), NSCursor.pointingHand)
        // The item's own words, well past the marker column.
        XCTAssertNotEqual(try moved(to: CGPoint(x: mark.maxX + 30, y: mark.midY)), NSCursor.pointingHand)
    }

    @MainActor
    func testABodyWithNoCheckboxesAsksForNoHand() {
        let view = MarkdownPreviewView(usingTextLayoutManager: true)
        view.isEditable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.onToggleCheckbox = { _ in }
        view.textStorage?.setAttributedString(render("- A bullet\n\n[a link](https://example.com)").text)
        _ = view.usedSize(forWidth: 320)

        XCTAssertTrue(view.checkboxRects().isEmpty)
    }

    @MainActor
    func testCopyWritesRichAndPlainFlavours() throws {
        let view = MarkdownPreviewView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.textStorage?.setAttributedString(render("- **Bold** item").text)
        view.setSelectedRange(NSRange(location: 0, length: view.textStorage?.length ?? 0))
        let pasteboard = NSPasteboard(name: .init("insert.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        guard view.writeSelection(to: pasteboard, types: [.rtf, .html, .string]) else {
            // The pasteboard server is out of reach in a sandboxed test run.
            throw XCTSkip("the pasteboard refused the write")
        }
        XCTAssertEqual(pasteboard.string(forType: .string), "• Bold item")
        guard let rtf = pasteboard.data(forType: .rtf),
              let back = NSAttributedString(rtf: rtf, documentAttributes: nil) else {
            return XCTFail("no RTF flavour")
        }
        XCTAssertEqual(back.string, "Bold item")
        let style = back.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(style?.textLists.count, 1, "the RTF carries the list, not a typed bullet")
        let bold = (back.string as NSString).range(of: "Bold")
        let font = back.attribute(.font, at: bold.location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        let html = pasteboard.data(forType: .html).flatMap { String(data: $0, encoding: .utf8) }
        XCTAssertTrue(html?.contains("<li") ?? false, "the HTML flavour is a list too")
        pasteboard.releaseGlobally()
    }
}
