import AppKit
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
}
