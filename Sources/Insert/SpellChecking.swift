import AppKit

/// Spell checking for what the user actually writes — a card's **title and its
/// body**, in both columns: red underlines while you type, and nothing else.
///
/// **SwiftUI has no hook for this on macOS.** There is no spell-checking
/// modifier in the SwiftUI interface at all (`autocorrectionDisabled` is iOS's,
/// and is a different thing), and the state lives per `NSTextView` —
/// `isContinuousSpellCheckingEnabled`. So this reaches the text view the way
/// `MarkdownReturn` does, through the **first responder**, from
/// `applicationDidUpdate`: focus moves between a card's two fields, and from one
/// card to the next, with no notification to hang it on.
///
/// **The flag is re-asserted, and a pass is forced after every edit.** Both
/// halves are here because switching the flag on once, when focus lands, was
/// tried and reported as *"it works, but it takes ages, only when I stop typing,
/// and not even always"*. That is the signature of marks that are made and then
/// dropped — a SwiftUI text view is reconfigured on every graph update, and a
/// card re-renders on every keystroke and again when its ~0.4s debounced save
/// lands. Which of those drops them was not established, so this fixes the
/// class rather than the instance:
///
/// - `applyToFocusedEditors()` compares the **live** property against the
///   preference on each update tick and writes when they differ, so nothing can
///   quietly turn checking back off mid-sentence. The cost is honest and is the
///   reason this was written the other way first: the text view's own "Check
///   Spelling While Typing" item in the Control-click menu no longer sticks —
///   unchecking it there is undone within a frame. Settings is the switch.
/// - `install()` watches every text view's own `NSText.didChangeNotification`
///   and asks AppKit to re-check the whole field shortly after typing settles
///   (`checkText(in:types:options:)`, the same call the automatic machinery
///   makes — it marks, and unlike "Check Document Now" it doesn't touch the
///   selection). Twice: once promptly, and once past the save's window, because
///   a pass that runs before the thing that clears the marks is a pass that
///   didn't happen.
///
/// **The two halves of a card are two different text views**, which is the rest
/// of the shape. A body is a `TextEditor` with an `NSTextView` of its own. A
/// title is a `TextField` (`ProjectHashField`), which has none: it borrows the
/// window's one shared **field editor**, and so do the toolbar's search field and
/// Settings' text fields — so what the field editor is given follows it to the
/// next field, and it has to be told on every focus change what the field it is
/// *currently* attached to wants. Hence the two exclusions in `checkable(_:in:)`.
///
/// **Underlines only, never a rewrite.** Grammar checking and automatic spelling
/// correction are switched off explicitly rather than left at whatever the text
/// view came with, because a bare `NSTextView` arrives with *both on* (measured:
/// `isContinuousSpellCheckingEnabled` false, `isGrammarCheckingEnabled` and
/// `isAutomaticSpellingCorrectionEnabled` true) and these are Markdown files
/// Obsidian also opens — a substitution made on the user's behalf is a write to
/// their note. Corrections are offered where they can be accepted deliberately
/// instead: the text view's own Control-click menu. The smart quote and dash
/// substitutions are left exactly as they are, on purpose — they're the status
/// quo of typing here, and switching spelling on is no reason to change what
/// lands in a file.
@MainActor
enum SpellChecking {
    /// Installed once, for the app's lifetime, from `AppDelegate` — beside
    /// `MarkdownReturn.install()`, and for a related reason: what a text view is
    /// doing is only observable from AppKit's own notifications.
    static func install() {
        guard changes == nil else { return }
        let observer = ChangeObserver()
        NotificationCenter.default.addObserver(
            observer,
            selector: #selector(ChangeObserver.textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: nil)
        changes = observer
    }

    /// Applies the preference to whatever is being edited, from
    /// `applicationDidUpdate`. Cheap: a handful of windows, one cast each, and
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

    // MARK: Re-checking after an edit

    /// The change observer, which only exists to have an `@objc` selector to
    /// register: a block-based observer would hand a non-`Sendable` `Notification`
    /// across an isolation boundary.
    private static var changes: ChangeObserver?

    @MainActor
    private final class ChangeObserver: NSObject {
        @objc func textDidChange(_ note: Notification) {
            guard let editor = note.object as? NSTextView else { return }
            SpellChecking.scheduleRecheck(of: editor)
        }
    }

    /// The pending pass, restarted by every keystroke, and the view it belongs to
    /// — weakly, so a card that closes mid-debounce is simply not re-checked.
    private static var recheck: Task<Void, Never>?
    private static weak var recheckTarget: NSTextView?

    /// Two passes over one debounce, and the second is the load-bearing one.
    ///
    /// 150ms reads as "while typing": it's shorter than the gap between
    /// keystrokes, so a finished word is marked while the sentence is still being
    /// written, and it costs one pass per pause rather than one per key. The
    /// second, past the ~0.4s debounced save and the re-render that follows it, is
    /// what makes the marks *stay* — see this type's note on what the first
    /// version got wrong.
    private static func scheduleRecheck(of editor: NSTextView) {
        recheck?.cancel()
        recheckTarget = editor
        recheck = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            checkNow()
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            checkNow()
        }
    }

    /// Asks AppKit to spell-check the whole field — spelling only, so a forced
    /// pass can't do what the preference above refuses to (grammar, corrections).
    private static func checkNow() {
        guard let editor = recheckTarget, editor.isContinuousSpellCheckingEnabled else { return }
        let length = (editor.string as NSString).length
        guard length > 0 else { return }
        editor.checkText(
            in: NSRange(location: 0, length: length),
            types: NSTextCheckingResult.CheckingType.spelling.rawValue,
            options: [:])
    }

    // MARK: Which field

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
    /// invalidates the text view's checking state, and this runs on the update
    /// path.
    private static func apply(spellChecking enabled: Bool, to editor: NSTextView) {
        if editor.isContinuousSpellCheckingEnabled != enabled {
            editor.isContinuousSpellCheckingEnabled = enabled
        }
        if editor.isGrammarCheckingEnabled { editor.isGrammarCheckingEnabled = false }
        if editor.isAutomaticSpellingCorrectionEnabled {
            editor.isAutomaticSpellingCorrectionEnabled = false
        }
    }
}
