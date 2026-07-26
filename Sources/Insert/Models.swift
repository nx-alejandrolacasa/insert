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
    /// Bumped whenever the project (or something under it) is used — drives the
    /// "Latest used" sort.
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

    /// Grey always means "All" (matching the notes filter row); pending is warm
    /// and done is green.
    var tint: Tint {
        switch self {
        case .all: .gray
        case .pending: .orange
        case .done: .green
        }
    }
}
