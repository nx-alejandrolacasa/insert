import AppKit

/// "Is a Markdown **body** what the keyboard is going to?" — asked in one place.
///
/// Four features turn on that question and each used to spell it differently:
/// `MarkdownReturn`'s monitor (an editable non-field-editor text view),
/// `RootView`'s ⌘K monitor (`is MarkdownTextView`), `SpellChecking`'s per-update
/// pass (editable, then branching on `isFieldEditor`) and
/// `ProjectMentionField`'s key monitor — which asked only for a text view that
/// is *not* a field editor, and so stood itself down for the read-only
/// `MarkdownPreviewView`, a text view that is not a body. Same question, four
/// answers, and the loosest of them was a defect.
///
/// Three things separate a body from every other text view in the window, and
/// all three are load-bearing:
///
/// - it is a **`MarkdownTextView`** — the editor is ours, so the class is the
///   answer rather than a heuristic over one;
/// - it is **editable** — the view-mode preview is an `NSTextView` too
///   (`MarkdownPreviewView`), selectable and first-responder-able, and only
///   `isEditable` tells the two apart;
/// - it is **not a field editor** — a card's title and the `@project` field
///   borrow the window's shared field editor, whose delegate is the
///   `NSTextField` it serves (the walk `SpellChecking.field(of:)` makes in the
///   other direction). A body is its own view and never that editor, so this
///   holds by construction; it is stated because the predicate is the one place
///   the distinction is written down.
@MainActor
enum MarkdownResponder {
    /// The Markdown body holding the keyboard in `window`, or `nil` — no window,
    /// something else focused, or a text view that isn't a body.
    static func markdownBody(in window: NSWindow?) -> MarkdownTextView? {
        markdownBody(responder: window?.firstResponder)
    }

    /// The predicate itself, over a responder rather than a window, so it can be
    /// tested without one — the shape `MarkdownCaret` uses for the same reason.
    static func markdownBody(responder: NSResponder?) -> MarkdownTextView? {
        guard let body = responder as? MarkdownTextView,
              body.isEditable, !body.isFieldEditor
        else { return nil }
        return body
    }

    /// The same question of whichever window has the keyboard, which is what
    /// the three key monitors ask.
    static func focusedMarkdownBody() -> MarkdownTextView? {
        markdownBody(in: NSApp.keyWindow)
    }
}
