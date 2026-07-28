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
struct MarkdownEditor: View {
    @Binding var text: String
    var font: Font = .body
    /// The composer pins its editor to a fixed height, so it scrolls; everywhere
    /// else the editor grows with a sizing proxy and scrolling is the list's job.
    var scrollable = false
    /// Owned by the caller, which decides when the editor takes focus.
    @FocusState.Binding var focused: Bool
    /// Owned by the caller as well, so that when it hands the editor focus it
    /// can also say where the caret goes — a card opening for editing puts it at
    /// the end of the text rather than at offset 0. Set it only alongside a
    /// programmatic focus: writing it on every focus change would stamp on the
    /// position a click inside the editor just chose.
    @Binding var selection: TextSelection?

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
