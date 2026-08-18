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
        .tint(Self.linkColour)
    }

    /// The colour SwiftUI draws a link in is the environment's tint, so that is
    /// how the theme's own link value reaches one. Without it a link inherited
    /// the app-wide tint, which is `AppTheme.primary` — a lavender or a mint link
    /// on a white card, at 2.4:1 and 1.6:1, where each theme's `link` is solved
    /// against the card it lands on. Read inside a view update, so the
    /// `@Observable` access registers and a theme change re-renders (the way
    /// `Card` reads the typeface).
    static var linkColour: Color { SettingsStore.shared.theme.link }

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
        //
        // Bullets and numbers share one block, and one `VStack`, because a nested
        // list may change marker (`1.` with `*` items under it) and two stacks
        // would put a paragraph gap in the middle of one list.
        case .list(let items):
            let numbers = MarkdownParser.numbering(items)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: Self.markerGap) {
                        if let number = numbers[idx] {
                            Text("\(number).")
                                .font(font)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            bulletDot
                        }
                        Self.inline(item.text, in: nsFont).font(font)
                    }
                    .padding(.leading, CGFloat(item.level) * Self.listIndent)
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

    /// The gap between a list marker and its item.
    private static let markerGap: CGFloat = 8

    /// One level of nesting. It is the marker column — the dot plus its gap — so
    /// a child's bullet lands under the first character of its parent's text,
    /// which is where the eye already expects the sub-list to start. A count of
    /// the source's own spaces would be no use: the same nesting can be written
    /// with two spaces or four, and both mean one level.
    private static let listIndent: CGFloat = bulletDiameter + markerGap

    private static let bulletDiameter: CGFloat = 5

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
            .frame(width: Self.bulletDiameter, height: Self.bulletDiameter)
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
    /// One line of a list: its text, whether it wore a number, and how deep it
    /// was nested. The depth is a **level**, not a column count — see
    /// `nestingLevel(for:in:)`.
    struct ListItem: Equatable {
        var level: Int
        var ordered: Bool
        var text: String
    }

    enum Block {
        case heading(Int, String)
        case paragraph(String)
        /// Bullets and numbers together, in source order — one block per run of
        /// list lines however their markers or nesting change inside it.
        case list([ListItem])
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

            // List — bullets and numbers alike, nested by indentation.
            if listMarker(line) != nil {
                flushParagraph()
                var items: [ListItem] = []
                var indents: [Int] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let marker = listMarker(l) else { break }
                    items.append(ListItem(
                        level: nestingLevel(for: indentColumns(lines[i]), in: &indents),
                        ordered: marker.ordered,
                        text: String(l.dropFirst(marker.length))
                    ))
                    i += 1
                }
                blocks.append(.list(items))
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
            case .list(let items):
                if let first = items.first(where: { !$0.text.isEmpty }) { return first.text }
            case .quote(let items):
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

    /// The numbers a list's items show, one per item, `nil` where the item is a
    /// bullet. The source's own numbers are ignored — Markdown renders `1. 1. 1.`
    /// as 1, 2, 3 and so does this — but each level counts for itself, so a
    /// sub-list starts again at 1 and its parent picks up where it left off.
    ///
    /// A bullet **resets** the level it sits at rather than consuming a number,
    /// so a numbered run interrupted by a bullet sibling starts over instead of
    /// silently skipping a number.
    static func numbering(_ items: [ListItem]) -> [Int?] {
        var counters: [Int] = []
        return items.map { item in
            if item.level < counters.count {
                counters.removeSubrange((item.level + 1)...)
            }
            while counters.count <= item.level { counters.append(0) }
            guard item.ordered else { counters[item.level] = 0; return nil }
            counters[item.level] += 1
            return counters[item.level]
        }
    }

    /// The width of a line's leading whitespace, a tab counting as four columns.
    private static func indentColumns(_ line: String) -> Int {
        var columns = 0
        for ch in line {
            if ch == "\t" { columns += 4 } else if ch == " " { columns += 1 } else { break }
        }
        return columns
    }

    /// How deep an item sits, from the indents of the items above it.
    ///
    /// Levels are counted **relative to the list**, not divided by a fixed unit,
    /// which is what lets two-space and four-space indentation both mean one
    /// level — and mixed indentation still read right. `indents` is the stack of
    /// columns each open level started at: a wider indent than the top opens a
    /// level, a narrower one closes every level it has left.
    private static func nestingLevel(for columns: Int, in indents: inout [Int]) -> Int {
        while let top = indents.last, columns < top { indents.removeLast() }
        if indents.last.map({ columns > $0 }) ?? true { indents.append(columns) }
        return indents.count - 1
    }

    /// The marker a list line opens with — its length, so the caller can drop it,
    /// and whether it was a number.
    private static func listMarker(_ line: String) -> (length: Int, ordered: Bool)? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return (2, false)
        }
        if let n = orderedPrefixLength(line) { return (n, true) }
        return nil
    }

    /// Returns the length of the `1. ` or `1) ` prefix if the line starts an
    /// ordered item. Both spellings, because Return continues either one
    /// (`LineMarker`) and a body should render what the editor just wrote.
    private static func orderedPrefixLength(_ line: String) -> Int? {
        var digits = 0
        for ch in line { if ch.isNumber { digits += 1 } else { break } }
        guard digits > 0 else { return nil }
        let rest = line.dropFirst(digits)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return digits + 2
    }
}

// MARK: - Collapsible body

/// A card body that can read collapsed: `MarkdownText` folded to a preview of
/// `previewLines` rendered lines, with a chevron beside the first line to reveal
/// the rest. One implementation for both cards — notes at `.body`, tasks at
/// `.callout` — driven by each kind's "Preview lines" setting; `nil` lines means
/// no collapsing and the body simply renders in full. View mode only by
/// construction: the cards only show this when they aren't editing.
///
/// Two collapsed shapes, because one line is not just a smaller ten:
///
/// - **One line** is the teaser: the body's lead line (`MarkdownParser.lead`,
///   block marker dropped, inline markers rendered), laid out at its natural
///   width and faded out at the trailing edge when the line is cut — never an
///   ellipsis. Expanding swaps in the full render in one frame
///   (`.transition(.identity)`: the default cross-fade showed the same words
///   twice at half opacity while the row was still resizing).
/// - **Several lines** clamp the full render to that many line heights of the
///   card face and fade to nothing over the last of them. Collapsed and
///   expanded are *one view* — only the `frame(maxHeight:)` value switches —
///   because a conditional branch is two identities and would kill the height
///   animation the owning card scopes to `expanded`; the mask is applied in
///   both states for the same reason (expanded it is opaque everywhere, a
///   no-op).
///
/// Whether the chevron appears is measured off the **render**, never the source
/// — the parser joins hard-wrapped lines, so a long source can render short and
/// used to earn a chevron that revealed nothing.
///
/// The chevron rides the body's **first** line, and the position is
/// load-bearing: a control under the fold travels with the card's height, so
/// collapsing an expanded body had it floating down through the contraction with
/// its `.replace` turn still playing. It wears the ⋯ menu's measured box
/// (`chevronBox`), both dimensions doing work: equal widths flush to one
/// trailing edge is what puts the two on one vertical axis, and at the menu's
/// own height the box sits inside the line box — taller, it pushed a
/// baseline-aligned row's top up and the preview text below the editor's first
/// line.
struct CollapsibleMarkdown: View {
    let markdown: String
    var textStyle: NSFont.TextStyle = .body
    /// How many rendered lines the collapsed preview shows; `nil` folds nothing.
    let previewLines: Int?
    /// Owned by the card, whose height animation is value-scoped to it.
    @Binding var expanded: Bool
    /// The ⋯ menu's box, measured by the card (a borderless `Menu` sizes itself).
    let chevronBox: CGSize
    /// The chevron's two spoken/help names, in the card's own words.
    let expandLabel: String
    let collapseLabel: String

    /// The body laid out unbounded — what expanding would show.
    @State private var fullHeight: CGFloat = 0
    /// The one-line teaser's rendered height. Compared against `fullHeight`
    /// rather than one line height of the card face, because the body's first
    /// block can be taller than a body line (a heading), and that alone mustn't
    /// earn a chevron.
    @State private var teaserHeight: CGFloat = 0
    /// The teaser at its natural single-line width, against the width the row
    /// actually gives it. Wider means the line is cut, which is the only case
    /// that earns the trailing fade — a teaser that fits must not dim its last
    /// characters as if something were hidden there.
    @State private var teaserWidth: CGFloat = 0
    @State private var teaserBoxWidth: CGFloat = 0

    private var nsFont: NSFont { Card.nsFont(textStyle) }

    /// One line of the card face, unrounded: the half-line tolerance below rides
    /// on it, and rounding per line is exactly the drift being tolerated.
    private var lineHeight: CGFloat {
        let font = nsFont
        return font.ascender - font.descender + font.leading
    }

    /// Long enough to fold. The teaser earns its chevron when the full render is
    /// taller than the one line on show; a clamp earns it when the render runs
    /// more than **half a line** past the cap — a body of exactly the preview
    /// height drifts a fraction of a point per line against `n ×` an unrounded
    /// line height, and must not earn a chevron that reveals nothing.
    private var collapsible: Bool {
        guard let lines = previewLines else { return false }
        // A card that has only ever been *expanded* — a note left open by the
        // edit it just finished — has never laid the teaser out, so there is no
        // measurement to compare against and a zero would call every body
        // collapsible. One line of the card face is the honest stand-in until
        // the teaser has been drawn once.
        if lines == 1 {
            return fullHeight > (teaserHeight > 0 ? teaserHeight : lineHeight) + 1
        }
        return fullHeight > CGFloat(lines) * lineHeight + lineHeight / 2
    }

    /// Shown when there's something hidden — or when we're expanded and it's
    /// the way back.
    private var showsChevron: Bool {
        previewLines != nil && (expanded || collapsible)
    }

    /// Whether the clamp is currently applied (several-lines mode only; the
    /// one-line mode swaps views instead of clamping).
    private var isClamped: Bool {
        guard let lines = previewLines, lines > 1 else { return false }
        return collapsible && !expanded
    }

    var body: some View {
        // Baseline, not `.top`: the chevron is a caption glyph in a measured
        // box, and top-aligning the boxes sat it below the line of text it
        // belongs to — `centredOnTextCap()` puts its centre on the first line's
        // cap height instead.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            content
            if showsChevron { chevron }
        }
    }

    /// `.transition(.identity)` on both branches of the teaser swap, and on the
    /// clamped body for the frames where the *setting* moves it between
    /// branches: the two are the same words with and without the rest of the
    /// body under them, so the default cross-fade showed them twice at half
    /// opacity mid-resize. The card's height is what animates.
    @ViewBuilder
    private var content: some View {
        if previewLines == 1 && !expanded {
            teaser.transition(.identity)
        } else {
            clamped.transition(.identity)
        }
    }

    /// The full render, clamped to the preview height while collapsed. The 5pt
    /// is the editor's text-container inset, which every body copy repeats so
    /// the first character doesn't shift sideways as a card opens. `fixedSize`
    /// because a clamp must *clip* the blocks, not propose them less height —
    /// squeezed, they truncate themselves into ellipses.
    private var clamped: some View {
        MarkdownText(markdown: markdown, textStyle: textStyle)
            .padding(.horizontal, 5)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                fullHeight = $0
            }
            .frame(
                maxHeight: isClamped ? CGFloat(previewLines ?? 1) * lineHeight : nil,
                alignment: .topLeading
            )
            .clipped()
            .mask(clampFade)
    }

    /// The teaser is **rendered**, not source. `MarkdownParser.lead(_:)` drops
    /// the block marker and `MarkdownText.inline(_:)` draws the rest — the same
    /// two steps the full render takes per block; printing the raw source read
    /// `**Ship it**` as asterisks. Laid out at its natural width so a line
    /// longer than the row overflows into the clip instead of truncating — the
    /// fade is the truncation mark, never an ellipsis.
    private var teaser: some View {
        MarkdownText.inline(MarkdownParser.lead(markdown), in: nsFont)
            .font(Font(nsFont))
            .foregroundStyle(.secondary)
            .tint(MarkdownText.linkColour)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { teaserWidth = $0 }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { teaserBoxWidth = $0 }
            .clipped()
            .mask(teaserFade)
            .padding(.horizontal, 5)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { teaserHeight = $0 }
            .background(alignment: .topLeading) {
                // What expanding would actually show, laid out unbounded and
                // hidden — the clamp measures its own render, but the teaser is
                // one line whatever the body holds, so it has to ask a proxy.
                MarkdownText(markdown: markdown, textStyle: textStyle)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        fullHeight = $0
                    }
            }
    }

    /// The clamp's fade: opaque until the last previewed line, then fading to
    /// nothing across it — "there is more" drawn where the more is, and what
    /// makes a clamp that lands mid-block read as a fold instead of a crop.
    /// The fade region is one line of `n`, so the stop is simply `1 - 1/n`.
    private var clampFade: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(
                    color: .black,
                    location: isClamped ? 1 - 1 / CGFloat(previewLines ?? 1) : 1
                ),
                .init(color: isClamped ? .clear : .black, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The teaser's truncation mark: opaque until one line height from the
    /// trailing edge, then fading to clear across it — the clamp's gradient
    /// turned sideways, so the two cuts read as one gesture. Only when the line
    /// really is cut; a teaser that fits stays fully opaque.
    private var teaserFade: some View {
        let cut = teaserBoxWidth > 0 && teaserWidth > teaserBoxWidth + 1
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: cut ? max(0, 1 - lineHeight / teaserBoxWidth) : 1),
                .init(color: cut ? .clear : .black, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var chevron: some View {
        Button {
            expanded.toggle()
        } label: {
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                // One symbol in two directions — `.replace` turns it over rather
                // than cutting, and drops to a cut under Reduce Motion.
                .contentTransition(.symbolEffect(.replace))
                .frame(width: chevronBox.width, height: chevronBox.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .centredOnTextCap(textStyle)
        .help(expanded ? collapseLabel : expandLabel)
        .accessibilityLabel(expanded ? collapseLabel : expandLabel)
    }
}
