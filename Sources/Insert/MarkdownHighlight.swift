import AppKit
import SwiftUI

/// Styles the Markdown **source** while it is being edited — option 2 of the
/// editing-experience discussion: the text in the editor stays the file's own
/// characters, byte for byte, but headings draw at heading size, `**bold**`
/// draws bold, list markers and syntax characters dim, links take the theme's
/// link colour. The structure a note's Markdown carries stays readable while it
/// is being typed, which is what a raw-source editor loses.
///
/// **Syntax recedes off the line being edited.** Every marker is still there
/// and still laid out at its own width — nothing here hides a character — but
/// on the lines the selection isn't touching it drops to `faintMarker`, so a
/// note reads as its words while the line under the caret shows what it is
/// made of. Deliberately the cheap half of the idea: real marker *hiding*
/// (Typora's, Obsidian's) reflows the line as the caret enters it, and inside a
/// card whose height is animated that is louder than in a full-window editor.
/// This cut is what tells us whether the noise was the markers or their width.
///
/// The split mirrors `MarkdownFormatting`: `spans(of:)` is a pure function over
/// the source (pinned by `MarkdownHighlightTests`), and the two appliers turn
/// its answer into attributes — `apply(to:…)` onto the editor's `NSTextStorage`,
/// `attributed(_:…)` into the `AttributedString` the cards' hidden sizing
/// proxies lay out in. Both go through the same `font(for:…)`, which is what
/// keeps the editor's height and the proxy's measurement from drifting once a
/// heading line is taller than a body line.
///
/// The scanner is deliberately not a CommonMark implementation — it matches
/// `MarkdownParser`'s block rules and approximates the inline ones, line by
/// line (no delimiter crosses a newline, which is also how the shapes are
/// typed). Where it declines to match — an unclosed `**`, a lone `*` in
/// arithmetic — the text simply stays in the base attributes, which is exactly
/// what the preview shows for the same source.
enum MarkdownHighlight {
    /// What a run of source should look like. Complete in itself — a bold span
    /// inside a heading carries both facts — so applying spans never depends on
    /// the order they were emitted in for its *fonts*; colours are only set
    /// where a span names one.
    struct Style: Equatable {
        /// Sized as this heading level (the preview's own heading fonts).
        var heading: Int? = nil
        var bold = false
        var italic = false
        /// Inline code and fenced blocks: monospaced at the context's size.
        var mono = false
        var strikethrough = false
        var underline = false
        var colour: Colour? = nil

        /// Whether this style changes the text's measured size — what the
        /// sizing proxies care about. Colour and the two line decorations
        /// don't move a wrap point.
        var affectsLayout: Bool {
            heading != nil || bold || italic || mono
        }
    }

    /// The two colours a span can ask for, by role: `marker` is every syntax
    /// character (dimmed, the theme's metadata grey), `link` is a link's label.
    enum Colour: Equatable {
        case marker
        case link
    }

    /// One styled run, in UTF-16 offsets — `NSRange`-native, because both
    /// appliers speak it. The scanner only anchors on ASCII characters, so a
    /// range can't split a surrogate pair.
    struct Span: Equatable {
        var range: NSRange
        var style: Style
    }

    /// The resolved colours the editor applies. `NSColor`s rather than theme
    /// reads so the pure parts stay pure; the bridge builds one from the theme.
    struct Palette: Equatable {
        var text: NSColor
        var marker: NSColor
        /// Syntax on a line the caret isn't on. Deliberately an *alpha wash* of
        /// `marker`, and deliberately held to no contrast floor: a marker is
        /// scaffolding the writer put there, not text anybody reads, and the
        /// word it wraps carries the meaning — `Tint.accent`'s argument, one
        /// file over. It only has to stay findable when you look for it.
        var faintMarker: NSColor
        var link: NSColor
    }

    /// Everything a highlight pass depends on, compared by the bridge so a pass
    /// only re-runs when one of its inputs really changed.
    struct Config: Equatable {
        var base: NSFont
        var typeface: Typeface
        var palette: Palette
    }

    // MARK: The revealed line

    /// The stretch of source whose syntax stays at full strength: the lines the
    /// selection touches. Everything else fades to `faintMarker`, so a note
    /// reads as its writing with the markers receding, and the line being
    /// worked on shows what it is made of.
    ///
    /// Whole *lines* rather than the spans under the caret, because a marker
    /// comes in pairs and revealing half of `**bold**` would be worse than
    /// revealing neither. A multi-line selection reveals every line it crosses.
    ///
    /// Nothing here moves a glyph — every character is laid out at the same
    /// width it always was, so the caret line does not reflow as it is entered.
    /// That is the whole point of this cut; see CLAUDE.md on marker *hiding*,
    /// which does reflow and is the question this is meant to answer.
    static func revealedLines(in text: String, selection: NSRange) -> NSRange {
        let ns = text as NSString
        guard selection.location <= ns.length else { return NSRange(location: 0, length: 0) }
        let clamped = NSRange(
            location: selection.location,
            length: min(selection.length, ns.length - selection.location)
        )
        return ns.lineRange(for: clamped)
    }

    // MARK: Fonts

    /// The font a style resolves to, from the context's base. Bold goes through
    /// the same descriptor union the preview uses (`MarkdownText.italicised`),
    /// so `**bold**` in the editor is the very face it renders in — including
    /// on Grotesk, whose *regular* descriptor carries no `wght` axis and so
    /// still answers the symbolic trait (the trap only the semibold axis case
    /// has). Italic is `Card.italic`, real face or synthesised oblique.
    static func font(for style: Style, base: NSFont, typeface: Typeface) -> NSFont {
        var font = style.heading.map { MarkdownText.headingFont($0, typeface: typeface) } ?? base
        if style.mono {
            font = .monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        }
        if style.bold {
            let descriptor = font.fontDescriptor.withSymbolicTraits(
                font.fontDescriptor.symbolicTraits.union(.bold)
            )
            font = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
        }
        if style.italic {
            font = Card.italic(font)
        }
        return font
    }

    // MARK: Applying — the editor

    /// One pass over the editor's storage: base attributes over everything,
    /// then each span's on top. Attribute-only edits register no undo and fire
    /// no `textDidChange`, so this can run from inside the change notification
    /// without feeding back into itself.
    @MainActor
    static func apply(
        to storage: NSTextStorage,
        config: Config,
        paragraphStyle: NSParagraphStyle,
        revealing: NSRange? = nil
    ) {
        let text = storage.string
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([
            .font: config.base,
            .foregroundColor: config.palette.text,
            .paragraphStyle: paragraphStyle,
        ], range: full)
        for span in spans(of: text) {
            guard span.range.upperBound <= full.length else { continue }
            var attrs: [NSAttributedString.Key: Any] = [:]
            let resolved = font(for: span.style, base: config.base, typeface: config.typeface)
            if resolved != config.base { attrs[.font] = resolved }
            switch span.style.colour {
            case .marker:
                let revealed = revealing.map { NSIntersectionRange(span.range, $0).length > 0 }
                attrs[.foregroundColor] = revealed == true
                    ? config.palette.marker : config.palette.faintMarker
            case .link: attrs[.foregroundColor] = config.palette.link
            case nil: break
            }
            if span.style.strikethrough {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if span.style.underline {
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if !attrs.isEmpty { storage.addAttributes(attrs, range: span.range) }
        }
        storage.endEditing()
    }

    // MARK: Applying — the sizing proxies

    /// The source with only its **layout-affecting** styles baked in, for the
    /// hidden `Text` proxies that drive an editor's height. The proxies used to
    /// lay the raw source out in the flat card face, which was right for as
    /// long as the editor drew everything at one size; a heading line is taller
    /// now, so the proxy has to wear the same fonts or the editor is measured
    /// short. Colours are left out — hidden text has no colour, and skipping
    /// them keeps the cache key to text + face.
    ///
    /// Memoised because the task card's proxy measures in *view* mode too, so
    /// this runs per visible task row per render — `MarkdownParser.parse`'s
    /// reason, one cache line over.
    static func attributed(_ text: String, base: NSFont, typeface: Typeface) -> AttributedString {
        let key = ProxyKey(text: text, font: base.fontName, size: base.pointSize, typeface: typeface)
        return proxies.value(for: key) {
            var out = AttributedString(text)
            out.font = Font(base)
            for span in spans(of: text) where span.style.affectsLayout {
                guard let range = Range(span.range, in: out) else { continue }
                out[range].font = Font(font(for: span.style, base: base, typeface: typeface))
            }
            return out
        }
    }

    private struct ProxyKey: Hashable {
        let text: String
        let font: String
        let size: CGFloat
        let typeface: Typeface
    }

    private static let proxies = MemoCache<ProxyKey, AttributedString>(limit: 512)

    // MARK: The scanner

    /// The styled runs of `text`, in source order, broad before narrow — a
    /// heading emits its whole-line font span before the marker and emphasis
    /// spans inside it, so the later, narrower spans win where they overlap.
    static func spans(of text: String) -> [Span] {
        let u = Array(text.utf16)
        var spans: [Span] = []
        var inFence = false

        var lineStart = 0
        while lineStart <= u.count {
            var lineEnd = lineStart
            while lineEnd < u.count, u[lineEnd] != nl { lineEnd += 1 }
            scanLine(u, lineStart..<lineEnd, inFence: &inFence, into: &spans)
            if lineEnd >= u.count { break }
            lineStart = lineEnd + 1
        }
        return spans
    }

    private static func scanLine(
        _ u: [UInt16], _ line: Range<Int>, inFence: inout Bool, into spans: inout [Span]
    ) {
        // Leading whitespace, the way `MarkdownParser` trims before classifying.
        var s = line.lowerBound
        while s < line.upperBound, u[s] == space || u[s] == tab { s += 1 }
        guard s < line.upperBound else { return }

        // A fence line toggles the block; both it and every line inside are mono.
        if matches(u, at: s, "```"), s + 3 <= line.upperBound {
            add(&spans, s..<line.upperBound, Style(mono: true, colour: .marker))
            inFence.toggle()
            return
        }
        if inFence {
            add(&spans, line, Style(mono: true))
            return
        }

        // Heading: the whole line at the level's size, the hashes dimmed.
        var hashes = s
        while hashes < line.upperBound, u[hashes] == hash { hashes += 1 }
        let level = hashes - s
        if level >= 1, level <= 6, hashes < line.upperBound, u[hashes] == space {
            add(&spans, s..<line.upperBound, Style(heading: level))
            add(&spans, s..<hashes, Style(heading: level, colour: .marker))
            scanInline(u, (hashes + 1)..<line.upperBound, context: Style(heading: level), into: &spans)
            return
        }

        // Rule — exactly the three spellings the parser reads.
        if isRule(u, s..<line.upperBound) {
            add(&spans, s..<line.upperBound, Style(colour: .marker))
            return
        }

        // Block quote: the run of `>`s dims, the quoted text stays the writing.
        if u[s] == gt {
            var q = s
            while q < line.upperBound, u[q] == gt { q += 1 }
            add(&spans, s..<q, Style(colour: .marker))
            scanInline(u, q..<line.upperBound, context: Style(), into: &spans)
            return
        }

        // List item: the marker dims; a checked box strikes its text through,
        // the same two marks the preview gives a ticked line.
        if let marker = listMarker(u, s..<line.upperBound) {
            add(&spans, s..<marker.contentStart, Style(colour: .marker))
            if marker.checked == true {
                add(&spans, marker.contentStart..<line.upperBound,
                    Style(strikethrough: true, colour: .marker))
            }
            scanInline(u, marker.contentStart..<line.upperBound, context: Style(), into: &spans)
            return
        }

        scanInline(u, s..<line.upperBound, context: Style(), into: &spans)
    }

    /// The inline shapes, within one line: code spans, `*`/`_` emphasis,
    /// `~~strike~~`, `<u>underline</u>` and `[label](url)` links. Flat — an
    /// emphasis span's content is not re-scanned — and every unmatched
    /// delimiter is left as the plain text it is.
    private static func scanInline(
        _ u: [UInt16], _ range: Range<Int>, context: Style, into spans: inout [Span]
    ) {
        var j = range.lowerBound
        while j < range.upperBound {
            let c = u[j]

            // `code` — first, so nothing inside it reads as emphasis.
            if c == backtick {
                if let close = find(u, backtick, from: j + 1, before: range.upperBound), close > j + 1 {
                    var marker = context; marker.colour = .marker
                    var code = context; code.mono = true
                    add(&spans, j..<(j + 1), marker)
                    add(&spans, (j + 1)..<close, code)
                    add(&spans, close..<(close + 1), marker)
                    j = close + 1
                    continue
                }
                j += 1
                continue
            }

            if c == star || c == underscore {
                if let end = emphasis(u, at: j, in: range, context: context, into: &spans) {
                    j = end
                    continue
                }
                j += 1
                continue
            }

            if c == tilde, j + 1 < range.upperBound, u[j + 1] == tilde {
                if let close = findPair(u, tilde, from: j + 2, before: range.upperBound), close > j + 2 {
                    var marker = context; marker.colour = .marker
                    var struck = context; struck.strikethrough = true
                    add(&spans, j..<(j + 2), marker)
                    add(&spans, (j + 2)..<close, struck)
                    add(&spans, close..<(close + 2), marker)
                    j = close + 2
                    continue
                }
                j += 2
                continue
            }

            // `<u>…</u>`, the span ⌘U writes.
            if c == lt, matches(u, at: j, "<u>") {
                if let close = find(u, "</u>", from: j + 3, before: range.upperBound) {
                    var marker = context; marker.colour = .marker
                    var underlined = context; underlined.underline = true
                    add(&spans, j..<(j + 3), marker)
                    add(&spans, (j + 3)..<close, underlined)
                    add(&spans, close..<(close + 4), marker)
                    j = close + 4
                    continue
                }
                j += 3
                continue
            }

            // `[label](url)` — the label in the link colour, everything else dimmed.
            if c == lbracket {
                if let mid = find(u, "](", from: j + 1, before: range.upperBound),
                   let close = find(u, rparen, from: mid + 2, before: range.upperBound) {
                    var marker = context; marker.colour = .marker
                    var label = context; label.colour = .link
                    add(&spans, j..<(j + 1), marker)
                    add(&spans, (j + 1)..<mid, label)
                    add(&spans, mid..<(close + 1), marker)
                    j = close + 1
                    continue
                }
                j += 1
                continue
            }

            j += 1
        }
    }

    /// A `*` or `_` run opening emphasis: 1 is italic, 2 bold, 3 both. Returns
    /// the offset after the closing run, or `nil` when the run doesn't open
    /// anything — flanked by a space (`2 * 3` is arithmetic) or, for `_`,
    /// inside a word (`snake_case` is a name).
    private static func emphasis(
        _ u: [UInt16], at j: Int, in range: Range<Int>, context: Style, into spans: inout [Span]
    ) -> Int? {
        let delimiter = u[j]
        var runEnd = j
        while runEnd < range.upperBound, u[runEnd] == delimiter { runEnd += 1 }
        let n = min(runEnd - j, 3)
        let open = j..<(j + n)

        // The content must hug the opening run.
        guard open.upperBound < range.upperBound, !isSpace(u[open.upperBound]) else { return nil }
        // `_` only opens at a word boundary.
        if delimiter == underscore, j > range.lowerBound, isWordy(u[j - 1]) { return nil }

        // The closing run: same delimiter, at least as long, hugging its text.
        var k = open.upperBound
        while k < range.upperBound {
            guard u[k] == delimiter else { k += 1; continue }
            var closeEnd = k
            while closeEnd < range.upperBound, u[closeEnd] == delimiter { closeEnd += 1 }
            if closeEnd - k >= n, !isSpace(u[k - 1]) {
                if delimiter == underscore, closeEnd < range.upperBound, isWordy(u[closeEnd]) {
                    k = closeEnd
                    continue
                }
                let close = k..<(k + n)
                var marker = context; marker.colour = .marker
                var styled = context
                styled.bold = styled.bold || n >= 2
                styled.italic = styled.italic || n % 2 == 1
                add(&spans, open, marker)
                add(&spans, open.upperBound..<close.lowerBound, styled)
                add(&spans, close, marker)
                return close.upperBound
            }
            k = closeEnd
        }
        return nil
    }

    // MARK: Line classification helpers

    /// `- `, `* `, `+ ` (with an optional `[x] ` box) or `1. ` / `1) ` — the
    /// same shapes `MarkdownParser.listMarker` and `LineMarker` read.
    private static func listMarker(
        _ u: [UInt16], _ line: Range<Int>
    ) -> (contentStart: Int, checked: Bool?)? {
        let s = line.lowerBound
        if s + 1 < line.upperBound, u[s] == dash || u[s] == star || u[s] == plus, u[s + 1] == space {
            let afterBullet = s + 2
            // `[c] ` or `[c]` at the end of the line; `](` disqualifies, so a
            // `- [x](url)` line stays a link at the head of a plain bullet.
            if afterBullet + 2 < line.upperBound,
               u[afterBullet] == lbracket, u[afterBullet + 2] == rbracket,
               afterBullet + 3 == line.upperBound || u[afterBullet + 3] == space {
                let checked = u[afterBullet + 1] != space
                return (min(afterBullet + 4, line.upperBound), checked)
            }
            return (afterBullet, nil)
        }
        var digits = s
        while digits < line.upperBound, u[digits] >= zero, u[digits] <= nine { digits += 1 }
        if digits > s, digits + 1 < line.upperBound,
           u[digits] == dot || u[digits] == rparen, u[digits + 1] == space {
            return (digits + 2, nil)
        }
        return nil
    }

    private static func isRule(_ u: [UInt16], _ range: Range<Int>) -> Bool {
        guard range.count == 3 else { return false }
        let c = u[range.lowerBound]
        guard c == dash || c == star || c == underscore else { return false }
        return u[range.lowerBound + 1] == c && u[range.lowerBound + 2] == c
    }

    // MARK: Scanning primitives

    private static func add(_ spans: inout [Span], _ range: Range<Int>, _ style: Style) {
        guard range.lowerBound < range.upperBound else { return }
        spans.append(Span(
            range: NSRange(location: range.lowerBound, length: range.count),
            style: style
        ))
    }

    private static func matches(_ u: [UInt16], at i: Int, _ literal: String) -> Bool {
        let l = Array(literal.utf16)
        guard i + l.count <= u.count else { return false }
        return Array(u[i..<(i + l.count)]) == l
    }

    private static func find(_ u: [UInt16], _ unit: UInt16, from: Int, before: Int) -> Int? {
        var i = from
        while i < before {
            if u[i] == unit { return i }
            i += 1
        }
        return nil
    }

    private static func findPair(_ u: [UInt16], _ unit: UInt16, from: Int, before: Int) -> Int? {
        var i = from
        while i + 1 < before {
            if u[i] == unit, u[i + 1] == unit { return i }
            i += 1
        }
        return nil
    }

    private static func find(_ u: [UInt16], _ literal: String, from: Int, before: Int) -> Int? {
        let l = Array(literal.utf16)
        guard !l.isEmpty else { return nil }
        var i = from
        while i + l.count <= before {
            if Array(u[i..<(i + l.count)]) == l { return i }
            i += 1
        }
        return nil
    }

    private static func isSpace(_ c: UInt16) -> Bool { c == space || c == tab }

    /// "Part of a word", for `_`'s boundary rule. Anything non-ASCII counts as
    /// wordy, which errs on the side of leaving text plain.
    private static func isWordy(_ c: UInt16) -> Bool {
        (c >= zero && c <= nine) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c > 0x7F
    }

    // ASCII, as UTF-16 units — the only characters the scanner anchors on.
    private static let nl: UInt16 = 0x0A
    private static let space: UInt16 = 0x20
    private static let tab: UInt16 = 0x09
    private static let hash: UInt16 = 0x23
    private static let star: UInt16 = 0x2A
    private static let plus: UInt16 = 0x2B
    private static let dash: UInt16 = 0x2D
    private static let dot: UInt16 = 0x2E
    private static let underscore: UInt16 = 0x5F
    private static let backtick: UInt16 = 0x60
    private static let tilde: UInt16 = 0x7E
    private static let gt: UInt16 = 0x3E
    private static let lt: UInt16 = 0x3C
    private static let lbracket: UInt16 = 0x5B
    private static let rbracket: UInt16 = 0x5D
    private static let rparen: UInt16 = 0x29
    private static let zero: UInt16 = 0x30
    private static let nine: UInt16 = 0x39
}
