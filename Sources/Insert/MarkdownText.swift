import SwiftUI

/// A compact, dependency-free Markdown renderer for note/task bodies. Supports
/// the "basic markdown" the plan calls for: headings, bold/italic/code/links
/// (inline), bullet & numbered lists, block quotes, fenced code, and rules.
/// Not a full CommonMark implementation — just the common shapes, rendered to
/// look at home in a Liquid Glass UI.
struct MarkdownText: View {
    let markdown: String
    /// The text style the body reads at, so a card's preview and its editor are
    /// the same size — note cards are `.body`, task cards `.callout`. Taken as an
    /// `NSFont.TextStyle` rather than a `Font` because the spacing below is
    /// measured off the very same font.
    var textStyle: NSFont.TextStyle = .body

    private var nsFont: NSFont { Card.nsFont(textStyle) }
    private var font: Font { Font(nsFont) }

    /// **One blank source line.**
    ///
    /// Two paragraphs are separated in Markdown by a blank line, which the editor
    /// shows at its full height; the preview has to leave the same gap or the
    /// card changes shape when it flips between the two, which is the one moment
    /// both are compared. It was a flat 8pt, half a line, so every paragraph
    /// break tightened on entering view mode. Measured off `nsFont` rather than
    /// written down, so the two modes can't drift apart if the style changes.
    private var blankLine: CGFloat {
        (nsFont.ascender - nsFont.descender + nsFont.leading).rounded()
    }

    var body: some View {
        let blocks = MarkdownParser.parse(markdown)
        VStack(alignment: .leading, spacing: blankLine) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownParser.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            let heading = headingFont(level)
            Self.inline(text, in: heading)
                .font(Font(heading))
                .padding(.top, level <= 2 ? 2 : 0)
        case .paragraph(let text):
            Self.inline(text, in: nsFont)
                .font(font)
        // Items sit on consecutive lines in the source with nothing between them,
        // so they get nothing here either — the 4pt this used to add was the list
        // loosening on the way *into* view mode while every paragraph tightened.
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        bulletDot
                        Self.inline(item, in: nsFont).font(font)
                    }
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(font)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Self.inline(item, in: nsFont).font(font)
                    }
                }
            }
        // A quote keeps its line breaks. Every `>` line used to be joined into one
        // paragraph, which read as a single run-on sentence for the shape quotes
        // are actually written in — the quotation on one line and its attribution,
        // usually italic, on the next. Spacing 0 for the list's reason: the lines
        // are consecutive in the source with nothing between them.
        case .quote(let lines):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.4)).frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        // A `>` on its own is a blank line *inside* the quote, and
                        // a space is how it keeps the font's full line height —
                        // exactly what the editor shows for the same source.
                        Self.inline(line.isEmpty ? " " : line, in: nsFont)
                            .font(font)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .foregroundStyle(.secondary)
            }
        case .code(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.06)))
        case .rule:
            Divider().padding(.vertical, 2)
        }
    }

    /// A bullet list's marker, drawn rather than typed. `Text("•")` is what this
    /// was, and that glyph measures **2.6pt** across at body size — a speck
    /// beside 13pt text, and the font is no lever on it: at 20pt the dot is still
    /// under 4pt, by which point the taller line has loosened the whole list. A
    /// circle's size is ours to pick, so it's 5pt.
    ///
    /// A shape has no baseline, so the row's `.firstTextBaseline` alignment would
    /// fall back to the dot's bottom edge and hang it below the text; the guide
    /// is declared here instead, putting the dot's centre on the body font's
    /// x-height — where the glyph's own centre sat, and read off the font so it
    /// tracks the text rather than pinning a number.
    private var bulletDot: some View {
        // Read outside the guide: its closure is `Sendable` and `nsFont` isn't.
        let xHeight = nsFont.xHeight
        return Circle()
            .fill(.secondary)
            .frame(width: 5, height: 5)
            .alignmentGuide(.firstTextBaseline) { d in
                d.height / 2 + xHeight / 2
            }
    }

    /// The inline half of the renderer — bold, italic, code, links, and the `<u>`
    /// span ⌘U writes — as a single `Text`.
    ///
    /// `static`, and reachable outside this view, because a **one-line teaser** is
    /// a real use for it on its own: the collapsed task row shows the first line
    /// of a body and has to show it rendered, not as source. It reads no instance
    /// state — but it does need the font the caller will draw it in, so that italic
    /// spans can be given a face that actually slants (see `italicised`).
    static func inline(_ text: String, in font: NSFont) -> Text {
        // Markdown has no underline; ⌘U writes `<u>…</u>` (the Obsidian
        // convention), which `AttributedString` would show literally — so pull
        // those spans out and underline them, parsing the rest as usual.
        guard text.contains("<u>") else { return inlineFragment(text, in: font) }
        var result = Text(verbatim: "")
        var rest = Substring(text)
        while let open = rest.range(of: "<u>"),
              let close = rest.range(of: "</u>", range: open.upperBound..<rest.endIndex) {
            let before = inlineFragment(String(rest[..<open.lowerBound]), in: font)
            let underlined = inlineFragment(
                String(rest[open.upperBound..<close.lowerBound]), in: font
            ).underline()
            result = Text("\(result)\(before)\(underlined)")
            rest = rest[close.upperBound...]
        }
        return Text("\(result)\(inlineFragment(String(rest), in: font))")
    }

    private static func inlineFragment(_ text: String, in font: NSFont) -> Text {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(italicised(attr, in: font))
        }
        return Text(text)
    }

    /// Gives every *italic* run an explicit font, because SwiftUI resolving the
    /// emphasis itself is not enough: a design with no italic face falls back to
    /// the upright one and the emphasis vanishes. SF Rounded is exactly that case
    /// and it is the app's default face, so `> *Author*` under a quote drew as
    /// plain text. `Card.italic(_:)` answers with a real italic where one exists
    /// and a synthesised oblique where none does.
    ///
    /// Bold-italic takes the bold face *then* slants it, so `***both***` keeps its
    /// weight. **Code** spans are left alone — a run that is both `code` and
    /// emphasised would otherwise lose its monospacing, which matters more than its
    /// slant. The ranges are collected before anything is written, since the
    /// string can't be mutated while its own `runs` are being walked.
    private static func italicised(_ attributed: AttributedString, in font: NSFont) -> AttributedString {
        let italicRuns = attributed.runs.compactMap {
            run -> (Range<AttributedString.Index>, InlinePresentationIntent)? in
            guard let intent = run.inlinePresentationIntent,
                  intent.contains(.emphasized),
                  !intent.contains(.code) else { return nil }
            return (run.range, intent)
        }
        guard !italicRuns.isEmpty else { return attributed }

        var out = attributed
        for (range, intent) in italicRuns {
            // `***both***` has to be weighted *before* it's slanted, and by us:
            // leaving the bold to SwiftUI meant it re-resolved the font and dropped
            // the synthesised oblique, so bold-italic came out bold and upright. The
            // trait is added to the card font's own descriptor rather than replacing
            // it, which keeps the design and the one-storey `a`, and it lands on the
            // same face SwiftUI's own bold would (`.SFNSRounded-Semibold`), so a
            // `**bold**` run beside it matches.
            let base = intent.contains(.stronglyEmphasized)
                ? NSFont(
                    descriptor: font.fontDescriptor.withSymbolicTraits(
                        font.fontDescriptor.symbolicTraits.union(.bold)
                    ),
                    size: font.pointSize
                ) ?? font
                : font
            out[range].font = Font(Card.italic(base))
            // **Both emphasis bits have to be given up along with it.** Left in
            // place, SwiftUI resolves the emphasis itself *on top* of the font just
            // set — and resolving either one goes through the symbolic traits, which
            // for italic is exactly the lookup that has no rounded italic to find,
            // so it lands back on an upright face and throws the oblique away.
            // `strikethrough` and the rest stay: they were never ours to draw.
            var remaining = intent
            remaining.remove(.emphasized)
            remaining.remove(.stronglyEmphasized)
            out[range].inlinePresentationIntent = remaining.isEmpty ? nil : remaining
        }
        return out
    }

    /// Headings take the card face too — a heading is body copy, not chrome.
    /// Fenced code doesn't: it stays monospaced, which is the whole point of it.
    ///
    /// The weight is baked in rather than added with `.fontWeight(.semibold)`
    /// afterwards, because that resolves to a different font and takes the
    /// one-storey `a` with it.
    ///
    /// Handed out as an `NSFont` because a heading's italic spans have to be
    /// slanted at the heading's own size and weight, and that is what
    /// `inline(_:in:)` needs to do it.
    private func headingFont(_ level: Int) -> NSFont {
        switch level {
        case 1: Card.nsFont(.title2, weight: .semibold)
        case 2: Card.nsFont(.title3, weight: .semibold)
        case 3: Card.nsFont(.headline, weight: .semibold)
        default: Card.nsFont(.subheadline, weight: .semibold)
        }
    }
}

enum MarkdownParser {
    enum Block {
        case heading(Int, String)
        case paragraph(String)
        case bullet([String])
        case ordered([String])
        /// One entry per `>` line, not one joined paragraph — a quote's line breaks
        /// are part of it (see the renderer).
        case quote([String])
        case code(String)
        case rule
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.isEmpty { flushParagraph(); i += 1; continue }

            // Fenced code block.
            if line.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 } // closing fence
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            // Horizontal rule.
            if line == "---" || line == "***" || line == "___" {
                flushParagraph(); blocks.append(.rule); i += 1; continue
            }

            // Heading.
            if let h = heading(line) {
                flushParagraph(); blocks.append(.heading(h.0, h.1)); i += 1; continue
            }

            // Block quote.
            if line.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard l.hasPrefix(">") else { break }
                    quoteLines.append(String(l.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                // Empty lines at either end would draw the bar past the text it
                // marks; ones *inside* the quote are the author's paragraph break
                // and are kept.
                while quoteLines.first?.isEmpty == true { quoteLines.removeFirst() }
                while quoteLines.last?.isEmpty == true { quoteLines.removeLast() }
                blocks.append(.quote(quoteLines))
                continue
            }

            // Unordered list.
            if isBullet(line) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count, isBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    items.append(String(l.dropFirst(2)))
                    i += 1
                }
                blocks.append(.bullet(items))
                continue
            }

            // Ordered list.
            if orderedPrefixLength(line) != nil {
                flushParagraph()
                var items: [String] = []
                while i < lines.count, let n = orderedPrefixLength(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    items.append(String(l.dropFirst(n)))
                    i += 1
                }
                blocks.append(.ordered(items))
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    /// The first line of text a body would *show* — what a collapsed task row
    /// teases, handed to `MarkdownText.inline(_:)` to draw.
    ///
    /// Block markers are dropped, because a marker isn't text: a heading reads as
    /// its words, a bullet as its item, a quote as its line. Inline markers are
    /// deliberately **left in place** for the renderer, which is the whole point —
    /// the row used to print the raw source, so a body of `**Ship it**` read as
    /// asterisks and a one-line note never earned the expand chevron that would
    /// have rendered it.
    ///
    /// A rule contributes nothing and is skipped rather than ending the search; it
    /// has no text, and a body that opens with `---` still has a first line
    /// somewhere below it.
    static func lead(_ text: String) -> String {
        for block in parse(text) {
            switch block {
            case .heading(_, let text), .paragraph(let text):
                if !text.isEmpty { return text }
            case .bullet(let items), .ordered(let items), .quote(let items):
                if let first = items.first(where: { !$0.isEmpty }) { return first }
            case .code(let code):
                let lines = code.components(separatedBy: "\n")
                if let first = lines.first(where: { !$0.isEmpty }) { return first }
            case .rule:
                continue
            }
        }
        return ""
    }

    private static func heading(_ line: String) -> (Int, String)? {
        var level = 0
        for ch in line { if ch == "#" { level += 1 } else { break } }
        guard level >= 1, level <= 6, line.count > level, line[line.index(line.startIndex, offsetBy: level)] == " " else { return nil }
        let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    /// Returns the length of the "1. " prefix if the line starts an ordered item.
    private static func orderedPrefixLength(_ line: String) -> Int? {
        var digits = 0
        for ch in line { if ch.isNumber { digits += 1 } else { break } }
        guard digits > 0 else { return nil }
        let rest = line.dropFirst(digits)
        guard rest.hasPrefix(". ") else { return nil }
        return digits + 2
    }
}
