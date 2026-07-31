import Foundation

// MARK: - Project

/// A project or topic. Persisted as one entry in `Projects.md`'s
/// frontmatter. Notes and tasks reference it by `id`.
struct Project: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    /// SF Symbol shown before the name in the sidebar.
    var symbol: String
    /// Colours that symbol, so projects are told apart at a glance.
    var tint: Tint
    var created: Date
    /// Bumped whenever the project (or something under it) is used. Kept in the
    /// file, read by nothing: the sidebar's rows are in the order they were dragged
    /// into, which outlived the "Latest used" sort this was added for.
    var lastUsed: Date

    init(id: UUID = UUID(), name: String, symbol: String = SymbolCatalog.defaultProject,
         tint: Tint = .blue, created: Date = Date(), lastUsed: Date = Date()) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.tint = tint
        self.created = created
        self.lastUsed = lastUsed
    }

    /// Projects render as symbol + name side by side (see `ProjectLabel`), so the
    /// display name is simply the name.
    var displayName: String { name }
}

// MARK: - Note type

/// A note category (Note / Meeting / Feedback / Staffing, plus any the user
/// adds). Editable in Settings; the built-in "Note" type is locked. Persisted
/// in `SettingsStore` (UserDefaults), referenced by notes via `typeID`.
struct NoteType: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    /// SF Symbol shown on the type's pills and on notes of this type.
    var symbol: String
    var tint: Tint
    /// Only the built-in "Note" type is locked (can't be renamed or removed).
    var isLocked: Bool

    init(id: String = UUID().uuidString, name: String, symbol: String, tint: Tint, isLocked: Bool = false) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.tint = tint
        self.isLocked = isLocked
    }

    /// The id of the mandatory, non-editable base type.
    static let noteID = "note"

    /// The four default types described in the plan. "Note" is locked.
    /// Grey is reserved for "All" in the filter rows, so the base type is blue.
    static let defaults: [NoteType] = [
        NoteType(id: noteID, name: "Note", symbol: "note.text", tint: .blue, isLocked: true),
        NoteType(id: "meeting", name: "Meeting", symbol: "person.2.wave.2", tint: .yellow),
        NoteType(id: "feedback", name: "Feedback", symbol: "bubble.left.and.text.bubble.right", tint: .purple),
        NoteType(id: "staffing", name: "Staffing", symbol: "person.3", tint: .green),
    ]

    static var fallback: NoteType { defaults[0] }

    /// Tolerates types stored before icons became symbols: an `emoji` key is read
    /// in `symbol`'s place and resolved (or replaced with a sensible default), so
    /// a user's custom types survive the change instead of resetting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        tint = try c.decode(Tint.self, forKey: .tint)
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        let raw = try c.decodeIfPresent(String.self, forKey: .symbol)
            ?? c.decodeIfPresent(String.self, forKey: .emoji)
            ?? ""
        symbol = SymbolCatalog.resolve(raw, fallback: SymbolCatalog.defaultNote)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(tint, forKey: .tint)
        try c.encode(isLocked, forKey: .isLocked)
    }

    /// `emoji` is read-only: it exists so the legacy key can be decoded, and is
    /// never written back (which is why `encode` is spelled out — synthesis can't
    /// handle a key with no property behind it).
    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, tint, isLocked
        case emoji
    }
}

// MARK: - Markdown-backed records

/// What `Library` needs from anything stored as one Markdown file per record:
/// where it lives and when it last changed. Lets the loader resolve duplicates
/// without knowing whether it's holding notes or tasks.
protocol MarkdownRecord: Identifiable where ID == UUID {
    var updated: Date { get }
    var fileURL: URL? { get }
}

// MARK: - Note

/// A note that lives as a single Markdown file under `Notes/`, with metadata in
/// the YAML frontmatter and the body as Markdown.
struct Note: MarkdownRecord, Hashable, Codable {
    var id: UUID
    var title: String
    /// SF Symbol shown on the card; seeded from the note's type.
    var symbol: String
    /// References a `NoteType.id`.
    var typeID: String
    /// Zero or more projects this note belongs to — like a task, a note can
    /// serve several at once (a meeting covering two workstreams, say).
    var projectIDs: [UUID]
    var body: String
    var created: Date
    var updated: Date
    /// Absolute file URL on disk; `nil` until first saved.
    var fileURL: URL?

    init(id: UUID = UUID(), title: String = "", symbol: String = SymbolCatalog.defaultNote,
         typeID: String = NoteType.noteID, projectIDs: [UUID] = [],
         body: String = "", created: Date = Date(), updated: Date = Date(),
         fileURL: URL? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.typeID = typeID
        self.projectIDs = projectIDs
        self.body = body
        self.created = created
        self.updated = updated
        self.fileURL = fileURL
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : title
    }
}

// MARK: - Task

/// A task that lives as a single Markdown file under `Tasks/`. Can be assigned
/// to several projects at once. An optional `due` date powers the menu-bar
/// past / today / future summary.
struct TaskItem: MarkdownRecord, Hashable, Codable {
    var id: UUID
    var title: String
    var body: String
    var done: Bool
    /// When the task was ticked off — `nil` while it's still pending. Drives the
    /// "remove completed tasks after…" housekeeping, which needs to know *when*
    /// a task was finished, not merely that it was.
    var completed: Date?
    /// Zero or more projects this task belongs to.
    var projectIDs: [UUID]
    /// Optional due date (day granularity).
    var due: Date?
    var created: Date
    var updated: Date
    var fileURL: URL?

    init(id: UUID = UUID(), title: String = "", body: String = "", done: Bool = false,
         completed: Date? = nil, projectIDs: [UUID] = [], due: Date? = nil,
         created: Date = Date(), updated: Date = Date(), fileURL: URL? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.done = done
        self.completed = completed
        self.projectIDs = projectIDs
        self.due = due
        self.created = created
        self.updated = updated
        self.fileURL = fileURL
    }

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled task" : title
    }
}

// MARK: - Sorting & filtering

// Projects are ordered manually (drag-and-drop in the sidebar); their on-disk
// order in Projects.md *is* the order, so there is no ProjectSort.

/// Whether a "week" means the full seven days or just the working days. Decides
/// what the task composer's "End of week" pill resolves to.
enum WeekStyle: String, CaseIterable, Identifiable {
    case full
    case work

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: "Full week"
        case .work: "Work week"
        }
    }

    /// Gregorian weekday the week ends on (Sunday = 1 … Saturday = 7).
    var endWeekday: Int {
        switch self {
        case .full: 1  // Sunday
        case .work: 6  // Friday
        }
    }
}

/// How long finished tasks stick around before Insert clears them out. Defaults
/// to `never`: housekeeping that deletes things is opt-in.
enum DoneTaskRetention: String, CaseIterable, Identifiable {
    case week
    case month
    case year
    case never

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: "After 1 week"
        case .month: "After 1 month"
        case .year: "After 1 year"
        case .never: "Never"
        }
    }

    /// The moment before which a completed task is considered expired, or `nil`
    /// when nothing ever expires.
    func cutoff(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .week: calendar.date(byAdding: .day, value: -7, to: now)
        case .month: calendar.date(byAdding: .month, value: -1, to: now)
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        case .never: nil
        }
    }
}

/// How much of a card's body shows before it is folded behind a chevron — a
/// preview of so many *rendered* lines, or everything, with no collapsing at
/// all. Notes and tasks each pick their own (Settings → Notes / Tasks); the
/// folding itself lives in `CollapsibleMarkdown`.
enum PreviewLines: String, CaseIterable, Identifiable {
    case everything
    case one
    case three
    case five
    case ten

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everything: "Show everything"
        case .one: "1 line"
        case .three: "3 lines"
        case .five: "5 lines"
        case .ten: "10 lines"
        }
    }

    /// The line count, or `nil` for no collapsing.
    var lines: Int? {
        switch self {
        case .everything: nil
        case .one: 1
        case .three: 3
        case .five: 5
        case .ten: 10
        }
    }
}

// Note: there is deliberately no note-archiving setting here. Insert briefly moved
// notes older than a month into `Notes/Archive/` and read them back on demand, to
// keep a large library off the launch path. Two things were wrong with it. What a
// project showed depended on *other* projects' activity, since the age window was
// global — and the cost it was avoiding turned out to be a bug in `DateCoding`,
// which built a `DateFormatter` per date and accounted for more than half of the
// time spent loading a library. With that fixed, reading everything is fast enough
// that the whole apparatus paid for itself in inconsistency and bought nothing.

enum NoteSort: String, CaseIterable, Identifiable {
    case createdDesc
    case createdAsc
    case updatedDesc
    case updatedAsc
    var id: String { rawValue }
    var label: String {
        switch self {
        case .createdDesc: "Created (newest)"
        case .createdAsc: "Created (oldest)"
        case .updatedDesc: "Updated (newest)"
        case .updatedAsc: "Updated (oldest)"
        }
    }
}

/// Holds edited notes' places in an Updated sort for as long as you stay in one
/// view of the list.
///
/// Typing saves on a debounce and every save bumps `updated`, so under the
/// default "Updated (newest)" order the card you were writing in slid to the top
/// of the list mid-sentence — from third place to first, taking the text under
/// the cursor with it. `NotesPanel` pins a note's `updated` as it opens for
/// editing and sorts it by that value; the pins are dropped only when the list is
/// being rebuilt anyway — a different project, type filter, search or sort order —
/// so a note never moves while you are looking at it, and the re-sort lands on the
/// frame that replaces the list. See
/// `Library.notes(forProject:sort:typeFilter:search:pinned:)`.
///
/// A date per note rather than a frozen list order, because an order can't say
/// where a note created (or externally edited) meanwhile belongs.
struct NotePins: Equatable {
    private var updated: [UUID: Date] = [:]

    /// Records the note's current `updated`, unless it is already pinned — a
    /// second edit in the same view must not re-pin it at its new timestamp.
    mutating func pin(_ note: Note) {
        if updated[note.id] == nil { updated[note.id] = note.updated }
    }

    /// The `updated` this note sorts by: its pinned value, or the live one.
    func key(for note: Note) -> Date {
        updated[note.id] ?? note.updated
    }
}

/// `NotePins` for the tasks column: holds a task's place for as long as you stay
/// in one view of the list.
///
/// The same problem read off a different sort key. Tasks sort pending-first, then
/// by due date, and **both halves of that are things a row can change under your
/// cursor**: giving an undated task a date sent it from the tail of the list to
/// wherever that date belongs, and ticking one dropped it into the done block. The
/// due-date popover made it worst — it dismisses on the click that sets the date,
/// so the row left at the same instant the popover did, and since two tasks are
/// often the same shape it read as the click having landed on the wrong card.
///
/// So the pair is frozen the moment the row changes it, and the list re-sorts only
/// when it is being rebuilt anyway — a different project, task filter or search.
/// See `Library.tasks(forProject:filter:search:pinned:)`.
///
/// Sorting only, never filtering: under "Pending" a task you tick still leaves the
/// list, because it is no longer one of the things that view is showing. That's the
/// same line `NotePins` draws against the notes column's type filter.
struct TaskPins: Equatable {
    /// The two components of the task order a row can change: `created` is the
    /// third and can't be edited, so it never needs pinning.
    struct Key: Equatable {
        var done: Bool
        var due: Date?
    }

    private var keys: [UUID: Key] = [:]

    /// Records the task's current place, unless it is already pinned — setting a
    /// date and *then* ticking the task must keep the slot it had before either.
    mutating func pin(_ task: TaskItem) {
        if keys[task.id] == nil { keys[task.id] = Key(done: task.done, due: task.due) }
    }

    /// The `done` / `due` this task sorts by: its pinned pair, or the live one.
    func key(for task: TaskItem) -> Key {
        keys[task.id] ?? Key(done: task.done, due: task.due)
    }
}

/// Which timestamps a card's footer carries (see `CardDatesFooter`). Notes and
/// tasks each have their own setting.
enum CardDates: String, CaseIterable, Identifiable {
    case none
    case created
    case updated
    case mostRecent
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .created: "Created only"
        case .updated: "Last edited only"
        case .mostRecent: "Most recent"
        case .both: "Both"
        }
    }

    /// `edited` is whether the card has been touched since it was made — the
    /// footer compares at the minute it displays, so a fresh card counts as
    /// unedited. `mostRecent` prefers the edit and falls back to creation;
    /// `both` collapses to one stamp rather than showing the same moment twice.
    func showsCreated(edited: Bool) -> Bool {
        switch self {
        case .created: true
        case .both: true
        case .mostRecent: !edited
        case .none, .updated: false
        }
    }

    func showsUpdated(edited: Bool) -> Bool {
        switch self {
        case .updated: true
        case .mostRecent, .both: edited
        case .none, .created: false
        }
    }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case all
    case pending
    case done
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .pending: "Pending"
        case .done: "Done"
        }
    }

    /// The colour each state's dot wears in the segmented track — grey for
    /// "All", warm for pending, green for done, the scheme the old filter
    /// pills wore. Briefly replaced by a single accent dot on the active
    /// segment during the refresh, and put back by request: the states have
    /// always had their own colours here, and the dots are where they live now.
    var tint: Tint {
        switch self {
        case .all: .gray
        case .pending: .orange
        case .done: .green
        }
    }

    /// Whether `task` belongs in this filter's list.
    func matches(_ task: TaskItem) -> Bool {
        switch self {
        case .all: true
        case .pending: !task.done
        case .done: task.done
        }
    }
}

/// The second axis of the tasks filter row, combinable with any `TaskFilter`:
/// Pending + Today is the day's remaining work, Done + Overdue is what got
/// finished late, All + Today is everything on today's plate. Presented as a
/// pill dropdown (`TasksPanel.dateMenu`) whose default entry, "All time", is
/// `nil` here — the axis switched off — rather than a fourth case, so every
/// case is a real window and `matches` has no always-true branch.
enum TaskDateFilter: String, CaseIterable, Identifiable {
    case overdue
    case today
    case tomorrow
    var id: String { rawValue }

    var label: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        }
    }

    // These windows used to wear the due badge's orange / green / purple; both
    // sides of that pairing went grey in the refresh (docs/plans/ decision 4),
    // so the dropdown now shows selection with the accent instead — see
    // `TasksPanel.dateMenu`.

    /// Whether `task`'s due date falls in this filter's window. The due date
    /// *alone*: done-ness belongs to the state axis, which is what lets the two
    /// combine — so "Overdue" here means "due before today", not "still owed",
    /// unlike the menu bar's pending-only buckets (`DateSections`). An undated
    /// task matches no window. `now` is injectable so the day boundaries are
    /// testable; call sites let it default.
    func matches(_ task: TaskItem, now: Date = Date()) -> Bool {
        guard let due = task.due else { return false }
        let cal = Calendar.current
        let days = cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: now),
            to: cal.startOfDay(for: due)
        ).day ?? 0
        return switch self {
        case .overdue: days < 0
        case .today: days == 0
        case .tomorrow: days == 1
        }
    }
}
