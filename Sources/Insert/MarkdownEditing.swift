import AppKit
import SwiftUI

/// The Markdown source editor shared by note cards, task cards and the task
/// composer: a plain `TextEditor` plus the formatting shortcuts — ⌘B bold,
/// ⌘I italic, ⌘U underline, ⇧⌘X strikethrough. Each wraps (or unwraps) the
/// *selected* text in the matching Markdown delimiters and does nothing when
/// nothing is selected; the actual string surgery lives in
/// `MarkdownFormatting` so it can be tested without a view.
///
/// The shortcuts are invisible zero-size buttons carrying `keyboardShortcut`s,
/// mounted only while the editor is focused — key equivalents resolve before
/// the focused text view sees the event, and gating them on focus means two
/// editors on screen never compete for ⌘B. Placeholders and sizing proxies
/// stay with the callers, which each have their own.
///
/// Return is different, and needs the **local `NSEvent` monitor** below rather
/// than a fifth button or an `onKeyPress`: an unmodified Return carries no key
/// equivalent, and the text view consumes it as `insertNewline(_:)` before
/// SwiftUI's key-press handlers get a look — the same wall `ProjectHashField`
/// hit with Tab and Return, and solved the same way. The monitor sees the event
/// before the window dispatches it, and swallows it only when the caret really
/// is in a list item, so Return keeps its ordinary meaning everywhere else.
struct MarkdownEditor: View {
    @Binding var text: String
    var font: Font = .body
    /// The composer pins its editor to a fixed height, so it scrolls; everywhere
    /// else the editor grows with a sizing proxy and scrolling is the list's job.
    var scrollable = false
    /// Tab or ⇧Tab — the owner's field traversal (a card hands focus back to
    /// its title). Without it the text view answers Tab itself, as a literal
    /// tab character, and there is no key that leaves the body. Intercepted by
    /// a local monitor for `ProjectHashField`'s reason: the text view consumes
    /// Tab before `onKeyPress` sees it.
    var onTab: (() -> Void)? = nil
    /// Owned by the caller, which decides when the editor takes focus.
    @FocusState.Binding var focused: Bool
    /// Owned by the caller as well, so that when it hands the editor focus it
    /// can also say where the caret goes — a card opening for editing puts it at
    /// the end of the text rather than at offset 0. Set it only alongside a
    /// programmatic focus: writing it on every focus change would stamp on the
    /// position a click inside the editor just chose.
    @Binding var selection: TextSelection?

    /// The Tab monitor, installed for the editor's lifetime when the owner
    /// asked for traversal (its handler no-ops unless this editor is focused).
    @State private var keyMonitor: Any?

    var body: some View {
        TextEditor(text: $text, selection: $selection)
            .font(font)
            .textEditorStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(!scrollable)
            .focused($focused)
            .background {
                if focused { formattingShortcuts }
            }
            .onAppear { installKeyMonitor() }
            .onDisappear { removeKeyMonitor() }
    }

    private func installKeyMonitor() {
        guard onTab != nil, keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Monitors fire on the main thread, but the closure isn't annotated;
            // `assumeIsolated` can't *return* the non-Sendable event, so it
            // answers "swallow?" instead.
            let swallow = MainActor.assumeIsolated { handleKeyDown(event) }
            return swallow ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Tab or ⇧Tab, unmodified otherwise, while this editor is focused. Shift is
    /// allowed through the guard: with two fields in a card the loop is the same
    /// in both directions, so both spellings traverse.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let onTab, focused, event.keyCode == 48 else { return false }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }
        onTab()
        return true
    }

    private var formattingShortcuts: some View {
        Group {
            Button("Bold") { toggle("**") }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { toggle("*") }
                .keyboardShortcut("i", modifiers: .command)
            // Markdown has no underline; `<u>…</u>` is the Obsidian convention,
            // and `MarkdownText` renders it.
            Button("Underline") { toggle("<u>", closing: "</u>") }
                .keyboardShortcut("u", modifiers: .command)
            Button("Strikethrough") { toggle("~~") }
                .keyboardShortcut("x", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Apply a delimiter toggle to the current selection, keeping the same text
    /// selected afterwards so toggles chain (⌘B ⌘B is a no-op).
    private func toggle(_ delimiter: String, closing: String? = nil) {
        guard let selection,
              case .selection(let range) = selection.indices,
              !range.isEmpty else { return }
        let lo = text.distance(from: text.startIndex, to: range.lowerBound)
        let hi = text.distance(from: text.startIndex, to: range.upperBound)
        guard let change = MarkdownFormatting.toggleWrap(
            text, selection: lo..<hi, delimiter: delimiter, closing: closing
        ) else { return }

        text = change.text
        let start = change.text.index(change.text.startIndex, offsetBy: change.selection.lowerBound)
        let end = change.text.index(change.text.startIndex, offsetBy: change.selection.upperBound)
        self.selection = TextSelection(range: start..<end)
    }
}

// MARK: - Return in a list

/// Continues a Markdown list when Return is pressed in a note or task body.
///
/// **One app-wide key-down monitor**, driven by the **first responder** — not one
/// monitor per editor reading SwiftUI's `@FocusState` and `TextSelection`
/// bindings, which is how it was written first (copying `ProjectHashField`).
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
/// title and the `#project` field are the latter and keep their own behaviour
/// (`ProjectHashField` has its own monitor for exactly that).
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
        guard let caret = characterOffset(in: text, utf16Offset: selected.location),
              let edit = MarkdownFormatting.listReturn(text, caret: caret),
              let range = nsRange(of: edit.range, in: text),
              textView.shouldChangeText(in: range, replacementString: edit.replacement)
        else { return false }

        textView.textStorage?.replaceCharacters(in: range, with: edit.replacement)
        textView.didChangeText()
        // Both edits — inserting a marker, and clearing an empty item — leave the
        // caret at the end of what was written, so one sum covers each.
        let caretUTF16 = range.location + (edit.replacement as NSString).length
        textView.setSelectedRange(NSRange(location: caretUTF16, length: 0))
        return true
    }

    /// The text view counts in UTF-16 and `MarkdownFormatting` counts in
    /// `Character`s, so every offset crosses this pair. `nil` when the caret
    /// isn't on a character boundary — mid-emoji, where there's no sensible
    /// answer and Return may as well behave normally.
    private static func characterOffset(in text: String, utf16Offset: Int) -> Int? {
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
