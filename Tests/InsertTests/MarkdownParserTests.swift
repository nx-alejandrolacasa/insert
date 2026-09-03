import AppKit
import SwiftUI
import XCTest
@testable import Insert

/// Pins the pieces of `MarkdownParser` that decide what a card *shows* rather
/// than how it is spaced: the line a collapsed task row teases (`lead(_:)`), and
/// the block structure of a quote, whose line breaks are part of the quote.
///
/// Plus the three pieces of `MarkdownText` every layout of a card's Markdown is
/// built from, which live here for the same reason: the one line splitter and
/// its UTF-16 offsets, the one base-paragraph-style factory and the rule it
/// states (a `lineSpacing`, never a `lineHeightMultiple`), and the emphasis
/// resolver on an already-weighted base. All of them are `String`-in,
/// values-out, so none needs a view — the same reason
/// `MarkdownFormattingTests` can pin the ⌘B/⌘I rules.
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

    /// The checkbox is a block marker now — the expanded render draws it as a
    /// glyph, not as brackets, and matching that render is the point. This test
    /// pinned the opposite while the parser didn't know the marker.
    func testLeadOfChecklistItemLosesItsBox() {
        XCTAssertEqual(MarkdownParser.lead("- [ ] pack the car"), "pack the car")
        XCTAssertEqual(MarkdownParser.lead("- [x] pack the car"), "pack the car")
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
                    .init(level: 0, ordered: false, text: "element 1", line: 0),
                    .init(level: 1, ordered: false, text: "element 1.1", line: 1),
                    .init(level: 0, ordered: false, text: "element 2", line: 2),
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

    // MARK: Checkboxes

    /// A checkbox item carries its state and loses its brackets; a plain item
    /// carries no state at all.
    func testCheckboxItemsParseWithTheirState() {
        XCTAssertEqual(
            list("- [ ] pack\n- [x] book\n- drive"),
            [
                .init(level: 0, ordered: false, text: "pack", checked: false, line: 0),
                .init(level: 0, ordered: false, text: "book", checked: true, line: 1),
                .init(level: 0, ordered: false, text: "drive", line: 2),
            ]
        )
    }

    /// Any non-space character between the brackets reads as checked — the rule
    /// Obsidian applies to its custom states (`- [-]`, `- [/]`…), and these files
    /// open there too.
    func testAnyNonSpaceStateCountsAsChecked() {
        XCTAssertEqual(list("- [-] parked\n- [/] half done")?.map(\.checked), [true, true])
    }

    /// Every bullet marker takes a checkbox, since `LineMarker` continues one on
    /// Return whichever bullet it follows.
    func testEveryBulletMarkerTakesACheckbox() {
        for marker in ["-", "*", "+"] {
            XCTAssertEqual(
                list("\(marker) [x] done")?.first,
                .init(level: 0, ordered: false, text: "done", checked: true),
                "marker \(marker)"
            )
        }
    }

    /// `- [x](url)` is a one-character link at the head of a plain bullet, not a
    /// ticked box — the `]` isn't followed by a space, which is the line between
    /// the two.
    func testALinkAtTheHeadOfABulletIsNotACheckbox() {
        XCTAssertEqual(
            list("- [x](https://example.com) the site")?.first,
            .init(level: 0, ordered: false, text: "[x](https://example.com) the site")
        )
    }

    /// A checkbox with nothing after it is still a checkbox — an empty item, the
    /// same shape an empty bullet parses to.
    func testABareCheckboxIsAnEmptyItem() {
        XCTAssertEqual(
            list("- [ ]")?.first,
            .init(level: 0, ordered: false, text: "", checked: false)
        )
    }

    /// Checkboxes nest like any other item, and mixing them into a list keeps it
    /// one block.
    func testCheckboxesNestAndShareTheList() {
        let items = list("- [ ] parent\n  - [x] child\n- plain")
        XCTAssertEqual(items?.map(\.level), [0, 1, 0])
        XCTAssertEqual(items?.map(\.checked), [false, true, nil])
    }

    // MARK: Toggling a checkbox from the render

    /// An item's recorded line is its index in the whole source, not within its
    /// block — it is what the rendered checkbox hands back to
    /// `toggleCheckbox(_:atLine:)`, which addresses the source.
    func testItemsRecordTheirSourceLine() {
        XCTAssertEqual(
            list("intro\n\n- [ ] first\n- [x] second")?.map(\.line),
            [2, 3]
        )
    }

    func testToggleChecksAnUncheckedBox() {
        XCTAssertEqual(
            MarkdownParser.toggleCheckbox("- [ ] pack\n- [x] book", atLine: 0),
            "- [x] pack\n- [x] book"
        )
    }

    func testToggleUnchecksACheckedBox() {
        XCTAssertEqual(
            MarkdownParser.toggleCheckbox("- [ ] pack\n- [x] book", atLine: 1),
            "- [ ] pack\n- [ ] book"
        )
    }

    /// A custom state is checked, so a click unchecks it — the same round Obsidian
    /// takes; the custom character is not preserved.
    func testToggleUnchecksACustomState() {
        XCTAssertEqual(MarkdownParser.toggleCheckbox("- [-] parked", atLine: 0), "- [ ] parked")
    }

    /// The indent is part of the line and must survive the flip, however it was
    /// typed.
    func testToggleKeepsTheIndent() {
        XCTAssertEqual(
            MarkdownParser.toggleCheckbox("- [ ] parent\n  - [ ] child", atLine: 1),
            "- [ ] parent\n  - [x] child"
        )
        XCTAssertEqual(
            MarkdownParser.toggleCheckbox("\t- [ ] tabbed", atLine: 0),
            "\t- [x] tabbed"
        )
    }

    /// A line that isn't a checkbox — or an index the body no longer has — edits
    /// nothing: a stale index from a render of an older body must not flip a
    /// bystander line.
    func testToggleRefusesANonCheckboxLine() {
        XCTAssertNil(MarkdownParser.toggleCheckbox("- plain bullet", atLine: 0))
        XCTAssertNil(MarkdownParser.toggleCheckbox("prose", atLine: 0))
        XCTAssertNil(MarkdownParser.toggleCheckbox("- [ ] only line", atLine: 3))
    }

    /// `- [x](url)` is a link at the head of a plain bullet to the parser, so the
    /// toggle must refuse it too — flipping it would corrupt the link.
    func testToggleRefusesALinkAtTheHeadOfABullet() {
        XCTAssertNil(MarkdownParser.toggleCheckbox("- [x](https://example.com) site", atLine: 0))
    }

    // MARK: The one line splitter

    private func split(_ source: String) -> [MarkdownText.Line] {
        MarkdownText.lines(of: source)
    }

    private func line(_ text: Substring, _ start: Int, _ end: Int) -> MarkdownText.Line {
        MarkdownText.Line(text: text, start: start, end: end)
    }

    /// `MarkdownText.lines(of:)` is what the parser, the highlighter's pass and
    /// the sizing proxy's segments all walk, and the offsets are the half that
    /// can be wrong silently: the highlighter attributes `NSRange`s over these
    /// lines, so an offset a unit out dresses the wrong character as syntax.
    func testTheSplitterCarriesEachLinesTextAndItsUTF16Offsets() {
        XCTAssertEqual(split("one\ntwo"), [line("one", 0, 3), line("two", 4, 7)])
        // A trailing newline opens one more, empty, line — which is what the
        // editor shows for it, and what `components(separatedBy:)` answers.
        XCTAssertEqual(split("one\n"), [line("one", 0, 3), line("", 4, 4)])
        XCTAssertEqual(split(""), [line("", 0, 0)])
        XCTAssertEqual(split("\n"), [line("", 0, 0), line("", 1, 1)])
        // An interior blank line is a line of its own, `start == end`.
        XCTAssertEqual(split("a\n\nb"), [line("a", 0, 1), line("", 2, 2), line("b", 3, 4)])
    }

    /// A `\r` stays on the line it ends, because the editor's passes address the
    /// storage as it stands and a normalisation on the way in would shift every
    /// offset after it. Walked over the unicode scalars for the reason recorded
    /// at the function: `"\r\n"` is a **single** `Character`, so a
    /// character-wise walk leaves a CRLF source as one long line.
    func testACarriageReturnStaysOnItsLineAndStillEndsIt() {
        XCTAssertEqual(split("a\r\nb"), [line("a\r", 0, 2), line("b", 3, 4)])
        XCTAssertEqual("a\r\nb".utf16.count, 4)
    }

    /// Offsets are UTF-16, and an emoji is two units of it — the case that
    /// breaks a splitter counting characters, and the one that would hand the
    /// highlighter a range splitting a surrogate pair.
    func testAnEmojiCostsTwoUnitsAndNoOffsetLandsInsideIt() {
        let source = "🙂 hola\n🙂"
        XCTAssertEqual(split(source), [line("🙂 hola", 0, 7), line("🙂", 8, 10)])
        XCTAssertEqual(source.utf16.count, 10)
        var boundaries: Set<Int> = [source.utf16.count]
        for index in source.indices { boundaries.insert(index.utf16Offset(in: source)) }
        for line in MarkdownText.lines(of: source) {
            XCTAssertTrue(boundaries.contains(line.start), "start \(line.start)")
            XCTAssertTrue(boundaries.contains(line.end), "end \(line.end)")
        }
    }

    // MARK: The base paragraph style

    /// The one factory both AppKit layouts of a card's Markdown start from, and
    /// the rule it exists to state: the reading leading is a **`lineSpacing`**,
    /// never a `lineHeightMultiple`. The multiple inflates every line including
    /// the first and SwiftUI has no counterpart for it, so the four places a
    /// card's text is laid out could not have been held to one rhythm through
    /// it — which is why this is asserted as an equality *and* as an absence.
    func testTheBaseParagraphStyleSpacesLinesAndNeverMultipliesThem() {
        for typeface in Typeface.allCases {
            let font = Card.nsFont(.body, typeface: typeface)
            var lineHeight = CardLineHeight.range.lowerBound
            while lineHeight <= CardLineHeight.range.upperBound + 0.0001 {
                let style = MarkdownText.paragraphStyle(base: font, lineHeight: lineHeight)
                XCTAssertEqual(style.lineSpacing,
                               MarkdownText.lineSpacing(font, lineHeight: lineHeight),
                               "\(typeface) at \(CardLineHeight.label(lineHeight))")
                XCTAssertEqual(style.lineHeightMultiple, 0,
                               "\(typeface) at \(CardLineHeight.label(lineHeight))")
                XCTAssertEqual(style.minimumLineHeight, 0)
                XCTAssertEqual(style.maximumLineHeight, 0)
                lineHeight += CardLineHeight.step
            }
        }
    }

    /// At 1.0 the lines sit at the **font's own leading** and nothing is added,
    /// which is what every card was drawn at before the setting existed: an
    /// install that never opens the pane must lay out identically.
    func testTheDefaultLeadingAddsNothingToTheFontsOwn() {
        for typeface in Typeface.allCases {
            let font = Card.nsFont(.body, typeface: typeface)
            XCTAssertEqual(
                MarkdownText.paragraphStyle(base: font, lineHeight: CardLineHeight.standard)
                    .lineSpacing,
                0, "\(typeface)"
            )
        }
    }

    // MARK: Emphasis on a weighted base

    /// `***both***` and `*emphasis*` **inside a heading** are the same case: the
    /// base is already bold, and the slant has to join that weight rather than
    /// replace it. Asking for the italic trait on its own replaces the whole
    /// symbolic set and drops the bold — and then the "is this a real italic?"
    /// name check believes the different name, which is how bold-italic once
    /// came out neither.
    ///
    /// Checked in all five faces because the slant arrives two different ways:
    /// a real italic face where one exists, and a shear in the **font matrix**
    /// under Rounded, which ships none.
    @MainActor
    func testEmphasisOnABoldBaseStaysBoldAndSlantsInEveryFace() {
        for typeface in Typeface.allCases {
            let bold = Card.nsFont(.body, weight: .bold, typeface: typeface)
            var source = AttributedString("both")
            source.inlinePresentationIntent = [.stronglyEmphasized, .emphasized]
            let run = MarkdownText.italicised(source, in: bold).runs.first

            // The face `italicised` is expected to have baked in: the editor's
            // own resolver, asked for both traits at once, which is what keeps
            // a run reading the same open and closed.
            let resolved = MarkdownHighlight.font(
                for: .init(bold: true, italic: true), base: bold, typeface: .standard
            )
            XCTAssertEqual(run?.font, Font(resolved), "\(typeface.label)")

            let plainItalic = Card.italic(Card.nsFont(.body, typeface: typeface))
            XCTAssertNotEqual(
                resolved.fontName, plainItalic.fontName,
                "\(typeface.label) bold-italic resolved to the same face as plain italic"
            )
            let slanted = resolved.fontName != bold.fontName
                || CTFontGetMatrix(resolved as CTFont).c != 0
            XCTAssertTrue(slanted, "\(typeface.label) is not slanted: \(resolved.fontName)")

            // And the emphasis intents are given up with the font, or SwiftUI
            // resolves them again on top and throws a synthesised oblique away.
            XCTAssertNil(run?.inlinePresentationIntent, "\(typeface.label)")
        }
    }
}
