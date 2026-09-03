import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.alejandrolacasa.insert", category: "Library")

/// The app's data store and in-memory index.
///
/// Everything lives as Markdown on disk (see `MarkdownFiles`); `Library` loads
/// it into memory, serves fast in-memory queries to the UI, and writes the
/// single affected file back on every change. A lightweight directory watcher
/// reloads when the folder is edited externally (e.g. in Obsidian).
///
/// **Everything is loaded, always** — every note, every task, on every load. There
/// is no window, no threshold and nothing deferred, which is what makes every list
/// complete and every count exact no matter how the library is shaped. That is
/// affordable because reading and parsing a note costs about 110 µs, of which 18 µs
/// is the file read: a thousand notes is well under a tenth of a second, and the
/// decode is spread across the cores (see `decoded(_:)`).
///
/// It was not always affordable, and the reason is worth remembering. `DateCoding`
/// used to build a `DateFormatter` per date, which was 180 µs of that 110 — more
/// than half the cost of loading a library went on formatters that were then thrown
/// away. An earlier version of this file answered that with archive folders, age
/// thresholds and on-demand loading; all of it was working around a bug, and all of
/// it is gone. Measure before adding laziness back.
@MainActor
@Observable
final class Library {
    static let shared = Library()

    struct DeletionFailure: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    typealias TrashOperation = @Sendable (URL) throws -> URL

    private(set) var projects: [Project] = []
    private(set) var notes: [Note] = [] { didSet { cachedProjectCounts = nil } }
    private(set) var tasks: [TaskItem] = [] { didSet { cachedProjectCounts = nil } }
    private(set) var deletionFailure: DeletionFailure?

    /// `counts(forProject:)`'s one-pass table, built on demand.
    ///
    /// Invalidated from the two `didSet`s above rather than from each of the
    /// dozen-odd places that append, assign, re-file or remove a record, so a
    /// new mutation site cannot forget to do it — and a stale count is a wrong
    /// number on screen. An in-place `notes[i] = …` is a mutating access to the
    /// property, so it fires too; `testProjectCountsFollowEveryMutation` is what
    /// holds that claim up.
    ///
    /// `@ObservationIgnored`, so filling it in during a read notifies nobody and
    /// cannot feed back into the render that asked. What registers the
    /// dependency instead is `counts(forProject:)` reading `notes` and `tasks`.
    @ObservationIgnored
    private var cachedProjectCounts: [UUID: (notes: Int, tasks: Int)]?

    /// Root storage folder. Setting it re-homes the index and reloads.
    private(set) var rootURL: URL

    private var watcher: DirectoryWatcher?
    /// While true, watcher-triggered reloads are ignored (our own writes).
    private var suppressReloadUntil = Date.distantPast
    private var pendingDeletions: Set<DeletionKey> = []
    private var pendingNoteUpdates: [UUID: Note] = [:]
    private var pendingTaskUpdates: [UUID: TaskItem] = [:]

    private enum DeletionKey: Hashable {
        case note(UUID)
        case task(UUID)
    }

    private enum TrashMoveError: Error, LocalizedError, Sendable {
        case missingFile
        case failed(String)
        case unconfirmed

        var errorDescription: String? {
            switch self {
            case .missingFile:
                "The Markdown file could not be found."
            case .failed(let message):
                message
            case .unconfirmed:
                "macOS did not confirm the file at its Trash destination."
            }
        }
    }

    /// How a true duplicate found while loading reaches the Trash. The deletion
    /// entry points take theirs as a parameter; this one is reached from
    /// `reloadAll` with no caller to pass it, so it is a property — which is also
    /// what keeps `StorageLayoutTests`' fixtures out of the real Trash.
    @ObservationIgnored
    var duplicateTrashOperation: TrashOperation = Library.systemTrash

    private static let systemTrash: TrashOperation = { source in
        var destination: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &destination)
        guard let destination else { throw TrashMoveError.unconfirmed }
        return destination as URL
    }

    // MARK: - Paths

    var notesDir: URL { rootURL.appendingPathComponent("Notes", isDirectory: true) }
    var tasksDir: URL { rootURL.appendingPathComponent("Tasks", isDirectory: true) }
    /// Completed tasks.
    ///
    /// Purely organisational — both folders are read in full on every load, so this
    /// buys no speed. It keeps a large vault navigable in Obsidian, and it means the
    /// folder a task file sits in agrees with its `done:` flag, which
    /// `reconcileTaskFolders` maintains in both directions.
    var tasksDoneDir: URL { tasksDir.appendingPathComponent("Done", isDirectory: true) }
    var projectsFile: URL { rootURL.appendingPathComponent("Projects.md") }

    /// Whether there is anything here at all.
    var isEmpty: Bool { projects.isEmpty && notes.isEmpty && tasks.isEmpty }

    // MARK: - Init

    private init() {
        self.rootURL = Self.resolveDefaultRoot()
        ensureStructure()
        reloadAllBlocking()
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
        guard isEmpty else { return }

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
        reloadAllBlocking()
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
        // A pending save must land in the old folders before they are walked, or
        // the relocation moves a file the queue is about to rewrite.
        flushDiskWrites()
        let fm = FileManager.default
        let source = rootURL.standardizedFileURL
        guard url.standardizedFileURL != source else { return MoveResult() }

        let destNotes = url.appendingPathComponent("Notes", isDirectory: true)
        let destTasks = url.appendingPathComponent("Tasks", isDirectory: true)

        // Every folder the library uses, source paired with destination. The done
        // folder is as much the user's Markdown as the active ones, so a relocation
        // carries it too — leaving it behind would look exactly like losing it.
        let folders: [(from: URL, to: URL)] = [
            (notesDir, destNotes),
            (tasksDir, destTasks),
            (tasksDoneDir, destTasks.appendingPathComponent("Done", isDirectory: true)),
        ]
        for folder in folders {
            try fm.createDirectory(at: folder.to, withIntermediateDirectories: true)
        }

        // Our own churn would otherwise have the watcher reload a half-moved
        // folder; drop it and re-arm from `setRoot` below.
        watcher = nil
        suppressReloadUntil = Date().addingTimeInterval(2)

        var result = MoveResult()
        for (from, to) in folders {
            for file in markdownFiles(in: from) {
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

    /// Creates the three folders the library reads from.
    ///
    /// `Done` is made up front even when it would stay empty, rather than on first
    /// use: `startWatching` opens a file descriptor per folder, and one conjured
    /// into existence later wouldn't be watched until the next relaunch — external
    /// edits inside it would go unnoticed. An empty folder is the cheaper price.
    private func ensureStructure() {
        let fm = FileManager.default
        for dir in [notesDir, tasksDir, tasksDoneDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: projectsFile.path) {
            try? MarkdownFiles.encodeProjects([]).write(to: projectsFile, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Loading

    /// Reads the entire library — every note, every task — into the index.
    ///
    /// The queued writes are drained **off** the main actor. The drain used to be
    /// the first statement here as a `diskQueue.sync {}`, which put a stalled
    /// iCloud rename between the watcher firing and the next frame — the exact
    /// stall the queue was added to remove. Suspending keeps the ordering that
    /// matters, since nothing is decoded until every queued write has landed, and
    /// gives up only the window it was holding while it waited.
    func reloadAll() async {
        await drainDiskWrites()
        load()
    }

    /// `reloadAll` for the two callers that have to be finished loading by the
    /// time they return: `init`, which has no `await` to make and no window yet
    /// to hold up, and `setRoot`, whose callers read the index on the next line.
    /// Both are once-off — a launch, or a folder picked in Settings — so a block
    /// there is a deliberate cost rather than one paid per external edit.
    private func reloadAllBlocking() {
        flushDiskWrites()
        load()
    }

    /// Everything after the drain. Main actor and with no suspension point in
    /// it, so two reloads can queue up behind each other but never interleave
    /// and leave the index half of one and half of the other.
    private func load() {
        projects = loadProjects()
        notes = deduped(
            Self.decoded(markdownFiles(in: notesDir), MarkdownFiles.decodeNote),
            encode: { (note: Note) in MarkdownFiles.encode(note) },
            reidentify: { note in
                var fresh = note
                fresh.id = UUID()
                persistNote(&fresh)
                return fresh
            }
        )
        tasks = deduped(
            Self.decoded(
                markdownFiles(in: tasksDir) + markdownFiles(in: tasksDoneDir),
                MarkdownFiles.decodeTask
            ),
            encode: { (task: TaskItem) in MarkdownFiles.encode(task) },
            reidentify: { task in
                var fresh = task
                fresh.id = UUID()
                persistTask(&fresh)
                return fresh
            }
        )
        reconcileTaskFolders()
    }

    private func loadProjects() -> [Project] {
        guard let content = try? String(contentsOf: projectsFile, encoding: .utf8) else { return [] }
        return MarkdownFiles.decodeProjects(from: content)
    }

    /// Reads and decodes `urls`, across the cores when there are enough of them to
    /// be worth the fan-out.
    ///
    /// `nonisolated` and `static` deliberately: it touches no library state, which is
    /// what makes it safe to run in parallel at all. Decoding is pure — `Frontmatter`
    /// and `DateCoding` hold only Sendable value types — so the work divides cleanly.
    ///
    /// Chunks are collected into pre-assigned slots rather than appended, so the
    /// result is in the same order however the threads finish. Order isn't load-
    /// bearing (every query sorts), but `deduped` breaks ties between two files
    /// claiming one id by position, and a tie-break that varies run to run would be
    /// a maddening thing to debug.
    private nonisolated static func decoded<T: Sendable>(
        _ urls: [URL],
        _ decode: @Sendable (String, URL) -> T?
    ) -> [T] {
        // `@Sendable` because the fan-out below calls it from several threads at
        // once: it captures only `decode`, which is itself `@Sendable`, so saying so
        // costs nothing and lets the compiler check the claim rather than assume it.
        @Sendable func read(_ url: URL) -> T? {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return decode(text, url)
        }
        // Under a few hundred files the whole load is a couple of milliseconds and
        // thread setup is a bigger share of it than the reading.
        guard urls.count >= 256 else { return urls.compactMap(read) }

        let slots = min(ProcessInfo.processInfo.activeProcessorCount, 8)
        let size = (urls.count + slots - 1) / slots
        let collected = Collected<T>(slots: slots)
        DispatchQueue.concurrentPerform(iterations: slots) { slot in
            let start = slot * size
            guard start < urls.count else { return }
            let chunk = urls[start..<min(start + size, urls.count)]
            collected.store(chunk.compactMap(read), at: slot)
        }
        return collected.joined()
    }

    /// Somewhere for `concurrentPerform`'s workers to put their results. A lock
    /// rather than actor isolation because the callers are synchronous; each worker
    /// takes it once, to hand over a finished chunk, so there is nothing to contend
    /// over. Same shape as `DirectoryWatcher`'s `DebounceState`.
    private final class Collected<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var slots: [[T]]

        init(slots count: Int) { self.slots = Array(repeating: [], count: count) }

        func store(_ values: [T], at slot: Int) {
            lock.lock()
            slots[slot] = values
            lock.unlock()
        }

        func joined() -> [T] {
            lock.lock()
            defer { lock.unlock() }
            return slots.flatMap { $0 }
        }
    }

    /// Files every task under the folder its `done` flag calls for.
    ///
    /// Runs after each load, and does two jobs: it migrates a library written before
    /// `Tasks/Done/` existed, and it keeps the folder honest when a task is ticked
    /// off — or reopened — by hand in Obsidian. Nothing depends on it for *finding*
    /// tasks, since both folders are read in full; it's what stops the layout
    /// quietly becoming a lie.
    ///
    /// It is also where a task ticked off outside Insert gets its completion date
    /// (see `stampUnstampedCompletion(at:)`), for the same reason: what the file
    /// says has to be made true rather than guessed at later.
    private func reconcileTaskFolders() {
        for idx in tasks.indices {
            stampUnstampedCompletion(at: idx)
            guard let from = tasks[idx].fileURL else { continue }
            let wanted = tasks[idx].done ? tasksDoneDir : tasksDir
            guard key(from.deletingLastPathComponent()) != key(wanted) else { continue }
            let to = wanted.appendingPathComponent(from.lastPathComponent)
            suppressReload()
            do {
                try FileManager.default.moveItem(at: from, to: to)
                tasks[idx].fileURL = to
            } catch {
                log.error("could not file \(from.lastPathComponent, privacy: .public) under \(wanted.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Gives a task ticked off outside Insert the completion date it has none of,
    /// and writes it back so the stamp survives the next launch.
    ///
    /// A task finished in Obsidian — or before `completed` existed — arrives done
    /// with no stamp, and the retention purge refuses to age one on `updated`: an
    /// edit date is not a completion date, so a note last touched a year ago and
    /// ticked off this morning would be trashed on sight. Stamping here is what
    /// gives it an age at all, and the age it gets is the moment Insert first saw
    /// it done. `updated` is deliberately left alone — nothing was edited.
    private func stampUnstampedCompletion(at idx: Int) {
        guard tasks[idx].done, tasks[idx].completed == nil else { return }
        var stamped = tasks[idx]
        stampCompletion(&stamped)
        persistTask(&stamped)
        tasks[idx] = stamped
    }

    /// Keeps one record per id, and never loses writing to do it.
    ///
    /// Two files can share an id if a rename went wrong (see `updateNote`) or the
    /// vault was duplicated in Finder, and duplicate ids poison the UI: SwiftUI's
    /// `ForEach` sees repeated identities and lays out phantom, empty rows.
    ///
    /// Only a **true** duplicate is trashed — one that `encode`s to the same
    /// string, which is the same id, the same `updated` and the same content, so
    /// there is nothing in it the survivor doesn't already have. Anything else is
    /// two pieces of writing under one id: the newer keeps the id, the older is
    /// given a fresh one and saved under it, so both files stay. Breaking an
    /// `updated` tie by directory order and trashing the loser is what this used
    /// to do, and a Finder duplicate whose frontmatter was untouched can be the
    /// copy carrying the new writing.
    ///
    /// Trashing rather than deleting still leaves a true duplicate recoverable.
    private func deduped<T: MarkdownRecord>(
        _ items: [T],
        encode: (T) -> String,
        reidentify: (T) -> T
    ) -> [T] {
        // Keeps the on-disk order of everything already seen; sorting is the
        // caller's job. A re-identified record lands at the end, which is as
        // stable as the load order it came from.
        var kept: [T] = []
        var slot: [UUID: Int] = [:]
        for item in items {
            guard let index = slot[item.id] else {
                slot[item.id] = kept.count
                kept.append(item)
                continue
            }
            let rival = kept[index]
            if encode(item) == encode(rival) {
                log.error("duplicate file, trashing \(item.fileURL?.lastPathComponent ?? "?", privacy: .public)")
                if let url = item.fileURL { enqueueTrash(url) }
                continue
            }
            let newer = item.updated > rival.updated ? item : rival
            let older = item.updated > rival.updated ? rival : item
            let renamed = reidentify(older)
            kept[index] = newer
            slot[renamed.id] = kept.count
            kept.append(renamed)
            log.error("duplicate id, re-identified \(renamed.fileURL?.lastPathComponent ?? "?", privacy: .public)")
        }
        return kept
    }

    /// A file's identity, for comparing one path with another.
    ///
    /// Not the `URL` itself. A URL built by appending to a folder and one handed
    /// back by `FileManager` can name the very same file and still compare unequal.
    /// That mismatch is not cosmetic: `persistNote` writes the new file *before*
    /// unlinking the old one, so a raw `!=` there reported two spellings of one path
    /// as different and deleted the file it had just written. Paths compare on the
    /// one thing both forms agree about. See `StorageLayoutTests`.
    private func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func markdownFiles(in dir: URL) -> [URL] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        // Non-recursive, so `Tasks/Done` is simply not `.md` and drops out here —
        // each folder is listed in its own right or not at all.
        return urls.filter { $0.pathExtension.lowercased() == "md" }
    }

    // MARK: - Writing helpers

    /// Where the disk I/O happens — a serial queue, **not** the main thread.
    ///
    /// The three helpers below used to write synchronously from the main actor,
    /// which put an atomic write (temp file + rename) between every debounced
    /// save and the next frame — and the root defaults to `~/Documents`, where
    /// iCloud's "Desktop & Documents" sync can hold a rename for tens to
    /// hundreds of milliseconds, non-deterministically. That is a UI stall per
    /// keystroke pause on an ordinary Mac.
    ///
    /// Serial, so the order the main actor decided is the order the disk sees —
    /// `persistNote` writes the renamed file *before* unlinking the old one, and
    /// that ordering is what makes a failure lose nothing. Anything that reads
    /// the folders back (`reloadAll`, `moveRoot`) drains the queue first, and
    /// `AppDelegate.applicationWillTerminate` drains it so a quit can't outrun a
    /// pending save. `StorageLayoutTests` drains it before asserting on disk.
    private static let diskQueue = DispatchQueue(
        label: "com.alejandrolacasa.insert.disk", qos: .utility)

    /// Blocks until every queued write has landed. Cheap when the queue is idle.
    ///
    /// Deliberately still blocking: `AppDelegate.applicationWillTerminate` has no
    /// suspension to make, and a quit that outran a pending save would lose it.
    /// Anything with a main actor to give back wants `drainDiskWrites()`.
    func flushDiskWrites() {
        Self.diskQueue.sync {}
    }

    /// The same drain as a suspension. The queue is serial, so an empty block
    /// resumes only once everything already on it has landed.
    private func drainDiskWrites() async {
        await withCheckedContinuation { continuation in
            Self.diskQueue.async { continuation.resume() }
        }
    }

    private func suppressReload() {
        suppressReloadUntil = Date().addingTimeInterval(1.0)
    }

    private func write(_ string: String, to url: URL) {
        suppressReload()
        Self.diskQueue.async {
            do {
                try string.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                log.error("write failed \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func remove(_ url: URL?) {
        guard let url else { return }
        suppressReload()
        Self.diskQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Moves a file to Trash and verifies both sides of the move. The source is
    /// never unlinked as a fallback: a failed Trash operation must leave the only
    /// copy where it was.
    private func trash(
        _ url: URL?,
        using operation: @escaping TrashOperation
    ) async throws {
        guard let url else { throw TrashMoveError.missingFile }
        suppressReload()

        let result: Result<Void, TrashMoveError> = await withCheckedContinuation { continuation in
            Self.diskQueue.async {
                continuation.resume(returning: Self.performTrash(url, using: operation))
            }
        }
        if case .failure(let error) = result {
            log.error("trash failed \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        try result.get()
    }

    /// Best-effort cleanup for duplicate files found while loading. Unlike a
    /// user-requested deletion this has no index entry to settle afterward, but
    /// it follows the same no-fallback rule and leaves a failed source untouched.
    private func enqueueTrash(_ url: URL) {
        suppressReload()
        let operation = duplicateTrashOperation
        Self.diskQueue.async {
            if case .failure(let error) = Self.performTrash(url, using: operation) {
                log.error("trash failed \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    nonisolated private static func performTrash(
        _ source: URL,
        using operation: TrashOperation
    ) -> Result<Void, TrashMoveError> {
        do {
            let destination = try operation(source)
            let fm = FileManager.default
            guard !fm.fileExists(atPath: source.path),
                  fm.fileExists(atPath: destination.path)
            else { return .failure(.unconfirmed) }
            return .success(())
        } catch let error as TrashMoveError {
            return .failure(error)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    func clearDeletionFailure() {
        deletionFailure = nil
    }

    private func persistProjects() {
        write(MarkdownFiles.encodeProjects(projects), to: projectsFile)
    }

    /// Writes the note to disk, renaming its file if the slug changed.
    private func persistNote(_ note: inout Note) {
        if pendingDeletions.contains(.note(note.id)) {
            pendingNoteUpdates[note.id] = note
            return
        }
        let desired = notesDir.appendingPathComponent(MarkdownFiles.noteFilename(note))
        let existing = note.fileURL
        note.fileURL = desired
        write(MarkdownFiles.encode(note), to: desired)
        // Write first, then drop the old file: `write` is atomic, so a failure
        // leaves the previous copy rather than nothing at all.
        //
        // Compared by `key`, and it has to be. A note loaded from disk carries
        // `FileManager`'s URL while `desired` is built by construction, so raw
        // `!=` reports two spellings of *the same path* as different — and this
        // would then delete the file it had just written.
        if let existing, key(existing) != key(desired) { remove(existing) }
    }

    /// Writes the task to disk. Which folder it lands in follows its done state:
    /// pending in `Tasks/`, completed in `Tasks/Done/`, so ticking a task off moves
    /// its file. Organisational only — both folders are read in full.
    private func persistTask(_ task: inout TaskItem) {
        if pendingDeletions.contains(.task(task.id)) {
            pendingTaskUpdates[task.id] = task
            return
        }
        let directory = task.done ? tasksDoneDir : tasksDir
        let desired = directory.appendingPathComponent(MarkdownFiles.taskFilename(task))
        let existing = task.fileURL
        task.fileURL = desired
        write(MarkdownFiles.encode(task), to: desired)
        // By `key`, for the reason spelled out in `persistNote`.
        if let existing, key(existing) != key(desired) { remove(existing) }
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

    /// The palette entry fewest projects wear, walked in the **theme's** order so
    /// the choice is stable rather than random — and so a Kanagawa install's new
    /// projects keep orange for the button (`AppTheme.projectTintOrder`).
    ///
    /// Only this auto-assignment follows the theme. A colour the user picked is
    /// *data*, in `Projects.md`, and switching theme must never rewrite it.
    private func leastUsedTint() -> Tint {
        var counts: [Tint: Int] = [:]
        for project in projects { counts[project.tint, default: 0] += 1 }
        let order = SettingsStore.shared.theme.projectTintOrder
        return order.min { (counts[$0] ?? 0, order.firstIndex(of: $0)!)
                         < (counts[$1] ?? 0, order.firstIndex(of: $1)!) } ?? .blue
    }

    func updateProject(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
        persistProjects()
    }

    /// Bumps `lastUsed` to now. Recorded only: the sidebar's order is the manual
    /// one (see `moveProject(_:before:)`), so nothing sorts by this.
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
        // Deliberately no `touchProject` here: this runs on every ~0.4s save
        // debounce while typing, and bumping `lastUsed` — which nothing reads —
        // rewrote `Projects.md` once per assigned project per save and
        // invalidated every view of `projects` with it. Creation and selection
        // still record it.
    }

    func deleteNote(
        id: UUID,
        trashOperation: @escaping TrashOperation = Library.systemTrash
    ) async -> Bool {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return false }
        let key = DeletionKey.note(id)
        guard pendingDeletions.insert(key).inserted else { return false }

        let note = notes[idx]
        do {
            try await trash(note.fileURL, using: trashOperation)
            pendingDeletions.remove(key)
            pendingNoteUpdates.removeValue(forKey: id)
            notes.removeAll { $0.id == id }
            return true
        } catch {
            pendingDeletions.remove(key)
            if var update = pendingNoteUpdates.removeValue(forKey: id) {
                persistNote(&update)
                if let current = notes.firstIndex(where: { $0.id == id }) {
                    notes[current] = update
                }
            }
            let name = note.title.isEmpty ? "Untitled note" : note.title
            deletionFailure = DeletionFailure(
                message: "“\(name)” was not deleted. \(error.localizedDescription)"
            )
            return false
        }
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
        // No `touchProject`, for `updateNote`'s reason.
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

    func deleteTask(
        id: UUID,
        trashOperation: @escaping TrashOperation = Library.systemTrash
    ) async -> Bool {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return false }
        let key = DeletionKey.task(id)
        guard pendingDeletions.insert(key).inserted else { return false }

        let task = tasks[idx]
        do {
            try await trash(task.fileURL, using: trashOperation)
            pendingDeletions.remove(key)
            pendingTaskUpdates.removeValue(forKey: id)
            tasks.removeAll { $0.id == id }
            return true
        } catch {
            pendingDeletions.remove(key)
            if var update = pendingTaskUpdates.removeValue(forKey: id) {
                persistTask(&update)
                if let current = tasks.firstIndex(where: { $0.id == id }) {
                    tasks[current] = update
                }
            }
            let name = task.title.isEmpty ? "Untitled task" : task.title
            deletionFailure = DeletionFailure(
                message: "“\(name)” was not deleted. \(error.localizedDescription)"
            )
            return false
        }
    }

    // MARK: - Housekeeping

    /// Clears out tasks finished longer ago than `retention` allows.
    ///
    /// A done task with no `completed` stamp is **never** purged. This used to
    /// fall back to `updated`, which is an edit date and not a completion date:
    /// a note last touched a year ago and ticked off in Obsidian this morning
    /// was trashed on the first housekeeping run. Those tasks are stamped as
    /// they load instead (`stampUnstampedCompletion(at:)`), so they age from
    /// when Insert first saw them done, and this guard is what makes a task that
    /// somehow reaches the purge unstamped survive it.
    ///
    /// Files go to the Trash rather than being unlinked: this runs unattended,
    /// so the user has to be able to get their notes back if the setting turns
    /// out to be more aggressive than they meant.
    @discardableResult
    func purgeCompletedTasks(
        retention: DoneTaskRetention,
        now: Date = Date(),
        trashOperation: @escaping TrashOperation = Library.systemTrash
    ) async -> Int {
        guard let cutoff = retention.cutoff(from: now) else { return 0 }

        let expired = completedTasks(finishedBefore: cutoff)
        guard !expired.isEmpty else { return 0 }

        var trashed = 0
        var failed = 0
        for task in expired {
            let key = DeletionKey.task(task.id)
            guard pendingDeletions.insert(key).inserted else { continue }
            do {
                try await trash(task.fileURL, using: trashOperation)
                pendingTaskUpdates.removeValue(forKey: task.id)
                tasks.removeAll { $0.id == task.id }
                trashed += 1
            } catch {
                if var update = pendingTaskUpdates.removeValue(forKey: task.id) {
                    pendingDeletions.remove(key)
                    persistTask(&update)
                    if let current = tasks.firstIndex(where: { $0.id == task.id }) {
                        tasks[current] = update
                    }
                }
                failed += 1
            }
            pendingDeletions.remove(key)
        }

        if failed > 0 {
            let noun = failed == 1 ? "task was" : "tasks were"
            deletionFailure = DeletionFailure(
                message: "\(failed) completed \(noun) not removed because macOS could not confirm the move to Trash."
            )
        }
        log.info("purged \(trashed, privacy: .public) completed task(s) to the Trash")
        return trashed
    }

    /// How many tasks `purgeCompletedTasks` would remove right now — lets the
    /// Settings pane say what a choice costs before it's made.
    func completedTaskCount(expiredUnder retention: DoneTaskRetention, now: Date = Date()) -> Int {
        guard let cutoff = retention.cutoff(from: now) else { return 0 }
        return completedTasks(finishedBefore: cutoff).count
    }

    /// The one definition of "finished long enough ago to go", so what Settings
    /// promises and what the purge does can't disagree.
    private func completedTasks(finishedBefore cutoff: Date) -> [TaskItem] {
        tasks.filter { task in
            guard task.done, let completed = task.completed else { return false }
            return completed < cutoff
        }
    }

    // MARK: - Queries

    /// (notes, tasks) counts for a project. Exact: everything is loaded.
    ///
    /// One pass over both arrays for *every* project, cached, because the
    /// sidebar asks per row: two full scans per row, on every library mutation,
    /// meant a 400-note library walked 4,000 records per debounced save with
    /// five projects listed — and the debounce fires while someone types.
    ///
    /// Both arrays are read on the way through whether the table is fresh or
    /// not, so a row registers exactly the `@Observable` dependency the two
    /// scans it replaces did and still re-renders when either changes. Reading
    /// them is a retain, not a copy. The table itself is `@ObservationIgnored`
    /// and would register nothing, which is why the reads are not inside the
    /// rebuild.
    func counts(forProject id: UUID) -> (notes: Int, tasks: Int) {
        let notes = self.notes, tasks = self.tasks
        let table = cachedProjectCounts ?? Self.projectCounts(notes: notes, tasks: tasks)
        cachedProjectCounts = table
        return table[id] ?? (0, 0)
    }

    private nonisolated static func projectCounts(
        notes: [Note], tasks: [TaskItem]
    ) -> [UUID: (notes: Int, tasks: Int)] {
        var table: [UUID: (notes: Int, tasks: Int)] = [:]
        // A record is counted once per project however many times it lists it.
        // Nothing in the app assigns a project twice, but a hand-edited
        // frontmatter can, and the `contains` this replaces counted such a
        // record once.
        for note in notes {
            var counted: Set<UUID> = []
            for id in note.projectIDs where counted.insert(id).inserted {
                table[id, default: (0, 0)].notes += 1
            }
        }
        for task in tasks {
            var counted: Set<UUID> = []
            for id in task.projectIDs where counted.insert(id).inserted {
                table[id, default: (0, 0)].tasks += 1
            }
        }
        return table
    }

    /// Case- and diacritic-insensitive substring match — the one rule all three
    /// columns and the toolbar field search by.
    ///
    /// `range(of:options:)` compares in place, where the `lowercased()` this
    /// replaces built a fresh copy of every record's title *and* body on every
    /// keystroke, for every column. Diacritic insensitivity comes along with it
    /// and is a gain rather than a cost: "navegacion" finds "navegación".
    ///
    /// No locale is passed and none is read. Both options are locale-independent,
    /// which is what keeps this clear of the `Locale.current` rule — see
    /// `Formatting`.
    private static let searchOptions: String.CompareOptions =
        [.caseInsensitive, .diacriticInsensitive]

    private func matches(_ query: String, in text: String) -> Bool {
        text.range(of: query, options: Self.searchOptions) != nil
    }

    /// Notes for a project (`nil` = all), sorted and filtered. `pinned` holds the
    /// sort position of notes being edited steady — see `NotePins`.
    func notes(
        forProject projectID: UUID?,
        sort: NoteSort,
        typeFilter: String?,
        search: String,
        pinned: NotePins = NotePins()
    ) -> [Note] {
        var result = notes
        if let projectID { result = result.filter { $0.projectIDs.contains(projectID) } }
        if let typeFilter { result = result.filter { $0.typeID == typeFilter } }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { matches(query, in: $0.title) || matches(query, in: $0.body) }
        }
        return result.sorted { sortNotes($0, $1, by: sort, pinned: pinned) }
    }

    private func sortNotes(_ a: Note, _ b: Note, by sort: NoteSort, pinned: NotePins) -> Bool {
        switch sort {
        case .createdDesc: a.created > b.created
        case .createdAsc: a.created < b.created
        case .updatedDesc: pinned.key(for: a) > pinned.key(for: b)
        case .updatedAsc: pinned.key(for: a) < pinned.key(for: b)
        }
    }

    /// Tasks for a project (`nil` = all), filtered by state + search.
    /// Tasks for a project (`nil` = all), filtered and sorted. `pinned` holds the
    /// place of rows whose due date or done state changed while you were looking
    /// at them — see `TaskPins`. `now` is the day the date window is measured
    /// against; the column passes `DayClock`'s, so a "Today" list is still today's
    /// after midnight rather than yesterday's.
    func tasks(
        forProject projectID: UUID?,
        filter: TaskFilter,
        dateFilter: TaskDateFilter? = nil,
        search: String,
        pinned: TaskPins = TaskPins(),
        now: Date = Date()
    ) -> [TaskItem] {
        var result = tasks
        if let projectID { result = result.filter { $0.projectIDs.contains(projectID) } }
        result = result.filter { task in
            filter.matches(task) && (dateFilter?.matches(task, now: now) ?? true)
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { matches(query, in: $0.title) || matches(query, in: $0.body) }
        }
        // Pending first, then by due date (soonest, undated last), then newest.
        // The filtering above reads the *live* `done`; only the order below is
        // pinned. See `TaskPins`.
        return result.sorted { taskOrder($0, pinned: pinned) < taskOrder($1, pinned: pinned) }
    }

    private func taskOrder(_ t: TaskItem, pinned: TaskPins) -> (Int, TimeInterval, TimeInterval) {
        let key = pinned.key(for: t)
        let donePenalty = key.done ? 1 : 0
        let dueKey = key.due?.timeIntervalSince1970 ?? Date.distantFuture.timeIntervalSince1970
        return (donePenalty, dueKey, -t.created.timeIntervalSince1970)
    }

    /// Reorders projects (drag-and-drop in the sidebar): `id` moves into the gap
    /// immediately *before* `beforeID`, or to the end of the list when that is nil.
    /// The array order is the canonical order and is persisted straight to
    /// `Projects.md`, whose line order it is.
    ///
    /// Ids rather than offsets, because what the sidebar has to hand are two rows —
    /// the one being dragged and the one it was dropped on — and a filtered list
    /// makes a visible offset a different number from the one this array wants.
    /// Translating a pair of rows into `move(fromOffsets:toOffset:)` also keeps
    /// that API's off-by-one (a destination past the source counts the source
    /// itself, so "stay put" is `from + 1`, not `from`) in one place.
    ///
    /// Returns whether anything moved, so a drop that changes nothing can be
    /// reported as refused rather than as a write.
    @discardableResult
    func moveProject(_ id: UUID, before beforeID: UUID?) -> Bool {
        guard let from = projects.firstIndex(where: { $0.id == id }) else { return false }
        let destination: Int
        if let beforeID {
            guard let target = projects.firstIndex(where: { $0.id == beforeID }) else { return false }
            destination = target
        } else {
            destination = projects.count
        }
        // Onto itself, or into the gap it already fills.
        guard destination != from, destination != from + 1 else { return false }
        projects.move(fromOffsets: IndexSet(integer: from), toOffset: destination)
        persistProjects()
        return true
    }

    // MARK: - Global search

    struct SearchResults {
        var projects: [Project]
        var notes: [Note]
        var tasks: [TaskItem]
        var isEmpty: Bool { projects.isEmpty && notes.isEmpty && tasks.isEmpty }
    }

    func search(_ query: String) -> SearchResults {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return SearchResults(projects: [], notes: [], tasks: []) }
        return SearchResults(
            projects: projects.filter { matches(q, in: $0.name) },
            notes: notes.filter { matches(q, in: $0.title) || matches(q, in: $0.body) },
            tasks: tasks.filter { matches(q, in: $0.title) || matches(q, in: $0.body) }
        )
    }

    // MARK: - Watching

    private func startWatching() {
        watcher = DirectoryWatcher(urls: [notesDir, tasksDir, tasksDoneDir, rootURL]) { [weak self] in
            guard let self else { return }
            if Date() < self.suppressReloadUntil { return }
            Task { await self.reloadAll() }
        }
    }
}
