import XCTest
@testable import Insert

/// Pins `MarkdownHighlight.spans(of:)`, the pure scanner behind the editor's
/// styled source. It decides what a body looks like *while it is being typed*,
/// and it fails silently in both directions: a missed match leaves structure
/// reading as flat text, and a false match dresses prose as syntax. The
/// interesting cases are the refusals — unclosed delimiters, `*` in
/// arithmetic, `_` inside an identifier — because those are where a naive
/// scanner corrupts the look of ordinary writing.
final class MarkdownHighlightTests: XCTestCase {

    private func spans(_ text: String) -> [MarkdownHighlight.Span] {
        MarkdownHighlight.spans(of: text)
    }

    /// Every style whose span covers exactly `sub` (first occurrence) — the
    /// tests read as "this substring wears that style".
    private func styles(of sub: String, in text: String) -> [MarkdownHighlight.Style] {
        let range = (text as NSString).range(of: sub)
        XCTAssertNotEqual(range.location, NSNotFound, "\(sub) not in \(text)")
        return spans(text).filter { $0.range == range }.map(\.style)
    }

    private func hasStyle(
        _ sub: String, in text: String, where predicate: (MarkdownHighlight.Style) -> Bool
    ) -> Bool {
        styles(of: sub, in: text).contains(where: predicate)
    }

    // MARK: Headings

    func testHeadingLineWearsTheHeadingFontAndDimsItsHashes() {
        let text = "## Meeting notes"
        XCTAssertTrue(hasStyle("## Meeting notes", in: text) { $0.heading == 2 && $0.colour == nil })
        XCTAssertTrue(hasStyle("##", in: text) { $0.heading == 2 && $0.colour == .marker })
    }

    func testSevenHashesIsNotAHeadingAndNeitherIsAHashWithoutASpace() {
        XCTAssertFalse(spans("####### deep").contains { $0.style.heading != nil })
        XCTAssertFalse(spans("#hashtag").contains { $0.style.heading != nil })
    }

    func testEmphasisInsideAHeadingKeepsTheHeadingSize() {
        let text = "# A **bold** claim"
        XCTAssertTrue(hasStyle("bold", in: text) { $0.heading == 1 && $0.bold })
    }

    // MARK: Emphasis

    func testStarRunLengthResolvesItalicBoldAndBoth() {
        XCTAssertTrue(hasStyle("i", in: "*i*") { $0.italic && !$0.bold })
        XCTAssertTrue(hasStyle("b", in: "**b**") { $0.bold && !$0.italic })
        XCTAssertTrue(hasStyle("bi", in: "***bi***") { $0.bold && $0.italic })
        XCTAssertTrue(hasStyle("**", in: "**b**") { $0.colour == .marker })
    }

    func testUnclosedEmphasisStaysPlain() {
        XCTAssertTrue(spans("**almost bold").isEmpty)
        XCTAssertTrue(spans("half *italic").isEmpty)
    }

    func testAStarFlankedBySpacesIsArithmeticNotEmphasis() {
        XCTAssertTrue(spans("2 * 3 * 4").isEmpty)
    }

    func testEmphasisNeverCrossesALine() {
        XCTAssertTrue(spans("open **here\nand close** there").isEmpty)
    }

    func testUnderscoreInsideAWordIsNotEmphasis() {
        XCTAssertTrue(spans("a snake_case_name in prose").isEmpty)
        XCTAssertTrue(hasStyle("word", in: "an _word_ apart") { $0.italic })
    }

    // MARK: Code

    func testInlineCodeIsMonoAndShieldsItsContentFromEmphasis() {
        let text = "run `ls *.md` now"
        XCTAssertTrue(hasStyle("ls *.md", in: text) { $0.mono })
        XCTAssertFalse(spans(text).contains { $0.style.italic })
    }

    func testFencedBlockIsMonoUntilTheClosingFence() {
        let text = "```\nlet *a* = 1\n```\n*after*"
        XCTAssertTrue(hasStyle("let *a* = 1", in: text) { $0.mono && !$0.italic })
        XCTAssertTrue(hasStyle("after", in: text) { $0.italic })
    }

    // MARK: Links

    func testLinkLabelTakesTheLinkColourAndTheRestDims() {
        let text = "see [the docs](https://example.com) first"
        XCTAssertTrue(hasStyle("the docs", in: text) { $0.colour == .link })
        XCTAssertTrue(hasStyle("](https://example.com)", in: text) { $0.colour == .marker })
    }

    func testABareBracketIsNotALink() {
        XCTAssertTrue(spans("an [aside] in prose").isEmpty)
    }

    // MARK: Blocks

    func testListMarkersDim() {
        XCTAssertTrue(hasStyle("- ", in: "- item") { $0.colour == .marker })
        XCTAssertTrue(hasStyle("3. ", in: "3. item") { $0.colour == .marker })
        XCTAssertTrue(hasStyle("- [ ] ", in: "- [ ] todo") { $0.colour == .marker })
    }

    func testACheckedItemStrikesItsTextThrough() {
        let text = "- [x] shipped"
        XCTAssertTrue(hasStyle("shipped", in: text) { $0.strikethrough && $0.colour == .marker })
        XCTAssertFalse(spans("- [ ] open").contains { $0.style.strikethrough })
    }

    func testABulletIsAMarkerNotEmphasis() {
        // The leading `* ` is the list marker, so it must not open italics.
        XCTAssertFalse(spans("* item one").contains { $0.style.italic })
    }

    func testQuoteMarkersDimAndNestedOnesComeWhole() {
        XCTAssertTrue(hasStyle(">", in: "> quoted") { $0.colour == .marker })
        XCTAssertTrue(hasStyle(">>", in: ">> deeper") { $0.colour == .marker })
    }

    func testARuleDims() {
        XCTAssertTrue(hasStyle("---", in: "---") { $0.colour == .marker })
        XCTAssertTrue(spans("--- not a rule").isEmpty)
    }

    // MARK: Decorations

    func testStrikethroughAndUnderlineSpans() {
        XCTAssertTrue(hasStyle("gone", in: "~~gone~~") { $0.strikethrough })
        XCTAssertTrue(hasStyle("kept", in: "<u>kept</u>") { $0.underline })
        XCTAssertTrue(hasStyle("<u>", in: "<u>kept</u>") { $0.colour == .marker })
    }

    // MARK: Offsets

    func testRangesSurviveEmoji() {
        // Spans are UTF-16 offsets; an emoji before the delimiter is the case
        // that breaks a scanner counting characters.
        let text = "🙂 keep **bold** styled"
        XCTAssertTrue(hasStyle("bold", in: text) { $0.bold })
    }

    // MARK: The revealed line

    private func revealed(_ text: String, _ selection: NSRange) -> String {
        (text as NSString).substring(with:
            MarkdownHighlight.revealedLines(in: text, selection: selection))
    }

    func testACaretRevealsWholeLineItSitsOn() {
        let text = "# One\n**two**\n> three"
        // Mid-line, at its start and at its end all name the same line — the
        // markers come in pairs, so half a line would be worse than none.
        XCTAssertEqual(revealed(text, NSRange(location: 9, length: 0)), "**two**\n")
        XCTAssertEqual(revealed(text, NSRange(location: 6, length: 0)), "**two**\n")
        XCTAssertEqual(revealed(text, NSRange(location: 13, length: 0)), "**two**\n")
    }

    func testACaretOnALineBoundaryBelongsToTheLineItStarts() {
        let text = "# One\n**two**"
        XCTAssertEqual(revealed(text, NSRange(location: 5, length: 0)), "# One\n")
        XCTAssertEqual(revealed(text, NSRange(location: 6, length: 0)), "**two**")
    }

    func testASelectionRevealsEveryLineItCrosses() {
        let text = "# One\n**two**\n> three"
        XCTAssertEqual(
            revealed(text, NSRange(location: 3, length: 8)), "# One\n**two**\n")
    }

    func testARangePastTheEndDoesNotTrap() {
        // The selection and the string are handed over separately, so they can
        // disagree for an update; answering an empty range beats crashing.
        XCTAssertEqual(revealed("", NSRange(location: 0, length: 0)), "")
        XCTAssertEqual(
            MarkdownHighlight.revealedLines(in: "ab", selection: NSRange(location: 9, length: 4)),
            NSRange(location: 0, length: 0))
        XCTAssertEqual(revealed("ab", NSRange(location: 1, length: 40)), "ab")
    }

    // MARK: Layout flag

    func testOnlyFontChangingStylesAffectLayout() {
        XCTAssertTrue(MarkdownHighlight.Style(heading: 1).affectsLayout)
        XCTAssertTrue(MarkdownHighlight.Style(bold: true).affectsLayout)
        XCTAssertTrue(MarkdownHighlight.Style(mono: true).affectsLayout)
        XCTAssertFalse(MarkdownHighlight.Style(strikethrough: true, colour: .marker).affectsLayout)
        XCTAssertFalse(MarkdownHighlight.Style(underline: true, colour: .link).affectsLayout)
    }

    // MARK: Lists' paragraph shape

    private func listLines(_ text: String) -> [(String, Bool)] {
        MarkdownHighlight.scan(text).listLines.map {
            ((text as NSString).substring(with: $0.range), $0.followsItem)
        }
    }

    func testOnlyAnItemUnderAnotherItemTakesTheGap() {
        XCTAssertEqual(
            listLines("- a\n- b\n  * c\n\n1. d\n2) e").map(\.1),
            [false, true, true, false, true]
        )
    }

    func testAnyOtherLineEndsTheRun() {
        XCTAssertEqual(listLines("- a\nprose\n- b").map(\.1), [false, false])
        XCTAssertEqual(listLines("- a\n> quoted\n- b").map(\.1), [false, false])
        XCTAssertTrue(listLines("> - quoted item\nprose").isEmpty)
        XCTAssertTrue(listLines("```\n- code\n```").isEmpty)
    }

    func testAListLineIsTheWholeLineIndentIncluded() {
        XCTAssertEqual(listLines("- a\n  - b").map(\.0), ["- a", "  - b"])
    }

    // MARK: The sizing proxy's segments

    private func segments(_ text: String) -> [String] {
        MarkdownHighlight.segments(text, base: .systemFont(ofSize: 15), typeface: .standard)
            .map { String($0.text.characters) }
    }

    func testEveryListLineIsItsOwnSegmentWearingTheEditorsInsetAndGap() {
        let base = NSFont.systemFont(ofSize: 15)
        let gap = MarkdownText.listGap(base)
        let inset = MarkdownText.listInset
        let out = MarkdownHighlight.segments("intro\n- a\n- b\n\n- c\nafter", base: base, typeface: .standard)
        XCTAssertEqual(out.map { String($0.text.characters) }, ["intro", "- a", "- b", " ", "- c", "after"])
        XCTAssertEqual(out.map(\.inset), [0, inset, inset, 0, inset, 0])
        XCTAssertEqual(out.map(\.gap), [0, 0, gap, 0, 0, 0])
        XCTAssertGreaterThan(gap, 0)
    }

    /// A `Text` of nothing has no height, where the editor shows every blank
    /// line at full height — including the one a final newline opens.
    func testEmptyLinesKeepTheirHeightAsSpaces() {
        XCTAssertEqual(segments("- a\n"), ["- a", " "])
        XCTAssertEqual(segments("- a\n\n\n- b"), ["- a", " \n ", "- b"])
        XCTAssertEqual(segments("plain\n"), ["plain\n"])
        XCTAssertEqual(segments("\n- a"), [" ", "- a"])
    }
}
