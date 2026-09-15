import Foundation

/// A pipe table, as GitHub Flavored Markdown writes one: a header line, a
/// delimiter row (`| --- | :-: | --: |`), then one line per row, until a blank
/// line or a line with no `|` on it. This is the pure half of tables — reading
/// one out of a source, writing it back **aligned**, and the edits the bar and
/// the keys make to it — all over `Character` offsets like `MarkdownFormatting`,
/// so it needs no view and `MarkdownTableTests` can pin it.
///
/// **A table stays aligned in the source.** Every write pads each cell to its
/// column's width, so the pipes line up under one another the way Obsidian's
/// Advanced Tables or Prettier leave them; the editor draws table lines in the
/// monospaced face for the same reason (`MarkdownHighlight`), since padding
/// only aligns anything in a face where every character is one column wide.
/// Widths are counted in `Character`s — a wide CJK glyph or an emoji is one
/// column here and two on screen, which is the approximation every such tool
/// makes.
enum MarkdownTable {
    enum Alignment: Equatable {
        case left, center, right
    }

    struct Table: Equatable {
        /// One entry per column; `nil` is an unmarked column, which reads left.
        var alignments: [Alignment?]
        /// The header, then every body row — `rows[0]` is the header. Every row
        /// has exactly `columns` cells, padded with empty ones where the source
        /// had fewer, so nothing the author typed is dropped.
        var rows: [[String]]

        var columns: Int { alignments.count }
    }

    /// Where a table sits in a source: the character range of its lines (the
    /// final line's newline excluded) and the table read out of them.
    struct Region: Equatable {
        var range: Range<Int>
        var table: Table
        /// The character range of each source line, header first, delimiter
        /// second.
        var lines: [Range<Int>]
    }

    /// A caret inside a table: which source line (0 the header, 1 the
    /// delimiter, 2 and up the body rows), which column, and how far into the
    /// cell's trimmed content.
    struct Position: Equatable {
        var line: Int
        var column: Int
        var offset: Int
    }

    // MARK: Reading

    /// How many source lines the table starting at `index` spans, or `nil` when
    /// no table starts there — the one rule the parser, the highlighter and the
    /// editor share. Header and delimiter, then rows for as long as each line
    /// carries a pipe and isn't blank. A fence line ends the run: a table can't
    /// contain one, and the parser would otherwise swallow the code block.
    static func runLength<S: StringProtocol>(in lines: [S], at index: Int) -> Int? {
        guard index + 1 < lines.count,
              hasPipe(lines[index]), !isFence(lines[index]),
              isDelimiterRow(lines[index + 1])
        else { return nil }
        var end = index + 2
        while end < lines.count, hasPipe(lines[end]), !isFence(lines[end]),
              !lines[end].allSatisfy(\.isWhitespace) {
            end += 1
        }
        return end - index
    }

    /// The table in a run of source lines (`runLength` lines, header first).
    static func parse<S: StringProtocol>(_ lines: [S]) -> Table? {
        guard lines.count >= 2, isDelimiterRow(lines[1]) else { return nil }
        let alignments = cells(of: lines[1]).map(alignment(of:))
        var rows = [cells(of: lines[0])] + lines.dropFirst(2).map { cells(of: $0) }
        let columns = max(alignments.count, rows.map(\.count).max() ?? 0)
        rows = rows.map { $0 + Array(repeating: "", count: columns - $0.count) }
        var padded = alignments
        padded += Array(repeating: nil, count: columns - padded.count)
        return Table(alignments: padded, rows: rows)
    }

    /// The trimmed cells of one line: what sits between the pipes, the outer
    /// pipes optional as GFM has them. A `\|` is a pipe *inside* a cell.
    static func cells<S: StringProtocol>(of line: S) -> [String] {
        let chars = Array(line)
        return cellSpans(of: chars).map {
            String(chars[$0]).trimmingCharacters(in: .whitespaces)
        }
    }

    /// The raw span of each cell in a line — between separators, the outer
    /// pipes' empty ends dropped.
    static func cellSpans(of chars: [Character]) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var start = 0
        var i = 0
        while i < chars.count {
            if chars[i] == "|", i == 0 || chars[i - 1] != "\\" {
                spans.append(start..<i)
                start = i + 1
            }
            i += 1
        }
        spans.append(start..<chars.count)
        if let first = spans.first, first.upperBound < chars.count,
           chars[first].allSatisfy(\.isWhitespace) {
            spans.removeFirst()
        }
        if spans.count > 1, let last = spans.last, last.lowerBound > 0,
           chars[last].allSatisfy(\.isWhitespace) {
            spans.removeLast()
        }
        return spans
    }

    /// `| --- | :---: | ---: |` — at least one dash per cell, colons optional,
    /// and at least one pipe so a lone `---` stays the rule it is.
    static func isDelimiterRow<S: StringProtocol>(_ line: S) -> Bool {
        guard hasPipe(line) else { return false }
        let parts = cells(of: line)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { cell in
            var body = Substring(cell)
            if body.hasPrefix(":") { body = body.dropFirst() }
            if body.hasSuffix(":") { body = body.dropLast() }
            return !body.isEmpty && body.allSatisfy { $0 == "-" }
        }
    }

    private static func alignment(of delimiter: String) -> Alignment? {
        switch (delimiter.hasPrefix(":"), delimiter.hasSuffix(":")) {
        case (true, true): .center
        case (false, true): .right
        case (true, false): .left
        case (false, false): nil
        }
    }

    private static func hasPipe<S: StringProtocol>(_ line: S) -> Bool { line.contains("|") }

    private static func isFence<S: StringProtocol>(_ line: S) -> Bool {
        line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("```")
    }

    // MARK: Writing

    /// The narrowest a column is written — what `---` needs.
    static let minimumWidth = 3

    /// The table as aligned source, and where each cell's content starts in
    /// it: `cellStarts[line][column]`, character offsets from the start of the
    /// text, the delimiter row included so a caret on it can be put back.
    static func format(_ table: Table) -> (text: String, cellStarts: [[Int]]) {
        let widths = (0..<table.columns).map { column in
            max(minimumWidth, table.rows.map { $0[column].count }.max() ?? 0)
        }
        var out: [Character] = []
        var starts: [[Int]] = []

        func write(_ cells: [String], pad: (String, Int, Int) -> (Int, Int)) {
            var lineStarts: [Int] = []
            out.append("|")
            for (column, cell) in cells.enumerated() {
                let (before, after) = pad(cell, widths[column], column)
                out.append(" ")
                out += Array(repeating: " ", count: before)
                lineStarts.append(out.count)
                out += Array(cell)
                out += Array(repeating: " ", count: after)
                out += [" ", "|"]
            }
            starts.append(lineStarts)
        }

        func contentPadding(_ cell: String, _ width: Int, _ column: Int) -> (Int, Int) {
            let slack = width - cell.count
            switch table.alignments[column] {
            case .right: return (slack, 0)
            case .center: return (slack / 2, slack - slack / 2)
            case .left, nil: return (0, slack)
            }
        }

        write(table.rows[0], pad: contentPadding)
        out.append("\n")
        write(widths.enumerated().map { column, width in
            delimiter(width: width, alignment: table.alignments[column])
        }, pad: { _, _, _ in (0, 0) })
        for row in table.rows.dropFirst() {
            out.append("\n")
            write(row, pad: contentPadding)
        }
        return (String(out), starts)
    }

    private static func delimiter(width: Int, alignment: Alignment?) -> String {
        switch alignment {
        case nil: String(repeating: "-", count: width)
        case .left: ":" + String(repeating: "-", count: width - 1)
        case .right: String(repeating: "-", count: width - 1) + ":"
        case .center: ":" + String(repeating: "-", count: width - 2) + ":"
        }
    }

    // MARK: Locating

    /// The table the caret is in, if any. A caret at the very end of a table's
    /// last line counts as inside it; one on the line after does not.
    static func region(in text: String, caret: Int) -> Region? {
        region(in: Array(text), caret: caret)
    }

    static func region(in chars: [Character], caret: Int) -> Region? {
        let caret = max(0, min(caret, chars.count))
        var lineRanges: [Range<Int>] = []
        var start = 0
        for (i, ch) in chars.enumerated() where ch == "\n" {
            lineRanges.append(start..<i)
            start = i + 1
        }
        lineRanges.append(start..<chars.count)
        guard let caretLine = lineRanges.firstIndex(where: {
            caret >= $0.lowerBound && caret <= $0.upperBound
        }) else { return nil }

        let lines = lineRanges.map { String(chars[$0]) }
        var i = 0
        while i <= caretLine {
            if let length = runLength(in: lines, at: i) {
                if caretLine < i + length, let table = parse(Array(lines[i..<(i + length)])) {
                    let ranges = Array(lineRanges[i..<(i + length)])
                    return Region(
                        range: ranges.first!.lowerBound..<ranges.last!.upperBound,
                        table: table,
                        lines: ranges
                    )
                }
                i += length
            } else {
                i += 1
            }
        }
        return nil
    }

    /// Where the caret sits within `region`.
    static func position(of caret: Int, in region: Region, chars: [Character]) -> Position {
        let line = region.lines.lastIndex { caret >= $0.lowerBound } ?? 0
        let lineRange = region.lines[line]
        let lineChars = Array(chars[lineRange])
        let local = max(0, min(caret - lineRange.lowerBound, lineChars.count))
        let spans = cellSpans(of: lineChars)
        let column = spans.lastIndex { local >= $0.lowerBound } ?? 0
        guard spans.indices.contains(column) else {
            return Position(line: line, column: 0, offset: 0)
        }
        let span = spans[column]
        var contentStart = span.lowerBound
        while contentStart < span.upperBound, lineChars[contentStart].isWhitespace { contentStart += 1 }
        var contentEnd = span.upperBound
        while contentEnd > contentStart, lineChars[contentEnd - 1].isWhitespace { contentEnd -= 1 }
        let offset = max(0, min(local - contentStart, contentEnd - contentStart))
        return Position(line: line, column: column, offset: offset)
    }

    // MARK: Edits

    typealias Change = MarkdownFormatting.Change

    /// The table the caret is in written back aligned, with the caret put back
    /// in its cell — `nil` when the caret isn't in a table, and a change whose
    /// text equals the source when the table is already aligned (the caller
    /// compares). This is what runs after every edit inside a table.
    ///
    /// **The caret's cell keeps its trailing spaces up to the caret.** Every
    /// other cell is trimmed — that is what padding is — but this runs after
    /// every keystroke, so a space typed at the end of a cell would be trimmed
    /// away before the next word arrived and "foo bar" would come out "foobar".
    static func realign(_ text: String, caret: Int) -> Change? {
        let chars = Array(text)
        guard let region = region(in: chars, caret: caret) else { return nil }
        var table = region.table
        var at = position(of: caret, in: region, chars: chars)
        if at.line != 1 {
            let lineRange = region.lines[at.line]
            let lineChars = Array(chars[lineRange])
            let local = caret - lineRange.lowerBound
            let spans = cellSpans(of: lineChars)
            if spans.indices.contains(at.column) {
                let span = spans[at.column]
                var contentStart = span.lowerBound
                while contentStart < span.upperBound, lineChars[contentStart].isWhitespace {
                    contentStart += 1
                }
                let row = rowIndex(ofLine: at.line, in: table)
                let trimmedEnd = contentStart + table.rows[row][at.column].count
                let keptEnd = min(max(trimmedEnd, local), span.upperBound)
                if keptEnd > trimmedEnd {
                    table.rows[row][at.column] = String(lineChars[contentStart..<keptEnd])
                    at.offset = local - contentStart
                }
            }
        }
        return rewrite(chars, region: region, table: table, caret: at)
    }

    /// Tab and ⇧Tab: the next or previous cell, the delimiter row skipped. Tab
    /// on the last cell of the last row adds a row, so a table grows by tabbing
    /// through it. ⇧Tab on the first header cell stays put.
    static func moveCell(_ text: String, caret: Int, forward: Bool) -> Change? {
        let chars = Array(text)
        guard let region = region(in: chars, caret: caret) else { return nil }
        var table = region.table
        var at = position(of: caret, in: region, chars: chars)
        var row = rowIndex(ofLine: at.line, in: table)
        var column = at.column
        if forward {
            column += 1
            if column >= table.columns {
                column = 0
                row += 1
                if row >= table.rows.count { table.rows.append(emptyRow(table)) }
            }
        } else {
            column -= 1
            if column < 0 {
                if row == 0 { column = 0 } else { row -= 1; column = table.columns - 1 }
            }
        }
        at = Position(line: lineIndex(ofRow: row), column: column, offset: 0)
        return rewrite(chars, region: region, table: table, caret: at, selectCell: true)
    }

    /// Return inside a table: the same column one row down, adding a row at the
    /// bottom — and on an **empty** last row it ends the table instead, the
    /// way Return on an empty list item ends the list: the row goes and the
    /// caret lands on the plain line left where it was.
    static func returnInTable(_ text: String, caret: Int) -> Change? {
        let chars = Array(text)
        guard let region = region(in: chars, caret: caret) else { return nil }
        var table = region.table
        let at = position(of: caret, in: region, chars: chars)
        let row = rowIndex(ofLine: at.line, in: table)
        let isLast = row == table.rows.count - 1
        if isLast, row > 0, table.rows[row].allSatisfy(\.isEmpty) {
            table.rows.removeLast()
            let formatted = format(table).text
            let out = String(chars[..<region.range.lowerBound]) + formatted + "\n"
                + String(chars[region.range.upperBound...])
            let caret = region.range.lowerBound + formatted.count + 1
            return Change(text: out, selection: caret..<caret)
        }
        if isLast { table.rows.append(emptyRow(table)) }
        let target = Position(line: lineIndex(ofRow: row + 1), column: at.column, offset: 0)
        return rewrite(chars, region: region, table: table, caret: target, selectCell: true)
    }

    /// A row above or below the caret's. Above the header inserts *below* it,
    /// since a header is one thing; the delimiter row counts as the header.
    static func insertRow(_ text: String, caret: Int, below: Bool) -> Change? {
        let chars = Array(text)
        guard let region = region(in: chars, caret: caret) else { return nil }
        var table = region.table
        let at = position(of: caret, in: region, chars: chars)
        let row = rowIndex(ofLine: at.line, in: table)
        let insertAt = (below || row == 0) ? row + 1 : row
        table.rows.insert(emptyRow(table), at: insertAt)
        let target = Position(line: lineIndex(ofRow: insertAt), column: at.column, offset: 0)
        return rewrite(chars, region: region, table: table, caret: target)
    }

    /// Deletes the caret's row. The header can't go — deleting it would leave
    /// no table — and neither can the last body row when it would leave one;
    /// instead deleting the only body row empties it.
    static func deleteRow(_ text: String, caret: Int) -> Change? {
        let chars = Array(text)
        guard let region = region(in: chars, caret: caret) else { return nil }
        var table = region.table
        let at = position(of: caret, in: region, chars: chars)
        let row = rowIndex(ofLine: at.line, in: table)
        guard row > 0 else { return nil }
        if table.rows.count == 2 {
            table.rows[1] = emptyRow(table)
        } else {
            table.rows.remove(at: row)
        }
        let target = Position(line: lineIndex(ofRow: min(row, table.rows.count - 1)),
                              column: at.column, offset: 0)
        return rewrite(chars, region: region, table: table, caret: target)
    }

    /// A column left or right of the caret's, unmarked.
    static func insertColumn(_ text: String, caret: Int, after: Bool) -> Change? {
        let chars = Array(text)
        guard let region = region(in: chars, caret: caret) else { return nil }
        var table = region.table
        let at = position(of: caret, in: region, chars: chars)
        let column = after ? at.column + 1 : at.column
        table.alignments.insert(nil, at: column)
        table.rows = table.rows.map { var row = $0; row.insert("", at: column); return row }
        let target = Position(line: at.line, column: column, offset: 0)
        return rewrite(chars, region: region, table: table, caret: target)
    }

    /// Deletes the caret's column; the last one left is emptied rather than
    /// removed, since a table with no columns isn't one.
    static func deleteColumn(_ text: String, caret: Int) -> Change? {
        let chars = Array(text)
        guard let region = region(in: chars, caret: caret) else { return nil }
        var table = region.table
        let at = position(of: caret, in: region, chars: chars)
        if table.columns == 1 {
            table.rows = table.rows.map { _ in [""] }
            table.alignments = [nil]
        } else {
            table.alignments.remove(at: at.column)
            table.rows = table.rows.map { var row = $0; row.remove(at: at.column); return row }
        }
        let target = Position(line: at.line, column: min(at.column, table.columns - 1), offset: 0)
        return rewrite(chars, region: region, table: table, caret: target)
    }

    /// Steps the caret's column through unmarked → left → centre → right and
    /// round again. Left is written explicitly (`:---`) so the step is visible.
    static func cycleAlignment(_ text: String, caret: Int) -> Change? {
        let chars = Array(text)
        guard let region = region(in: chars, caret: caret) else { return nil }
        var table = region.table
        let at = position(of: caret, in: region, chars: chars)
        table.alignments[at.column] = switch table.alignments[at.column] {
        case nil: .left
        case .left: .center
        case .center: .right
        case .right: nil
        }
        return rewrite(chars, region: region, table: table, caret: at)
    }

    /// A fresh two-column table with a header and two rows, on its own lines
    /// below the selection — the divider's placement rules — with the caret in
    /// the first header cell.
    static func insertTable(_ text: String, selection: Range<Int>) -> Change {
        let chars = Array(text)
        let lo = max(0, min(selection.lowerBound, chars.count))
        var at = max(lo, min(selection.upperBound, chars.count))
        if at > lo, chars[at - 1] == "\n" { at -= 1 }
        var lineStart = at
        while lineStart > 0, chars[lineStart - 1] != "\n" { lineStart -= 1 }
        var lineEnd = at
        while lineEnd < chars.count, chars[lineEnd] != "\n" { lineEnd += 1 }
        let lineIsBlank = chars[lineStart..<lineEnd].allSatisfy(\.isWhitespace)

        var before = chars[..<(lineIsBlank ? lineStart : lineEnd)]
        while let last = before.last, last.isWhitespace { before = before.dropLast() }
        var after = chars[lineEnd...]
        while let blank = after.firstIndex(of: "\n"), after[..<blank].allSatisfy(\.isWhitespace) {
            after = after[(blank + 1)...]
        }

        let table = Table(alignments: [nil, nil],
                          rows: [["Column", "Column"], ["", ""], ["", ""]])
        let formatted = format(table)
        var out = Array(before)
        if !out.isEmpty { out += "\n\n" }
        let tableStart = out.count
        out += Array(formatted.text)
        out += "\n"
        if !after.isEmpty { out += "\n" + after }
        let cellStart = tableStart + formatted.cellStarts[0][0]
        return Change(text: String(out), selection: cellStart..<(cellStart + table.rows[0][0].count))
    }

    // MARK: Helpers

    /// `Position.line` counts the delimiter as line 1; `Table.rows` doesn't
    /// have it. Header is row 0 either way; a caret on the delimiter row acts
    /// on the header.
    private static func rowIndex(ofLine line: Int, in table: Table) -> Int {
        line <= 1 ? 0 : min(line - 1, table.rows.count - 1)
    }

    private static func lineIndex(ofRow row: Int) -> Int {
        row == 0 ? 0 : row + 1
    }

    private static func emptyRow(_ table: Table) -> [String] {
        Array(repeating: "", count: table.columns)
    }

    /// Writes `table` over `region` and places the caret at `caret` in the
    /// result — or selects that cell's whole content when `selectCell`, so a
    /// Tab into a filled cell overtypes it, as a spreadsheet does.
    private static func rewrite(
        _ chars: [Character], region: Region, table: Table, caret: Position,
        selectCell: Bool = false
    ) -> Change {
        let formatted = format(table)
        let out = String(chars[..<region.range.lowerBound]) + formatted.text
            + String(chars[region.range.upperBound...])
        let line = min(caret.line, formatted.cellStarts.count - 1)
        let starts = formatted.cellStarts[line]
        let column = min(caret.column, starts.count - 1)
        let start = region.range.lowerBound + starts[column]
        let content = line == 1 ? "" : table.rows[rowIndex(ofLine: line, in: table)][column]
        if selectCell, line != 1 {
            return Change(text: out, selection: start..<(start + content.count))
        }
        let offset = min(caret.offset, content.count)
        return Change(text: out, selection: (start + offset)..<(start + offset))
    }
}
