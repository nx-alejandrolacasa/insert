import SwiftUI

/// A compact, dependency-free Markdown renderer for note/task bodies. Supports
/// the "basic markdown" the plan calls for: headings, bold/italic/code/links
/// (inline), bullet & numbered lists, block quotes, fenced code, and rules.
/// Not a full CommonMark implementation — just the common shapes, rendered to
/// look at home in a Liquid Glass UI.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        let blocks = MarkdownParser.parse(markdown)
        VStack(alignment: .leading, spacing: 8) {
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
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 2 : 0)
        case .paragraph(let text):
            inline(text)
                .font(.body)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        inline(item).font(.body)
                    }
                }
            }
        case .ordered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(idx + 1).").foregroundStyle(.secondary).monospacedDigit()
                        inline(item).font(.body)
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(.secondary.opacity(0.4)).frame(width: 3)
                inline(text).font(.body).foregroundStyle(.secondary)
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

    private func inline(_ text: String) -> Text {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title2
        case 2: .title3
        case 3: .headline
        default: .subheadline
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
