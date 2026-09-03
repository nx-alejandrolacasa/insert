import SwiftUI

// MARK: - The record a card edits

/// One field of a card's draft, merged on its own so an upstream change to a
/// *different* field can never rewrite it. Built from a key path, so the rule
/// is written once here and each record only lists the fields it edits.
struct CardDraftField<Record>: Sendable {
    private let take: @Sendable (inout Record, Record, Record) -> Bool

    init<Value: Equatable & Sendable>(_ field: WritableKeyPath<Record, Value> & Sendable) {
        take = { draft, upstream, base in
            // The draft still holds what was last seeded, so nobody has typed
            // over this field and upstream's value is the newer of the two.
            guard draft[keyPath: field] == base[keyPath: field],
                  draft[keyPath: field] != upstream[keyPath: field]
            else { return false }
            draft[keyPath: field] = upstream[keyPath: field]
            return true
        }
    }

    /// - Returns: whether the draft's value for this field changed.
    @discardableResult
    func merge(into draft: inout Record, from upstream: Record, base: Record) -> Bool {
        take(&draft, upstream, base)
    }
}

/// A record edited in place on a card — a note or a task.
protocol CardDraft: Identifiable, Equatable where ID == UUID {
    /// The fields the card edits, so a reseed merges them one at a time.
    ///
    /// Bookkeeping is deliberately absent: `Library.updateNote` /
    /// `updateTask` take the file URL from their own index and re-derive
    /// `updated` and `completed`, so a draft's copy of any of them never
    /// reaches the disk.
    static var editedFields: [CardDraftField<Self>] { get }
    var title: String { get }
    var body: String { get }
}

extension CardDraft {
    /// A card left with no title and no writing is discarded rather than
    /// saved — which is also how a just-created one is cancelled: blur the
    /// empty card and it's gone.
    var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension Note: CardDraft {
    static let editedFields: [CardDraftField<Note>] = [
        .init(\.title), .init(\.body), .init(\.symbol), .init(\.typeID), .init(\.projectIDs),
    ]
}

extension TaskItem: CardDraft {
    static let editedFields: [CardDraftField<TaskItem>] = [
        .init(\.title), .init(\.body), .init(\.done), .init(\.due), .init(\.projectIDs),
    ]
}

// MARK: - Persistence

/// The two `Library` calls a session makes, handed in rather than held, so the
/// session is drivable without a `Library` — which is what lets the merge rule
/// be pinned by a suite rather than by a running window.
struct CardPersistence<Record: CardDraft>: Sendable {
    /// Write the record. The library owns the file URL and the stamps.
    let save: @Sendable @MainActor (Record) -> Void
    /// Move the record's file to the Trash. `false` means it is still there,
    /// so the card has to come back.
    let discard: @Sendable @MainActor (Record.ID) async -> Bool
}

/// Which of a card's two fields takes the keyboard as the card opens.
enum CardEntryFocus {
    case title
    case body
}

// MARK: - The session

/// Everything a card does with its draft between the keystroke and the disk:
/// the ~0.4s debounce, the flush, the discard-if-blank on the way out, the
/// deferred focus write, and the merge of an upstream change.
///
/// **One implementation for both cards.** The note panel and the task panel
/// held a copy each and the copies had already drifted — the task row's reseed
/// counted `done` among the fields that could differ but re-seeded the *whole*
/// draft, so ticking a task from the menu bar while typing in it reverted the
/// notes and the debounce then wrote the reverted text back.
///
/// The reseed rule the merge replaces both copies with:
///
/// - **While editing, nothing upstream reaches the draft.** Our own save's
///   timestamp, a tick from the menu bar and an Obsidian edit all arrive as a
///   changed record, and the one thing none of them may do is replace text
///   somebody is in the middle of typing.
/// - **Otherwise the merge is field-wise against the last seeded value**: a
///   field is taken from upstream only where the draft still holds what was
///   seeded, so an upstream `done` flip lands on `done` and leaves a body
///   edited in view mode (a checkbox click) alone.
///
/// The skip has a cost, and it is the deliberate side of the trade: an upstream
/// change to a field the *card* also owns — a tick from the menu bar, a due date
/// set elsewhere — is dropped while the card is open, and the draft's older
/// value goes back to disk on the next save. Typed text cannot be recovered
/// where a tick can be repeated, so the text wins.
@MainActor @Observable
final class CardEditingSession<Record: CardDraft> {
    /// The live, editable copy. Typing writes here; the disk lags by the
    /// debounce.
    var draft: Record
    /// The upstream value the draft was last seeded from — the base of the
    /// field-wise merge, so "the user changed this field" is a comparison
    /// rather than a flag that has to be maintained.
    private(set) var seeded: Record
    /// The body editor's caret. Owned here so the reseed can drop it: a
    /// `String.Index` belongs to the string it was made from, and one measured
    /// against a body that has just been replaced describes text that no
    /// longer exists (see `MarkdownCaret`).
    var bodySelection: TextSelection?
    /// Holds every save path closed while a Trash move is being confirmed.
    var deleting = false

    private var saveTask: Task<Void, Never>?

    /// Long enough to coalesce a burst of typing into one file write, short
    /// enough that a card left alone is on disk before anyone notices.
    static var debounce: Duration { .seconds(0.4) }

    init(_ record: Record) {
        draft = record
        seeded = record
    }

    /// The caret at the end of the body, ready to keep writing. Written only
    /// alongside a programmatic focus — on every focus change it would stamp
    /// on the position a click inside the editor just chose.
    func placeCaretAtBodyEnd() {
        bodySelection = TextSelection(insertionPoint: draft.body.endIndex)
    }

    // MARK: Upstream changes

    /// Merge an upstream change into the draft. See the type's own comment for
    /// the rule and for the two defects it replaces.
    func reseed(from upstream: Record, isEditing: Bool) {
        guard !isEditing else { return }
        if upstream.body != draft.body { bodySelection = nil }
        var merged = draft
        var changed = false
        for field in Record.editedFields {
            if field.merge(into: &merged, from: upstream, base: seeded) { changed = true }
        }
        seeded = upstream
        if changed { draft = merged }
    }

    // MARK: Focus

    /// Put the cursor where it's most useful: the title for a brand-new card,
    /// otherwise the end of the body, ready to keep writing.
    ///
    /// **The one-turn delay is the point.** Called straight from
    /// `onChange(of: isEditing)` this wrote focus into fields that did not
    /// exist yet — the same update swaps the rendered Markdown for the editor,
    /// and a `@FocusState` write naming a field SwiftUI hasn't registered is
    /// dropped silently. That was the first click doing nothing visible: the
    /// card opened with no caret, and Esc never reached it either, because
    /// nothing was focused to receive the key. The second click then focused
    /// the field the AppKit way and both worked. Deferring to the next
    /// main-actor turn puts the write after the editor is in the hierarchy
    /// (and after the click's own responder handling, which is the other thing
    /// that can take focus straight back).
    ///
    /// `isEditing` is a closure rather than a value because it is re-read
    /// *after* the turn: the card may have been closed again in between.
    func focusForEntry(
        isEditing: @escaping @Sendable @MainActor () -> Bool,
        focus: @escaping @Sendable @MainActor (CardEntryFocus) -> Void
    ) {
        Task {
            guard isEditing() else { return }
            if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                focus(.title)
            } else {
                // The caret would otherwise land at offset 0, in front of the
                // text, which reads as an editor that isn't ready.
                placeCaretAtBodyEnd()
                focus(.body)
            }
        }
    }

    // MARK: Persistence

    var hasPendingSave: Bool { saveTask != nil }

    /// Restart the debounce: persist shortly after the last edit. The snapshot
    /// is captured by value so a later keystroke can't mutate what is being
    /// saved.
    func scheduleSave(_ persistence: CardPersistence<Record>) {
        saveTask?.cancel()
        let snapshot = draft
        saveTask = Task {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            persistence.save(snapshot)
            saveTask = nil
        }
    }

    /// Persist immediately, cancelling any pending debounce, so nothing is
    /// lost when editing ends. A no-op with nothing pending — settling a card
    /// twice must not cost a second write.
    func flushSave(_ persistence: CardPersistence<Record>) {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        persistence.save(draft)
    }

    /// An immediate, structural change — a task's done state or due date.
    /// Cancels the text debounce and writes the whole draft, so no stale
    /// snapshot can revert what was just set.
    func persistNow(_ persistence: CardPersistence<Record>) {
        saveTask?.cancel()
        saveTask = nil
        persistence.save(draft)
    }

    /// Ending an edit either persists the draft or, when the card was left
    /// with no text at all, discards it.
    func finishEditing(_ persistence: CardPersistence<Record>) {
        guard !deleting else { return }
        guard draft.isBlank else {
            flushSave(persistence)
            return
        }
        persistence.save(draft)
        deleting = true
        saveTask?.cancel()
        saveTask = nil
        let id = draft.id
        Task {
            if !(await persistence.discard(id)) { deleting = false }
        }
    }

    /// The card is going away — the row scrolled out, the project changed.
    /// Settle a pending edit, mid-edit included, where an empty card must
    /// still be discarded rather than flushed.
    func settle(isEditing: Bool, _ persistence: CardPersistence<Record>) {
        guard !deleting else {
            saveTask?.cancel()
            return
        }
        if isEditing { finishEditing(persistence) } else { flushSave(persistence) }
    }
}
