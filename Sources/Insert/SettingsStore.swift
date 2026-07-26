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

    /// Whether the menu-bar extra is shown.
    var showMenuBar: Bool {
        didSet { defaults.set(showMenuBar, forKey: Keys.showMenuBar) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        // Note: there is no `appearance` key. Insert used to offer an Auto /
        // Light / Dark override; HIG advises against a per-app appearance
        // setting, because it leaves people adjusting two places to get one
        // result and looks broken when the app ignores their system choice. The
        // app now always follows the system. An `appearance` value saved by an
        // older build is simply left in `UserDefaults` and never read.
        static let noteTypes = "noteTypes"
        static let noteSort = "noteSort"
        static let weekStyle = "weekStyle"
        static let doneTaskRetention = "doneTaskRetention"
        static let showMenuBar = "showMenuBar"
        static let noteTintMigrated = "noteTintMigrated"
    }

    private init() {
        noteTypes = Self.loadNoteTypes(from: defaults)
        noteSort = NoteSort(rawValue: defaults.string(forKey: Keys.noteSort) ?? "") ?? .updatedDesc
        weekStyle = WeekStyle(rawValue: defaults.string(forKey: Keys.weekStyle) ?? "") ?? .full
        // Deleting finished work is opt-in, so an install that has never been
        // asked keeps everything.
        doneTaskRetention = DoneTaskRetention(rawValue: defaults.string(forKey: Keys.doneTaskRetention) ?? "") ?? .never
        showMenuBar = defaults.object(forKey: Keys.showMenuBar) as? Bool ?? true

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
