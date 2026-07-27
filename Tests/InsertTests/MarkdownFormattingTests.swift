import XCTest
@testable import Insert

/// Pins the selection-wrapping behind the formatting shortcuts (⌘B/⌘I/⌘U/⇧⌘X).
/// This code rewrites the user's Markdown around an arbitrary selection, so the
/// interesting cases are the ones that would corrupt text: delimiters landing on
/// whitespace (which un-parses them), unwrapping from either side of the
/// selection, and bold/italic sharing the `*` character.
final class MarkdownFormattingTests: XCTestCase {

    /// Offsets of `sub` within `text`, so the tests read as prose.
    private func range(of sub: String, in text: String) -> Range<Int> {
        let r = text.range(of: sub)!
        return text.distance(from: text.startIndex, to: r.lowerBound)
            ..< text.distance(from: text.startIndex, to: r.upperBound)
    }

    private func selected(_ change: MarkdownFormatting.Change) -> String {
        let chars = Array(change.text)
        return String(chars[change.selection])
    }

    // MARK: Wrapping

    func testWrapsBold() {
        let change = MarkdownFormatting.toggleWrap(
            "make this bold now", selection: range(of: "this bold", in: "make this bold now"),
            delimiter: "**"
        )
        XCTAssertEqual(change?.text, "make **this bold** now")
        XCTAssertEqual(change.map(selected), "this bold")
    }

    func testWrapKeepsEdgeWhitespaceOutside() {
        // "** bold **" doesn't parse, so the delimiters must hug the words.
        let text = "a  word  b"
        let change = MarkdownFormatting.toggleWrap(
            text, selection: range(of: " word ", in: text), delimiter: "**"
        )
        XCTAssertEqual(change?.text, "a  **word**  b")
        XCTAssertEqual(change.map(selected), "word")
    }

    func testWhitespaceOnlySelectionDoesNothing() {
        XCTAssertNil(MarkdownFormatting.toggleWrap("a   b", selection: 1..<4, delimiter: "**"))
    }

    func testEmptySelectionDoesNothing() {
        XCTAssertNil(MarkdownFormatting.toggleWrap("abc", selection: 1..<1, delimiter: "**"))
    }

    func testWrapUnderlineAsymmetricDelimiters() {
        let change = MarkdownFormatting.toggleWrap(
            "say word here", selection: range(of: "word", in: "say word here"),
            delimiter: "<u>", closing: "</u>"
        )
        XCTAssertEqual(change?.text, "say <u>word</u> here")
        XCTAssertEqual(change.map(selected), "word")
    }

    func testWrapStrikethrough() {
        let change = MarkdownFormatting.toggleWrap(
            "done", selection: 0..<4, delimiter: "~~"
        )
        XCTAssertEqual(change?.text, "~~done~~")
        XCTAssertEqual(change.map(selected), "done")
    }

    // MARK: Unwrapping

    func testUnwrapWhenDelimitersInsideSelection() {
        let text = "a **bold** b"
        let change = MarkdownFormatting.toggleWrap(
            text, selection: range(of: "**bold**", in: text), delimiter: "**"
        )
        XCTAssertEqual(change?.text, "a bold b")
        XCTAssertEqual(change.map(selected), "bold")
    }

    func testUnwrapWhenDelimitersSurroundSelection() {
        let text = "a **bold** b"
        let change = MarkdownFormatting.toggleWrap(
            text, selection: range(of: "bold", in: text), delimiter: "**"
        )
        XCTAssertEqual(change?.text, "a bold b")
        XCTAssertEqual(change.map(selected), "bold")
    }

    func testUnwrapUnderlineEitherSide() {
        let text = "a <u>word</u> b"
        let inside = MarkdownFormatting.toggleWrap(
            text, selection: range(of: "<u>word</u>", in: text), delimiter: "<u>", closing: "</u>"
        )
        XCTAssertEqual(inside?.text, "a word b")
        let outside = MarkdownFormatting.toggleWrap(
            text, selection: range(of: "word", in: text), delimiter: "<u>", closing: "</u>"
        )
        XCTAssertEqual(outside?.text, "a word b")
        XCTAssertEqual(outside.map(selected), "word")
    }

    func testToggleTwiceRoundTrips() {
        let once = MarkdownFormatting.toggleWrap("word", selection: 0..<4, delimiter: "~~")!
        let twice = MarkdownFormatting.toggleWrap(once.text, selection: once.selection, delimiter: "~~")!
        XCTAssertEqual(twice.text, "word")
        XCTAssertEqual(selected(twice), "word")
    }

    // MARK: Bold/italic share `*`

    func testItalicOnBoldStacksToBoldItalic() {
        let text = "a **bold** b"
        let change = MarkdownFormatting.toggleWrap(
            text, selection: range(of: "bold", in: text), delimiter: "*"
        )
        XCTAssertEqual(change?.text, "a ***bold*** b")
        XCTAssertEqual(change.map(selected), "bold")
    }

    func testItalicOffBoldItalicLeavesBold() {
        let text = "a ***bold*** b"
        let change = MarkdownFormatting.toggleWrap(
            text, selection: range(of: "bold", in: text), delimiter: "*"
        )
        XCTAssertEqual(change?.text, "a **bold** b")
    }

    func testBoldOffBoldItalicLeavesItalic() {
        let text = "a ***bold*** b"
        let change = MarkdownFormatting.toggleWrap(
            text, selection: range(of: "bold", in: text), delimiter: "**"
        )
        XCTAssertEqual(change?.text, "a *bold* b")
    }

    func testBoldOnItalicStacksToBoldItalic() {
        let text = "a *word* b"
        let change = MarkdownFormatting.toggleWrap(
            text, selection: range(of: "word", in: text), delimiter: "**"
        )
        XCTAssertEqual(change?.text, "a ***word*** b")
    }

    func testUnwrapBoldWithWholeSelection() {
        let text = "**bold**"
        let change = MarkdownFormatting.toggleWrap(text, selection: 0..<8, delimiter: "**")
        XCTAssertEqual(change?.text, "bold")
        XCTAssertEqual(change.map(selected), "bold")
    }

    func testStarsOnlySelectionDoesNothing() {
        XCTAssertNil(MarkdownFormatting.toggleWrap("a ** b", selection: 2..<4, delimiter: "*"))
    }

    func testEmojiSurvivesWrapping() {
        let text = "ship 🚀 now"
        let change = MarkdownFormatting.toggleWrap(
            text, selection: range(of: "🚀 now", in: text), delimiter: "**"
        )
        XCTAssertEqual(change?.text, "ship **🚀 now**")
        XCTAssertEqual(change.map(selected), "🚀 now")
    }

    func testSelectionClampedToTextBounds() {
        let change = MarkdownFormatting.toggleWrap("hi", selection: 0..<99, delimiter: "**")
        XCTAssertEqual(change?.text, "**hi**")
    }
}
