import AppKit
import SwiftUI

/// The Markdown source editor shared by note cards and task cards: an
/// `NSTextView` of our own, plus the formatting shortcuts — ⌘B bold, ⌘I italic,
/// ⌘U underline, ⇧⌘X strikethrough. Each wraps (or unwraps) the *selected* text
/// in the matching Markdown delimiters and does nothing when nothing is
/// selected; the actual string surgery lives in `MarkdownFormatting` so it can
/// be tested without a view. The keys are answered by the text view itself
/// (`performKeyEquivalent`), like Tab and Esc below — they were invisible
/// SwiftUI `keyboardShortcut` buttons reading the `selection` binding, and that
/// path stopped firing when the editor became a hosted text view (which link
/// broke was not instrumented; the buttons also applied the edit by assigning
/// the `text` binding, which never had undo).
///
/// **This was a SwiftUI `TextEditor` until spell checking had to work, and the
/// reason it isn't one any more is measured, not stylistic.** SwiftUI writes
/// `isContinuousSpellCheckingEnabled = false` on the hosted text view on every
/// graph update: instrumenting a typing session in this app on macOS 26 logged
/// **45 reversions across 44 keystrokes**, one per edit, 8–20ms after it, always
/// on the same text view object — so SwiftUI reconfigures the view rather than
/// rebuilding it. That is FB13607434
/// (github.com/feedback-assistant/reports/issues/467), still open, and Apple's
/// forums (thread 744800) describe the same thing from the outside: enabling
/// checking from the text view's own Control-click menu "works briefly but
/// becomes disabled again after typing a few characters". Turning the flag off
/// *clears* the marks and turning it on schedules a fresh check, so the only
/// workaround available from outside — re-asserting the flag — buys underlines
/// that flicker on every keystroke. Hosting the text view is the fix everyone
/// lands on, and it is the fix here: the flag is set once, in `makeNSView`, and
/// nothing takes it away, so AppKit marks incrementally around the edit and
/// keeps the marks it already has, the way Notes does.
///
/// What came with the change, since a hosted text view answers its own keys:
/// **⇧Tab** and **Esc** are now `insertBacktab(_:)` / `cancelOperation(_:)` overrides
/// rather than a local `NSEvent` monitor and an `onKeyPress` at the call sites —
/// the same two keys, answered in the one place that gets them first. **Return**
/// still goes through `MarkdownReturn`'s app-wide monitor below, which reads the
/// first responder and so needs no changing. And the editor takes an `NSFont`
/// rather than a `Font`: `Card` hands out both spellings of the same face, and
/// the call sites' sizing proxies keep using the SwiftUI one.
///
/// Placeholders and sizing proxies stay with the callers, which each have
/// their own.
struct MarkdownEditor: View {
    @Binding var text: String
    /// The card's face, as AppKit's. `Card.nsFont(_:)` is the same font the
    /// call sites' proxies measure with through `Card.font(_:)`.
    var font: NSFont
    /// The colour the source draws in, so the editor matches the preview it
    /// replaces — `AppTheme.bodyText`, which is `labelColor` in every theme
    /// since Dracula's removal. Passed in rather than
    /// read here, like `font`: the call site reads it inside a view body, so the
    /// `@Observable` access registers and a theme change repaints an open editor.
    var textColor: NSColor = .labelColor
    /// ⇧Tab — the owner's field traversal, which in a card means handing focus
    /// back to the title. **Tab is not this**: it inserts a literal tab, the
    /// text view's own behaviour, because a body is prose where an indent is
    /// something you type rather than a field in a form you page through.
    var onBacktab: (() -> Void)? = nil
    /// Esc — the owner leaves edit mode. A hook rather than the `.onKeyPress`
    /// the call sites used to carry: the text view answers keys before SwiftUI's
    /// key-press handlers see them, which is why Tab needed a monitor in the
    /// first place.
    var onEscape: (() -> Void)? = nil
    /// Owned by the caller, which decides when the editor takes focus. The text
    /// view reports its own first-responder changes back into it, so a click
    /// inside the editor still counts as focus.
    @FocusState.Binding var focused: Bool
    /// Owned by the caller as well, so that when it hands the editor focus it
    /// can also say where the caret goes — a card opening for editing puts it at
    /// the end of the text rather than at offset 0. Set it only alongside a
    /// programmatic focus: writing it on every focus change would stamp on the
    /// position a click inside the editor just chose.
    @Binding var selection: TextSelection?

    var body: some View {
        MarkdownTextViewBridge(
            text: $text,
            font: font,
            textColor: textColor,
            onBacktab: onBacktab,
            onEscape: onEscape,
            focused: $focused,
            selection: $selection
        )
    }
}

// MARK: - The text view

/// The `NSTextView` behind `MarkdownEditor`, and the two-way plumbing that used
/// to be `TextEditor`'s job: text, selection and focus.
///
/// Everything set in `makeNSView` is chosen to leave the card looking and
/// measuring exactly as it did, because the card's own rules depend on it — the
/// preview and the source are compared on the frame the mode flips (see
/// CLAUDE.md), and the height comes from a hidden `Text` proxy at the call site
/// with `.padding(.horizontal, 5)`. That 5pt is `NSTextContainer`'s default
/// `lineFragmentPadding`, which is where SwiftUI's inset came from too, so it is
/// left alone; `textContainerInset` is zero for the same reason, since the
/// editor's first line has always started at the very top of its frame.
private struct MarkdownTextViewBridge: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var onBacktab: (() -> Void)?
    var onEscape: (() -> Void)?
    @FocusState.Binding var focused: Bool
    @Binding var selection: TextSelection?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.delegate = context.coordinator

        view.isEditable = true
        view.isSelectable = true
        // Markdown source: no styling to carry, and a paste should arrive as the
        // characters it is.
        view.isRichText = false
        view.usesFontPanel = false
        view.usesRuler = false
        view.allowsUndo = true
        // The card is the surface; the editor is a layer of text on it.
        view.drawsBackground = false
        view.focusRingType = .none
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 5
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.minSize = .zero
        view.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]

        view.font = font
        view.textColor = textColor

        // Spelling — the reason this is a text view of ours at all. Set once;
        // nothing here ever takes it away again.
        view.isContinuousSpellCheckingEnabled = SettingsStore.shared.checkSpelling
        // Marked, never corrected: a substitution made on the user's behalf is a
        // write to a Markdown file that Obsidian also opens. A bare `NSTextView`
        // arrives with all of these *on*, so each one is refused by name.
        view.isGrammarCheckingEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        // **Text replacement is the exception, and it is on.** It was refused
        // with the rest and shouldn't have been: the others are macOS deciding
        // that what someone typed isn't what they meant — `--` becoming an en
        // dash in a file where the two characters differ — while this one is a
        // table the user wrote themselves in System Settings, firing only on the
        // exact strings they put in it. Typing `->` and getting `→` is the
        // feature working, in every other app on the Mac, and refusing it here
        // read as the shortcut being broken.
        view.isAutomaticTextReplacementEnabled = true

        applyTabStops(to: view, font: font)

        view.string = text
        return view
    }

    /// Makes a tab a **four-space step, anywhere in the line**.
    ///
    /// An `NSTextView` arrives with twelve tab stops 28pt apart and a
    /// `defaultTabInterval` of **0**, and that zero is the bug: past the twelfth
    /// stop there is no next one, so the layout manager gives the tab the rest of
    /// the line and the caret lands on the line below. Typing a tab at the end of
    /// a long line looked like it inserted a newline as well. Clearing the stops
    /// and giving the interval a real value makes every tab the same step
    /// wherever it is typed.
    ///
    /// Four spaces because that is what a tab means in the file: `MarkdownParser`
    /// counts one as four columns when it works out a sub-list's depth, so the
    /// indent the editor shows and the nesting the card renders agree. Measured
    /// in the editor's own font, so a serif or monospaced card steps by its own
    /// four spaces rather than by a number written down here.
    private func applyTabStops(to view: MarkdownTextView, font: NSFont) {
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = 4 * NSAttributedString(
            string: " ", attributes: [.font: font]
        ).size().width
        view.defaultParagraphStyle = style
        view.typingAttributes[.paragraphStyle] = style
    }

    func updateNSView(_ view: MarkdownTextView, context: Context) {
        // The coordinator writes through this, so it has to be the current one:
        // the closures a card passes capture that card's state.
        context.coordinator.parent = self
        view.onBacktab = onBacktab
        view.onEscape = onEscape
        view.onFocusChange = { [coordinator = context.coordinator] focused in
            // The overrides that call this are main-actor isolated already; the
            // closure type isn't, so say so here — the same shape the key
            // monitors in this file use.
            MainActor.assumeIsolated { coordinator.report(focus: focused) }
        }

        if view.font != font {
            view.font = font
            // The step is measured in the font, so it moves with it.
            applyTabStops(to: view, font: font)
        }
        // Assigned only when it really differs, like the font and the text
        // itself: `textColor` on an `NSTextView` rewrites the whole storage's
        // attributes, so setting it every update would be a full re-attribution
        // per keystroke.
        if view.textColor != textColor { view.textColor = textColor }
        // The caret wears the theme's primary, which is what `.tint()` gave the
        // SwiftUI editor for free.
        let caret = NSColor(SettingsStore.shared.theme.primary)
        if view.insertionPointColor != caret { view.insertionPointColor = caret }
        // Followed live so the Settings toggle lands on an open card. Reading the
        // store here doesn't register a dependency — `SpellChecking` is what
        // actually notices a change — but it costs nothing and keeps this view
        // right whenever it is updated for any other reason.
        let spelling = SettingsStore.shared.checkSpelling
        if view.isContinuousSpellCheckingEnabled != spelling {
            view.isContinuousSpellCheckingEnabled = spelling
        }

        // Only ever write the text when it really differs: typing round-trips
        // through the binding and comes back equal, and assigning it then would
        // throw away the caret and the undo stack on every keystroke.
        if view.string != text {
            let caretLocation = view.selectedRange().location
            view.string = text
            let length = (view.string as NSString).length
            view.setSelectedRange(NSRange(location: min(caretLocation, length), length: 0))
        }

        // The caret the owner asked for — entry puts it at the end of the body.
        // A no-op in the ordinary case, since the coordinator has already written
        // the live selection back into the binding.
        if let wanted = Self.nsRange(of: selection, in: view.string),
           wanted != view.selectedRange() {
            view.setSelectedRange(wanted)
        }

        // Focus in: the owner asked, so take it. `reportsFocus` is cleared
        // around the call because the callback would otherwise write SwiftUI
        // state from inside a view update. Focus *out* is left to AppKit — the
        // field that took it says so itself, and the editor is torn down anyway
        // when the card leaves edit mode.
        if focused, view.window?.firstResponder !== view {
            view.reportsFocus = false
            view.window?.makeFirstResponder(view)
            view.reportsFocus = true
        }
    }

    /// `TextSelection` counts in `String.Index`, a text view in UTF-16, so every
    /// caret crosses one of these two.
    private static func nsRange(of selection: TextSelection?, in string: String) -> NSRange? {
        guard let selection, case .selection(let range) = selection.indices else { return nil }
        return NSRange(range, in: string)
    }

    fileprivate static func selection(of range: NSRange, in string: String) -> TextSelection? {
        guard let converted = Range(range, in: string) else { return nil }
        return range.length == 0
            ? TextSelection(insertionPoint: converted.lowerBound)
            : TextSelection(range: converted)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextViewBridge

        init(_ parent: MarkdownTextViewBridge) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            if parent.text != view.string { parent.text = view.string }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.selection = MarkdownTextViewBridge.selection(
                of: view.selectedRange(), in: view.string)
        }

        func report(focus: Bool) {
            if parent.focused != focus { parent.focused = focus }
        }
    }
}

/// The text view itself, a subclass for exactly two jobs.
///
/// **The keys it gets first.** Tab, ⇧Tab and Esc are answered by the text view
/// before SwiftUI's `onKeyPress` sees them — the wall `ProjectMentionField`
/// documents, and this is the side of it where the keys can simply be answered
/// instead of intercepted. Return is *not* here: `MarkdownReturn` reads the first
/// responder, so it keeps working unchanged.
///
/// **The focus it reports.** A `@FocusState` the owner drives has to know when
/// the user clicks *into* the editor, so first-responder changes are handed back.
final class MarkdownTextView: NSTextView {
    // Plain closure types, called from overrides that are already on the main
    // actor. Annotating them `@MainActor` would make them `@Sendable` too, which
    // the owner's own closures are not.
    var onBacktab: (() -> Void)?
    var onEscape: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    /// Cleared around a `makeFirstResponder` we asked for ourselves, so the
    /// callback can't write SwiftUI state from inside a view update.
    var reportsFocus = true

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, reportsFocus { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, reportsFocus { onFocusChange?(false) }
        return resigned
    }

    /// The two directions mean **different** things here, which is the one place
    /// a card's field traversal departs from a form's.
    ///
    /// On a **list item** they are each other's opposite: Tab adds a level,
    /// ⇧Tab takes one off. Anywhere else Tab is left to the text view, so it
    /// inserts a tab — the body is prose, and an indent is something you type
    /// into it — while ⇧Tab is the way back to the title, and the only key that
    /// leaves the body, so it has to be answered.
    override func insertTab(_ sender: Any?) {
        // On a list item, Tab sets the item's *level* — see
        // `MarkdownFormatting.listIndent`. Anywhere else it is a tab. Only a
        // caret indents; with text selected Tab is the text view's business.
        let selected = selectedRange()
        if selected.length == 0,
           let caret = MarkdownEdits.characterOffset(in: string, utf16Offset: selected.location),
           let edit = MarkdownFormatting.listIndent(string, caret: caret),
           MarkdownEdits.apply(edit, to: self) {
            return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        // On a list item ⇧Tab is Tab's opposite and takes a level off. Only
        // where there is no level to take off does it mean the other thing it
        // means in a card — back to the title.
        let selected = selectedRange()
        if selected.length == 0,
           let caret = MarkdownEdits.characterOffset(in: string, utf16Offset: selected.location),
           let edit = MarkdownFormatting.listOutdent(string, caret: caret),
           MarkdownEdits.apply(edit, to: self) {
            return
        }
        guard let onBacktab else { return super.insertBacktab(sender) }
        onBacktab()
    }

    /// The formatting shortcuts — ⌘B bold, ⌘I italic, ⌘U underline, ⇧⌘X
    /// strikethrough — toggle the Markdown delimiters around the selection,
    /// and ⌘K makes it a link.
    ///
    /// Answered here rather than as SwiftUI `keyboardShortcut` buttons in the
    /// editor's background, which is what they were until the text view was
    /// hosted and they stopped firing. Unlike `keyDown`, a key equivalent is
    /// offered to **every** view in the window, so the first-responder guard is
    /// what keeps two open cards from both applying the toggle. A matched key is
    /// swallowed even when there is no selection to style — the buttons
    /// swallowed it too, and letting it fall through would beep.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.modifierFlags.intersection([.command, .control, .option]) == .command,
              let key = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }

        let shifted = event.modifierFlags.contains(.shift)
        switch (key, shifted) {
        case ("b", false): toggleWrapAroundSelection("**")
        case ("i", false): toggleWrapAroundSelection("*")
        // Markdown has no underline; `<u>…</u>` is the Obsidian convention,
        // and `MarkdownText` renders it.
        case ("u", false): toggleWrapAroundSelection("<u>", closing: "</u>")
        case ("x", true): toggleWrapAroundSelection("~~")
        // ⌘K means search everywhere else; `RootView`'s monitor stands down
        // while a Markdown body is first responder so it can mean "link" here.
        case ("k", false): insertLinkAroundSelection()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    private func toggleWrapAroundSelection(_ delimiter: String, closing: String? = nil) {
        let selected = selectedRange()
        guard selected.length > 0,
              let lo = MarkdownEdits.characterOffset(in: string, utf16Offset: selected.location),
              let hi = MarkdownEdits.characterOffset(in: string, utf16Offset: selected.location + selected.length),
              let change = MarkdownFormatting.toggleWrap(
                  string, selection: lo..<hi, delimiter: delimiter, closing: closing
              )
        else { return }
        _ = MarkdownEdits.apply(change, to: self)
    }

    /// ⌘K, unlike the toggles above, accepts an empty selection — the inserted
    /// skeleton is the point — and reads the clipboard so a copied URL fills
    /// the destination in the same keystroke.
    private func insertLinkAroundSelection() {
        let selected = selectedRange()
        guard let lo = MarkdownEdits.characterOffset(in: string, utf16Offset: selected.location),
              let hi = MarkdownEdits.characterOffset(
                  in: string, utf16Offset: selected.location + selected.length
              ),
              let change = MarkdownFormatting.insertLink(
                  string, selection: lo..<hi,
                  clipboard: NSPasteboard.general.string(forType: .string)
              )
        else { return }
        _ = MarkdownEdits.apply(change, to: self)
    }

    /// ⌘Return leaves the card too, and it is caught here rather than as a
    /// command because AppKit binds it to nothing: Return alone is
    /// `insertNewline(_:)`, and with ⌘ held there is no action to override. Only
    /// the first responder gets `keyDown`, so two open cards can't both answer.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76,
           event.modifierFlags.intersection([.command, .control, .option, .shift]) == [.command],
           let onEscape {
            onEscape()
            return
        }
        super.keyDown(with: event)
    }

    /// Esc leaves the card. `complete(_:)` is overridden alongside
    /// `cancelOperation(_:)` because Esc is bound to *completion* in a text view
    /// by default — the inline word list this editor has no use for, and which
    /// would otherwise swallow the key.
    override func cancelOperation(_ sender: Any?) {
        guard let onEscape else { return super.cancelOperation(sender) }
        onEscape()
    }

    override func complete(_ sender: Any?) {
        guard let onEscape else { return super.complete(sender) }
        onEscape()
    }
}

// MARK: - Tab, from the title into the body

/// Hands focus from a card's **title** to its Markdown editor, in AppKit.
///
/// This exists because the SwiftUI route didn't work, twice. A card's two fields
/// are two `@FocusState<Bool>`s, and Tab out of the title clears one and sets the
/// other; the arriving half never landed, so the caret went nowhere. Writing the
/// pair as a pair (clear the old flag before setting the new one) didn't fix it,
/// and neither did deferring the arriving write by a main-actor turn — both were
/// tried against the reported symptom and both left the title focused. What is
/// *known* is that: the key reaches the handler (Esc from the same field, through
/// the same monitor, leaves edit mode), and the reverse direction — Tab out of the
/// **body** — has always worked, which is the asymmetry worth reading. The body is
/// an `NSTextView` of ours, so it reports its own first-responder changes back
/// into `@FocusState`; the title is a plain SwiftUI `TextField` with no hook of
/// ours. Why the write is dropped is **not** established and shouldn't be
/// repeated as fact.
///
/// So the handoff is made where focus actually lives. It is the same conclusion
/// this file already reached for Return, Tab-in-the-body and Esc, and the same one
/// `SpellChecking` and the window title reached: when SwiftUI won't say it, say it
/// to AppKit. The owner's `@FocusState` still ends up correct, because
/// `MarkdownTextView.becomeFirstResponder()` reports the change back out.
///
/// Finding the right editor is a **walk up from the current first responder**,
/// stopping at the first ancestor that contains **exactly one** editor — that
/// ancestor is the card. The count is the safety: a note card and a task card can
/// both be open at once, and an ancestor holding several editors means the walk
/// has gone past the card, so it stops rather than guessing. No match is a no-op
/// and the caller falls back to the `@FocusState` route, which is the discipline
/// `AppDelegate.flattenToolbarGlass()` follows for the same kind of reach.
@MainActor
enum CardFocus {
    /// Focuses the Markdown editor sharing a card with whatever is focused now.
    /// Returns `false` if there is nothing unambiguous to focus.
    @discardableResult
    static func moveToEditorBesideCurrentField() -> Bool {
        guard let window = NSApp.keyWindow else { return false }
        // A focused `TextField` makes the window's shared **field editor** first
        // responder, not the field; the field is the editor's delegate, and it is
        // the one actually in the view hierarchy.
        var start = window.firstResponder as? NSView
        if let fieldEditor = start as? NSTextView, fieldEditor.isFieldEditor {
            start = fieldEditor.delegate as? NSView ?? fieldEditor.superview
        }
        var node = start
        while let current = node {
            let editors = editors(in: current)
            if editors.count == 1 {
                return window.makeFirstResponder(editors[0])
            }
            // More than one means this is the column, not the card.
            if editors.count > 1 { return false }
            node = current.superview
        }
        return false
    }

    private static func editors(in view: NSView) -> [MarkdownTextView] {
        if let editor = view as? MarkdownTextView { return [editor] }
        return view.subviews.flatMap { editors(in: $0) }
    }
}

// MARK: - Return in a list

/// Continues a Markdown list when Return is pressed in a note or task body.
///
/// **One app-wide key-down monitor**, driven by the **first responder** — not one
/// monitor per editor reading SwiftUI's `@FocusState` and `TextSelection`
/// bindings, which is how it was written first (copying `ProjectMentionField`).
/// Whether that version worked was never actually established: it was replaced
/// while chasing a report of "nothing happens", which turned out to be Return
/// pressed on lines that weren't list items. So treat "the bindings can't be
/// read from an `NSEvent` monitor" as *unproven* rather than as the reason this
/// looks the way it does.
///
/// It is still the better of the two, on grounds that don't depend on that: the
/// text view holds the text and the caret, so there's no asking SwiftUI for
/// state outside a view update, and nothing to gate on focus — the first
/// responder *is* the focused editor, so two editors can't both answer.
///
/// The edit goes **through the text view** rather than through the `text`
/// binding, which is what earns it native undo and leaves the caret placed by
/// the same code that places it when you type; `didChangeText()` is what tells
/// SwiftUI to pull the new string back into the binding.
///
/// **Field editors are skipped**, and that's the line between a multiline
/// Markdown body and a single-line field where Return means submit — the note
/// title and the `@project` field are the latter and keep their own behaviour
/// (`ProjectMentionField` has its own monitor for exactly that).
@MainActor
enum MarkdownReturn {
    private static var monitor: Any?

    /// Installed once, for the app's lifetime, from `AppDelegate`.
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Monitors fire on the main thread, but the closure isn't annotated;
            // `assumeIsolated` can't *return* the non-Sendable event, so it
            // answers "swallow?" instead.
            let swallow = MainActor.assumeIsolated { handle(event) }
            return swallow ? nil : event
        }
    }

    /// Returns `true` to swallow the event, `false` to let it through.
    private static func handle(_ event: NSEvent) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76 else { return false } // Return / ⌤
        // ⇧Return is the plain newline that leaves a list without ending it; the
        // modified presses keep their usual meaning too.
        guard event.modifierFlags
            .intersection([.command, .control, .option, .shift]).isEmpty else { return false }

        // SwiftUI's `TextEditor` is backed by an `NSTextView` subclass
        // (`PlatformTextView`), which is the first responder while it has focus.
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
              textView.isEditable, !textView.isFieldEditor else { return false }
        // Only a caret continues a list. With text selected Return replaces the
        // selection, which is the text view's job, not ours.
        let selected = textView.selectedRange()
        guard selected.length == 0 else { return false }

        let text = textView.string
        guard let caret = MarkdownEdits.characterOffset(in: text, utf16Offset: selected.location),
              let edit = MarkdownFormatting.listReturn(text, caret: caret)
        else { return false }

        return MarkdownEdits.apply(edit, to: textView)
    }
}

/// Applying a `MarkdownFormatting.Edit` to a live text view.
///
/// Shared by the two keys that rewrite a line rather than insert a character —
/// Return continuing a list (`MarkdownReturn`) and Tab indenting one
/// (`MarkdownTextView.insertTab`) — because the interesting part is identical:
/// the edit goes **through the text view**, which is what earns it native undo
/// and leaves the caret placed by the same code that places it when you type,
/// and `didChangeText()` is what tells SwiftUI to pull the new string back into
/// the binding.
@MainActor
enum MarkdownEdits {
    /// `false` when the edit can't be made, which is the caller's cue to let the
    /// key through untouched.
    static func apply(_ edit: MarkdownFormatting.Edit, to textView: NSTextView) -> Bool {
        guard let range = nsRange(of: edit.range, in: textView.string),
              textView.shouldChangeText(in: range, replacementString: edit.replacement)
        else { return false }

        textView.textStorage?.replaceCharacters(in: range, with: edit.replacement)
        textView.didChangeText()

        // The edit says where the caret lands, and it is an offset into the text
        // *after* the replacement — so it is resolved against the new string.
        let updated = textView.string
        let caret = max(0, min(edit.caret, updated.count))
        let index = updated.index(updated.startIndex, offsetBy: caret)
        textView.setSelectedRange(NSRange(location: index.utf16Offset(in: updated), length: 0))
        return true
    }

    /// The formatting toggles hand back a whole new string plus the range to
    /// keep selected (`Change`) rather than an `Edit`, so this variant reduces
    /// the change to the smallest contiguous replacement before going through
    /// the same path — one undo step, and the styled text stays selected so
    /// toggles chain (⌘B ⌘B is a no-op).
    static func apply(_ change: MarkdownFormatting.Change, to textView: NSTextView) -> Bool {
        let old = Array(textView.string)
        let new = Array(change.text)

        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }

        let replacement = String(new[prefix..<(new.count - suffix)])
        guard let range = nsRange(of: prefix..<(old.count - suffix), in: textView.string),
              textView.shouldChangeText(in: range, replacementString: replacement)
        else { return false }

        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()

        if let selection = nsRange(of: change.selection, in: textView.string) {
            textView.setSelectedRange(selection)
        }
        return true
    }

    /// The text view counts in UTF-16 and `MarkdownFormatting` counts in
    /// `Character`s, so every offset crosses this pair. `nil` when the caret
    /// isn't on a character boundary — mid-emoji, where there's no sensible
    /// answer and the key may as well behave normally.
    static func characterOffset(in text: String, utf16Offset: Int) -> Int? {
        let clamped = max(0, min(utf16Offset, text.utf16.count))
        guard let index = String.Index(utf16Offset: clamped, in: text).samePosition(in: text)
        else { return nil }
        return text.distance(from: text.startIndex, to: index)
    }

    private static func nsRange(of range: Range<Int>, in text: String) -> NSRange? {
        guard range.lowerBound >= 0, range.upperBound <= text.count else { return nil }
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        let upper = text.index(text.startIndex, offsetBy: range.upperBound)
        return NSRange(lower..<upper, in: text)
    }
}

/// Pure selection-wrapping logic for the formatting shortcuts. Offsets are in
/// `Character`s so the maths survives emoji and combining marks.
enum MarkdownFormatting {
    struct Change: Equatable {
        var text: String
        /// Where the styled (inner) text now sits, as character offsets into
        /// `text` — handed back to the editor as the new selection.
        var selection: Range<Int>
    }

    /// Toggle `delimiter` (…`closing`) around the selected text: wrap when the
    /// delimiters aren't there, unwrap when they sit just inside or just outside
    /// the selection. Returns `nil` when there's nothing usable to style.
    static func toggleWrap(
        _ text: String,
        selection: Range<Int>,
        delimiter: String,
        closing: String? = nil
    ) -> Change? {
        let chars = Array(text)
        var lo = max(0, min(selection.lowerBound, chars.count))
        var hi = max(lo, min(selection.upperBound, chars.count))
        // Delimiters must hug the text they style — "** bold **" doesn't parse —
        // so shrink the selection past edge whitespace first.
        while lo < hi, chars[lo].isWhitespace { lo += 1 }
        while hi > lo, chars[hi - 1].isWhitespace { hi -= 1 }
        guard lo < hi else { return nil }

        if delimiter.allSatisfy({ $0 == "*" }) {
            return toggleStars(chars, lo: lo, hi: hi, single: delimiter.count == 1)
        }

        let open = Array(delimiter)
        let close = Array(closing ?? delimiter)

        // Unwrap when the delimiters sit just inside the selection…
        if hi - lo > open.count + close.count,
           Array(chars[lo..<(lo + open.count)]) == open,
           Array(chars[(hi - close.count)..<hi]) == close {
            var out = chars
            out.removeSubrange((hi - close.count)..<hi)
            out.removeSubrange(lo..<(lo + open.count))
            return Change(text: String(out), selection: lo..<(hi - open.count - close.count))
        }
        // …or just outside it…
        if lo >= open.count, hi + close.count <= chars.count,
           Array(chars[(lo - open.count)..<lo]) == open,
           Array(chars[hi..<(hi + close.count)]) == close {
            var out = chars
            out.removeSubrange(hi..<(hi + close.count))
            out.removeSubrange((lo - open.count)..<lo)
            return Change(text: String(out), selection: (lo - open.count)..<(hi - open.count))
        }
        // …otherwise wrap.
        var out = chars
        out.insert(contentsOf: close, at: hi)
        out.insert(contentsOf: open, at: lo)
        return Change(text: String(out), selection: (lo + open.count)..<(hi + open.count))
    }

    // MARK: Links

    /// ⌘K: make the selection a Markdown link, or take one apart.
    ///
    /// Plain text selected becomes the label — `[text](‸)`, or `[text](url)`
    /// with the URL *selected* when the clipboard already holds one, so the
    /// copy-then-link flow is a single key and a wrong guess is overtyped. A
    /// selected URL inverts (`[‸](url)`), since a URL as its own label says
    /// nothing. Reapplied to a link — the whole of one selected, or just its
    /// label — it unwraps back to plain text, which is what makes the key a
    /// toggle like the ones above. An empty selection inserts the skeleton
    /// with the caret in the label.
    static func insertLink(_ text: String, selection: Range<Int>, clipboard: String? = nil) -> Change? {
        let chars = Array(text)
        var lo = max(0, min(selection.lowerBound, chars.count))
        var hi = max(lo, min(selection.upperBound, chars.count))
        // Like the wraps above, the brackets must hug the words.
        while lo < hi, chars[lo].isWhitespace { lo += 1 }
        while hi > lo, chars[hi - 1].isWhitespace { hi -= 1 }

        let clip = clipboard?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = isLinkDestination(clip) ? clip : ""

        guard lo < hi else {
            var out = chars
            out.insert(contentsOf: "[](\(url))", at: lo)
            return Change(text: String(out), selection: (lo + 1)..<(lo + 1))
        }

        // A label can't span lines.
        guard !chars[lo..<hi].contains(where: \.isNewline) else { return nil }

        // Unwrap a wholly selected link…
        if hi - lo >= 4, chars[lo] == "[", chars[hi - 1] == ")",
           let mid = ((lo + 1)..<(hi - 2)).first(where: { chars[$0] == "]" && chars[$0 + 1] == "(" }) {
            let label = chars[(lo + 1)..<mid]
            var out = chars
            out.replaceSubrange(lo..<hi, with: label)
            return Change(text: String(out), selection: lo..<(lo + label.count))
        }
        // …or the link whose label is selected.
        if lo > 0, chars[lo - 1] == "[", hi + 1 < chars.count, chars[hi] == "]", chars[hi + 1] == "(",
           let close = ((hi + 2)..<chars.count).first(where: { chars[$0] == ")" }),
           !chars[(hi + 2)..<close].contains(where: \.isNewline) {
            var out = chars
            out.replaceSubrange((lo - 1)...close, with: chars[lo..<hi])
            return Change(text: String(out), selection: (lo - 1)..<(lo - 1 + hi - lo))
        }
        // A selected URL becomes the destination, the caret ready for its label.
        if isLinkDestination(String(chars[lo..<hi])) {
            var out = chars
            out.insert(")", at: hi)
            out.insert(contentsOf: "[](", at: lo)
            return Change(text: String(out), selection: (lo + 1)..<(lo + 1))
        }
        // Otherwise the selection is the label.
        var out = chars
        out.insert(contentsOf: "](\(url))", at: hi)
        out.insert("[", at: lo)
        let urlStart = hi + 3
        return Change(text: String(out), selection: urlStart..<(urlStart + url.count))
    }

    /// Whether `text` reads as a link destination: one unbroken run with a
    /// web-ish scheme, or a bare `www.` host.
    static func isLinkDestination(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else { return false }
        if trimmed.lowercased().hasPrefix("www."), trimmed.count > "www.".count { return true }
        guard let scheme = URL(string: trimmed)?.scheme else { return false }
        return ["http", "https", "mailto", "ftp"].contains(scheme.lowercased())
    }

    // MARK: Lists and quotes

    /// What a line opens with, when it opens a list item or a block quote — the
    /// two shapes Return carries onto the next line.
    private struct LineMarker {
        /// The line's leading whitespace, reproduced verbatim on the next line so
        /// a nested item stays at its level.
        var indent: [Character]
        /// The marker to write after the indent — `- `, `- [ ] `, `3. `, `> `.
        var lead: [Character]
        /// Offset within the line where the item's own text starts.
        var contentStart: Int
    }

    /// One text replacement: what to swap out, what for, and where the caret
    /// lands afterwards. Offsets are `Character`s, as everywhere else here.
    ///
    /// A *range* rather than a whole new string, because the edit is applied to
    /// the live `NSTextView` — which wants exactly this shape, and gives back
    /// native undo for it.
    struct Edit: Equatable {
        var range: Range<Int>
        var replacement: String
        var caret: Int
    }

    /// Return inside a list item or a block quote, as an edit to apply. `nil` when
    /// the caret is in neither — the caller then lets Return through and the
    /// editor inserts an ordinary newline.
    ///
    /// See `continueList` for the rules.
    static func listReturn(_ text: String, caret: Int) -> Edit? {
        let chars = Array(text)
        let caret = max(0, min(caret, chars.count))

        var lineStart = caret
        while lineStart > 0, chars[lineStart - 1] != "\n" { lineStart -= 1 }
        var lineEnd = caret
        while lineEnd < chars.count, chars[lineEnd] != "\n" { lineEnd += 1 }

        let line = Array(chars[lineStart..<lineEnd])
        guard let marker = lineMarker(line) else { return nil }
        // A caret inside the marker itself isn't editing the item's text, so
        // Return there means what it usually means.
        let caretInLine = caret - lineStart
        guard caretInLine >= marker.contentStart else { return nil }

        if line[marker.contentStart...].allSatisfy(\.isWhitespace) {
            return Edit(range: lineStart..<lineEnd, replacement: "", caret: lineStart)
        }

        let inserted = String(["\n"] + marker.indent + marker.lead)
        return Edit(
            range: caret..<caret,
            replacement: inserted,
            caret: caret + inserted.count
        )
    }

    /// **One level of indentation**, as a string. Two spaces, which is what the
    /// renderer reads as one level (`MarkdownParser` counts levels relative to
    /// the indents already open, so two and four both work — two is simply the
    /// smaller of the conventions and the one this app writes).
    static let indentUnit = "  "

    /// Tab on a list item, as an edit that indents the **line**. `nil` when the
    /// caret is not on a list item at all — the caller then lets Tab through and
    /// the editor inserts a tab character.
    ///
    /// This is where the two meanings of Tab in this editor meet. A body is
    /// prose, so a tab is something you type into it; but the one place a leading
    /// indent is *structure* rather than whitespace is a list item, where it sets
    /// the item's level. **Anywhere on the line counts**, which is Obsidian's
    /// rule and so this app's (the same reason `continueList` follows it): the
    /// caret's position within an item says nothing about whether its author
    /// meant to nest it. The cost, accepted, is that a tab cannot be typed inside
    /// an item's text.
    ///
    /// Quotes are excluded. `>` nests by repeating the marker, not by
    /// indentation, so spaces in front of one change nothing the renderer reads.
    static func listIndent(_ text: String, caret: Int) -> Edit? {
        let chars = Array(text)
        let caret = max(0, min(caret, chars.count))

        var lineStart = caret
        while lineStart > 0, chars[lineStart - 1] != "\n" { lineStart -= 1 }
        var lineEnd = caret
        while lineEnd < chars.count, chars[lineEnd] != "\n" { lineEnd += 1 }

        let line = Array(chars[lineStart..<lineEnd])
        guard let marker = lineMarker(line) else { return nil }
        guard marker.lead.first != ">" else { return nil }

        return Edit(
            range: lineStart..<lineStart,
            replacement: indentUnit,
            caret: caret + indentUnit.count
        )
    }

    /// ⇧Tab on a list item, as an edit that takes **one level off** the line.
    /// `nil` when there is no level to take off — the caller then does what ⇧Tab
    /// otherwise means in a card, which is hand focus back to the title.
    ///
    /// It removes what one Tab put on: `indentUnit`'s worth of spaces, or a
    /// single tab character, whichever the line actually starts with. A line
    /// indented by an odd number of spaces loses what there is rather than
    /// refusing — the renderer reads levels relative to the indents already open,
    /// so leaving a stray space behind would keep the item nested on a level of
    /// its own.
    static func listOutdent(_ text: String, caret: Int) -> Edit? {
        let chars = Array(text)
        let caret = max(0, min(caret, chars.count))

        var lineStart = caret
        while lineStart > 0, chars[lineStart - 1] != "\n" { lineStart -= 1 }
        var lineEnd = caret
        while lineEnd < chars.count, chars[lineEnd] != "\n" { lineEnd += 1 }

        let line = Array(chars[lineStart..<lineEnd])
        guard let marker = lineMarker(line) else { return nil }
        guard marker.lead.first != ">" else { return nil }

        let removed: Int
        if marker.indent.first == "\t" {
            removed = 1
        } else {
            let spaces = marker.indent.prefix(while: { $0 == " " }).count
            removed = min(spaces, indentUnit.count)
        }
        guard removed > 0 else { return nil }

        return Edit(
            range: lineStart..<(lineStart + removed),
            replacement: "",
            caret: max(lineStart, caret - removed)
        )
    }

    /// Return inside a list item: continue the list on the next line.
    ///
    /// The whole-text form of `listReturn`, which is how the rules are pinned by
    /// `MarkdownFormattingTests`.
    ///
    /// The rules are Obsidian's, because that's the app these files open in:
    /// indentation is preserved, ordered items increment, and a checked `- [x]`
    /// continues as an *unchecked* `- [ ]` rather than copying the tick. Text to
    /// the right of the caret comes down with the new marker, so Return in the
    /// middle of an item splits it into two.
    ///
    /// Return on an item with **no content** ends the list instead of adding an
    /// empty item to it, which is the behaviour that stops a list being a trap.
    /// It clears the line outright rather than outdenting one level at a time:
    /// nesting can only be reached by typing the spaces by hand until Tab
    /// indents too, so there is rarely a level to step back through.
    ///
    /// A **block quote** continues the same way, and for the same reason a list
    /// does: a quote is a run of `> ` lines, so writing the next one by hand is
    /// exactly the friction this removes. It carries the whole run of `>`s, so a
    /// nested quote stays nested, and an empty `> ` ends the quote — everything a
    /// list item does, read off a different marker.
    static func continueList(_ text: String, caret: Int) -> Change? {
        guard let edit = listReturn(text, caret: caret) else { return nil }
        var chars = Array(text)
        chars.replaceSubrange(edit.range, with: Array(edit.replacement))
        return Change(text: String(chars), selection: edit.caret..<edit.caret)
    }

    /// Parse a line's list marker, or `nil` when it doesn't open an item.
    private static func lineMarker(_ line: [Character]) -> LineMarker? {
        var i = 0
        while i < line.count, line[i] == " " || line[i] == "\t" { i += 1 }
        let indent = Array(line[0..<i])

        // Bullets: "- ", "* ", "+ ", optionally followed by a "[ ]" checkbox.
        if i + 1 < line.count, "-*+".contains(line[i]), line[i + 1] == " " {
            let bullet = line[i]
            let afterBullet = i + 2
            if afterBullet + 3 < line.count,
               line[afterBullet] == "[", line[afterBullet + 2] == "]",
               line[afterBullet + 3] == " " {
                return LineMarker(
                    indent: indent,
                    lead: [bullet, " ", "[", " ", "]", " "],
                    contentStart: afterBullet + 4
                )
            }
            return LineMarker(indent: indent, lead: [bullet, " "], contentStart: afterBullet)
        }

        // Ordered: "1. " or "1) ", continuing with the next number. The rest of
        // the list isn't renumbered — Markdown doesn't care, and rewriting lines
        // the caret isn't on is how an editor loses someone's text.
        var digitsEnd = i
        while digitsEnd < line.count, line[digitsEnd].isNumber { digitsEnd += 1 }
        if digitsEnd > i, digitsEnd + 1 < line.count,
           line[digitsEnd] == "." || line[digitsEnd] == ")",
           line[digitsEnd + 1] == " ",
           let number = Int(String(line[i..<digitsEnd])) {
            return LineMarker(
                indent: indent,
                lead: Array("\(number + 1)\(line[digitsEnd]) "),
                contentStart: digitsEnd + 2
            )
        }

        // Block quote: the same run of `>`s again, so a nested `>> ` stays nested.
        // The space is **normalised in** — `>quoted` is a quote to the renderer
        // (which strips the marker and trims), and the line being opened wants the
        // space regardless of how the one above it was typed.
        var quoteEnd = i
        while quoteEnd < line.count, line[quoteEnd] == ">" { quoteEnd += 1 }
        if quoteEnd > i {
            let hasSpace = quoteEnd < line.count && line[quoteEnd] == " "
            return LineMarker(
                indent: indent,
                lead: Array(line[i..<quoteEnd]) + [" "],
                contentStart: hasSpace ? quoteEnd + 1 : quoteEnd
            )
        }

        return nil
    }

    /// Bold and italic share a character, so they're toggled by *run length*
    /// rather than literal prefixes: counting the asterisks hugging each edge of
    /// the selection (inside it or out), 1 means italic, 2 bold, 3 both. The
    /// toggle recomputes the run, which is what makes ⌘I on "**bold**" produce
    /// "***bold***" instead of eating one star from each side.
    private static func toggleStars(_ chars: [Character], lo: Int, hi: Int, single: Bool) -> Change? {
        var innerLo = lo, innerHi = hi
        var runStart = lo, runEnd = hi
        while innerLo < innerHi, chars[innerLo] == "*" { innerLo += 1 }
        while runStart > 0, chars[runStart - 1] == "*" { runStart -= 1 }
        while innerHi > innerLo, chars[innerHi - 1] == "*" { innerHi -= 1 }
        while runEnd < chars.count, chars[runEnd] == "*" { runEnd += 1 }
        guard innerLo < innerHi else { return nil } // nothing but stars selected

        let startRun = innerLo - runStart
        let endRun = runEnd - innerHi
        let run = min(startRun, endRun, 3)
        var bold = run >= 2
        var italic = run % 2 == 1
        if single { italic.toggle() } else { bold.toggle() }
        let newRun = (bold ? 2 : 0) + (italic ? 1 : 0)

        // Any stars beyond the recognised run (a lopsided "**bold***") are kept
        // as plain text. Replace the end run first so the start indices hold.
        var out = chars
        out.replaceSubrange(innerHi..<runEnd, with: Array(repeating: "*", count: endRun - run + newRun))
        out.replaceSubrange(runStart..<innerLo, with: Array(repeating: "*", count: startRun - run + newRun))
        let start = runStart + (startRun - run) + newRun
        return Change(text: String(out), selection: start..<(start + innerHi - innerLo))
    }
}
