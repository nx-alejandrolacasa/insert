import XCTest
@testable import Insert

/// Pins the two pieces of `MarkdownParser` that decide what a card *shows*
/// rather than how it is spaced: the line a collapsed task row teases
/// (`lead(_:)`), and the block structure of a quote, whose line breaks are part
/// of the quote. Both are `String`-in, values-out, so neither needs a view — the
/// same reason `MarkdownFormattingTests` can pin the ⌘B/⌘I rules.
final class MarkdownParserTests: XCTestCase {

    /// The lines of the first quote block in a source, or `nil` if there is none.
    private func quote(_ source: String) -> [String]? {
        for block in MarkdownParser.parse(source) {
            if case .quote(let lines) = block { return lines }
        }
        return nil
    }

    // MARK: Quotes keep their line breaks

    /// The shape a quote is actually written in — the quotation, then its
    /// attribution on its own line. These used to be joined with a space into one
    /// run-on line, which is the bug this pins.
    func testQuoteKeepsEachLine() {
        XCTAssertEqual(
            quote("> This is the quote\n> *Author*"),
            ["This is the quote", "*Author*"]
        )
    }

    /// Inline markers are the renderer's job, so the attribution's italics have to
    /// arrive here untouched.
    func testQuoteLeavesInlineMarkersAlone() {
        XCTAssertEqual(quote("> **bold** and `code`"), ["**bold** and `code`"])
    }

    /// A `>` on its own is the author's paragraph break, and survives as an empty
    /// line the renderer draws at full line height.
    func testQuoteKeepsAnInteriorBlankLine() {
        XCTAssertEqual(quote("> first\n>\n> second"), ["first", "", "second"])
    }

    /// Blank lines at the ends are not a break between anything, and would draw
    /// the quote bar past the text it marks.
    func testQuoteTrimsBlankLinesAtItsEnds() {
        XCTAssertEqual(quote(">\n> the line\n>"), ["the line"])
        XCTAssertEqual(quote(">"), [])
    }

    /// A quote still ends where the `>` lines end — this is about line breaks
    /// inside one, not about swallowing what follows.
    func testQuoteEndsAtTheFirstUnquotedLine() {
        let blocks = MarkdownParser.parse("> quoted\nplain again")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(quote("> quoted\nplain again"), ["quoted"])
        guard case .paragraph(let text) = blocks[1] else {
            return XCTFail("expected a paragraph after the quote, got \(blocks[1])")
        }
        XCTAssertEqual(text, "plain again")
    }

    // MARK: lead — block markers come off

    func testLeadOfPlainParagraph() {
        XCTAssertEqual(MarkdownParser.lead("Call the bank"), "Call the bank")
    }

    func testLeadOfHeadingLosesItsHashes() {
        XCTAssertEqual(MarkdownParser.lead("## Agenda\n\nfirst item"), "Agenda")
    }

    func testLeadOfBulletLosesItsMarker() {
        XCTAssertEqual(MarkdownParser.lead("- milk\n- eggs"), "milk")
    }

    func testLeadOfOrderedItemLosesItsNumber() {
        XCTAssertEqual(MarkdownParser.lead("1. book the room\n2. send invites"), "book the room")
    }

    func testLeadOfQuoteIsItsFirstLine() {
        XCTAssertEqual(MarkdownParser.lead("> This is the quote\n> *Author*"), "This is the quote")
    }

    /// A checkbox is *not* a block marker the parser knows, so it stays — the same
    /// thing the expanded render shows, and matching it is the point.
    func testLeadOfChecklistItemKeepsItsBox() {
        XCTAssertEqual(MarkdownParser.lead("- [ ] pack the car"), "[ ] pack the car")
    }

    // MARK: lead — inline markers stay for the renderer

    /// The row renders its teaser, so these must arrive intact. Printing them raw
    /// is what the collapsed task row used to do.
    func testLeadKeepsInlineMarkers() {
        XCTAssertEqual(MarkdownParser.lead("**Ship it** on `main`"), "**Ship it** on `main`")
    }

    // MARK: lead — blocks with no text of their own

    func testLeadSkipsALeadingRule() {
        XCTAssertEqual(MarkdownParser.lead("---\nafter the rule"), "after the rule")
    }

    func testLeadSkipsLeadingBlankLines() {
        XCTAssertEqual(MarkdownParser.lead("\n\n   \nfinally"), "finally")
    }

    func testLeadOfEmptyBodyIsEmpty() {
        XCTAssertEqual(MarkdownParser.lead(""), "")
        XCTAssertEqual(MarkdownParser.lead("   \n\n"), "")
    }

    /// Nothing but a rule has no line to show, and must come back empty rather
    /// than falling through to something else.
    func testLeadOfRuleOnlyBodyIsEmpty() {
        XCTAssertEqual(MarkdownParser.lead("***"), "")
    }

    func testLeadOfFencedCodeIsItsFirstLine() {
        XCTAssertEqual(MarkdownParser.lead("```\nswift build\nswift test\n```"), "swift build")
    }

    /// Hard-wrapped prose is one paragraph to the parser, so the teaser is the
    /// joined paragraph — the same text the expanded render lays out, which is why
    /// the expand chevron is measured off the render and not off the source.
    func testLeadJoinsHardWrappedLines() {
        XCTAssertEqual(MarkdownParser.lead("one two\nthree four"), "one two three four")
    }

    // MARK: Nested lists

    /// The items of the first list block in a source, or `nil` if there is none.
    private func list(_ source: String) -> [MarkdownParser.ListItem]? {
        for block in MarkdownParser.parse(source) {
            if case .list(let items) = block { return items }
        }
        return nil
    }

    /// A level is counted against the indents already open, not divided by a
    /// fixed unit, so two spaces and four spaces both mean one level down — the
    /// two conventions a Markdown editor writes, and Obsidian opens these files
    /// too.
    func testTwoAndFourSpaceIndentsBothMeanOneLevel() {
        for indent in ["  ", "    "] {
            XCTAssertEqual(
                list("* element 1\n\(indent)* element 1.1\n* element 2"),
                [
                    .init(level: 0, ordered: false, text: "element 1"),
                    .init(level: 1, ordered: false, text: "element 1.1"),
                    .init(level: 0, ordered: false, text: "element 2"),
                ],
                "indented with \(indent.count) spaces"
            )
        }
    }

    /// Deeper still, and back out again — the closing side is the half a stack of
    /// indents exists for, and returning to a level must not open a new one.
    func testNestingClosesBackToTheLevelItReturnsTo() {
        XCTAssertEqual(
            list("- a\n  - b\n    - c\n  - d\n- e")?.map(\.level),
            [0, 1, 2, 1, 0]
        )
    }

    /// Indentation the author didn't line up still nests by what it is *relative*
    /// to: three spaces then two is a level opened and closed, not a level and a
    /// half.
    func testMixedIndentationStillNestsByRelativeDepth() {
        XCTAssertEqual(list("- a\n   - b\n  - c")?.map(\.level), [0, 1, 1])
    }

    /// One run of list lines is one block whatever the markers do inside it —
    /// two blocks would put a paragraph's worth of space in the middle of a list.
    func testABulletSubListUnderANumberedItemStaysOneList() {
        let items = list("1. first\n   * note\n2. second")
        XCTAssertEqual(items?.count, 3)
        XCTAssertEqual(items?.map(\.ordered), [true, false, true])
        XCTAssertEqual(items?.map(\.level), [0, 1, 0])
    }

    /// Each level counts for itself: a sub-list starts again at 1 and its parent
    /// picks up where it left off.
    func testNumberingRestartsPerLevel() {
        let items = list("1. a\n  1. a1\n  1. a2\n1. b") ?? []
        XCTAssertEqual(MarkdownParser.numbering(items), [1, 1, 2, 2])
    }

    /// Bullets take no number, and reset the level they sit at rather than
    /// consuming one — otherwise a numbered run after a bullet sibling would skip.
    func testBulletsTakeNoNumberAndResetTheirLevel() {
        let items = list("1. a\n* aside\n1. b") ?? []
        XCTAssertEqual(MarkdownParser.numbering(items), [1, nil, 1])
    }

    /// Every marker the app writes nests the same way — `-`, `*`, `+` and both
    /// spellings of a number — since which one an author reaches for says nothing
    /// about the shape of their list.
    func testEveryMarkerNests() {
        for marker in ["-", "*", "+", "1.", "1)"] {
            let items = list("\(marker) parent\n  \(marker) child")
            XCTAssertEqual(items?.map(\.level), [0, 1], "marker \(marker)")
            XCTAssertEqual(items?.map(\.text), ["parent", "child"], "marker \(marker)")
        }
    }

    /// The teaser is still the first item's text, marker and indent dropped.
    func testLeadReadsANestedFirstItem() {
        XCTAssertEqual(MarkdownParser.lead("  * buried\n* after"), "buried")
    }
}
