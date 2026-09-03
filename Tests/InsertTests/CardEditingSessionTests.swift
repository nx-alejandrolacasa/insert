import SwiftUI
import XCTest
@testable import Insert

/// Pins the one editing session both cards now share — and above all its
/// **merge rule**, which is the fix for two confirmed ways typed text used to
/// revert: the task row re-seeded its whole draft whenever any field differed
/// (so a tick from the menu bar reverted the notes, and the debounce then wrote
/// the reverted text back), and the note card had no `isEditing` guard at all.
///
/// Worth a suite of its own because the rule is arithmetic over values — three
/// records and a flag — so it needs no window, which is the same reason
/// `MarkdownFormattingTests` and `TaskFilterTests` exist. A merge that quietly
/// stops protecting a field fails in the one way nothing on screen announces:
/// the text is still there while you look at it, and gone after the save.
@MainActor
final class CardEditingSessionTests: XCTestCase {

    /// Collects what a session asked the library to do. A class because the
    /// persistence closures are `@Sendable` and cannot capture a local `var`.
    @MainActor
    private final class Recorder {
        var saved: [Note] = []
        var savedTasks: [TaskItem] = []
        var discarded: [UUID] = []
        var discardSucceeds = true
        var onDiscard: (() -> Void)?
    }

    private func notePersistence(_ recorder: Recorder) -> CardPersistence<Note> {
        CardPersistence(
            save: { recorder.saved.append($0) },
            discard: { id in
                recorder.discarded.append(id)
                recorder.onDiscard?()
                return recorder.discardSucceeds
            }
        )
    }

    private func note(title: String = "Title", body: String = "One") -> Note {
        Note(title: title, body: body)
    }

    private func task(
        title: String = "Task", body: String = "One", done: Bool = false, due: Date? = nil
    ) -> TaskItem {
        TaskItem(title: title, body: body, done: done, due: due)
    }

    // MARK: The reseed is skipped while editing

    /// The typing burst the whole fix is about: an upstream change arriving
    /// mid-sentence must not reach the draft at all.
    func testUpstreamChangeIsIgnoredWhileEditing() {
        let original = task(body: "One")
        let session = CardEditingSession(original)
        session.draft.body = "One, and the sentence being typed"
        session.placeCaretAtBodyEnd()

        var upstream = original
        upstream.done = true
        upstream.body = "One"
        upstream.title = "Renamed elsewhere"
        session.reseed(from: upstream, isEditing: true)

        XCTAssertEqual(session.draft.body, "One, and the sentence being typed")
        XCTAssertEqual(session.draft.title, "Task")
        XCTAssertFalse(session.draft.done)
        // The body under the caret never moved, so the caret still describes
        // the string it was measured against.
        XCTAssertNotNil(session.bodySelection)
        // Nothing was seen, so the merge's base doesn't move either.
        XCTAssertEqual(session.seeded, original)
    }

    // MARK: Field-wise merge when not editing

    /// The task row's reported defect, from the one route that edits a body
    /// without opening the card: a checkbox clicked in view mode, then a tick
    /// from the menu bar. The tick lands; the body doesn't move.
    func testUpstreamDoneFlipLeavesALocallyEditedBodyAlone() {
        let original = task(body: "- [ ] ship it")
        let session = CardEditingSession(original)
        session.draft.body = "- [x] ship it"

        var upstream = original
        upstream.done = true
        session.reseed(from: upstream, isEditing: false)

        XCTAssertTrue(session.draft.done)
        XCTAssertEqual(session.draft.body, "- [x] ship it")
    }

    /// The other half of the same rule: a field nobody has touched locally
    /// really does take the newer value — an Obsidian edit still shows up.
    func testUpstreamBodyChangeIsTakenWhenTheDraftIsUntouched() {
        let original = note(body: "One")
        let session = CardEditingSession(original)

        var upstream = original
        upstream.body = "One, edited in Obsidian"
        session.reseed(from: upstream, isEditing: false)

        XCTAssertEqual(session.draft.body, "One, edited in Obsidian")
        XCTAssertEqual(session.seeded, upstream)
    }

    func testLocallyEditedFieldSurvivesAnUpstreamChangeToAnotherField() {
        let original = note(title: "Title", body: "One")
        let session = CardEditingSession(original)
        session.draft.title = "Title, renamed here"

        var upstream = original
        upstream.body = "One, edited in Obsidian"
        session.reseed(from: upstream, isEditing: false)

        XCTAssertEqual(session.draft.title, "Title, renamed here")
        XCTAssertEqual(session.draft.body, "One, edited in Obsidian")
    }

    func testUpstreamChangeToALocallyEditedFieldIsDeclined() {
        let original = note(title: "Title")
        let session = CardEditingSession(original)
        session.draft.title = "Title, renamed here"

        var upstream = original
        upstream.title = "Title, renamed in Obsidian"
        session.reseed(from: upstream, isEditing: false)

        XCTAssertEqual(session.draft.title, "Title, renamed here")

        // And it stays declined: the base advanced to what was last seen, so a
        // second upstream change to the same field still finds a local edit
        // rather than comparing against a value from two changes ago.
        var later = upstream
        later.title = "Title, renamed in Obsidian again"
        session.reseed(from: later, isEditing: false)
        XCTAssertEqual(session.draft.title, "Title, renamed here")
    }

    /// Every field the card edits is merged, not just the two the panels' old
    /// tests would have caught — a type change and a project assignment made
    /// elsewhere arrive too.
    func testEveryEditedFieldOfANoteIsMerged() {
        let project = UUID()
        let original = note()
        let session = CardEditingSession(original)

        var upstream = original
        upstream.symbol = "sparkles"
        upstream.typeID = "meeting"
        upstream.projectIDs = [project]
        session.reseed(from: upstream, isEditing: false)

        XCTAssertEqual(session.draft.symbol, "sparkles")
        XCTAssertEqual(session.draft.typeID, "meeting")
        XCTAssertEqual(session.draft.projectIDs, [project])
    }

    func testEveryEditedFieldOfATaskIsMerged() {
        let due = Calendar.current.startOfDay(for: Date())
        let original = task()
        let session = CardEditingSession(original)

        var upstream = original
        upstream.due = due
        upstream.done = true
        session.reseed(from: upstream, isEditing: false)

        XCTAssertEqual(session.draft.due, due)
        XCTAssertTrue(session.draft.done)
    }

    // MARK: The caret

    /// `MarkdownCaret`'s trap: a `String.Index` belongs to the string it was
    /// made from, so a caret measured against a body that has just been
    /// replaced has to go rather than be converted.
    func testCaretIsDroppedWhenTheUpstreamBodyDiffers() {
        let original = note(body: "One")
        let session = CardEditingSession(original)
        session.placeCaretAtBodyEnd()
        XCTAssertNotNil(session.bodySelection)

        var upstream = original
        upstream.body = "One, edited in Obsidian"
        session.reseed(from: upstream, isEditing: false)

        XCTAssertNil(session.bodySelection)
    }

    /// The common case is our own save coming back with a new timestamp and
    /// nothing else, which must leave the caret where the user put it.
    func testCaretSurvivesAnUpstreamChangeThatLeavesTheBodyAlone() {
        let original = task(body: "One")
        let session = CardEditingSession(original)
        session.placeCaretAtBodyEnd()

        var upstream = original
        upstream.done = true
        upstream.updated = Date().addingTimeInterval(1)
        session.reseed(from: upstream, isEditing: false)

        XCTAssertNotNil(session.bodySelection)
        XCTAssertTrue(session.draft.done)
    }

    // MARK: The debounce

    func testDebounceIsStillFourTenthsOfASecond() {
        XCTAssertEqual(CardEditingSession<Note>.debounce, .seconds(0.4))
    }

    /// A flush writes a pending edit exactly once. The second call is what the
    /// `hasPendingSave` guard is for — settling a card twice (editing ended,
    /// then the row scrolled away) must not cost a second file write.
    func testFlushWritesAPendingEditOnceAndOnlyWhenSomethingIsPending() {
        let recorder = Recorder()
        let persistence = notePersistence(recorder)
        let session = CardEditingSession(note())

        session.flushSave(persistence)
        XCTAssertTrue(recorder.saved.isEmpty)

        session.draft.body = "Two"
        session.scheduleSave(persistence)
        XCTAssertTrue(session.hasPendingSave)

        session.flushSave(persistence)
        XCTAssertEqual(recorder.saved.map(\.body), ["Two"])
        XCTAssertFalse(session.hasPendingSave)

        session.flushSave(persistence)
        XCTAssertEqual(recorder.saved.count, 1)
    }

    /// A card left with no title and no writing is discarded rather than
    /// saved — which is also how a just-created one is cancelled.
    func testFinishingABlankEditDiscardsTheCard() async {
        let recorder = Recorder()
        let discarded = expectation(description: "discarded")
        recorder.onDiscard = { discarded.fulfill() }
        let session = CardEditingSession(note(title: "  ", body: "\n"))

        session.finishEditing(notePersistence(recorder))
        XCTAssertTrue(session.deleting)
        await fulfillment(of: [discarded], timeout: 2)
        XCTAssertEqual(recorder.discarded, [session.draft.id])
    }

    /// A refused Trash move leaves the card in place, so every save path opens
    /// again rather than the record being stranded.
    func testARefusedDiscardReopensTheSavePaths() async {
        let recorder = Recorder()
        recorder.discardSucceeds = false
        let discarded = expectation(description: "discarded")
        recorder.onDiscard = { discarded.fulfill() }
        let session = CardEditingSession(note(title: "", body: ""))

        session.finishEditing(notePersistence(recorder))
        await fulfillment(of: [discarded], timeout: 2)
        XCTAssertFalse(session.deleting)
    }

    func testFinishingANonBlankEditFlushesInstead() {
        let recorder = Recorder()
        let persistence = notePersistence(recorder)
        let session = CardEditingSession(note(body: "One"))

        session.draft.body = "One, more"
        session.scheduleSave(persistence)
        session.finishEditing(persistence)

        XCTAssertEqual(recorder.saved.map(\.body), ["One, more"])
        XCTAssertTrue(recorder.discarded.isEmpty)
        XCTAssertFalse(session.deleting)
    }

    /// The row going away settles a pending edit; a Trash move already in
    /// flight holds every save path closed instead.
    func testSettleFlushesUnlessACardIsBeingDeleted() {
        let recorder = Recorder()
        let persistence = notePersistence(recorder)
        let session = CardEditingSession(note())

        session.draft.body = "Two"
        session.scheduleSave(persistence)
        session.settle(isEditing: false, persistence)
        XCTAssertEqual(recorder.saved.count, 1)

        session.draft.body = "Three"
        session.scheduleSave(persistence)
        session.deleting = true
        session.settle(isEditing: false, persistence)
        XCTAssertEqual(recorder.saved.count, 1)
    }
}
