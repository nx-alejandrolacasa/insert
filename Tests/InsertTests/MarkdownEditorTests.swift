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
