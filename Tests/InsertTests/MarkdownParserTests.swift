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
}
