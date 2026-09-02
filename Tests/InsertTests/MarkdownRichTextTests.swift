import AppKit
import XCTest
@testable import Insert

/// Pins what the preview's rich text promises: that the formatting a body is
/// written in reaches the pasteboard (bold and italic faces, heading sizes,
/// links, list indents) and that what *shouldn't* travel doesn't — the bullet
/// glyph and checkbox attachment become their plain spelling, no colour leaves
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

    func testListItemsIndentByLevelAndWrapUnderTheirText() {
        let text = render("- One\n  - Two").text
        let lines = text.string.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        let firstStyle = text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let secondStyle = text.attribute(.paragraphStyle, at: text.length - 1, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(firstStyle?.firstLineHeadIndent, 0)
        XCTAssertEqual(secondStyle?.firstLineHeadIndent, 13, "one level is the marker column: 5pt dot + 8pt gap")
        XCTAssertGreaterThan(firstStyle?.headIndent ?? 0, 0, "wrapped lines sit under the item's text, not its marker")
        XCTAssertEqual(firstStyle?.tabStops.first?.location, firstStyle?.headIndent)
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
        let oneLine = view.height(forWidth: 300)
        XCTAssertGreaterThan(oneLine, 0)
        let long = render(String(repeating: "word ", count: 60)).text
        view.textStorage?.setAttributedString(long)
        XCTAssertGreaterThan(view.height(forWidth: 200), oneLine * 2, "a long paragraph wraps at the width it is given")
        XCTAssertGreaterThan(view.height(forWidth: 200), view.height(forWidth: 400), "wider wraps less")
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

    @MainActor
    func testCopyWritesRichAndPlainFlavours() throws {
        let view = MarkdownPreviewView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.textStorage?.setAttributedString(render("- **Bold** item").text)
        view.setSelectedRange(NSRange(location: 0, length: view.textStorage?.length ?? 0))
        let pasteboard = NSPasteboard(name: .init("insert.tests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        guard view.writeSelection(to: pasteboard, types: [.rtf, .string]) else {
            // The pasteboard server is out of reach in a sandboxed test run.
            throw XCTSkip("the pasteboard refused the write")
        }
        XCTAssertEqual(pasteboard.string(forType: .string), "• Bold item")
        guard let rtf = pasteboard.data(forType: .rtf),
              let back = NSAttributedString(rtf: rtf, documentAttributes: nil) else {
            return XCTFail("no RTF flavour")
        }
        XCTAssertEqual(back.string, "• Bold item")
        let bold = (back.string as NSString).range(of: "Bold")
        let font = back.attribute(.font, at: bold.location, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
        pasteboard.releaseGlobally()
    }
}
