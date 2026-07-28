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
            inline(text)
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 2 : 0)
        case .paragraph(let text):
            inline(text)
                .font(font)
        // Items sit on consecutive lines in the source with nothing between them,
        // so they get nothing here either — the 4pt this used to add was the list
        // loosening on the way *into* view mode while every paragraph tightened.
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        bulletDot
                        inline(item).font(font)
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
                        inline(item).font(font)
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.4)).frame(width: 3)
                inline(text).font(font).foregroundStyle(.secondary)
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

    private func inline(_ text: String) -> Text {
        // Markdown has no underline; ⌘U writes `<u>…</u>` (the Obsidian
        // convention), which `AttributedString` would show literally — so pull
        // those spans out and underline them, parsing the rest as usual.
        guard text.contains("<u>") else { return inlineFragment(text) }
        var result = Text(verbatim: "")
        var rest = Substring(text)
        while let open = rest.range(of: "<u>"),
              let close = rest.range(of: "</u>", range: open.upperBound..<rest.endIndex) {
            let before = inlineFragment(String(rest[..<open.lowerBound]))
            let underlined = inlineFragment(String(rest[open.upperBound..<close.lowerBound])).underline()
            result = Text("\(result)\(before)\(underlined)")
            rest = rest[close.upperBound...]
        }
        return Text("\(result)\(inlineFragment(String(rest)))")
    }

    private func inlineFragment(_ text: String) -> Text {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(text)
    }

    /// Headings take the card face too — a heading is body copy, not chrome.
    /// Fenced code doesn't: it stays monospaced, which is the whole point of it.
    ///
    /// The weight is baked in rather than added with `.fontWeight(.semibold)`
    /// afterwards, because that resolves to a different font and takes the
    /// one-storey `a` with it.
    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: Card.font(.title2, weight: .semibold)
        case 2: Card.font(.title3, weight: .semibold)
        case 3: Card.font(.headline, weight: .semibold)
        default: Card.font(.subheadline, weight: .semibold)
        }
    }
}

enum MarkdownParser {
    enum Block {
        case heading(Int, String)
        case paragraph(String)
        case bullet([String])
        case ordered([String])
        case quote(String)
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
                blocks.append(.quote(quoteLines.joined(separator: " ")))
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
