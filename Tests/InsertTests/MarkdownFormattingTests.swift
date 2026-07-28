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

    // MARK: Continuing a list on Return

    /// Presses Return with the caret written into the text as `|`, and gives the
    /// result back the same way, so each case reads as the keystroke it is.
    /// `nil` means "not a list item" — the editor lets Return through.
    private func pressReturn(_ marked: String) -> String? {
        let caret = marked.distance(from: marked.startIndex, to: marked.firstIndex(of: "|")!)
        let text = marked.replacingOccurrences(of: "|", with: "")
        guard let change = MarkdownFormatting.continueList(text, caret: caret) else { return nil }
        var out = Array(change.text)
        out.insert("|", at: change.selection.lowerBound)
        return String(out)
    }

    func testContinuesBullet() {
        XCTAssertEqual(pressReturn("- one|"), "- one\n- |")
    }

    func testContinuesStarAndPlusBullets() {
        XCTAssertEqual(pressReturn("* one|"), "* one\n* |")
        XCTAssertEqual(pressReturn("+ one|"), "+ one\n+ |")
    }

    func testContinuesOrderedAndIncrements() {
        XCTAssertEqual(pressReturn("1. one|"), "1. one\n2. |")
        XCTAssertEqual(pressReturn("9. nine|"), "9. nine\n10. |")
    }

    func testOrderedKeepsItsDelimiter() {
        XCTAssertEqual(pressReturn("3) three|"), "3) three\n4) |")
    }

    func testFollowingItemsAreNotRenumbered() {
        // Rewriting lines the caret isn't on is how an editor loses text, and
        // Markdown renders the list right either way.
        XCTAssertEqual(pressReturn("1. one|\n2. two"), "1. one\n2. |\n2. two")
    }

    func testCheckedTaskContinuesUnchecked() {
        XCTAssertEqual(pressReturn("- [x] done|"), "- [x] done\n- [ ] |")
        XCTAssertEqual(pressReturn("- [ ] todo|"), "- [ ] todo\n- [ ] |")
    }

    func testIndentIsPreserved() {
        XCTAssertEqual(pressReturn("    - deep|"), "    - deep\n    - |")
        XCTAssertEqual(pressReturn("  1. deep|"), "  1. deep\n  2. |")
    }

    func testEmptyItemEndsTheList() {
        XCTAssertEqual(pressReturn("- one\n- |"), "- one\n|")
        XCTAssertEqual(pressReturn("1. one\n2. |"), "1. one\n|")
        XCTAssertEqual(pressReturn("- [ ] |"), "|")
    }

    func testEmptyIndentedItemClearsTheWholeLine() {
        XCTAssertEqual(pressReturn("  - |"), "|")
    }

    func testWhitespaceOnlyItemCountsAsEmpty() {
        XCTAssertEqual(pressReturn("- one\n-  |"), "- one\n|")
    }

    func testReturnMidItemSplitsIt() {
        XCTAssertEqual(pressReturn("- one| two"), "- one\n- | two")
    }

    func testContinuesFromTheMiddleOfADocument() {
        XCTAssertEqual(pressReturn("- a\n- b|\n- c"), "- a\n- b\n- |\n- c")
    }

    func testCaretInsideTheMarkerDoesNothing() {
        XCTAssertNil(pressReturn("-| one"))
        XCTAssertNil(pressReturn("  |- one"))
    }

    func testNonListLinesDoNothing() {
        XCTAssertNil(pressReturn("just text|"))
        XCTAssertNil(pressReturn("# Heading|"))
        XCTAssertNil(pressReturn("-no space|"))
        XCTAssertNil(pressReturn("1.no space|"))
        XCTAssertNil(pressReturn("|"))
    }

    func testEmojiInAnItemKeepsTheCaretRight() {
        XCTAssertEqual(pressReturn("- 🚀 ship|"), "- 🚀 ship\n- |")
    }

    /// The welcome note, which is the first list most people will meet: bullets
    /// carrying `**bold**` and em dashes, in the middle of a longer document.
    func testTheWelcomeNotesList() {
        let body = """
            **Insert** keeps your projects, notes and tasks in one calm place.

            - The left column is your **projects** — add, rename, sort and filter them.|
            - The middle column is **notes** — pick a type.

            Everything is saved as plain Markdown you can open anywhere.
            """
        XCTAssertEqual(
            pressReturn(body)?.contains("filter them.\n- |\n- The middle column"),
            true
        )
    }

    /// The lines the trace was actually taken on — none of them lists, so Return
    /// has to stay an ordinary newline.
    func testProseLinesStayOrdinary() {
        XCTAssertNil(pressReturn("**hi**|"))
        XCTAssertNil(pressReturn("howdy!|"))
        XCTAssertNil(pressReturn("**nope...**|"))
    }
}
