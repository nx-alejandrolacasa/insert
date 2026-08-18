import AppKit

/// Carries the "Check spelling while typing" preference to the **title** fields,
/// and to any body editor whose setting changed while it was open.
///
/// It used to do more, and what shrank it is worth keeping. **SwiftUI's
/// `TextEditor` cannot spell-check on macOS**: it writes
/// `isContinuousSpellCheckingEnabled = false` on the hosted text view on every
/// graph update — measured here as 45 reversions across 44 keystrokes, one per
/// edit — which is FB13607434, still open. Re-asserting the flag from this file
/// was the only lever available from outside, and since turning checking off
/// clears the marks and turning it on schedules a fresh check, it bought
/// underlines that flickered on every keystroke. So the body editor is now an
/// `NSTextView` of our own (`MarkdownEditor`), which sets the flag once and keeps
/// it; the whole mechanism this file used to carry — the re-assert, and a forced
/// `checkText` pass over the entire note twice per typing pause — is gone with
/// the problem it was working around.
///
/// **The titles are why it still exists.** A title is a `TextField`
/// (`ProjectMentionField`), which has no text view of its own: it borrows the
/// window's one shared **field editor**, and so do the toolbar's search field and
/// Settings' text fields. What that editor is given follows it to the next field,
/// so it has to be told, on each focus change, what the field it is *currently*
/// attached to wants — hence the two exclusions in `checkable(_:in:)`. The same
/// pass also picks up a body editor after the Settings toggle is flipped, which
/// no view update of its own would notice.
///
/// **Underlines only, never a rewrite** — grammar checking and automatic spelling
/// correction are refused by name here as well as in `MarkdownEditor`, because a
/// bare `NSTextView` arrives with both *on* and these are Markdown files Obsidian
/// also opens: a substitution made on the user's behalf is a write to their note.
/// Corrections are offered where they can be accepted deliberately instead, in
/// the text view's own Control-click menu.
@MainActor
enum SpellChecking {
    /// Applies the preference to whatever is being edited, from
    /// `applicationDidUpdate` — there is no notification for "focus landed in an
    /// editor", and this is cheap: a handful of windows, one cast each, and
    /// nothing written that isn't already a change.
    ///
    /// It asks **every** window rather than just the key one, so the editor left
    /// focused in the main window still follows a toggle flipped in the Settings
    /// window, which is the key window at that moment.
    static func applyToFocusedEditors() {
        let wanted = SettingsStore.shared.checkSpelling
        for window in NSApp.windows {
            guard let editor = window.firstResponder as? NSTextView, editor.isEditable else {
                continue
            }
            // A title's field editor is shared, so what it should do depends on
            // the field it is attached to right now; a body's text view is its
            // own and always follows the preference.
            let enabled = editor.isFieldEditor
                ? wanted && checkable(field(of: editor), in: window)
                : wanted
            apply(spellChecking: enabled, to: editor)
        }
    }

    /// Whether the field currently holding the field editor is one of the cards'
    /// — a note's title or a task's text. Two kinds are excluded, and an
    /// unidentified field is treated as excluded so nothing inherits underlines
    /// from the field edited before it:
    ///
    /// - the toolbar's **search field**, which is a query rather than prose (and
    ///   is an `NSSearchField`, so it names itself);
    /// - **Settings' own fields** — a note type's name, for one. Those are
    ///   ordinary `NSTextField`s exactly as a card's title is, so the window is
    ///   the only thing that tells the two apart.
    private static func checkable(_ field: NSTextField?, in window: NSWindow) -> Bool {
        guard let field, !(field is NSSearchField) else { return false }
        return !SettingsWindowController.shared.owns(window)
    }

    /// The text field a field editor is currently attached to. AppKit makes the
    /// control the field editor's delegate *and* parents the editor inside it, so
    /// this asks both ways round — neither is contractual, and an answer of `nil`
    /// costs a field its underlines rather than breaking anything.
    private static func field(of editor: NSTextView) -> NSTextField? {
        if let field = editor.delegate as? NSTextField { return field }
        var view: NSView? = editor.superview
        while let current = view {
            if let field = current as? NSTextField { return field }
            view = current.superview
        }
        return nil
    }

    /// Only ever writes a property that's about to change: setting one of these
    /// clears the marks or schedules a check, and this runs on the update path.
    private static func apply(spellChecking enabled: Bool, to editor: NSTextView) {
        if editor.isContinuousSpellCheckingEnabled != enabled {
            editor.isContinuousSpellCheckingEnabled = enabled
        }
        if editor.isGrammarCheckingEnabled { editor.isGrammarCheckingEnabled = false }
        if editor.isAutomaticSpellingCorrectionEnabled {
            editor.isAutomaticSpellingCorrectionEnabled = false
        }
        // The user's own replacement table, on for the same reason the body
        // editor turns it on (see `MarkdownTextViewBridge.makeNSView`). Set here
        // rather than left to the default because this editor is *shared*: it
        // arrives carrying whatever the last field it served was given.
        if !editor.isAutomaticTextReplacementEnabled {
            editor.isAutomaticTextReplacementEnabled = true
        }
    }
}
