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
/// own tap gesture never sees it), except on a link, whose destination the view
/// checks and opens itself, and on a checkbox, which flips its line; and the
/// text sits at the same 5pt inset the editor's `lineFragmentPadding` gives,
/// applied by the caller as padding, so the preview/source flip still lands on
/// one frame.
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
        // Its own delegate, so a clicked link goes through `follow(_:)` — the
        // second half of the destination check the render already made.
        view.delegate = view
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
        // and a typeface, theme, size or leading change re-renders (the `Card`
        // pattern). All four are in the key, so the render cache misses too.
        //
        // The three reading values come from `CardTextMetrics`, the one resolver
        // the editor and both sizing proxies also consume; the render itself
        // runs **nonisolated** off this `Config`, which is why the multiple
        // travels rather than the resolved leading and why the reads happen
        // here rather than there.
        let reading = CardTextMetrics.current(for: textStyle)
        let config = MarkdownRichText.Config(
            textStyle: textStyle,
            typeface: reading.typeface,
            theme: SettingsStore.shared.theme,
            scale: reading.scale,
            lineHeight: reading.lineHeight
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
        Self.size(for: proposal, of: nsView)
    }

    /// `sizeThatFits` without the representable's `Context` — which the answer
    /// never depended on, and which a test can't build.
    @MainActor
    static func size(for proposal: ProposedViewSize, of nsView: MarkdownPreviewView) -> CGSize? {
        // A purely geometric re-run evaluates no view body at all, so this is
        // the only counter that sees one. See `LayoutProbe`.
        LayoutProbe.count(.measure, "preview")
        guard let key = nsView.key else { return nil }
        // A finite width is a real wrap — and **zero** is how the minimum width
        // is asked for, so the *width* answered there stays zero rather than
        // the natural one, which would tell the row this body can never be
        // narrower than its longest line.
        let proposed = proposal.width.flatMap { $0.isFinite ? max($0, 0) : nil }
        // The *height* is a different question, and a wrap can't answer it at
        // zero: laying the body out at one point (the old `max($0, 1)`) stacks
        // it one character per line, a height nothing on screen will ever have.
        // So zero and unspecified both lay out unbounded — the ideal width's
        // height — and only an unspecified or infinite width also *answers*
        // with that width.
        let width = proposed.flatMap { $0 > 0 ? $0 : nil } ?? CGFloat.greatestFiniteMagnitude
        // Memoised on the body and the width: SwiftUI asks several times per
        // pass and per card, and a miss costs the measurer a fresh copy of the
        // text. `MarkdownParser.parse`'s reason, on the layout path.
        let used = sizes.value(for: SizeKey(key: key, width: width)) {
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

/// The read-only text view behind `MarkdownPreview`. Five things are its own:
/// the click-versus-drag decision that turns a plain click into `onTap`, the
/// pointing hand over the one run that answers a click of its own, the block
/// decorations drawn under the text (the quote bar, the code block's
/// background, the rule), a copy that hands out `MarkdownRichText.export`
/// rather than the storage as it is — the marker runs carry glyphs and
/// attachments that mean nothing pasted elsewhere — and which destinations a
/// clicked link is allowed to open.
final class MarkdownPreviewView: NSTextView, NSTextViewDelegate {
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

    /// The box the text occupies at `width` — its height, and the width the
    /// longest line wanted, which is the honest answer to an ideal-width ask.
    /// From TextKit 2's own usage bounds after a forced layout: setting the
    /// container's width is what re-wraps, and an unchanged width is a no-op
    /// whose layout is already cached.
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
        switch clickTarget(at: point) {
        case .checkbox(let line): onToggleCheckbox?(line)
        case .link: break
        case .tap: onTap?()
        }
    }

    /// What a settled click lands on: the checkbox it flips, a link (which the
    /// view follows itself), or the words — which the card reads as "open me".
    enum ClickTarget: Equatable {
        case tap
        case checkbox(line: Int)
        case link
    }

    /// Internal rather than folded into `settleClick`, so the rule can be
    /// driven without a window: `NSTextView`'s own `mouseDown` tracks the drag
    /// out of the window's event queue, and a test has no window to feed it.
    func clickTarget(at point: CGPoint) -> ClickTarget {
        guard let storage = textStorage else { return .tap }
        let length = storage.length
        let index = characterIndexForInsertion(at: point)
        // Insertion indices land either side of a one-character marker, so the
        // character before the point counts too — but not past the end of the
        // text, where `characterIndexForInsertion` answers `length` for a click
        // anywhere in the card's empty space below the body. A body ending in
        // an empty checklist item ends in that marker's tab, so accepting
        // `index - 1` there flipped the box, and saved it, on a click that
        // should have opened the card. The last character counts only when the
        // click really landed on it.
        var candidates = [index]
        if index < length || glyphRect(at: index - 1)?.contains(point) == true {
            candidates.append(index - 1)
        }
        for candidate in candidates where candidate >= 0 && candidate < length {
            let attrs = storage.attributes(at: candidate, effectiveRange: nil)
            if let line = attrs[.markdownCheckbox] as? Int { return .checkbox(line: line) }
            if attrs[.link] != nil { return .link }
        }
        return .tap
    }

    /// The box the character at `index` occupies, in view coordinates — the
    /// same TextKit 2 segments `checkboxRects()` measures the hand from.
    private func glyphRect(at index: Int) -> CGRect? {
        guard index >= 0, let storage = textStorage, index < storage.length,
              let layout = textLayoutManager, let content = layout.textContentManager,
              let start = content.location(layout.documentRange.location, offsetBy: index),
              let end = content.location(start, offsetBy: 1),
              let span = NSTextRange(location: start, end: end)
        else { return nil }
        var union: CGRect?
        layout.enumerateTextSegments(in: span, type: .standard, options: [.rangeNotRequired]) {
            _, frame, _, _ in
            union = union.map { $0.union(frame) } ?? frame
            return true
        }
        return union?.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    // MARK: Links

    /// A clicked link is the view's to follow, not AppKit's: its default hands
    /// the destination to the workspace whatever it is, so `file://` in a
    /// synced note is one click from launching an application. Both routes end
    /// here — the view's own `clicked(onLink:at:)`, which is what mouse
    /// tracking calls, and the delegate message it sends on.
    override func clicked(onLink link: Any, at charIndex: Int) {
        follow(link)
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        follow(link)
        return true
    }

    private func follow(_ link: Any) {
        guard let url = Self.openableDestination(link) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The destination this view will open, or `nil`. The render already
    /// refuses a scheme `MarkdownFormatting.isLinkDestination` doesn't name, so
    /// a body of ours carries no other kind — this is the same check made again
    /// where the click lands, because a `.link` attribute is only ever one
    /// attribute in a storage that other code can write to.
    nonisolated static func openableDestination(_ link: Any) -> URL? {
        let text: String
        switch link {
        case let url as URL: text = url.absoluteString
        case let string as String: text = string
        default: return nil
        }
        guard MarkdownFormatting.isLinkDestination(text) else { return nil }
        return link as? URL ?? URL(string: text)
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
        pboard.declareTypes([.rtf, .html, .string], owner: nil)
        var wrote = false
        if let rtf = export.rtf { wrote = pboard.setData(rtf, forType: .rtf) || wrote }
        if let html = export.html { wrote = pboard.setData(html, forType: .html) || wrote }
        wrote = pboard.setString(export.string, forType: .string) || wrote
        return wrote
    }

    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = writeSelection(to: pasteboard, types: [.rtf, .html, .string])
    }
}

extension NSAttributedString.Key {
    /// What a run stands for when it leaves the view: the bullet glyph and its
    /// tab become `• `, a number `1. `, a checkbox `☐ ` or `☑ `, a rule `---`.
    static let markdownPlain = NSAttributedString.Key("insert.markdownPlain")
    /// The list item a bullet or number run heads (`MarkdownRichText.ListMark`),
    /// so the export can make the paragraph a real list entry.
    static let markdownList = NSAttributedString.Key("insert.markdownList")
    /// The source line of the `- [ ]` item whose mark this run is.
    static let markdownCheckbox = NSAttributedString.Key("insert.markdownCheckbox")
}

/// Markdown → `NSAttributedString`, the preview's half of `MarkdownText` said in
/// AppKit terms. Same parser, same block rules, same faces: headings through
/// `MarkdownText.headingFont`, bold by the descriptor union, italic through
/// `Card.italic` (so Rounded's synthesised oblique and Grotesk's variable-axis
/// trap arrive solved), code monospaced, links in the theme's link colour.
///
/// Also the **export** the copy hands out: the same string with bullets and
/// numbers turned into real list paragraphs, the other marker runs replaced by
/// their plain spelling, every colour dropped (a `labelColor` resolved in Dark
/// Mode is white, and white text pasted into a white document is invisible),
/// and the card face swapped for a family other apps can name — none of the
/// five faces is installed on the Mac under a name RTF can carry.
enum MarkdownRichText {
    struct ListMark: Hashable {
        var ordered: Bool
        var level: Int
    }

    struct Config: Hashable {
        var textStyle: NSFont.TextStyle
        var typeface: Typeface
        var theme: AppTheme
        /// The reading size, as a multiple of the style's own — `CardTextSize`.
        var scale: CGFloat = 1
        /// The reading leading, as a multiple of the font's own line height.
        /// Both ride in the config rather than being read here because this
        /// half is nonisolated and the config is the render and size cache key:
        /// changing either setting has to miss the cache, which it does by
        /// being part of what the key hashes.
        var lineHeight: Double = 1
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

    // MARK: Rendering

    static func render(_ markdown: String, config: Config) -> Rendered {
        let base = Card.nsFont(config.textStyle, typeface: config.typeface, scale: config.scale)
        let palette = Palette(
            text: NSColor(config.theme.bodyText),
            secondary: .secondaryLabelColor,
            link: NSColor(config.theme.link),
            primary: NSColor(config.theme.primary)
        )
        var builder = Builder(base: base, typeface: config.typeface, palette: palette,
                              scale: config.scale, lineHeight: config.lineHeight)
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
        let scale: CGFloat
        let lineHeight: Double
        var out = NSMutableAttributedString()
        var decorations: [Decoration] = []

        init(base: NSFont, typeface: Typeface, palette: Palette,
             scale: CGFloat, lineHeight: Double) {
            self.base = base
            self.typeface = typeface
            self.palette = palette
            self.scale = scale
            self.lineHeight = lineHeight
        }

        /// One blank source line, `MarkdownText.blankLine`'s rule: the gap
        /// between blocks is what the editor shows for the empty line between
        /// them, so the card keeps its shape across the flip. It carries the
        /// line spacing but not twice — AppKit puts one between the two
        /// paragraphs itself, which is the half `MarkdownText`'s own stack has
        /// to add by hand because separate views get none.
        private var blankLine: CGFloat {
            MarkdownText.blankLine(base, lineHeight: lineHeight)
        }

        /// Every paragraph in the render starts here: the base style both AppKit
        /// layouts of a card's Markdown share, which carries the reading leading
        /// and nothing else, plus this side's own extra — the wrap mode — on a
        /// copy of it. The editor layers a tab step on the same base.
        private func paragraph(_ configure: (NSMutableParagraphStyle) -> Void = { _ in }) -> NSParagraphStyle {
            let style = MarkdownText.paragraphStyle(base: base, lineHeight: lineHeight)
                .mutableCopy() as! NSMutableParagraphStyle
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
                let font = MarkdownText.headingFont(level, typeface: typeface, scale: scale)
                let style = paragraph {
                    $0.paragraphSpacing = after
                    $0.paragraphSpacingBefore = MarkdownText.headingGap(level)
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
                        $0.firstLineHeadIndent = quoteBarWidth + MarkdownText.markerGap
                        $0.headIndent = quoteBarWidth + MarkdownText.markerGap
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
                let font = MarkdownText.codeFont(scale: scale)
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
            let indent = MarkdownText.listInset + CGFloat(item.level) * MarkdownText.listIndent
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
                    .markdownList: ListMark(ordered: true, level: item.level),
                ])
            } else {
                marker = bullet(level: item.level)
            }
            // The marker without its tab: a tab measured on its own is a stop
            // nobody set.
            let markerWidth = marker.attributedSubstring(from: NSRange(location: 0, length: marker.length - 1)).size().width
            let textStart = indent + ceil(markerWidth) + MarkdownText.markerGap
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
        private func bullet(level: Int) -> NSAttributedString {
            let size = (base.pointSize * 0.48).rounded(toPlaces: 1)
            let inkCentre = size * 0.373
            return NSAttributedString(string: "\u{25CF}\t", attributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: palette.secondary,
                .baselineOffset: (base.xHeight / 2 - inkCentre).rounded(toPlaces: 1),
                .markdownPlain: "\u{2022} ",
                .markdownList: ListMark(ordered: false, level: level),
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
                // A destination `MarkdownFormatting.isLinkDestination` doesn't
                // name renders as the plain words it wraps: a body is Markdown
                // from a folder anything can write to, and
                // `[Report](file:///Applications/Calculator.app)` is otherwise
                // one click from launching an application. The same check runs
                // again on the click (`openableDestination`).
                if let link = run.link, MarkdownFormatting.isLinkDestination(link.absoluteString) {
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
        var html: Data?
    }

    /// What leaves the view. Bullets and numbers become list paragraphs, the
    /// other marker runs their plain spelling, colours go, the card face becomes
    /// a portable family with its size and traits kept. The plain flavour keeps
    /// every marker spelled out, since plain text has no lists to make. HTML
    /// rides beside the RTF because that is the flavour a web-based app reads.
    static func export(_ attributed: NSAttributedString) -> Export {
        let rich = portableText(attributed)
        let range = NSRange(location: 0, length: rich.length)
        return Export(
            string: spelledOut(attributed).string,
            rtf: rich.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]),
            html: try? rich.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
        )
    }

    /// The string the rich flavours are written from: the lists made real, the
    /// remaining marker runs spelled out, only the portable attributes left on
    /// it, and every font a family another app can name.
    static func portableText(_ attributed: NSAttributedString) -> NSAttributedString {
        let rich = spelledOut(listed(attributed))
        let range = NSRange(location: 0, length: rich.length)
        stripToPortableAttributes(rich)
        rich.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont else { return }
            rich.addAttribute(.font, value: portable(font), range: run)
        }
        return rich
    }

    /// Everything that may leave the view: the face, a destination, the two
    /// decorations ⌘U and `~~` write, and the paragraph's geometry — which
    /// carries the list, the indents and the spacing.
    ///
    /// An **allowlist**, not a list of the renderer's private keys: a wrong
    /// export is only ever seen in some other application, so an attribute the
    /// renderer gains later has to be dropped by default rather than leak until
    /// somebody pastes it somewhere. Colour is the case that matters most — a
    /// `labelColor` resolved in Dark Mode is white, invisible on a white page.
    static let portableAttributes: Set<NSAttributedString.Key> = [
        .font, .link, .underlineStyle, .strikethroughStyle, .paragraphStyle,
    ]

    private static func stripToPortableAttributes(_ text: NSMutableAttributedString) {
        var strips: [(range: NSRange, keys: [NSAttributedString.Key])] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            let extra = attrs.keys.filter { !portableAttributes.contains($0) }
            if !extra.isEmpty { strips.append((range, extra)) }
        }
        for strip in strips {
            for key in strip.keys { text.removeAttribute(key, range: strip.range) }
        }
    }

    /// One level of an exported list, in points — Word's own half inch.
    private static let exportListStep: CGFloat = 36

    /// Bullet and number runs become `NSTextList` paragraphs: the marker run
    /// itself is deleted, since both the RTF and the HTML writer draw a list
    /// paragraph's marker from the list rather than from the text. One list
    /// object per level, kept while the items run on consecutive paragraphs, so
    /// the numbering the writers count matches the parser's — a fresh list
    /// starts after any other paragraph, and a bullet interrupting a numbered
    /// level restarts that level. Checkboxes stay spelled out: neither format
    /// has a checklist.
    private static func listed(_ attributed: NSAttributedString) -> NSMutableAttributedString {
        let out = NSMutableAttributedString(attributedString: attributed)
        let string = out.string as NSString
        var open: [NSTextList] = []
        var previousEnd = -1
        var edits: [(marker: NSRange, paragraph: NSRange, style: NSParagraphStyle)] = []
        out.enumerateAttribute(.markdownList, in: NSRange(location: 0, length: out.length)) { value, range, _ in
            guard let mark = value as? ListMark else { return }
            let paragraph = string.paragraphRange(for: range)
            if paragraph.location != previousEnd { open.removeAll() }
            previousEnd = paragraph.upperBound
            let format: NSTextList.MarkerFormat = mark.ordered ? .decimal : .disc
            if open.count > mark.level + 1 { open.removeLast(open.count - mark.level - 1) }
            while open.count < mark.level { open.append(NSTextList(markerFormat: .disc, options: 0)) }
            if open.count == mark.level + 1, open[mark.level].markerFormat != format { open.removeLast() }
            if open.count == mark.level { open.append(NSTextList(markerFormat: format, options: 0)) }
            let existing = out.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let style = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.textLists = open
            style.headIndent = exportListStep * CGFloat(open.count)
            style.firstLineHeadIndent = exportListStep * CGFloat(open.count - 1)
            style.tabStops = []
            style.defaultTabInterval = exportListStep
            edits.append((range, paragraph, style))
        }
        for edit in edits.reversed() {
            out.addAttribute(.paragraphStyle, value: edit.style, range: edit.paragraph)
            out.deleteCharacters(in: edit.marker)
        }
        return out
    }

    /// The marker runs that are still characters — checkboxes and the rule, and
    /// every bullet and number in the plain flavour — as their plain spelling.
    private static func spelledOut(_ attributed: NSAttributedString) -> NSMutableAttributedString {
        let out = NSMutableAttributedString(attributedString: attributed)
        var replacements: [(NSRange, NSAttributedString)] = []
        out.enumerateAttribute(.markdownPlain, in: NSRange(location: 0, length: out.length)) { value, range, _ in
            guard let plain = value as? String else { return }
            var attrs = out.attributes(at: range.location, effectiveRange: nil)
            attrs[.attachment] = nil
            attrs[.markdownPlain] = nil
            attrs[.markdownList] = nil
            attrs[.markdownCheckbox] = nil
            attrs[.cursor] = nil
            attrs[.baselineOffset] = nil
            replacements.append((range, NSAttributedString(string: plain, attributes: attrs)))
        }
        for (range, replacement) in replacements.reversed() {
            out.replaceCharacters(in: range, with: replacement)
        }
        return out
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
