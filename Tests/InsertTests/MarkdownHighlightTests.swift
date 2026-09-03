import AppKit
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

    /// The two multi-unit literals the scanner looks for — `](` and `</u>` —
    /// are matched unit by unit against the source buffer rather than by
    /// slicing a fresh `Array` at every position stepped. The offsets are
    /// spelled out rather than looked up, because that arithmetic is the whole
    /// of what the rewrite could get wrong, and non-ASCII on both sides of the
    /// marker is what makes a units-versus-characters slip visible.
    func testMultiUnitLiteralsAreFoundAtTheRightUTF16Offsets() {
        let link = "🙂 véase [el enlace](https://ej.com) año 🙂"
        XCTAssertEqual(link.utf16.count, 43)
        let label = spans(link).filter { $0.style.colour == .link }
        XCTAssertEqual(label.map(\.range), [NSRange(location: 10, length: 9)])
        let markers = spans(link).filter { $0.style.colour == .marker }.map(\.range)
        XCTAssertEqual(
            markers,
            [NSRange(location: 9, length: 1), NSRange(location: 19, length: 17)]
        )

        let underlined = "🙂 <u>subrayado</u> año"
        XCTAssertEqual(underlined.utf16.count, 23)
        XCTAssertEqual(
            spans(underlined).filter(\.style.underline).map(\.range),
            [NSRange(location: 6, length: 9)]
        )
        XCTAssertEqual(
            spans(underlined).filter { $0.style.colour == .marker }.map(\.range),
            [NSRange(location: 3, length: 3), NSRange(location: 15, length: 4)]
        )
    }

    /// Every UTF-16 offset that is a real character boundary. The second unit
    /// of a surrogate pair is not one, and a range starting or ending there
    /// traps as soon as anything converts it to a `String.Index`.
    private func boundaries(of text: String) -> Set<Int> {
        var out: Set<Int> = [text.utf16.count]
        for index in text.indices { out.insert(index.utf16Offset(in: text)) }
        return out
    }

    func testNoSpanBoundaryLandsInsideASurrogatePair() {
        let text = """
        # 🙂 Título 🙂
        🙂 **negrita** 🙂 `código` 🙂 ~~ido~~ 🙂
        - [x] 🙂 hecho 🙂
        > 🙂 citado <u>🙂</u> 🙂
        🙂 [🙂 etiqueta 🙂](https://ej.com) 🙂
        """
        let allowed = boundaries(of: text)
        let scanned = spans(text)
        XCTAssertFalse(scanned.isEmpty)
        for span in scanned {
            XCTAssertTrue(
                allowed.contains(span.range.location),
                "span starts inside a surrogate pair at \(span.range.location)"
            )
            XCTAssertTrue(
                allowed.contains(span.range.upperBound),
                "span ends inside a surrogate pair at \(span.range.upperBound)"
            )
        }
    }

    // MARK: Fonts

    private func resolved(
        _ style: MarkdownHighlight.Style, base: NSFont = .systemFont(ofSize: 15)
    ) -> NSFont {
        MarkdownHighlight.font(for: style, base: base, typeface: .standard)
    }

    /// `font(for:)` is memoised, so the same key must always answer with the
    /// first font made for it — the purity `MemoCache` requires of its callers.
    func testAStyleResolvesToTheSameFontOnEveryCall() {
        let styles: [MarkdownHighlight.Style] = [
            .init(),
            .init(bold: true),
            .init(italic: true),
            .init(bold: true, italic: true),
            .init(mono: true),
            .init(heading: 2),
            .init(heading: 2, bold: true),
        ]
        for style in styles {
            let first = resolved(style)
            let second = resolved(style)
            XCTAssertEqual(first.fontName, second.fontName)
            XCTAssertEqual(first.pointSize, second.pointSize)
        }
    }

    /// The bold trait is **added** to the base's own traits, never set on its
    /// own: `withSymbolicTraits` replaces the whole set, so asking for `.bold`
    /// alone on an italic base drops the slant and both bases resolve to the
    /// very same bold face. Memoising must not have flattened it.
    func testBoldIsUnionedOntoTheBasesOwnTraits() throws {
        let upright = NSFont.systemFont(ofSize: 15)
        let italicBase = try XCTUnwrap(NSFont(
            descriptor: upright.fontDescriptor.withSymbolicTraits(
                upright.fontDescriptor.symbolicTraits.union(.italic)
            ),
            size: upright.pointSize
        ))
        XCTAssertNotEqual(italicBase.fontName, upright.fontName, "no italic base to test with")
        XCTAssertNotEqual(
            resolved(.init(bold: true), base: italicBase).fontName,
            resolved(.init(bold: true), base: upright).fontName,
            "the bold trait replaced the base's italic instead of joining it"
        )
    }

    /// Two bases that differ only in size must not share a cached font — the
    /// key carries the size, and a card read at 22pt is the case that proves it.
    func testTheBaseSizeIsPartOfTheKey() {
        let small = resolved(.init(bold: true), base: .systemFont(ofSize: 13))
        let large = resolved(.init(bold: true), base: .systemFont(ofSize: 22))
        XCTAssertEqual(small.pointSize, 13)
        XCTAssertEqual(large.pointSize, 22)
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

    // MARK: Headings' paragraph shape

    private func headingLines(_ text: String) -> [(String, Int)] {
        MarkdownHighlight.scan(text).headingLines.map {
            ((text as NSString).substring(with: $0.range), $0.level)
        }
    }

    /// The editor opens the same air above a heading that both renderers do
    /// (`MarkdownText.headingGap`), which needs the heading's *line* and its
    /// level rather than only the span that fonts it.
    func testAHeadingLineIsReportedWholeWithItsLevel() {
        // Mapped a member at a time, the way `listLines` is read above: a tuple
        // is not `Equatable`.
        let scanned = headingLines("intro\n## Two\n### Three\n- item")
        XCTAssertEqual(scanned.map(\.0), ["## Two", "### Three"])
        XCTAssertEqual(scanned.map(\.1), [2, 3])
        XCTAssertTrue(headingLines("#hashtag\n####### deep").isEmpty)
        XCTAssertTrue(headingLines("```\n# in a fence\n```").isEmpty)
    }

    func testAHeadingLineIsItsOwnSegmentCarryingTheHeadingGap() {
        let base = NSFont.systemFont(ofSize: 15)
        let out = MarkdownHighlight.segments("intro\n## Two\nafter\n### Three",
                                             base: base, typeface: .standard)
        XCTAssertEqual(out.map { String($0.text.characters) },
                       ["intro", "## Two", "after", "### Three"])
        XCTAssertEqual(out.map(\.gap),
                       [0, MarkdownText.headingGap(2), 0, MarkdownText.headingGap(3)])
        XCTAssertEqual(out.map(\.inset), [0, 0, 0, 0])
        XCTAssertGreaterThan(MarkdownText.headingGap(2), 0)
    }

    // MARK: A fenced block's size

    /// Inline code is monospaced at the **context's** size, because it sits on a
    /// line of prose; a fenced block is set at the code block's own size, which
    /// both renderers take from `MarkdownText.codeFont` and the editor used to
    /// take from the card's base. The two are a point apart on a note card,
    /// times the reading scale, so a card with a fenced block changed height on
    /// every open and close.
    func testAFencedSpanIsSetAtTheCodeBlocksSizeAndInlineCodeAtTheContexts() {
        let text = "run `ls` now\n```\nlet a = 1\n```"
        XCTAssertTrue(hasStyle("ls", in: text) { $0.mono && !$0.fenced })
        XCTAssertTrue(hasStyle("let a = 1", in: text) { $0.mono && $0.fenced })
        XCTAssertTrue(hasStyle("```", in: text) { $0.mono && $0.fenced })

        let base = NSFont.systemFont(ofSize: 15)
        for scale in [CardTextSize.scale(CardTextSize.range.lowerBound), 1,
                      CardTextSize.scale(CardTextSize.range.upperBound)] {
            let fenced = MarkdownHighlight.font(for: .init(mono: true, fenced: true),
                                                base: base, typeface: .standard, scale: scale)
            XCTAssertEqual(fenced, MarkdownText.codeFont(scale: scale), "scale \(scale)")
            let inline = MarkdownHighlight.font(for: .init(mono: true),
                                                base: base, typeface: .standard, scale: scale)
            XCTAssertEqual(inline.pointSize, base.pointSize, "scale \(scale)")
        }
    }
}
