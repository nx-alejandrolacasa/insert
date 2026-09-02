import AppKit
import SwiftUI

/// A card body in view mode: the Markdown rendered as **rich text in a
/// read-only `NSTextView`**, so the words can be selected across the whole body
/// and ⌘C carries the formatting — bold, italic, headings, lists, links — into
/// whatever the selection is pasted into, with a plain-text flavour beside it.
///
/// It replaced `MarkdownText`'s stack of SwiftUI `Text`s as the *full* render.
/// SwiftUI's `textSelection(.enabled)` is per `Text`, so a selection could never
/// cross from one paragraph into the next, and what it copies is not ours to
/// shape; a text view gives both for free and hands back the system's own
/// Look Up / Translate / Services menu with them. `MarkdownText` stays for the
/// one-line teaser and the hidden measuring proxies, which are never selected.
///
/// What the card around it relies on: the view answers `sizeThatFits` with its
/// laid-out height at the proposed width, so `CollapsibleMarkdown`'s clamp,
/// fade and chevron measurement work unchanged; a **click that isn't a drag**
/// is reported through `onTap` (the text view consumes the mouse, so the card's
/// own tap gesture never sees it), except on a link, which the text view opens
/// itself, and on a checkbox, which flips its line; and the text sits at the
/// same 5pt inset the editor's `lineFragmentPadding` gives, applied by the
/// caller as padding, so the preview/source flip still lands on one frame.
struct MarkdownPreview: NSViewRepresentable {
    let markdown: String
    var textStyle: NSFont.TextStyle = .body
    /// A plain click on the text — the card's "open for editing".
    var onTap: (() -> Void)? = nil
    /// A `- [ ]` mark clicked; the argument is the item's source line.
    var onToggleCheckbox: ((Int) -> Void)? = nil

    func makeNSView(context: Context) -> MarkdownPreviewView {
        let view = MarkdownPreviewView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.usesFontPanel = false
        view.usesRuler = false
        view.allowsUndo = false
        view.drawsBackground = false
        view.focusRingType = .none
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.minSize = .zero
        view.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        // The run's own colour is the theme's link colour; the view adds only
        // the hand, not its default blue and underline.
        view.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        apply(to: view)
        return view
    }

    func updateNSView(_ view: MarkdownPreviewView, context: Context) {
        apply(to: view)
    }

    /// Rebuilds the text only when one of its inputs changed: the closures are
    /// reassigned every update (cheap), the attributed string is not.
    private func apply(to view: MarkdownPreviewView) {
        view.onTap = onTap
        view.onToggleCheckbox = onToggleCheckbox
        // Read inside the view update, so the `@Observable` accesses register
        // and a typeface or theme change re-renders (the `Card` pattern).
        let settings = SettingsStore.shared
        let config = MarkdownRichText.Config(
            textStyle: textStyle,
            typeface: settings.typeface,
            theme: settings.theme
        )
        let key = MarkdownPreviewView.Key(markdown: markdown, config: config)
        guard view.key != key else { return }
        view.key = key
        let rendered = MarkdownRichText.render(markdown, config: config)
        view.textStorage?.setAttributedString(rendered.text)
        view.decorations = rendered.decorations
    }

    /// The height the text lays out to at the width being proposed.
    ///
    /// Measured on an **offscreen** text view rather than the one on screen:
    /// SwiftUI asks several times per layout pass, at widths it is only trying
    /// out, and each ask sets the container's width — so a stale one could be
    /// left behind on the view that has to draw. The measurer carries the same
    /// text and the same container settings, so its answer is the real one's.
    ///
    /// An unspecified or unbounded width is the *ideal*-width question, not a
    /// wrap: lay out unbounded and answer the width the longest line actually
    /// wants, which is what the `frame(maxWidth: .infinity)` around this then
    /// overrides.
    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: MarkdownPreviewView, context: Context
    ) -> CGSize? {
        guard let key = nsView.key else { return nil }
        // A finite width is a real wrap — **including zero**, which is how the
        // minimum width is asked for; answering the natural width there would
        // tell the row this body can never be narrower than its longest line.
        // Only an unspecified or infinite width is the ideal-width question.
        let proposed = proposal.width.flatMap { $0.isFinite ? max($0, 0) : nil }
        let width = proposed.map { max($0, 1) } ?? CGFloat.greatestFiniteMagnitude
        // Memoised on the body and the width: SwiftUI asks several times per
        // pass and per card, and a miss costs the measurer a fresh copy of the
        // text. `MarkdownParser.parse`'s reason, on the layout path.
        let used = Self.sizes.value(for: SizeKey(key: key, width: width)) {
            let measurer = MarkdownPreviewView.measurer
            measurer.adopt(nsView)
            return measurer.usedSize(forWidth: width)
        }
        return CGSize(width: proposed ?? used.width, height: used.height)
    }

    private struct SizeKey: Hashable {
        var key: MarkdownPreviewView.Key
        var width: CGFloat
    }

    @MainActor private static let sizes = MemoCache<SizeKey, CGSize>(limit: 512)
}

/// The read-only text view behind `MarkdownPreview`. Four things are its own:
/// the click-versus-drag decision that turns a plain click into `onTap`, the
/// pointing hand over the one run that answers a click of its own, the block
/// decorations drawn under the text (the quote bar, the code block's
/// background, the rule), and a copy that hands out `MarkdownRichText.export`
/// rather than the storage as it is — the marker runs carry glyphs and
/// attachments that mean nothing pasted elsewhere.
final class MarkdownPreviewView: NSTextView {
    struct Key: Hashable {
        var markdown: String
        var config: MarkdownRichText.Config
    }

    var key: Key?
    var onTap: (() -> Void)?
    var onToggleCheckbox: ((Int) -> Void)?
    var decorations: [MarkdownRichText.Decoration] = [] {
        didSet { needsDisplay = true }
    }

    /// The height of the text laid out at `width`, from TextKit 2's own usage
    /// bounds after a forced layout. Setting the container's width is what
    /// re-wraps; an unchanged width is a no-op and the layout is cached.
    func height(forWidth width: CGFloat) -> CGFloat {
        usedSize(forWidth: width).height
    }

    /// The box the text occupies at `width` — its height, and the width the
    /// longest line wanted, which is the honest answer to an ideal-width ask.
    func usedSize(forWidth width: CGFloat) -> CGSize {
        guard let container = textContainer, let layout = textLayoutManager else { return .zero }
        let size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        if container.size != size { container.size = size }
        layout.ensureLayout(for: layout.documentRange)
        let used = layout.usageBoundsForTextContainer
        return CGSize(width: ceil(used.width), height: ceil(used.height))
    }

    /// The one offscreen view every measurement goes through, so no measuring
    /// pass ever re-wraps a view that is on screen.
    @MainActor static let measurer: MarkdownPreviewView = {
        let view = MarkdownPreviewView(usingTextLayoutManager: true)
        view.isEditable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        return view
    }()

    /// Takes on another view's text, if it isn't already carrying it.
    func adopt(_ other: MarkdownPreviewView) {
        guard key != other.key else { return }
        key = other.key
        textStorage?.setAttributedString(other.textStorage ?? NSAttributedString())
    }

    // MARK: Clicks

    /// Where the mouse went down, in the view; `nil` once the click is settled.
    /// `NSTextView.mouseDown` tracks the whole drag before it returns on some
    /// paths and hands `mouseUp` on others, so the click is settled from
    /// whichever of the two comes with the button up — once.
    private var pressPoint: CGPoint?

    override func mouseDown(with event: NSEvent) {
        pressPoint = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
        if NSEvent.pressedMouseButtons & 1 == 0 {
            settleClick(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        settleClick(with: event)
    }

    private func settleClick(with event: NSEvent) {
        guard let start = pressPoint else { return }
        pressPoint = nil
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) < 4,
              selectedRange().length == 0 else { return }
        let index = characterIndexForInsertion(at: point)
        guard let storage = textStorage else { return }
        let length = storage.length
        // Insertion indices land either side of a one-character marker, so the
        // character before the point counts too.
        for candidate in [index, index - 1] where candidate >= 0 && candidate < length {
            let attrs = storage.attributes(at: candidate, effectiveRange: nil)
            if let line = attrs[.markdownCheckbox] as? Int {
                onToggleCheckbox?(line)
                return
            }
            if attrs[.link] != nil { return }
        }
        onTap?()
    }

    // MARK: Cursor

    /// The pointing hand over a checkbox — the one run in a body that answers a
    /// click of its own rather than starting a selection, so the pointer says so
    /// before the click is spent. Everywhere else keeps the I-beam, which is the
    /// honest mark for text that selects.
    ///
    /// **A cursor rect was tried first and never appeared.** `resetCursorRects`
    /// with the hand added after `super`'s I-beam is the pattern every "pointing
    /// hand over a link in an `NSTextView`" uses, and inside a card it did
    /// nothing — the window's cursor-rect machinery is not what puts the I-beam
    /// on a text view hosted by SwiftUI. *Why* was not instrumented; that it
    /// didn't show is the finding. So the cursor is set where the mouse is
    /// actually reported instead: a tracking area of our own, answered in
    /// `cursorUpdate` (the entry) and `mouseMoved` (crossing from text onto the
    /// mark without leaving the view). Both set the cursor **last**, after the
    /// window has already had its say, which is what makes them stick.
    private var hoverArea: NSTrackingArea?

    /// `.inVisibleRect` keeps the area in step with scrolling and resizing on
    /// its own, so the rect passed here is ignored — the one thing a cursor rect
    /// would have needed re-establishing by hand.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        guard isOverCheckbox(event) else { return super.cursorUpdate(with: event) }
        NSCursor.pointingHand.set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard isOverCheckbox(event) else { return super.mouseMoved(with: event) }
        NSCursor.pointingHand.set()
    }

    private func isOverCheckbox(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        return cachedCheckboxRects().contains { $0.contains(point) }
    }

    /// The rects, memoised on the text and the width that wrapped it: this runs
    /// per mouse-moved event, and measuring segments per event is the
    /// formatter-per-call mistake on the hover path.
    private var hoverCache: (key: Key?, width: CGFloat, rects: [CGRect])?

    private func cachedCheckboxRects() -> [CGRect] {
        if let hoverCache, hoverCache.key == key, hoverCache.width == bounds.width {
            return hoverCache.rects
        }
        let rects = checkboxRects()
        hoverCache = (key, bounds.width, rects)
        return rects
    }

    /// The boxes the checkbox markers occupy, in view coordinates.
    ///
    /// TextKit 2's own **segments** rather than `textRect(for:in:)`'s line
    /// boxes: a line box is the whole item, and the hand belongs on the mark.
    /// The run is the mark *and its tab*, which is deliberate — that is exactly
    /// what `settleClick` treats as the checkbox, so the pointer promises a
    /// click where a click really lands.
    func checkboxRects() -> [CGRect] {
        guard onToggleCheckbox != nil, let storage = textStorage, storage.length > 0,
              let layout = textLayoutManager, let content = layout.textContentManager
        else { return [] }
        let origin = textContainerOrigin
        var rects: [CGRect] = []
        storage.enumerateAttribute(
            .markdownCheckbox, in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            guard value != nil,
                  let start = content.location(layout.documentRange.location, offsetBy: range.location),
                  let end = content.location(layout.documentRange.location, offsetBy: range.upperBound),
                  let span = NSTextRange(location: start, end: end)
            else { return }
            layout.enumerateTextSegments(in: span, type: .standard, options: [.rangeNotRequired]) {
                _, frame, _, _ in
                rects.append(frame.offsetBy(dx: origin.x, dy: origin.y))
                return true
            }
        }
        return rects
    }

    // MARK: Decorations

    override func draw(_ dirtyRect: NSRect) {
        drawDecorations()
        super.draw(dirtyRect)
    }

    private func drawDecorations() {
        guard !decorations.isEmpty, let layout = textLayoutManager else { return }
        let width = bounds.width
        for decoration in decorations {
            guard let rect = textRect(for: decoration.range, in: layout) else { continue }
            switch decoration.kind {
            case .quote:
                // At the paragraph's edge, not the text's: the lines are indented
                // past the bar, so their box starts where the bar ends.
                let bar = CGRect(x: textContainerOrigin.x, y: rect.minY,
                                 width: MarkdownRichText.quoteBarWidth, height: rect.height)
                NSColor.secondaryLabelColor.withAlphaComponent(0.4).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
            case .code:
                let pad = MarkdownRichText.codePadding
                let box = CGRect(x: 0, y: rect.minY - pad, width: width, height: rect.height + 2 * pad)
                NSColor.labelColor.withAlphaComponent(0.06).setFill()
                NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
            case .rule:
                let line = CGRect(x: 0, y: rect.midY.rounded() - 0.5, width: width, height: 1)
                NSColor.separatorColor.setFill()
                line.fill()
            }
        }
    }

    /// The union of the **line** boxes a character range occupies, in view
    /// coordinates — the lines rather than the layout fragments, so a
    /// paragraph's spacing before and after it isn't painted as part of it.
    private func textRect(for range: NSRange, in layout: NSTextLayoutManager) -> CGRect? {
        guard let content = layout.textContentManager,
              let start = content.location(layout.documentRange.location, offsetBy: range.location),
              let end = content.location(layout.documentRange.location, offsetBy: range.upperBound)
        else { return nil }
        var union: CGRect?
        _ = layout.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let origin = fragment.layoutFragmentFrame.origin
            for line in fragment.textLineFragments {
                let box = line.typographicBounds.offsetBy(dx: origin.x, dy: origin.y)
                union = union.map { $0.union(box) } ?? box
            }
            return fragment.rangeInElement.endLocation.compare(end) == .orderedAscending
        }
        return union?.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    // MARK: Copy

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let selected = textStorage?.attributedSubstring(from: selectedRange()) ?? NSAttributedString()
        let export = MarkdownRichText.export(selected)
        pboard.declareTypes([.rtf, .string], owner: nil)
        var wrote = false
        if let rtf = export.rtf { wrote = pboard.setData(rtf, forType: .rtf) || wrote }
        wrote = pboard.setString(export.string, forType: .string) || wrote
        return wrote
    }

    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = writeSelection(to: pasteboard, types: [.rtf, .string])
    }
}

extension NSAttributedString.Key {
    /// What a run stands for when it leaves the view: the bullet glyph and its
    /// tab become `• `, a number `1. `, a checkbox `☐ ` or `☑ `, a rule `---`.
    static let markdownPlain = NSAttributedString.Key("insert.markdownPlain")
    /// The source line of the `- [ ]` item whose mark this run is.
    static let markdownCheckbox = NSAttributedString.Key("insert.markdownCheckbox")
}

/// Markdown → `NSAttributedString`, the preview's half of `MarkdownText` said in
/// AppKit terms. Same parser, same block rules, same faces: headings through
/// `MarkdownText.headingFont`, bold by the descriptor union, italic through
/// `Card.italic` (so Rounded's synthesised oblique and Grotesk's variable-axis
/// trap arrive solved), code monospaced, links in the theme's link colour.
///
/// Also the **export** the copy hands out: the same string with the marker runs
/// replaced by their plain spelling, every colour dropped (a `labelColor`
/// resolved in Dark Mode is white, and white text pasted into a white document
/// is invisible), and the card face swapped for a family other apps can name —
/// none of the five faces is installed on the Mac under a name RTF can carry.
enum MarkdownRichText {
    struct Config: Hashable {
        var textStyle: NSFont.TextStyle
        var typeface: Typeface
        var theme: AppTheme
    }

    struct Decoration: Equatable {
        enum Kind { case quote, code, rule }
        var kind: Kind
        var range: NSRange
    }

    struct Rendered {
        var text: NSAttributedString
        var decorations: [Decoration]
    }

    static let quoteBarWidth: CGFloat = 3
    static let codePadding: CGFloat = 10
    /// The gap between a list marker and its item (`MarkdownText.markerGap`).
    private static let markerGap: CGFloat = 8
    /// One level of nesting: the marker column, dot plus gap (`MarkdownText.listIndent`).
    /// The list as a whole steps in by `MarkdownText.listInset` on top of it, so
    /// the render matches the editor's paragraph style line for line.
    private static let listIndent: CGFloat = 5 + markerGap

    // MARK: Rendering

    static func render(_ markdown: String, config: Config) -> Rendered {
        let base = Card.nsFont(config.textStyle, typeface: config.typeface)
        let palette = Palette(
            text: NSColor(config.theme.bodyText),
            secondary: .secondaryLabelColor,
            link: NSColor(config.theme.link),
            primary: NSColor(config.theme.primary)
        )
        var builder = Builder(base: base, typeface: config.typeface, palette: palette)
        let blocks = MarkdownParser.parse(markdown)
        for (index, block) in blocks.enumerated() {
            builder.append(block, last: index == blocks.count - 1)
        }
        return Rendered(text: builder.out, decorations: builder.decorations)
    }

    struct Palette {
        var text: NSColor
        var secondary: NSColor
        var link: NSColor
        /// The tick's colour — the task checkbox's, read off the theme.
        var primary: NSColor
    }

    private struct Builder {
        let base: NSFont
        let typeface: Typeface
        let palette: Palette
        var out = NSMutableAttributedString()
        var decorations: [Decoration] = []

        init(base: NSFont, typeface: Typeface, palette: Palette) {
            self.base = base
            self.typeface = typeface
            self.palette = palette
        }

        /// One blank source line, `MarkdownText.blankLine`'s rule: the gap
        /// between blocks is what the editor shows for the empty line between
        /// them, so the card keeps its shape across the flip.
        private var blankLine: CGFloat {
            (base.ascender - base.descender + base.leading).rounded()
        }

        private func paragraph(_ configure: (NSMutableParagraphStyle) -> Void = { _ in }) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            configure(style)
            return style
        }

        private mutating func newline() {
            out.append(NSAttributedString(string: "\n", attributes: [.font: base]))
        }

        mutating func append(_ block: MarkdownParser.Block, last: Bool) {
            let after = last ? 0 : blankLine
            switch block {
            case .heading(let level, let text):
                let font = MarkdownText.headingFont(level, typeface: typeface)
                let style = paragraph {
                    $0.paragraphSpacing = after
                    $0.paragraphSpacingBefore = level <= 2 ? 2 : 0
                }
                out.append(inline(text, font: font, colour: palette.text, paragraph: style))
            case .paragraph(let text):
                let style = paragraph { $0.paragraphSpacing = after }
                out.append(inline(text, font: base, colour: palette.text, paragraph: style))
            // Half a line between items and an inset for the whole list, the two
            // things `MarkdownText` and the editor's paragraph style already do —
            // the flip between the modes has to move nothing.
            case .list(let items):
                let numbers = MarkdownParser.numbering(items)
                let gap = MarkdownText.listGap(base)
                for (index, item) in items.enumerated() {
                    appendItem(item, number: numbers[index],
                               after: index == items.count - 1 ? after : gap)
                    if index < items.count - 1 { newline() }
                }
            case .quote(let lines):
                let start = out.length
                for (index, line) in lines.enumerated() {
                    let style = paragraph {
                        $0.firstLineHeadIndent = quoteBarWidth + markerGap
                        $0.headIndent = quoteBarWidth + markerGap
                        $0.paragraphSpacing = index == lines.count - 1 ? after : 0
                    }
                    // A `>` on its own is a paragraph break inside the quote; a
                    // space keeps the line at full height, as the editor shows it.
                    out.append(inline(line.isEmpty ? " " : line, font: base,
                                      colour: palette.secondary, paragraph: style))
                    if index < lines.count - 1 { newline() }
                }
                decorations.append(Decoration(kind: .quote, range: NSRange(location: start, length: out.length - start)))
            case .code(let code):
                let start = out.length
                let font = NSFont.monospacedSystemFont(
                    ofSize: NSFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular
                )
                let lines = code.components(separatedBy: "\n")
                for (index, line) in lines.enumerated() {
                    let style = paragraph {
                        $0.firstLineHeadIndent = codePadding
                        $0.headIndent = codePadding
                        $0.tailIndent = -codePadding
                        $0.lineBreakMode = .byCharWrapping
                        $0.paragraphSpacingBefore = index == 0 ? codePadding : 0
                        $0.paragraphSpacing = index == lines.count - 1 ? codePadding + after : 0
                    }
                    out.append(NSAttributedString(string: line.isEmpty ? " " : line, attributes: [
                        .font: font, .foregroundColor: palette.text, .paragraphStyle: style,
                    ]))
                    if index < lines.count - 1 { newline() }
                }
                decorations.append(Decoration(kind: .code, range: NSRange(location: start, length: out.length - start)))
            case .rule:
                // `Divider` plus its 2pt of padding either side: a 5pt line box
                // holding a character too small to show, with the line drawn
                // across it by the view.
                let start = out.length
                let style = paragraph {
                    $0.minimumLineHeight = 5
                    $0.maximumLineHeight = 5
                    $0.paragraphSpacing = after
                }
                out.append(NSAttributedString(string: "\u{00A0}", attributes: [
                    .font: NSFont.systemFont(ofSize: 4),
                    .paragraphStyle: style,
                    .markdownPlain: "---",
                ]))
                decorations.append(Decoration(kind: .rule, range: NSRange(location: start, length: 1)))
            }
            if !last { newline() }
        }

        /// A list item: marker, tab, text — the marker column sized off the
        /// marker actually drawn, so a wrapped line's text lines up under the
        /// first line's, and a `10.` gets the width it needs.
        private mutating func appendItem(_ item: MarkdownParser.ListItem, number: Int?, after: CGFloat) {
            let indent = MarkdownText.listInset + CGFloat(item.level) * listIndent
            let marker: NSAttributedString
            if let checked = item.checked {
                marker = checkbox(checked, line: item.line)
            } else if let number {
                marker = NSAttributedString(string: "\(number).\t", attributes: [
                    .font: NSFont(descriptor: base.fontDescriptor.addingAttributes([
                        .featureSettings: [[
                            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
                        ]],
                    ]), size: base.pointSize) ?? base,
                    .foregroundColor: palette.secondary,
                    .markdownPlain: "\(number). ",
                ])
            } else {
                marker = bullet()
            }
            // The marker without its tab: a tab measured on its own is a stop
            // nobody set.
            let markerWidth = marker.attributedSubstring(from: NSRange(location: 0, length: marker.length - 1)).size().width
            let textStart = indent + ceil(markerWidth) + markerGap
            let style = paragraph {
                $0.firstLineHeadIndent = indent
                $0.headIndent = textStart
                $0.tabStops = [NSTextTab(textAlignment: .left, location: textStart)]
                $0.defaultTabInterval = textStart
                $0.paragraphSpacing = after
            }
            let line = NSMutableAttributedString(attributedString: marker)
            var text = inline(item.text, font: base, colour: palette.text, paragraph: style)
            if item.checked == true {
                // A ticked item's text is struck through and stepped back — the
                // done task's two marks.
                let struck = NSMutableAttributedString(attributedString: text)
                struck.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: palette.secondary,
                ], range: NSRange(location: 0, length: struck.length))
                text = struck
            }
            line.append(text)
            line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
            out.append(line)
        }

        /// The bullet, drawn rather than typed: `•` is 2.6pt of ink at body
        /// size, so the glyph is `●` scaled to the 5pt circle `MarkdownText`
        /// draws (0.48 of the body size measures 5.1pt), lifted onto the
        /// x-height. It leaves the view as `• `.
        private func bullet() -> NSAttributedString {
            let size = (base.pointSize * 0.48).rounded(toPlaces: 1)
            let inkCentre = size * 0.373
            return NSAttributedString(string: "\u{25CF}\t", attributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: palette.secondary,
                .baselineOffset: (base.xHeight / 2 - inkCentre).rounded(toPlaces: 1),
                .markdownPlain: "\u{2022} ",
            ])
        }

        /// The task row's own glyph pair at the body size, as an attachment the
        /// view can hit-test back to its source line.
        private func checkbox(_ checked: Bool, line: Int) -> NSAttributedString {
            let name = checked ? "checkmark.circle.fill" : "circle"
            let colour = checked ? palette.primary : palette.secondary
            let attachment = NSTextAttachment()
            let configuration = NSImage.SymbolConfiguration(pointSize: base.pointSize, weight: .regular)
                .applying(.init(paletteColors: [colour]))
            attachment.image = NSImage(systemSymbolName: name, accessibilityDescription: checked ? "Done" : "Not done")?
                .withSymbolConfiguration(configuration)
            let side = base.pointSize
            attachment.bounds = CGRect(x: 0, y: (base.capHeight - side) / 2, width: side, height: side)
            let mark = NSMutableAttributedString(attachment: attachment)
            mark.append(NSAttributedString(string: "\t"))
            mark.addAttributes([
                .font: base,
                .markdownPlain: checked ? "\u{2611} " : "\u{2610} ",
                .markdownCheckbox: line,
                // The second route to the pointing hand, beside the view's own
                // hover tracking: `NSCursorAttributeName` is AppKit's own way of
                // saying a run isn't the I-beam's — it is how a link gets the
                // hand (`linkTextAttributes`) — and it costs a dictionary entry.
                // Whether a text view still reads it under TextKit 2 was not
                // established, which is why the view doesn't rely on it.
                .cursor: NSCursor.pointingHand,
            ], range: NSRange(location: 0, length: mark.length))
            return mark
        }

        /// The inline half: bold, italic, code, links, strikethrough and the
        /// `<u>` spans ⌘U writes, resolved to fonts and attributes.
        private func inline(_ text: String, font: NSFont, colour: NSColor,
                            paragraph: NSParagraphStyle) -> NSAttributedString {
            let out = NSMutableAttributedString()
            var rest = Substring(text)
            while let open = rest.range(of: "<u>"),
                  let close = rest.range(of: "</u>", range: open.upperBound..<rest.endIndex) {
                out.append(fragment(String(rest[..<open.lowerBound]), font: font, colour: colour))
                let underlined = NSMutableAttributedString(attributedString: fragment(
                    String(rest[open.upperBound..<close.lowerBound]), font: font, colour: colour
                ))
                underlined.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                        range: NSRange(location: 0, length: underlined.length))
                out.append(underlined)
                rest = rest[close.upperBound...]
            }
            out.append(fragment(String(rest), font: font, colour: colour))
            out.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: out.length))
            return out
        }

        private func fragment(_ text: String, font: NSFont, colour: NSColor) -> NSAttributedString {
            guard !text.isEmpty else { return NSAttributedString() }
            guard let parsed = try? AttributedString(
                markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) else {
                return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: colour])
            }
            let out = NSMutableAttributedString()
            for run in parsed.runs {
                let intent = run.inlinePresentationIntent ?? []
                var style = MarkdownHighlight.Style()
                style.bold = intent.contains(.stronglyEmphasized)
                style.italic = intent.contains(.emphasized)
                style.mono = intent.contains(.code)
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: MarkdownHighlight.font(for: style, base: font, typeface: typeface),
                    .foregroundColor: colour,
                ]
                if intent.contains(.strikethrough) {
                    attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
                if let link = run.link {
                    attrs[.link] = link
                    attrs[.foregroundColor] = palette.link
                }
                out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attrs))
            }
            return out
        }
    }

    // MARK: Export

    struct Export {
        var string: String
        var rtf: Data?
    }

    /// What leaves the view. Marker runs become their plain spelling, colours
    /// go, the card face becomes a portable family with its size and traits
    /// kept, and the plain flavour is the same characters with no attributes.
    static func export(_ attributed: NSAttributedString) -> Export {
        let out = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: out.length)
        var replacements: [(NSRange, NSAttributedString)] = []
        out.enumerateAttribute(.markdownPlain, in: full) { value, range, _ in
            guard let plain = value as? String else { return }
            var attrs = out.attributes(at: range.location, effectiveRange: nil)
            attrs[.attachment] = nil
            attrs[.markdownPlain] = nil
            attrs[.markdownCheckbox] = nil
            attrs[.cursor] = nil
            attrs[.baselineOffset] = nil
            replacements.append((range, NSAttributedString(string: plain, attributes: attrs)))
        }
        for (range, replacement) in replacements.reversed() {
            out.replaceCharacters(in: range, with: replacement)
        }
        let range = NSRange(location: 0, length: out.length)
        out.removeAttribute(.foregroundColor, range: range)
        out.removeAttribute(.backgroundColor, range: range)
        out.removeAttribute(.markdownCheckbox, range: range)
        out.removeAttribute(.cursor, range: range)
        out.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont else { return }
            out.addAttribute(.font, value: portable(font), range: run)
        }
        let rtf = out.rtf(from: range, documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf,
        ])
        return Export(string: out.string, rtf: rtf)
    }

    /// The same size and traits in a family another app can resolve. The five
    /// card faces are the system's hidden designs or the bundled Grotesk, none
    /// reachable by the name RTF would carry; monospaced runs go to Menlo.
    static func portable(_ font: NSFont) -> NSFont {
        let traits = font.fontDescriptor.symbolicTraits
        let family = traits.contains(.monoSpace) ? "Menlo" : "Helvetica Neue"
        var descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        var wanted: NSFontDescriptor.SymbolicTraits = []
        if traits.contains(.bold) { wanted.insert(.bold) }
        // A synthesised oblique (`Card.italic` on a face with no italic) is a
        // slant in the matrix, not a trait; it leaves as a real italic.
        if traits.contains(.italic) || CTFontGetMatrix(font as CTFont).c != 0 { wanted.insert(.italic) }
        if !wanted.isEmpty { descriptor = descriptor.withSymbolicTraits(wanted) }
        let candidate = NSFont(descriptor: descriptor, size: font.pointSize)
        // A trait the family has no face for hands back nil rather than a
        // fallback; drop to the plain family before giving up on the family.
        return candidate
            ?? NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: font.pointSize)
            ?? font
    }
}

private extension CGFloat {
    func rounded(toPlaces places: Int) -> CGFloat {
        let factor = pow(10, CGFloat(places))
        return (self * factor).rounded() / factor
    }
}
