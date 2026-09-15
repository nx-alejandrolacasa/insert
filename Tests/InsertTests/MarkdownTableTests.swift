import AppKit
import XCTest
@testable import Insert

/// Pins `MarkdownTable`: reading a pipe table out of a source, writing it back
/// aligned, and the edits the bar's table tools and the keys make. All of it
/// rewrites the user's Markdown around a caret, so the cases that matter are
/// the ones that would lose text — a ragged row, an escaped pipe, a space typed
/// at the end of a cell — and the ones that would put the caret in the wrong
/// cell afterwards.
final class MarkdownTableTests: XCTestCase {

    private let source = """
    Intro

    | Name | Qty |
    | --- | ---: |
    | Apple | 3 |
    | Pear | 12 |

    Outro
    """

    private func offset(of sub: String, in text: String, occurrence: Int = 0) -> Int {
        var search = text.startIndex
        var found: Range<String.Index>?
        for _ in 0...occurrence {
            found = text.range(of: sub, range: search..<text.endIndex)
            search = found!.upperBound
        }
        return text.distance(from: text.startIndex, to: found!.lowerBound)
    }

    private func selected(_ change: MarkdownFormatting.Change) -> String {
        String(Array(change.text)[change.selection])
    }

    private func lineOfCaret(_ change: MarkdownFormatting.Change) -> String {
        let chars = Array(change.text)
        var lo = change.selection.lowerBound
        while lo > 0, chars[lo - 1] != "\n" { lo -= 1 }
        var hi = change.selection.lowerBound
        while hi < chars.count, chars[hi] != "\n" { hi += 1 }
        return String(chars[lo..<hi])
    }

    // MARK: Reading

    func testRunNeedsADelimiterRowAndStopsAtABlankLine() {
        let lines = source.components(separatedBy: "\n")
        XCTAssertNil(MarkdownTable.runLength(in: lines, at: 0))
        XCTAssertEqual(MarkdownTable.runLength(in: lines, at: 2), 4)
        XCTAssertNil(MarkdownTable.runLength(in: ["| a |", "| b |"], at: 0))
        XCTAssertNil(MarkdownTable.runLength(in: ["---", "---"], at: 0), "a rule is not a table")
    }

    func testParseReadsAlignmentsAndPadsRaggedRows() {
        let table = MarkdownTable.parse(["a | b", ":-: | --:", "1", "x | y | z"])!
        XCTAssertEqual(table.alignments, [.center, .right, nil])
        XCTAssertEqual(table.rows, [["a", "b", ""], ["1", "", ""], ["x", "y", "z"]])
    }

    func testAnEscapedPipeStaysInsideItsCell() {
        XCTAssertEqual(MarkdownTable.cells(of: "| a \\| b | c |"), ["a \\| b", "c"])
    }

    func testParserEmitsATableBlockAndTheLeadIsItsFirstCell() {
        let blocks = MarkdownParser.parse(source)
        guard case .table(let table) = blocks[1] else { return XCTFail("\(blocks)") }
        XCTAssertEqual(table.rows[0], ["Name", "Qty"])
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(MarkdownParser.lead("| Only | Header |\n|---|---|"), "Only")
    }

    // MARK: Writing

    func testFormatPadsEveryColumnToItsWidestCellAndWritesTheAlignment() {
        let table = MarkdownTable.parse(["a | bb | c", ":-: | --: | ---", "long | 1 | x"])!
        XCTAssertEqual(MarkdownTable.format(table).text, """
        |  a   |  bb | c   |
        | :--: | --: | --- |
        | long |   1 | x   |
        """)
    }

    func testFormatNeverWritesADelimiterNarrowerThanThreeDashes() {
        let table = MarkdownTable.parse(["| a |", "| - |", "| b |"])!
        XCTAssertEqual(MarkdownTable.format(table).text, "| a   |\n| --- |\n| b   |")
    }

    // MARK: Locating

    func testRegionCoversTheTableLinesAndNothingElse() {
        let region = MarkdownTable.region(in: source, caret: offset(of: "Pear", in: source))!
        XCTAssertEqual(String(Array(source)[region.range]), """
        | Name | Qty |
        | --- | ---: |
        | Apple | 3 |
        | Pear | 12 |
        """)
        XCTAssertNil(MarkdownTable.region(in: source, caret: offset(of: "Outro", in: source)))
        XCTAssertNil(MarkdownTable.region(in: source, caret: 0))
    }

    func testPositionNamesTheLineColumnAndOffsetInTheCell() {
        let chars = Array(source)
        let region = MarkdownTable.region(in: chars, caret: offset(of: "Pear", in: source))!
        let caret = offset(of: "ear", in: source)
        XCTAssertEqual(
            MarkdownTable.position(of: caret, in: region, chars: chars),
            MarkdownTable.Position(line: 3, column: 0, offset: 1)
        )
        let qty = offset(of: "12", in: source) + 2
        XCTAssertEqual(
            MarkdownTable.position(of: qty, in: region, chars: chars),
            MarkdownTable.Position(line: 3, column: 1, offset: 2)
        )
    }

    // MARK: Re-aligning

    func testRealignPadsTheTableAndKeepsTheCaretInItsCell() {
        let caret = offset(of: "ear", in: source)
        let change = MarkdownTable.realign(source, caret: caret)!
        XCTAssertTrue(change.text.contains("| Apple |   3 |"))
        XCTAssertTrue(change.text.contains("| Pear  |  12 |"))
        XCTAssertTrue(change.text.hasPrefix("Intro\n\n"))
        XCTAssertTrue(change.text.hasSuffix("\n\nOutro"))
        XCTAssertEqual(String(Array(change.text)[change.selection.lowerBound...].prefix(3)), "ear")
    }

    func testRealignKeepsASpaceTypedAtTheEndOfTheCaretsCell() {
        let text = "| a | b |\n| --- | --- |\n| foo  | y |"
        let caret = offset(of: "foo ", in: text) + 4
        let change = MarkdownTable.realign(text, caret: caret)!
        XCTAssertEqual(lineOfCaret(change), "| foo  | y   |")
        XCTAssertEqual(change.selection.lowerBound, offset(of: "foo ", in: change.text) + 4)
    }

    func testRealignOfAnAlignedTableChangesNoText() {
        let aligned = MarkdownTable.realign(source, caret: offset(of: "Pear", in: source))!.text
        let again = MarkdownTable.realign(aligned, caret: offset(of: "Pear", in: aligned))!
        XCTAssertEqual(again.text, aligned)
    }

    // MARK: Keys

    func testTabMovesToTheNextCellAndSelectsIt() {
        let change = MarkdownTable.moveCell(source, caret: offset(of: "Apple", in: source), forward: true)!
        XCTAssertEqual(selected(change), "3")
    }

    func testTabOnTheLastCellAddsARow() {
        let change = MarkdownTable.moveCell(source, caret: offset(of: "12", in: source), forward: true)!
        XCTAssertTrue(change.text.contains("| Pear  |  12 |\n|       |     |\n\nOutro"))
        XCTAssertEqual(lineOfCaret(change), "|       |     |")
        XCTAssertEqual(change.selection.count, 0)
    }

    func testShiftTabMovesBackAndStaysOnTheFirstHeaderCell() {
        let back = MarkdownTable.moveCell(source, caret: offset(of: "Apple", in: source), forward: false)!
        XCTAssertEqual(selected(back), "Qty")
        let stay = MarkdownTable.moveCell(source, caret: offset(of: "Name", in: source), forward: false)!
        XCTAssertEqual(selected(stay), "Name")
    }

    func testReturnMovesDownAColumnAndGrowsTheTable() {
        let down = MarkdownTable.returnInTable(source, caret: offset(of: "3 |", in: source))!
        XCTAssertEqual(selected(down), "12")
        let grow = MarkdownTable.returnInTable(source, caret: offset(of: "Pear", in: source))!
        XCTAssertEqual(lineOfCaret(grow), "|       |     |")
    }

    func testReturnOnAnEmptyLastRowLeavesTheTable() {
        let text = "| a | b |\n| --- | --- |\n| x | y |\n|   |   |"
        let change = MarkdownTable.returnInTable(text, caret: text.count - 3)!
        XCTAssertEqual(change.text, "| a   | b   |\n| --- | --- |\n| x   | y   |\n")
        XCTAssertEqual(change.selection.lowerBound, change.text.count)
        XCTAssertNil(MarkdownTable.region(in: change.text, caret: change.text.count))
    }

    // MARK: The bar's tools

    func testRowsAreInsertedAboveAndBelowAndTheHeaderStaysFirst() {
        let below = MarkdownTable.insertRow(source, caret: offset(of: "Apple", in: source), below: true)!
        XCTAssertTrue(below.text.contains("| Apple |   3 |\n|       |     |\n| Pear  |  12 |"))
        let above = MarkdownTable.insertRow(source, caret: offset(of: "Pear", in: source), below: false)!
        XCTAssertTrue(above.text.contains("| Apple |   3 |\n|       |     |\n| Pear  |  12 |"))
        let header = MarkdownTable.insertRow(source, caret: offset(of: "Name", in: source), below: false)!
        XCTAssertTrue(header.text.contains("| ----- | --: |\n|       |     |\n| Apple"), header.text)
    }

    func testDeleteRowRefusesTheHeaderAndEmptiesTheLastBodyRow() {
        XCTAssertNil(MarkdownTable.deleteRow(source, caret: offset(of: "Name", in: source)))
        let gone = MarkdownTable.deleteRow(source, caret: offset(of: "Apple", in: source))!
        XCTAssertFalse(gone.text.contains("Apple"))
        XCTAssertTrue(gone.text.contains("Pear"))
        let only = "| a |\n| --- |\n| x |"
        let emptied = MarkdownTable.deleteRow(only, caret: only.count - 2)!
        XCTAssertEqual(emptied.text, "| a   |\n| --- |\n|     |")
    }

    func testColumnsAreInsertedEitherSideAndDeleted() {
        let right = MarkdownTable.insertColumn(source, caret: offset(of: "Apple", in: source), after: true)!
        XCTAssertTrue(right.text.contains("| Name  |     | Qty |"))
        XCTAssertTrue(right.text.contains("| ----- | --- | --: |"))
        XCTAssertEqual(lineOfCaret(right), "| Apple |     |   3 |")
        let left = MarkdownTable.insertColumn(source, caret: offset(of: "Apple", in: source), after: false)!
        XCTAssertTrue(left.text.contains("|     | Name  | Qty |"))
        let fewer = MarkdownTable.deleteColumn(source, caret: offset(of: "Qty", in: source))!
        XCTAssertTrue(fewer.text.contains("| Name  |\n| ----- |\n| Apple |\n| Pear  |"))
        let last = MarkdownTable.deleteColumn(fewer.text, caret: offset(of: "Apple", in: fewer.text))!
        XCTAssertTrue(last.text.contains("|     |\n| --- |\n|     |\n|     |"))
    }

    func testAlignmentCyclesThroughTheFourStates() {
        var text = source
        var seen: [String] = []
        for _ in 0..<4 {
            text = MarkdownTable.cycleAlignment(text, caret: offset(of: "Apple", in: text))!.text
            seen.append(String(text.components(separatedBy: "\n")[3].prefix(9)))
        }
        XCTAssertEqual(seen, ["| :---- |", "| :---: |", "| ----: |", "| ----- |"])
    }

    func testInsertTableLandsOnItsOwnLinesWithTheFirstHeaderCellSelected() {
        let change = MarkdownTable.insertTable("Some text", selection: 9..<9)
        XCTAssertEqual(change.text, """
        Some text

        | Column | Column |
        | ------ | ------ |
        |        |        |
        |        |        |

        """)
        XCTAssertEqual(selected(change), "Column")
        let empty = MarkdownTable.insertTable("", selection: 0..<0)
        XCTAssertTrue(empty.text.hasPrefix("| Column |"))
    }

    // MARK: The editor and the preview

    func testTableLinesAreMonospacedWithDimmedPipes() {
        let text = "| a | b |\n| --- | --- |\n| **x** | y |"
        let spans = MarkdownHighlight.spans(of: text)
        let mono = spans.filter { $0.style == MarkdownHighlight.tableStyle }
        XCTAssertEqual(mono.count, 3, "one whole-line span per table line")
        let pipes = spans.filter { $0.range.length == 1 && $0.style.colour == .marker && $0.style.mono }
        XCTAssertEqual(pipes.count, 6, "three pipes on each of the two content lines")
        XCTAssertTrue(spans.contains { $0.style.bold && $0.style.mono }, "emphasis inside a cell keeps the table face")
    }

    @MainActor
    func testRichTextRendersOneTabbedParagraphPerRowWithAGridDecoration() {
        let rendered = MarkdownRichText.render(source, config: .init(textStyle: .body, typeface: .standard, theme: .system))
        let rows = rendered.decorations.compactMap { decoration -> MarkdownRichText.TableRow? in
            if case .tableRow(let row) = decoration.kind { return row }
            return nil
        }
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows[0].header && rows[0].first && !rows[0].last)
        XCTAssertTrue(rows[2].last)
        XCTAssertEqual(rows[0].columns.count, 3, "two columns are three boundaries")
        XCTAssertEqual(rows[0].columns, rows[2].columns)
        let string = rendered.text.string
        XCTAssertTrue(string.contains("\tName\tQty\n\tApple\t3\n\tPear\t12"))
        let style = rendered.text.attribute(.paragraphStyle, at: rendered.decorations[0].range.location,
                                            effectiveRange: nil) as! NSParagraphStyle
        XCTAssertEqual(style.tabStops.count, 2)
        XCTAssertEqual(style.tabStops[1].alignment, .right)
    }
}

/// The table re-alignment runs right after the typing that caused it — the
/// one place in the editor a programmatic rewrite lands in the same event as
/// AppKit's typing-undo operation. Pinned on a real text view, because a
/// broken undo stack reads as "⌘Z does nothing" and no pure function can say
/// that. (A report of exactly that, September 2026, turned out to be the
/// Edit menu's undo manager — see `MarkdownEditorTests` — not this.)
@MainActor
final class MarkdownTableUndoTests: XCTestCase {

    func testTypingInATableThenUndoRestoresTheOriginalText() {
        let editor = MarkdownTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        let original = "| a   | b   |\n| --- | --- |\n| x   | y   |"
        editor.string = original
        editor.undoManager?.removeAllActions()

        let caret = (original as NSString).range(of: "x").upperBound
        editor.setSelectedRange(NSRange(location: caret, length: 0))
        editor.insertText("yz", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.string, "| a   | b   |\n| --- | --- |\n| xyz | y   |")
        XCTAssertTrue(editor.undoManager?.canUndo ?? false)

        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, original)

        editor.undoManager?.redo()
        XCTAssertEqual(editor.string, "| a   | b   |\n| --- | --- |\n| xyz | y   |")
    }

    /// One keystroke at a time, the way it really arrives: each one is
    /// coalesced into AppKit's typing operation, and each one is followed by
    /// a re-alignment that moves the text the next keystroke lands in.
    func testTypingKeyByKeyInATableThenUndoRestoresTheOriginalText() {
        let editor = MarkdownTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        let original = "| a   | b   |\n| --- | --- |\n| x   | y   |"
        editor.string = original
        editor.undoManager?.removeAllActions()

        // One undo group per keystroke, which is what the app's run loop does
        // (`groupsByEvent`) and what a test with no run loop doesn't.
        editor.undoManager?.groupsByEvent = false
        let caret = (original as NSString).range(of: "x").upperBound
        editor.setSelectedRange(NSRange(location: caret, length: 0))
        for key in ["y", "z", "w"] {
            editor.undoManager?.beginUndoGrouping()
            editor.insertText(key, replacementRange: editor.selectedRange())
            editor.undoManager?.endUndoGrouping()
        }
        XCTAssertEqual(editor.string, "| a    | b   |\n| ---- | --- |\n| xyzw | y   |")

        var steps = 0
        while editor.undoManager?.canUndo == true, steps < 10 {
            editor.undoManager?.undo()
            steps += 1
        }
        XCTAssertEqual(editor.string, original, "undo never got back to the original in \(steps) steps")
    }

    func testTypingOutsideATableStillUndoes() {
        let editor = MarkdownTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = "Plain prose"
        editor.undoManager?.removeAllActions()
        editor.setSelectedRange(NSRange(location: 11, length: 0))
        for key in [" ", "h", "i"] {
            editor.insertText(key, replacementRange: editor.selectedRange())
        }
        XCTAssertEqual(editor.string, "Plain prose hi")
        editor.undoManager?.undo()
        XCTAssertEqual(editor.string, "Plain prose")
    }
}

/// Typing into a table cell, one key at a time through the real text view:
/// the cell grows to fit, a space at the end of a full cell survives, and the
/// caret never leaves the cell being typed in. Reported as "the cursor jumps
/// to the next cell after 'This is'", and traced to the re-align reading the
/// caret before `insertText` had moved it.
@MainActor
final class MarkdownTableTypingTests: XCTestCase {
    func testTypingASentenceIntoAFreshCellGrowsTheCellAndKeepsTheCaretInIt() {
        let editor = MarkdownTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = MarkdownTable.insertTable("", selection: 0..<0).text
        let ns = editor.string as NSString
        let firstRow = ns.range(of: "|        |        |")
        editor.setSelectedRange(NSRange(location: firstRow.location + 2, length: 0))

        for character in "This is a cell" {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
        }

        let lines = editor.string.components(separatedBy: "\n")
        XCTAssertEqual(lines[0], "| Column         | Column |")
        XCTAssertEqual(lines[1], "| -------------- | ------ |")
        XCTAssertEqual(lines[2], "| This is a cell |        |")
        let caret = editor.selectedRange().location
        let cellEnd = (editor.string as NSString).range(of: "This is a cell").upperBound
        XCTAssertEqual(caret, cellEnd, "the caret stays at the end of the text it typed")
    }

    func testDeletingBackIntoACellShrinksItAgain() {
        let editor = MarkdownTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = "| Column  | b   |\n| ------- | --- |\n| This is | y   |"
        let caret = (editor.string as NSString).range(of: "This is").upperBound
        editor.setSelectedRange(NSRange(location: caret, length: 0))
        editor.deleteBackward(nil)
        // `deleteBackward` is a key binding, reached through `keyDown` in the
        // app; called directly it has no re-align of its own, so the pass is
        // asked for the way `keyDown` would.
        editor.realignTable()
        XCTAssertEqual(editor.string, "| Column | b   |\n| ------ | --- |\n| This i | y   |")
        XCTAssertEqual(editor.selectedRange().location,
                       (editor.string as NSString).range(of: "This i").upperBound)
    }
}
