import AppKit
import Observation
import SwiftUI

/// App-wide settings, persisted to `UserDefaults` and observable by SwiftUI.
/// Mirrors prtscn's pattern: each property saves itself in `didSet`; property
/// observers don't fire during `init`, so loading in `init` is side-effect free.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    /// The editable list of note types. "Note" (id `note`) is always present
    /// and locked; helpers below enforce that invariant.
    var noteTypes: [NoteType] {
        didSet { persistNoteTypes() }
    }

    /// Default sort order for the notes panel.
    var noteSort: NoteSort {
        didSet { defaults.set(noteSort.rawValue, forKey: Keys.noteSort) }
    }

    /// Whether "End of week" means Sunday (full week) or Friday (work week).
    var weekStyle: WeekStyle {
        didSet { defaults.set(weekStyle.rawValue, forKey: Keys.weekStyle) }
    }

    /// How long completed tasks are kept before Insert clears them out.
    var doneTaskRetention: DoneTaskRetention {
        didSet { defaults.set(doneTaskRetention.rawValue, forKey: Keys.doneTaskRetention) }
    }

    /// Auto / Light / Dark — applied to the whole app immediately.
    var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }

    /// The gradient wash behind the main window — decoration only, and off by
    /// default. Adapts to `appearance` on its own (see `Backdrop`), so this
    /// needs no re-apply step the way the theme does.
    var backdrop: Backdrop {
        didSet { defaults.set(backdrop.rawValue, forKey: Keys.backdrop) }
    }

    /// The face note and task cards are written in. Read by `Card` during every
    /// view update, so a change re-renders the cards on its own — nothing to
    /// re-apply here.
    var typeface: Typeface {
        didSet { defaults.set(typeface.rawValue, forKey: Keys.typeface) }
    }

    /// Whether the menu-bar extra is shown.
    var showMenuBar: Bool {
        didSet { defaults.set(showMenuBar, forKey: Keys.showMenuBar) }
    }

    /// Whether Insert posts one notification a day counting the tasks due that day.
    /// Off by default: it needs the system's permission, and asking for that is
    /// something the user should have started (see `TaskReminder`).
    var dailyReminder: Bool {
        didSet { defaults.set(dailyReminder, forKey: Keys.dailyReminder) }
    }

    /// When that reminder goes out, as minutes since midnight — one of
    /// `ReminderSchedule.slots`, which the Settings picker offers directly.
    ///
    /// Minutes rather than a `Date`: the setting is a time of day, and storing a
    /// date would carry a day and a timezone with it that would then have to be
    /// ignored on every read. It is also what lets the picker be a plain list of
    /// `Int`s — see `ReminderSchedule.slots` for why that matters.
    var reminderMinutes: Int {
        didSet { defaults.set(reminderMinutes, forKey: Keys.reminderMinutes) }
    }

    /// Wash each task row in its due badge's colour — orange overdue, green
    /// today, purple upcoming. Undated and done rows keep the neutral stone,
    /// same as when this is off.
    var dueTintedTasks: Bool {
        didSet { defaults.set(dueTintedTasks, forKey: Keys.dueTintedTasks) }
    }

    /// How much of a note shows before it's folded — a preview of so many
    /// rendered lines with a chevron to reveal the rest, or everything.
    /// Everything by default, so an install that never opens Settings keeps
    /// showing whole notes. View mode only; the editor always shows everything.
    var notePreviewLines: PreviewLines {
        didSet { defaults.set(notePreviewLines.rawValue, forKey: Keys.notePreviewLines) }
    }

    /// The same choice for a task's notes — one line by default, the teaser the
    /// rows have always shown.
    var taskPreviewLines: PreviewLines {
        didSet { defaults.set(taskPreviewLines.rawValue, forKey: Keys.taskPreviewLines) }
    }

    /// Which timestamps the card footers carry (✦ created, ✎ last edited) —
    /// notes and tasks each pick their own. See `CardDatesFooter`.
    var noteCardDates: CardDates {
        didSet { defaults.set(noteCardDates.rawValue, forKey: Keys.noteCardDates) }
    }

    var taskCardDates: CardDates {
        didSet { defaults.set(taskCardDates.rawValue, forKey: Keys.taskCardDates) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let appearance = "appearance"
        static let backdrop = "backdrop"
        static let typeface = "typeface"
        static let noteTypes = "noteTypes"
        static let noteSort = "noteSort"
        static let weekStyle = "weekStyle"
        static let doneTaskRetention = "doneTaskRetention"
        static let showMenuBar = "showMenuBar"
        static let dailyReminder = "dailyReminder"
        static let reminderMinutes = "reminderMinutes"
        static let dueTintedTasks = "dueTintedTasks"
        static let notePreviewLines = "notePreviewLines"
        static let taskPreviewLines = "taskPreviewLines"
        static let noteCardDates = "noteCardDates"
        static let taskCardDates = "taskCardDates"
        // Superseded by the two per-kind pickers above; still read once to seed
        // them, never written.
        static let showCreatedDate = "showCreatedDate"
        static let showUpdatedDate = "showUpdatedDate"
        // Superseded by notePreviewLines ("Collapse long notes" was ten lines
        // or nothing); still read once to seed it, never written.
        static let collapseLongNotes = "collapseLongNotes"
        static let noteTintMigrated = "noteTintMigrated"
    }

    private init() {
        noteTypes = Self.loadNoteTypes(from: defaults)
        noteSort = NoteSort(rawValue: defaults.string(forKey: Keys.noteSort) ?? "") ?? .updatedDesc
        weekStyle = WeekStyle(rawValue: defaults.string(forKey: Keys.weekStyle) ?? "") ?? .full
        // Deleting finished work is opt-in, so an install that has never been
        // asked keeps everything.
        doneTaskRetention = DoneTaskRetention(rawValue: defaults.string(forKey: Keys.doneTaskRetention) ?? "") ?? .never
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .auto
        // Plain window background unless asked otherwise, so an install that
        // never opens Settings looks exactly as it did before backdrops existed.
        backdrop = Backdrop(rawValue: defaults.string(forKey: Keys.backdrop) ?? "") ?? .plain
        // Rounded, which is the only face the cards had before this was a choice.
        typeface = Typeface(rawValue: defaults.string(forKey: Keys.typeface) ?? "") ?? .rounded
        showMenuBar = defaults.object(forKey: Keys.showMenuBar) as? Bool ?? true
        dailyReminder = defaults.object(forKey: Keys.dailyReminder) as? Bool ?? false
        // 09:00 by default, and snapped to the offered half hours: the picker used
        // to allow any minute of any hour, so an install saved before that became a
        // list can hold a time no longer on it. (`didSet` doesn't fire during init,
        // so nothing is written back — the snap is idempotent and runs each launch
        // until the user picks something.)
        reminderMinutes = ReminderSchedule.nearestSlot(
            to: defaults.object(forKey: Keys.reminderMinutes) as? Int ?? 9 * 60)
        dueTintedTasks = defaults.object(forKey: Keys.dueTintedTasks) as? Bool ?? false
        // Seeded from the "Collapse long notes" toggle this replaced, which was
        // ten lines or nothing — an install that had it on keeps its fold.
        let legacyCollapse = defaults.object(forKey: Keys.collapseLongNotes) as? Bool ?? false
        notePreviewLines = PreviewLines(rawValue: defaults.string(forKey: Keys.notePreviewLines) ?? "")
            ?? (legacyCollapse ? .ten : .everything)
        // One line is the teaser task rows have always shown.
        taskPreviewLines = PreviewLines(rawValue: defaults.string(forKey: Keys.taskPreviewLines) ?? "") ?? .one
        // Both seeded from the toggle pair this setting used to be — which also
        // covers the fresh install: absent toggles read as "last edited only",
        // the stamp the cards have always worn.
        let legacyCardDates = Self.legacyCardDates(from: defaults)
        noteCardDates = CardDates(rawValue: defaults.string(forKey: Keys.noteCardDates) ?? "") ?? legacyCardDates
        taskCardDates = CardDates(rawValue: defaults.string(forKey: Keys.taskCardDates) ?? "") ?? legacyCardDates

        // Grey became the reserved "All" colour in the filter rows, so the base
        // "Note" type moved to blue. Recolour it once for installs that saved
        // the old grey — but only if the user hasn't picked something else.
        // (`didSet` doesn't fire during init, so persist by hand.)
        if !defaults.bool(forKey: Keys.noteTintMigrated) {
            defaults.set(true, forKey: Keys.noteTintMigrated)
            if let idx = noteTypes.firstIndex(where: { $0.id == NoteType.noteID }),
               noteTypes[idx].tint == .gray {
                noteTypes[idx].tint = .blue
                persistNoteTypes()
            }
        }
    }

    /// The card-dates choice implied by the old show-created/show-updated
    /// toggle pair, for installs that set them before the pickers existed.
    private static func legacyCardDates(from defaults: UserDefaults) -> CardDates {
        let created = defaults.object(forKey: Keys.showCreatedDate) as? Bool ?? false
        let updated = defaults.object(forKey: Keys.showUpdatedDate) as? Bool ?? true
        switch (created, updated) {
        case (false, false): return .none
        case (true, false): return .created
        case (false, true): return .updated
        case (true, true): return .both
        }
    }

    // MARK: - Appearance

    /// Re-applies the saved appearance. Call once at launch (see `AppDelegate`),
    /// since `didSet` doesn't fire for the value loaded in `init`.
    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    // MARK: - Note types

    /// Resolve a note's `typeID` to its type, falling back to "Note".
    func noteType(id: String) -> NoteType {
        noteTypes.first { $0.id == id } ?? (noteTypes.first { $0.id == NoteType.noteID } ?? .fallback)
    }

    /// Adds a new custom type.
    @discardableResult
    func addNoteType(name: String, symbol: String, tint: Tint) -> NoteType {
        let type = NoteType(name: name, symbol: symbol, tint: tint)
        noteTypes.append(type)
        return type
    }

    /// Updates a type in place (locked "Note" can still be recolored, but not
    /// removed or renamed away from "Note" — the UI enforces name/removal).
    func updateNoteType(_ type: NoteType) {
        guard let idx = noteTypes.firstIndex(where: { $0.id == type.id }) else { return }
        var t = type
        if noteTypes[idx].isLocked {
            t.isLocked = true
            t.id = NoteType.noteID
        }
        noteTypes[idx] = t
    }

    /// Removes a type unless it's locked.
    func removeNoteType(id: String) {
        guard let idx = noteTypes.firstIndex(where: { $0.id == id }), !noteTypes[idx].isLocked else { return }
        noteTypes.remove(at: idx)
    }

    private func persistNoteTypes() {
        var types = noteTypes
        // Guarantee the locked base type always exists.
        if !types.contains(where: { $0.id == NoteType.noteID }) {
            types.insert(.fallback, at: 0)
        }
        if let data = try? JSONEncoder().encode(types) {
            defaults.set(data, forKey: Keys.noteTypes)
        }
    }

    private static func loadNoteTypes(from defaults: UserDefaults) -> [NoteType] {
        guard let data = defaults.data(forKey: Keys.noteTypes),
              var types = try? JSONDecoder().decode([NoteType].self, from: data),
              !types.isEmpty
        else { return NoteType.defaults }
        if !types.contains(where: { $0.id == NoteType.noteID }) {
            types.insert(.fallback, at: 0)
        }
        return types
    }

}
