import AppKit
import SwiftUI
import XCTest
@testable import Insert

@MainActor
final class MarkdownEditorTests: XCTestCase {
    func testEachEditorOwnsItsUndoHistory() {
        let first = MarkdownTextView()
        let second = MarkdownTextView()

        XCTAssertNotNil(first.undoManager)
        XCTAssertFalse(first.undoManager === second.undoManager)
    }

    func testDismantlingClearsOnlyThatEditorsUndoHistory() {
        let first = MarkdownTextView()
        let second = MarkdownTextView()

        first.undoManager?.registerUndo(withTarget: first) { _ in }
        second.undoManager?.registerUndo(withTarget: second) { _ in }

        first.prepareForDismantle()

        XCTAssertFalse(first.undoManager?.canUndo ?? true)
        XCTAssertTrue(second.undoManager?.canUndo ?? false)
    }

    func testPrivateManagerStillProvidesNativeTextUndo() {
        let editor = MarkdownTextView()
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = "Draft"
        editor.undoManager?.removeAllActions()

        editor.setSelectedRange(NSRange(location: 5, length: 0))
        editor.insertText(" note", replacementRange: editor.selectedRange())

        XCTAssertEqual(editor.string, "Draft note")
        XCTAssertTrue(editor.undoManager?.canUndo ?? false)

        editor.undoManager?.undo()

        XCTAssertEqual(editor.string, "Draft")
    }

    // MARK: - Accented input (the dead-key crash)

    /// The crash this pins, in full. On a Spanish layout `ó` is typed as a dead
    /// key: `´` arrives as **marked text**, provisional and underlined. AppKit
    /// posts selection changes for it but **no** `textDidChange`, so the caret
    /// binding was written from a string — `"navegac´"` — that the text binding
    /// had never been given. The resulting SwiftUI update then assigned the
    /// shorter text back over the composition and converted the longer string's
    /// index against it, trapping in `String.UTF16View._offsetRange`.
    ///
    /// This is the measurement the fix rests on, so it is asserted rather than
    /// written down: one dead key, two selection changes, no text change, a
    /// longer string.
    func testADeadKeyMovesTheStringWithoutPostingATextChange() {
        let editor = MarkdownTextView()
        let spy = TextChangeSpy()
        editor.delegate = spy
        editor.string = "navegac"
        editor.setSelectedRange(NSRange(location: 7, length: 0))
        spy.textChanges = 0
        spy.selectionChanges = 0

        editor.setMarkedText(
            "\u{B4}",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 7, length: 0)
        )

        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertEqual(editor.string, "navegac\u{B4}")
        XCTAssertEqual(spy.textChanges, 0, "a composition publishes no text change")
        XCTAssertEqual(spy.selectionChanges, 2, "but it does move the caret")
        XCTAssertGreaterThan(editor.string.utf8.count, "navegac".utf8.count)
    }

    /// The trap itself: the caret the composition produced, measured against the
    /// text the binding still holds. `NSRange(_:in:)` would abort here.
    func testAStaleCaretIsDeclinedRatherThanTrapping() {
        let marked = "navegac\u{B4}"
        let published = "navegac"
        let caret = TextSelection(insertionPoint: marked.endIndex)

        XCTAssertNil(MarkdownCaret.nsRange(of: caret, in: published))
    }

    /// …and the same caret against the string it was actually made from still
    /// converts, so the guard declines only what it must.
    func testACaretFromTheSameStringStillConverts() {
        let marked = "navegac\u{B4}"
        let caret = TextSelection(insertionPoint: marked.endIndex)

        XCTAssertEqual(
            MarkdownCaret.nsRange(of: caret, in: marked),
            NSRange(location: marked.utf16.count, length: 0)
        )
    }

    /// The other route to the same trap, and the reason the guard lives in the
    /// conversion rather than only in the composition path: a card re-seeding its
    /// draft from an external edit shortens the body under a caret written
    /// earlier.
    func testACaretIntoAReplacedBodyIsDeclined() {
        let before = "Lista de componentes en el CMS"
        let after = "Lista"
        let caret = TextSelection(range: before.index(before.startIndex, offsetBy: 6)..<before.endIndex)

        XCTAssertNil(MarkdownCaret.nsRange(of: caret, in: after))
    }

    /// An accented character is more than one UTF-8 byte and more than one
    /// UTF-16 unit is possible too, so the conversion is checked on real
    /// Spanish text rather than on ASCII alone.
    func testAccentedTextConvertsOnUTF16Offsets() {
        let text = "navegaci\u{F3}n"
        let caret = TextSelection(insertionPoint: text.endIndex)

        XCTAssertEqual(
            MarkdownCaret.nsRange(of: caret, in: text),
            NSRange(location: 10, length: 0)
        )
        XCTAssertEqual(text.utf8.count, 11, "the accent is two UTF-8 bytes")
    }

    /// A caret landing inside a character rather than on a boundary is declined
    /// too — an index can be in bounds and still not belong to the string.
    func testACaretInsideACharacterIsDeclined() {
        let composed = "a\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}b"
        let inside = composed.unicodeScalars.index(composed.unicodeScalars.startIndex, offsetBy: 2)
        let caret = TextSelection(insertionPoint: inside)

        XCTAssertNil(MarkdownCaret.nsRange(of: caret, in: composed))
    }

    func testNoSelectionConvertsToNoRange() {
        XCTAssertNil(MarkdownCaret.nsRange(of: nil, in: "anything"))
    }

    // MARK: - The write path, while a composition owns the storage

    /// `MarkdownEdits` is the single write path — Return, Tab, ⇧Tab, ⌘B/I/U/K
    /// and every `FormattingBar` button — and while text is **marked** it has to
    /// decline. The marked character belongs to the input context: replacing a
    /// range across it destroys the composition, swallows the commit, and leaves
    /// the caret binding describing a string the text binding has never been
    /// given, which is the 0.17.1 trap. `false` is what the callers already read
    /// as "not ours", so the key falls through to AppKit.
    func testAnEditIsDeclinedWhileTheTextViewHasMarkedText() throws {
        let editor = markedEditor(startingFrom: "- item")
        let before = editor.string
        let caret = editor.selectedRange()

        // Return at the end of a list item — the edit that would otherwise
        // rewrite the line the composition is sitting on.
        let edit = try XCTUnwrap(MarkdownFormatting.listReturn("- item", caret: 6))
        XCTAssertFalse(MarkdownEdits.apply(edit, to: editor))
        XCTAssertEqual(editor.string, before, "the composition is left alone")
        XCTAssertEqual(editor.selectedRange(), caret, "and so is the caret")
    }

    /// The same guard, reached through the other overload: the formatting
    /// toggles hand back a whole new string, so ⌘B has its own route in.
    func testAFormattingChangeIsDeclinedWhileTheTextViewHasMarkedText() {
        let editor = markedEditor(startingFrom: "bold me")
        let before = editor.string
        let caret = editor.selectedRange()

        let change = MarkdownFormatting.Change(text: "**bold me**", selection: 2..<9)
        XCTAssertFalse(MarkdownEdits.apply(change, to: editor))
        XCTAssertEqual(editor.string, before)
        XCTAssertEqual(editor.selectedRange(), caret)
    }

    /// Esc mid-accent is the **composition's**: `´` is provisional until the
    /// vowel lands, and Esc is how it is abandoned. Answering it as "leave the
    /// card" closed the card and took the character in flight with it. Once
    /// nothing is marked, Esc means what it always meant.
    func testEscapeWhileMarkedDoesNotLeaveTheCard() {
        var escapes = 0
        let editor = markedEditor(startingFrom: "navegac")
        editor.onEscape = { escapes += 1 }

        editor.cancelOperation(nil)
        XCTAssertEqual(escapes, 0)

        editor.unmarkText()
        editor.cancelOperation(nil)
        XCTAssertEqual(escapes, 1)
    }

    /// ⌘Return is Esc's twin and is guarded with it.
    func testCommandReturnWhileMarkedDoesNotLeaveTheCard() throws {
        var escapes = 0
        let editor = markedEditor(startingFrom: "navegac")
        editor.onEscape = { escapes += 1 }
        let commandReturn = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: 0, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
            )
        )

        editor.keyDown(with: commandReturn)
        XCTAssertEqual(escapes, 0)

        editor.unmarkText()
        editor.keyDown(with: commandReturn)
        XCTAssertEqual(escapes, 1)
    }

    /// An editor with a dead key pending, which is the state all four guards
    /// above are about: `´` is in the storage, provisional, and no
    /// `textDidChange` has been posted for it.
    private func markedEditor(startingFrom text: String) -> MarkdownTextView {
        let editor = MarkdownTextView()
        // Nothing here should reach the spell checker or the completion list;
        // the guarded routes defer to `super`, which would otherwise ask both.
        editor.isContinuousSpellCheckingEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        editor.string = text
        let end = (text as NSString).length
        editor.setSelectedRange(NSRange(location: end, length: 0))
        editor.setMarkedText(
            "\u{B4}",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: end, length: 0)
        )
        XCTAssertTrue(editor.hasMarkedText())
        return editor
    }

    // MARK: - Which text view is a body

    /// One predicate for "is a Markdown body what the keyboard is going to?",
    /// and the case it exists for: the view-mode preview is an `NSTextView`
    /// too, so "a text view that isn't a field editor" answered *yes* for a card
    /// nobody is typing in — which stood the `@project` monitor down.
    func testTheBodyPredicateRejectsThePreviewAndAcceptsTheEditor() {
        let preview = MarkdownPreviewView()
        preview.isEditable = false
        XCTAssertNil(MarkdownResponder.markdownBody(responder: preview))

        // Rejected on the class as well as on `isEditable`, so neither half is
        // load-bearing on its own.
        preview.isEditable = true
        XCTAssertNil(MarkdownResponder.markdownBody(responder: preview))

        let editor = MarkdownTextView()
        XCTAssertTrue(editor.isEditable, "a body editor arrives editable")
        XCTAssertNotNil(MarkdownResponder.markdownBody(responder: editor))

        XCTAssertNil(MarkdownResponder.markdownBody(responder: nil))
        XCTAssertNil(MarkdownResponder.markdownBody(responder: NSTextView()))
    }

    // MARK: - A checkbox that ends the line

    /// `- [x]` with nothing after the box is the ticked box the renderer draws
    /// (`MarkdownParser.checkboxMarker` accepts a space **or the end of the
    /// line**), so the marker Return reads is the whole `- [x]`. It used to
    /// require the space, which made the box literal text on a plain bullet:
    /// Return inserted a bare `- ` underneath and left `[x]` sitting above it.
    ///
    /// With the box read as the marker the item has no content, so Return does
    /// what it does on any empty item and **ends the list** — it does not add an
    /// empty one to it.
    func testReturnOnACheckboxEndingTheLineReadsTheBoxAsItsMarker() {
        XCTAssertEqual(MarkdownFormatting.continueList("- [x]", caret: 5)?.text, "")
        XCTAssertEqual(MarkdownFormatting.continueList("- [ ]", caret: 5)?.text, "")
        XCTAssertEqual(
            MarkdownFormatting.continueList("- [x] milk\n- [ ]", caret: 16)?.text,
            "- [x] milk\n"
        )
    }

    /// The other half of the same rule: an item *with* content still continues
    /// as an unchecked box, so reading the marker further has changed nothing
    /// about the ordinary case.
    func testReturnOnAChecklistItemStillContinuesTheChecklist() {
        XCTAssertEqual(
            MarkdownFormatting.continueList("- [x] milk", caret: 10)?.text,
            "- [x] milk\n- [ ] "
        )
    }

    /// And the same marker, read by the formatting bar's list buttons: toggling
    /// the bullet off takes the box with it rather than leaving `[x]` behind as
    /// words.
    func testTogglingAChecklistOffRemovesTheWholeMarker() {
        XCTAssertEqual(
            MarkdownFormatting.toggleList("- [x]", selection: 0..<5, ordered: false)?.text,
            ""
        )
    }

    // MARK: - Lists' paragraph shape

    /// The editor opens half a line above an item that sits under another and
    /// insets every item, through paragraph attributes — the source stays the
    /// file's, byte for byte. Pinned because the sizing proxy carries the same
    /// two values as real padding, and the editor is only as tall as it says.
    func testListItemsCarryTheInsetAndTheGapAsParagraphStyle() {
        let editor = MarkdownTextView()
        let base = NSFont.systemFont(ofSize: 15)
        editor.highlightConfig = MarkdownHighlight.Config(
            base: base,
            typeface: .standard,
            palette: .init(text: .labelColor, marker: .gray, faintMarker: .lightGray, link: .linkColor)
        )
        editor.string = "- a\n- b\nprose"
        editor.rehighlight()

        func style(at offset: Int) -> NSParagraphStyle? {
            editor.textStorage?.attribute(.paragraphStyle, at: offset, effectiveRange: nil)
                as? NSParagraphStyle
        }
        XCTAssertEqual(style(at: 0)?.headIndent, MarkdownText.listInset)
        XCTAssertEqual(style(at: 0)?.firstLineHeadIndent, MarkdownText.listInset)
        XCTAssertEqual(style(at: 0)?.paragraphSpacingBefore, 0)
        XCTAssertEqual(style(at: 4)?.headIndent, MarkdownText.listInset)
        XCTAssertEqual(style(at: 4)?.paragraphSpacingBefore, MarkdownText.listGap(base))
        XCTAssertEqual(style(at: 8)?.headIndent, 0)
        XCTAssertEqual(style(at: 8)?.paragraphSpacingBefore, 0)
    }

}

/// Counts `textDidChange`, which a composition is shown not to post, and the
/// selection changes it posts instead.
private final class TextChangeSpy: NSObject, NSTextViewDelegate {
    var textChanges = 0
    var selectionChanges = 0
    func textDidChange(_ notification: Notification) { textChanges += 1 }
    func textViewDidChangeSelection(_ notification: Notification) { selectionChanges += 1 }
}
