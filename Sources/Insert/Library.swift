import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.alejandrolacasa.insert", category: "Library")

/// The app's data store and in-memory index.
///
/// Everything lives as Markdown on disk (see `MarkdownFiles`); `Library` loads
/// it once into memory, serves fast in-memory queries to the UI, and writes the
/// single affected file back on every change. A lightweight directory watcher
/// reloads when the folder is edited externally (e.g. in Obsidian).
@MainActor
@Observable
final class Library {
    static let shared = Library()

    private(set) var projects: [Project] = []
    private(set) var notes: [Note] = []
    private(set) var tasks: [TaskItem] = []

    /// Root storage folder. Setting it re-homes the index and reloads.
    private(set) var rootURL: URL

    private var watcher: DirectoryWatcher?
    /// While true, watcher-triggered reloads are ignored (our own writes).
    private var suppressReloadUntil = Date.distantPast

    // MARK: - Paths

    var notesDir: URL { rootURL.appendingPathComponent("Notes", isDirectory: true) }
    var tasksDir: URL { rootURL.appendingPathComponent("Tasks", isDirectory: true) }
    var projectsFile: URL { rootURL.appendingPathComponent("Projects.md") }

    // MARK: - Init

    private init() {
        self.rootURL = Self.resolveDefaultRoot()
        ensureStructure()
        reloadAll()
        seedIfFirstRun()
        startWatching()
    }

    /// On the very first launch (once per machine), drop in a small set of
    /// sample projects, notes and tasks so the app opens with something to look
    /// at instead of three empty columns. Guarded by a UserDefaults flag so it
    /// never resurrects content the user later deletes.
    private func seedIfFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didSeed") else { return }
        defaults.set(true, forKey: "didSeed")
        guard projects.isEmpty, notes.isEmpty, tasks.isEmpty else { return }

        let welcome = addProject(name: "Welcome", symbol: "hand.wave", tint: .blue)
        let sideProject = addProject(name: "Side Project", symbol: "paperplane", tint: .purple)

        var intro = Note(
            title: "Welcome to Insert",
            symbol: "hand.wave",
            typeID: NoteType.noteID,
            projectIDs: [welcome.id],
            body: """
            **Insert** keeps your projects, notes and tasks in one calm place.

            - The left column is your **projects** — add, rename, sort and filter them.
            - The middle column is **notes** — pick a type (Note, Meeting, Feedback, Staffing…) and write in Markdown.
            - The right column is **tasks** — tick them off, give them due dates, and tag projects with `#`.

            Everything is saved as plain Markdown you can open anywhere. Hide this sidebar with **⌘ + the key left of 1**.
            """
        )
        persistNote(&intro); notes.append(intro)

        var meeting = Note(
            title: "Kickoff meeting",
            symbol: "person.2.wave.2",
            typeID: "meeting",
            projectIDs: [sideProject.id],
            body: """
            ## Agenda
            1. Goals for the first milestone
            2. Who owns what
            3. Timeline

            > Decision: ship a small, sharp v1 first.
            """
        )
        persistNote(&meeting); notes.append(meeting)

        let cal = Calendar.current
        let today = Date()
        addTask(title: "Read the welcome note", projectIDs: [welcome.id], due: today)
        addTask(title: "Add your first project", projectIDs: [welcome.id],
                due: cal.date(byAdding: .day, value: 1, to: today))
        addTask(title: "Sketch the v1 scope", projectIDs: [sideProject.id],
                due: cal.date(byAdding: .day, value: -1, to: today))
        addTask(title: "Someday: explore ideas", projectIDs: [sideProject.id], due: nil)
    }

    static func resolveDefaultRoot() -> URL {
        if let saved = UserDefaults.standard.string(forKey: "rootFolderPath"), !saved.isEmpty {
            return URL(fileURLWithPath: saved, isDirectory: true)
        }
        // "Insert Dev" for the dev build. Its UserDefaults are its own, so it
        // never inherits the real build's saved path and always lands here —
        // which keeps test deletions and the retention sweep off real notes.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(BuildVariant.defaultFolderName, isDirectory: true)
    }

    /// Point the library at a new folder (persists the choice, reloads).
    ///
    /// Nothing on disk is moved: the old folder keeps its files and the app
    /// simply reads whatever lives at the new location. Use `moveRoot(to:)` to
    /// take the Markdown along.
    func setRoot(_ url: URL) {
        rootURL = url
        UserDefaults.standard.set(url.path, forKey: "rootFolderPath")
        ensureStructure()
        reloadAll()
        startWatching()
    }

    /// What a relocation actually did, so Settings can say so plainly.
    struct MoveResult {
        var moved = 0
        /// Files left behind because the destination already had that filename
        /// (or the move itself failed) — never overwritten, never lost.
        var skipped = 0
    }

    /// Move the library's Markdown into `url` and re-home there.
    ///
    /// Existing files at the destination win: a name collision leaves both
    /// copies alone and is reported as skipped, so this can never clobber a
    /// folder that already holds Insert data. `Projects.md` is *merged* rather
    /// than replaced for the same reason.
    @discardableResult
    func moveRoot(to url: URL) throws -> MoveResult {
        let fm = FileManager.default
        let source = rootURL.standardizedFileURL
        guard url.standardizedFileURL != source else { return MoveResult() }

        let destNotes = url.appendingPathComponent("Notes", isDirectory: true)
        let destTasks = url.appendingPathComponent("Tasks", isDirectory: true)
        try fm.createDirectory(at: destNotes, withIntermediateDirectories: true)
        try fm.createDirectory(at: destTasks, withIntermediateDirectories: true)

        // Our own churn would otherwise have the watcher reload a half-moved
        // folder; drop it and re-arm from `setRoot` below.
        watcher = nil
        suppressReloadUntil = Date().addingTimeInterval(2)

        var result = MoveResult()
        for (from, to) in [(notesDir, destNotes), (tasksDir, destTasks)] {
            let files = (try? fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension.lowercased() == "md" {
                let target = to.appendingPathComponent(file.lastPathComponent)
                if fm.fileExists(atPath: target.path) {
                    result.skipped += 1
                    continue
                }
                do {
                    try fm.moveItem(at: file, to: target)
                    result.moved += 1
                } catch {
                    log.error("move failed for \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    result.skipped += 1
                }
            }
        }

        // Union the two project lists by id: whatever was already at the
        // destination keeps its entry, ours are appended.
        let destProjects = url.appendingPathComponent("Projects.md")
        let existing = (try? String(contentsOf: destProjects, encoding: .utf8))
            .map(MarkdownFiles.decodeProjects) ?? []
        var merged = existing
        for project in projects where !merged.contains(where: { $0.id == project.id }) {
            merged.append(project)
        }
        try MarkdownFiles.encodeProjects(merged).write(to: destProjects, atomically: true, encoding: .utf8)
        // Only retire the old list once every note and task made it across —
        // otherwise the leftovers would lose their project names.
        if result.skipped == 0 {
            try? fm.removeItem(at: projectsFile)
        }

        setRoot(url)
        return result
    }

    // MARK: - Filesystem setup

    private func ensureStructure() {
        let fm = FileManager.default
        try? fm.createDirectory(at: notesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: tasksDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: projectsFile.path) {
            try? MarkdownFiles.encodeProjects([]).write(to: projectsFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Loading

    func reloadAll() {
        projects = loadProjects()
        notes = loadNotes()
        tasks = loadTasks()
    }

    private func loadProjects() -> [Project] {
        guard let content = try? String(contentsOf: projectsFile, encoding: .utf8) else { return [] }
        return MarkdownFiles.decodeProjects(from: content)
    }

    private func loadNotes() -> [Note] {
        deduped(markdownFiles(in: notesDir).compactMap { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return MarkdownFiles.decodeNote(from: content, url: url)
        })
    }

    private func loadTasks() -> [TaskItem] {
        deduped(markdownFiles(in: tasksDir).compactMap { url in
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return MarkdownFiles.decodeTask(from: content, url: url)
        })
    }

    /// Keeps one file per id — the most recently updated — and trashes the rest.
    ///
    /// Two files can only share an id if a rename went wrong (see `updateNote`),
    /// and duplicate ids poison the UI: SwiftUI's `ForEach` sees repeated
    /// identities and lays out phantom, empty rows. Trashing rather than deleting
    /// leaves the loser recoverable.
    private func deduped<T: MarkdownRecord>(_ items: [T]) -> [T] {
        var newest: [UUID: T] = [:]
        var stale: [URL] = []
        for item in items {
            guard let rival = newest[item.id] else {
                newest[item.id] = item
                continue
            }
            let loser = item.updated > rival.updated ? rival : item
            newest[item.id] = item.updated > rival.updated ? item : rival
            if let url = loser.fileURL { stale.append(url) }
        }
        for url in stale {
            log.error("duplicate id, trashing \(url.lastPathComponent, privacy: .public)")
            trash(url)
        }
        // Keep the on-disk order of the survivors; sorting is the caller's job.
        return items.filter { newest[$0.id]?.fileURL == $0.fileURL }
    }

    private func markdownFiles(in dir: URL) -> [URL] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "md" }
    }

    // MARK: - Writing helpers

    private func suppressReload() {
        suppressReloadUntil = Date().addingTimeInterval(1.0)
    }

    private func write(_ string: String, to url: URL) {
        suppressReload()
        do {
            try string.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            log.error("write failed \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func remove(_ url: URL?) {
        guard let url else { return }
        suppressReload()
        try? FileManager.default.removeItem(at: url)
    }

    /// Moves a file to the Trash, falling back to a plain delete where that
    /// isn't possible (a volume with no trash, say).
    private func trash(_ url: URL?) {
        guard let url else { return }
        suppressReload()
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            log.error("trash failed \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            remove(url)
        }
    }

    private func persistProjects() {
        write(MarkdownFiles.encodeProjects(projects), to: projectsFile)
    }

    /// Writes the note to disk, renaming its file if the slug changed.
    private func persistNote(_ note: inout Note) {
        let desired = notesDir.appendingPathComponent(MarkdownFiles.noteFilename(note))
        if let existing = note.fileURL, existing != desired {
            remove(existing)
        }
        note.fileURL = desired
        write(MarkdownFiles.encode(note), to: desired)
    }

    private func persistTask(_ task: inout TaskItem) {
        let desired = tasksDir.appendingPathComponent(MarkdownFiles.taskFilename(task))
        if let existing = task.fileURL, existing != desired {
            remove(existing)
        }
        task.fileURL = desired
        write(MarkdownFiles.encode(task), to: desired)
    }

    // MARK: - Projects CRUD

    @discardableResult
    func addProject(
        name: String,
        symbol: String = SymbolCatalog.defaultProject,
        tint: Tint? = nil
    ) -> Project {
        // With no colour asked for, take the one the sidebar is using least, so a
        // run of new projects comes out distinguishable rather than all blue.
        let project = Project(name: name, symbol: symbol, tint: tint ?? leastUsedTint())
        projects.append(project)
        persistProjects()
        return project
    }

    /// The palette entry fewest projects wear, in `Tint.allCases` order so the
    /// choice is stable rather than random.
    private func leastUsedTint() -> Tint {
        var counts: [Tint: Int] = [:]
        for project in projects { counts[project.tint, default: 0] += 1 }
        return Tint.allCases.min { (counts[$0] ?? 0, Tint.allCases.firstIndex(of: $0)!)
                                 < (counts[$1] ?? 0, Tint.allCases.firstIndex(of: $1)!) } ?? .blue
    }

    func updateProject(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
        persistProjects()
    }

    /// Bumps `lastUsed` to now (drives the "Latest used" sort).
    func touchProject(id: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].lastUsed = Date()
        persistProjects()
    }

    /// Deletes a project and unassigns it from every note and task.
    func deleteProject(id: UUID) {
        projects.removeAll { $0.id == id }
        persistProjects()
        for i in notes.indices where notes[i].projectIDs.contains(id) {
            notes[i].projectIDs.removeAll { $0 == id }
            var n = notes[i]; persistNote(&n); notes[i] = n
        }
        for i in tasks.indices where tasks[i].projectIDs.contains(id) {
            tasks[i].projectIDs.removeAll { $0 == id }
            var t = tasks[i]; persistTask(&t); tasks[i] = t
        }
    }

    func project(id: UUID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    // MARK: - Notes CRUD

    @discardableResult
    func addNote(title: String = "", type: NoteType = .fallback, projectIDs: [UUID] = []) -> Note {
        var note = Note(title: title, symbol: type.symbol, typeID: type.id, projectIDs: projectIDs)
        persistNote(&note)
        notes.append(note)
        for id in projectIDs { touchProject(id: id) }
        return note
    }

    func updateNote(_ note: Note) {
        guard let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = note
        // Take the file URL from the index, not from `note`: a card's draft holds
        // the URL the note had when it was last re-seeded, and the filename tracks
        // the title. Renaming from a stale URL left the intermediate files behind
        // — one orphan per debounced save, all sharing the same id.
        updated.fileURL = notes[idx].fileURL
        updated.updated = Date()
        persistNote(&updated)
        notes[idx] = updated
        for id in updated.projectIDs { touchProject(id: id) }
    }

    func deleteNote(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        // Trash rather than unlink: deleting a note is a one-click, unconfirmed
        // action, and Settings promises "moved to the Trash, so you can always
        // get them back" — that has to hold for this path too, not just for the
        // completed-task sweep.
        trash(notes[idx].fileURL)
        notes.remove(at: idx)
    }

    // MARK: - Tasks CRUD

    @discardableResult
    func addTask(title: String = "", projectIDs: [UUID] = [], due: Date? = nil) -> TaskItem {
        var task = TaskItem(title: title, projectIDs: projectIDs, due: due)
        persistTask(&task)
        tasks.append(task)
        for pid in projectIDs { touchProject(id: pid) }
        return task
    }

    func updateTask(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        // The index knows where this task lives on disk; the caller's draft may
        // not (see `updateNote`).
        updated.fileURL = tasks[idx].fileURL
        stampCompletion(&updated)
        updated.updated = Date()
        persistTask(&updated)
        tasks[idx] = updated
        for pid in updated.projectIDs { touchProject(id: pid) }
    }

    func toggleTask(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        var updated = tasks[idx]
        updated.done.toggle()
        stampCompletion(&updated)
        updated.updated = Date()
        persistTask(&updated)
        tasks[idx] = updated
    }

    /// Keeps `completed` in step with `done`: stamped the moment a task is
    /// ticked off, cleared when it's reopened. An existing stamp is left alone
    /// so ordinary edits to a finished task don't reset its age.
    private func stampCompletion(_ task: inout TaskItem) {
        if task.done {
            if task.completed == nil { task.completed = Date() }
        } else {
            task.completed = nil
        }
    }

    func deleteTask(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        // Recoverable, for the same reason `deleteNote` is.
        trash(tasks[idx].fileURL)
        tasks.remove(at: idx)
    }

    // MARK: - Housekeeping

    /// Clears out tasks finished longer ago than `retention` allows. Tasks the
    /// user never stamped (ticked off in Obsidian, or before `completed`
    /// existed) fall back to their `updated` date, which is the closest thing
    /// on record.
    ///
    /// Files go to the Trash rather than being unlinked: this runs unattended,
    /// so the user has to be able to get their notes back if the setting turns
    /// out to be more aggressive than they meant.
    @discardableResult
    func purgeCompletedTasks(retention: DoneTaskRetention, now: Date = Date()) -> Int {
        guard let cutoff = retention.cutoff(from: now) else { return 0 }
        let expired = tasks.filter { $0.done && ($0.completed ?? $0.updated) < cutoff }
        guard !expired.isEmpty else { return 0 }

        for task in expired { trash(task.fileURL) }
        let expiredIDs = Set(expired.map(\.id))
        tasks.removeAll { expiredIDs.contains($0.id) }
        log.info("purged \(expired.count, privacy: .public) completed task(s) to the Trash")
        return expired.count
    }

    /// How many tasks `purgeCompletedTasks` would remove right now — lets the
    /// Settings pane say what a choice costs before it's made.
    func completedTaskCount(expiredUnder retention: DoneTaskRetention, now: Date = Date()) -> Int {
        guard let cutoff = retention.cutoff(from: now) else { return 0 }
        return tasks.filter { $0.done && ($0.completed ?? $0.updated) < cutoff }.count
    }

    // MARK: - Queries

    /// (notes, tasks) counts for a project.
    func counts(forProject id: UUID) -> (notes: Int, tasks: Int) {
        let n = notes.lazy.filter { $0.projectIDs.contains(id) }.count
        let t = tasks.lazy.filter { $0.projectIDs.contains(id) }.count
        return (n, t)
    }

    /// Notes for a project (`nil` = all), sorted and filtered.
    func notes(forProject projectID: UUID?, sort: NoteSort, typeFilter: String?, search: String) -> [Note] {
        var result = notes
        if let projectID { result = result.filter { $0.projectIDs.contains(projectID) } }
        if let typeFilter { result = result.filter { $0.typeID == typeFilter } }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(query) || $0.body.lowercased().contains(query)
            }
        }
        return result.sorted { sortNotes($0, $1, by: sort) }
    }

    private func sortNotes(_ a: Note, _ b: Note, by sort: NoteSort) -> Bool {
        switch sort {
        case .createdDesc: a.created > b.created
        case .createdAsc: a.created < b.created
        case .updatedDesc: a.updated > b.updated
        case .updatedAsc: a.updated < b.updated
        }
    }

    /// Tasks for a project (`nil` = all), filtered by state + search.
    func tasks(forProject projectID: UUID?, filter: TaskFilter, search: String) -> [TaskItem] {
        var result = tasks
        if let projectID { result = result.filter { $0.projectIDs.contains(projectID) } }
        switch filter {
        case .all: break
        case .pending: result = result.filter { !$0.done }
        case .done: result = result.filter { $0.done }
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.title.lowercased().contains(query) || $0.body.lowercased().contains(query)
            }
        }
        // Pending first, then by due date (soonest, undated last), then newest.
        return result.sorted { taskOrder($0) < taskOrder($1) }
    }

    private func taskOrder(_ t: TaskItem) -> (Int, TimeInterval, TimeInterval) {
        let donePenalty = t.done ? 1 : 0
        let dueKey = t.due?.timeIntervalSince1970 ?? Date.distantFuture.timeIntervalSince1970
        return (donePenalty, dueKey, -t.created.timeIntervalSince1970)
    }

    /// Reorders projects (drag-and-drop in the sidebar). The array order is the
    /// canonical order and is persisted straight to `Projects.md`.
    func moveProjects(fromOffsets source: IndexSet, toOffset destination: Int) {
        projects.move(fromOffsets: source, toOffset: destination)
        persistProjects()
    }

    // MARK: - Global search

    struct SearchResults {
        var projects: [Project]
        var notes: [Note]
        var tasks: [TaskItem]
        var isEmpty: Bool { projects.isEmpty && notes.isEmpty && tasks.isEmpty }
    }

    func search(_ query: String) -> SearchResults {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return SearchResults(projects: [], notes: [], tasks: []) }
        return SearchResults(
            projects: projects.filter { $0.name.lowercased().contains(q) },
            notes: notes.filter { $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q) },
            tasks: tasks.filter { $0.title.lowercased().contains(q) || $0.body.lowercased().contains(q) }
        )
    }

    // MARK: - Watching

    private func startWatching() {
        watcher = DirectoryWatcher(urls: [notesDir, tasksDir, rootURL]) { [weak self] in
            guard let self else { return }
            if Date() < self.suppressReloadUntil { return }
            self.reloadAll()
        }
    }
}
