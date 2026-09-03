import Foundation
import Observation
import XCTest
@testable import Insert

/// Drives the real `Library` against a throwaway root, covering the parts of the
/// storage layout that move the user's Markdown files about: filing tasks under
/// `Tasks/Done/`, migrating a library written before that folder existed, writes
/// that must not lose a file, and the retention purge.
///
/// One long test rather than a dozen small ones, on purpose. `Library` is a
/// singleton with a good deal of on-disk state, and these steps are a *sequence* —
/// a task can only be reopened after it has been ticked off. Splitting it up would
/// mean rebuilding the fixture per case.
///
/// It reports every check rather than stopping at the first failure, because when a
/// change to the loading rules breaks one expectation it usually breaks several, and
/// the pattern is what tells you which rule moved.
final class StorageLayoutTests: XCTestCase {

    @MainActor
    func testFolderLayoutAndWrites() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-storage-\(UUID().uuidString)", isDirectory: true)
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        let tasks = root.appendingPathComponent("Tasks", isDirectory: true)
        let trashBin = root.appendingPathComponent("Test Trash", isDirectory: true)
        for dir in [notes, tasks, trashBin] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }
        let moveToTestTrash: Library.TrashOperation = { source in
            let destination = trashBin.appendingPathComponent(
                "\(UUID().uuidString)-\(source.lastPathComponent)"
            )
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }

        let cal = Calendar.current
        let now = Date()
        func ago(_ days: Int) -> Date { cal.date(byAdding: .day, value: -days, to: now)! }

        var failures: [String] = []
        func check<T: Equatable>(_ label: String, _ actual: T, _ expected: T) {
            let ok = actual == expected
            print("\(ok ? "ok  " : "FAIL") \(label): \(actual)\(ok ? "" : " (expected \(expected))")")
            if !ok { failures.append(label) }
        }
        func mdCount(_ dir: URL) -> Int {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "md" }.count
        }

        // MARK: Fixture — a library in the old flat layout

        let projectA = UUID(), projectB = UUID()
        try MarkdownFiles.encodeProjects([
            Project(id: projectA, name: "Alpha"),
            Project(id: projectB, name: "Beta"),
        ]).write(to: root.appendingPathComponent("Projects.md"), atomically: true, encoding: .utf8)

        // Enough notes to cross `decoded`'s parallel threshold, so the concurrent
        // path is what these assertions actually exercise. Half are Beta's, and
        // ages run from today back over a year — neither of which affects what
        // loads any more, which is the point.
        for i in 0..<400 {
            let note = Note(
                title: "Note \(i)",
                projectIDs: [i >= 200 ? projectB : projectA],
                body: "body \(i)",
                created: ago(i), updated: ago(i)
            )
            try MarkdownFiles.encode(note).write(
                to: notes.appendingPathComponent(MarkdownFiles.noteFilename(note)),
                atomically: true, encoding: .utf8)
        }

        // 40 tasks flat in `Tasks/`, done and pending mixed as a library written
        // before `Tasks/Done/` would have them: 10 pending, 10 finished recently,
        // 20 finished long ago.
        for i in 0..<40 {
            let done = i < 30
            let when = ago(done ? (i < 10 ? 3 : 100 + i * 10) : i)
            let task = TaskItem(
                title: "Task \(i)", done: done, completed: done ? when : nil,
                projectIDs: [projectA], created: when, updated: when
            )
            try MarkdownFiles.encode(task).write(
                to: tasks.appendingPathComponent(MarkdownFiles.taskFilename(task)),
                atomically: true, encoding: .utf8)
        }

        // Point the singleton at an empty folder before it is first touched, so its
        // own `init` can't read the real library. `setRoot` is then the only load.
        UserDefaults.standard.set(true, forKey: "didSeed")
        UserDefaults.standard.set(
            root.appendingPathComponent("unused", isDirectory: true).path,
            forKey: "rootFolderPath"
        )
        let library = Library.shared
        library.setRoot(root)

        // MARK: Everything loads, and the done folder gets populated

        print("\n— first launch on a legacy flat layout —")
        check("notes loaded", library.notes.count, 400)
        check("tasks loaded", library.tasks.count, 40)
        check("Beta's notes loaded",
              library.notes.filter { $0.projectIDs.contains(projectB) }.count, 200)
        check("no duplicate note ids", Set(library.notes.map(\.id)).count, 400)
        // The load sweep files every done task under `Tasks/Done/`.
        check("Tasks/ on disk", mdCount(tasks), 10)
        check("Tasks/Done/ on disk", mdCount(library.tasksDoneDir), 30)

        print("\n— a reload finds the same thing, from the new layout —")
        await library.reloadAll()
        check("notes loaded", library.notes.count, 400)
        check("tasks loaded", library.tasks.count, 40)
        check("done tasks loaded", library.tasks.filter(\.done).count, 30)

        // MARK: Writing

        print("\n— an in-place edit keeps its file —")
        // The title is untouched, so the filename doesn't change: `persistNote` has
        // to recognize the old and new URLs as one file and leave it alone.
        // Comparing the URLs rather than their paths deleted the copy it had just
        // written — the two spellings of one path aren't `==`.
        let resident = library.notes[0]
        var touched = resident
        touched.body = "edited in place"
        library.updateNote(touched)
        // Writes land on a serial background queue; drain it before reading the
        // disk back. Same at every disk assertion below.
        library.flushDiskWrites()
        let after = library.notes.first { $0.id == resident.id }!
        check("file still there", fm.fileExists(atPath: after.fileURL!.path), true)
        check("and holds the edit",
              (try? String(contentsOf: after.fileURL!, encoding: .utf8))?
                .contains("edited in place") ?? false, true)
        check("no file lost", mdCount(notes), 400)

        print("\n— a retitle renames the file and leaves no orphan —")
        var renamed = library.notes[1]
        let oldURL = renamed.fileURL!
        renamed.title = "A completely different title"
        library.updateNote(renamed)
        library.flushDiskWrites()
        let moved = library.notes.first { $0.id == renamed.id }!
        check("new filename", moved.fileURL!.lastPathComponent.hasPrefix("a-completely"), true)
        check("old file gone", fm.fileExists(atPath: oldURL.path), false)
        check("still no file lost", mdCount(notes), 400)

        print("\n— toggling done moves the file —")
        let pending = library.tasks.first { !$0.done }!
        library.toggleTask(id: pending.id)
        library.flushDiskWrites()
        let ticked = library.tasks.first { $0.id == pending.id }!
        check("now under Done/",
              ticked.fileURL!.deletingLastPathComponent().lastPathComponent, "Done")
        check("pending copy gone", fm.fileExists(atPath: pending.fileURL!.path), false)
        library.toggleTask(id: pending.id)
        check("reopened, back under Tasks/",
              library.tasks.first { $0.id == pending.id }!.fileURL!
                .deletingLastPathComponent().lastPathComponent, "Tasks")

        // MARK: Housekeeping and project deletion

        print("\n— the retention purge —")
        library.setRoot(root)
        check(
            "purged",
            await library.purgeCompletedTasks(
                retention: .month,
                now: now,
                trashOperation: moveToTestTrash
            ),
            20
        )
        library.flushDiskWrites()
        check("Tasks/Done/ on disk", mdCount(library.tasksDoneDir), 10)
        check("tasks left in memory", library.tasks.count, 20)

        print("\n— manual deletion is confirmed at the Trash destination —")
        let disposableNote = library.addNote(title: "Disposable note")
        let noteSource = disposableNote.fileURL!
        library.flushDiskWrites()
        let trashCountBeforeNote = mdCount(trashBin)
        let noteDeleted = await library.deleteNote(
            id: disposableNote.id,
            trashOperation: moveToTestTrash
        )
        check("note deletion confirmed", noteDeleted, true)
        check("deleted note left the index",
              library.notes.contains { $0.id == disposableNote.id }, false)
        check("deleted note left its source", fm.fileExists(atPath: noteSource.path), false)
        check("deleted note reached Trash", mdCount(trashBin), trashCountBeforeNote + 1)

        let disposableTask = library.addTask(title: "Disposable task")
        let taskSource = disposableTask.fileURL!
        library.flushDiskWrites()
        let trashCountBeforeTask = mdCount(trashBin)
        let taskDeleted = await library.deleteTask(
            id: disposableTask.id,
            trashOperation: moveToTestTrash
        )
        check("task deletion confirmed", taskDeleted, true)
        check("deleted task left the index",
              library.tasks.contains { $0.id == disposableTask.id }, false)
        check("deleted task left its source", fm.fileExists(atPath: taskSource.path), false)
        check("deleted task reached Trash", mdCount(trashBin), trashCountBeforeTask + 1)

        print("\n— a failed Trash move keeps the record and file —")
        let retained = library.addNote(title: "Must stay")
        let retainedSource = retained.fileURL!
        library.flushDiskWrites()
        let refuseTrash: Library.TrashOperation = { _ in
            throw NSError(
                domain: "StorageLayoutTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Test refusal"]
            )
        }
        let refused = await library.deleteNote(
            id: retained.id,
            trashOperation: refuseTrash
        )
        check("failed deletion was refused", refused, false)
        check("failed note stayed in the index",
              library.notes.contains { $0.id == retained.id }, true)
        check("failed note stayed on disk", fm.fileExists(atPath: retainedSource.path), true)
        check("failed delete was surfaced", library.deletionFailure != nil, true)
        library.clearDeletionFailure()
        _ = await library.deleteNote(id: retained.id, trashOperation: moveToTestTrash)

        print("\n— deleting a project unassigns it everywhere —")
        library.setRoot(root)
        library.deleteProject(id: projectB)
        library.flushDiskWrites()
        check("no note still holds Beta",
              library.notes.contains { $0.projectIDs.contains(projectB) }, false)
        // And on disk, not merely in the index.
        let onDiskStillAssigned = ((try? fm.contentsOfDirectory(
            at: notes, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> Note? in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return MarkdownFiles.decodeNote(from: text, url: url)
            }
            .filter { $0.projectIDs.contains(projectB) }
        check("nor does any file", onDiskStillAssigned.count, 0)
        check("the notes themselves are kept", library.notes.count, 400)

        print("\n\(failures.isEmpty ? "ALL PASS" : "FAILURES: \(failures)")")
        XCTAssertEqual(failures, [])
    }

    /// `decoded` splits its work across the cores and collects it into pre-assigned
    /// slots. Both halves of that need checking: nothing dropped, and the order the
    /// same every run — `deduped` breaks ties between two files claiming one id by
    /// position, and a tie-break that varied run to run would be a horrible bug.
    @MainActor
    func testParallelLoadIsCompleteAndOrdered() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-parallel-\(UUID().uuidString)", isDirectory: true)
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        try fm.createDirectory(at: notes, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Deliberately not a multiple of the core count, so the last chunk is short.
        for i in 0..<1_001 {
            let note = Note(title: "Note \(i)", body: "body \(i)")
            try MarkdownFiles.encode(note).write(
                to: notes.appendingPathComponent(MarkdownFiles.noteFilename(note)),
                atomically: true, encoding: .utf8)
        }

        UserDefaults.standard.set(true, forKey: "didSeed")
        let library = Library.shared
        library.setRoot(root)
        XCTAssertEqual(library.notes.count, 1_001)

        let order = library.notes.map(\.id)
        for _ in 0..<5 {
            await library.reloadAll()
            XCTAssertEqual(library.notes.count, 1_001, "a chunk went missing")
            XCTAssertEqual(library.notes.map(\.id), order, "load order is not stable")
        }
    }

    /// `NotePins` keeps the note you're typing in where it is under an Updated
    /// sort, and gives it up when the pins are dropped — the two halves of what
    /// stops a card sliding out from under the cursor mid-sentence.
    @MainActor
    func testEditingPinsHoldNotesPlacesUnderUpdatedSort() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-pin-\(UUID().uuidString)", isDirectory: true)
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        try fm.createDirectory(at: notes, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Three notes an hour apart, so "Second" is the one in the middle — the
        // 2nd/3rd place the bug was reported from.
        let now = Date()
        let titles = ["First", "Second", "Third"]
        for (i, title) in titles.enumerated() {
            let stamp = now.addingTimeInterval(TimeInterval(-3_600 * i))
            let note = Note(title: title, created: stamp, updated: stamp)
            try MarkdownFiles.encode(note).write(
                to: notes.appendingPathComponent(MarkdownFiles.noteFilename(note)),
                atomically: true, encoding: .utf8)
        }

        UserDefaults.standard.set(true, forKey: "didSeed")
        let library = Library.shared
        library.setRoot(root)

        func order(pinned: NotePins = NotePins()) -> [String] {
            library.notes(
                forProject: nil, sort: .updatedDesc, typeFilter: nil, search: "", pinned: pinned
            ).map(\.title)
        }

        XCTAssertEqual(order(), titles)

        // Opening "Second" for editing pins it where it is.
        var second = try XCTUnwrap(library.notes.first { $0.title == "Second" })
        var pins = NotePins()
        pins.pin(second)

        // A debounced save while it's open: `updated` jumps to now.
        second.body = "typing"
        library.updateNote(second)
        XCTAssertEqual(order(pinned: pins), titles, "the pinned note moved while being edited")

        // Closing the card doesn't drop the pin, and neither does editing it again
        // in the same view — a second `pin(_:)` must not re-pin it at the newer
        // timestamp, which would put it back at the top.
        second = try XCTUnwrap(library.notes.first { $0.id == second.id })
        second.body = "typing more"
        library.updateNote(second)
        pins.pin(second)
        XCTAssertEqual(order(pinned: pins), titles, "a re-pin moved the note")

        // Another note edited in the same view is held too, rather than displacing
        // the first one.
        var third = try XCTUnwrap(library.notes.first { $0.title == "Third" })
        pins.pin(third)
        third.body = "typing"
        library.updateNote(third)
        XCTAssertEqual(order(pinned: pins), titles, "the second pinned note moved")

        // Changing project / filter / search / sort drops the pins, and the list
        // re-sorts on the frame it was being rebuilt on anyway.
        XCTAssertEqual(order(), ["Third", "Second", "First"])
    }

    /// `TaskPins` is the same guarantee over the tasks column's sort key, where
    /// *both* mutable halves — the due date and the done flag — are things a row
    /// changes about itself. The due date is the one that was reported: it is the
    /// list's main key, and the popover that sets it dismisses on the same click,
    /// so the row left at the instant the popover did.
    @MainActor
    func testDueAndDonePinsHoldTasksPlaces() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-taskpin-\(UUID().uuidString)", isDirectory: true)
        let tasks = root.appendingPathComponent("Tasks", isDirectory: true)
        try fm.createDirectory(at: tasks, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Three pending, undated tasks an hour apart. Undated sorts last and by
        // newest-created, so "First" leads and "Third" trails.
        let now = Date()
        let titles = ["First", "Second", "Third"]
        for (i, title) in titles.enumerated() {
            let stamp = now.addingTimeInterval(TimeInterval(-3_600 * i))
            let task = TaskItem(title: title, created: stamp, updated: stamp)
            try MarkdownFiles.encode(task).write(
                to: tasks.appendingPathComponent(MarkdownFiles.taskFilename(task)),
                atomically: true, encoding: .utf8)
        }

        UserDefaults.standard.set(true, forKey: "didSeed")
        let library = Library.shared
        library.setRoot(root)

        func order(filter: TaskFilter = .all, pinned: TaskPins = TaskPins()) -> [String] {
            library.tasks(forProject: nil, filter: filter, search: "", pinned: pinned)
                .map(\.title)
        }

        XCTAssertEqual(order(), titles)

        // Dating the last task would send it to the front. Pinned first, it stays
        // where it is being looked at.
        let today = Calendar.current.startOfDay(for: now)
        var third = try XCTUnwrap(library.tasks.first { $0.title == "Third" })
        var pins = TaskPins()
        pins.pin(third)
        third.due = today
        library.updateTask(third)
        XCTAssertEqual(order(pinned: pins), titles, "the pinned task moved when it was dated")

        // Changing the date again in the same view must not re-pin it at the place
        // the first change would have given it.
        third = try XCTUnwrap(library.tasks.first { $0.id == third.id })
        third.due = Calendar.current.date(byAdding: .day, value: -1, to: today)
        library.updateTask(third)
        pins.pin(third)
        XCTAssertEqual(order(pinned: pins), titles, "a re-pin moved the task")

        // Ticking a task is the other half of the key, and is held the same way.
        var second = try XCTUnwrap(library.tasks.first { $0.title == "Second" })
        pins.pin(second)
        second.done = true
        library.updateTask(second)
        XCTAssertEqual(order(pinned: pins), titles, "the ticked task moved")

        // The *filter* is never pinned: a task you tick leaves the Pending view,
        // because it is no longer one of the things that view is showing — while the
        // rows that stay keep their held order.
        XCTAssertEqual(order(filter: .pending, pinned: pins), ["First", "Third"])

        // Dropping the pins re-sorts on the frame the list is rebuilt on: the dated
        // task leads, the done one sinks.
        XCTAssertEqual(order(), ["Third", "First", "Second"])
    }

    /// The tasks column measures its date window against `DayClock`'s day rather
    /// than `Date()`, so a "Today" list is still today's after midnight instead of
    /// yesterday's. That only holds if `tasks(…)` hands `now` on to the filter, and
    /// the parameter has a default — so dropping it compiles, changes nothing on a
    /// machine that never crosses midnight with the app open, and silently puts the
    /// bug back. Hence a test rather than trust.
    @MainActor
    func testTaskDateWindowFollowsTheDayItIsGiven() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-dayclock-\(UUID().uuidString)", isDirectory: true)
        let tasks = root.appendingPathComponent("Tasks", isDirectory: true)
        try fm.createDirectory(at: tasks, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!

        for (title, due) in [("Today's", today), ("Tomorrow's", tomorrow)] {
            let task = TaskItem(title: title, due: due)
            try MarkdownFiles.encode(task).write(
                to: tasks.appendingPathComponent(MarkdownFiles.taskFilename(task)),
                atomically: true, encoding: .utf8)
        }

        UserDefaults.standard.set(true, forKey: "didSeed")
        let library = Library.shared
        library.setRoot(root)

        func titles(dueIn window: TaskDateFilter, on day: Date) -> [String] {
            library.tasks(forProject: nil, filter: .all, dateFilter: window,
                          search: "", now: day)
                .map(\.title)
        }

        XCTAssertEqual(titles(dueIn: .today, on: today), ["Today's"])
        XCTAssertEqual(titles(dueIn: .tomorrow, on: today), ["Tomorrow's"])

        // Midnight: the same two tasks, one day later. Everything moves up a window.
        XCTAssertEqual(titles(dueIn: .today, on: tomorrow), ["Tomorrow's"])
        XCTAssertEqual(titles(dueIn: .overdue, on: tomorrow), ["Today's"])
        XCTAssertEqual(titles(dueIn: .tomorrow, on: tomorrow), [])
    }

    /// The projects sidebar is ordered by hand, and `Projects.md`'s line order *is*
    /// that order — so a drag has to come back the same after a reload. This also
    /// pins the two ends of `moveProject`'s insert-*before* rule, which is where a
    /// reorder gets its off-by-one: dropping a project into the gap it already fills
    /// must change nothing, and "before nobody" means last.
    @MainActor
    func testProjectsReorderByDragAndPersist() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-order-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let ids = (0..<4).map { _ in UUID() }
        let names = ["Alpha", "Beta", "Gamma", "Delta"]
        try MarkdownFiles.encodeProjects(zip(ids, names).map { Project(id: $0, name: $1) })
            .write(to: root.appendingPathComponent("Projects.md"), atomically: true, encoding: .utf8)

        UserDefaults.standard.set(true, forKey: "didSeed")
        let library = Library.shared
        library.setRoot(root)
        func order() -> [String] { library.projects.map(\.name) }
        XCTAssertEqual(order(), names, "the file's line order is not the list's order")

        // Gamma dragged onto Alpha's row: it takes the gap above it.
        XCTAssertTrue(library.moveProject(ids[2], before: ids[0]))
        XCTAssertEqual(order(), ["Gamma", "Alpha", "Beta", "Delta"])

        // Dropped past the last row, which is the only way to reach the end.
        XCTAssertTrue(library.moveProject(ids[2], before: nil))
        XCTAssertEqual(order(), ["Alpha", "Beta", "Delta", "Gamma"])

        // The no-ops, both of which must be refused rather than written: a project
        // dropped on itself, and one dropped into the gap it is already in — the
        // row *below* it, since a gap is named by the row under it.
        XCTAssertFalse(library.moveProject(ids[0], before: ids[0]))
        XCTAssertFalse(library.moveProject(ids[0], before: ids[1]))
        XCTAssertFalse(library.moveProject(ids[2], before: nil), "the last project moved to last")
        XCTAssertEqual(order(), ["Alpha", "Beta", "Delta", "Gamma"])

        // And the whole thing survives a round trip through the Markdown.
        await library.reloadAll()
        XCTAssertEqual(order(), ["Alpha", "Beta", "Delta", "Gamma"], "the order did not persist")
    }
    // MARK: Completion stamps

    /// A task ticked off in Obsidian arrives done with no `completed` stamp, and
    /// the retention purge used to age one on `updated` — an edit date, not a
    /// completion date — so a task last edited a year ago and finished this
    /// morning was trashed on the first housekeeping run. The load stamps it
    /// instead, and both halves of that are pinned here: the stamp is written, to
    /// the index and to the file, and the task then ages from the day Insert saw
    /// it rather than the day it was last edited.
    ///
    /// The purge's own refusal to age an unstamped task is a second line of
    /// defence and is deliberately not reached from here: with the load stamping
    /// every done task, nothing that goes through `Library` can leave an unstamped
    /// one in the index for the purge to see. What this pins is what a user gets.
    @MainActor
    func testAnExternallyTickedTaskIsStampedOnLoadAndSurvivesRetention() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-stamp-\(UUID().uuidString)", isDirectory: true)
        let tasks = root.appendingPathComponent("Tasks", isDirectory: true)
        let trashBin = root.appendingPathComponent("Test Trash", isDirectory: true)
        for dir in [tasks, trashBin] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }
        let moveToTestTrash: Library.TrashOperation = { source in
            let destination = trashBin.appendingPathComponent(
                "\(UUID().uuidString)-\(source.lastPathComponent)"
            )
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }

        let cal = Calendar.current
        let now = Date()
        let lastYear = cal.date(byAdding: .day, value: -400, to: now)!

        // Ticked off outside Insert: done, no stamp, and an edit date old enough
        // that the `updated` fallback would have taken it on sight.
        let unstamped = TaskItem(
            title: "Ticked in Obsidian", done: true, completed: nil,
            created: lastYear, updated: lastYear
        )
        // And one Insert finished itself, long enough ago to really go.
        let expired = TaskItem(
            title: "Finished last year", done: true, completed: lastYear,
            created: lastYear, updated: lastYear
        )
        for task in [unstamped, expired] {
            try MarkdownFiles.encode(task).write(
                to: tasks.appendingPathComponent(MarkdownFiles.taskFilename(task)),
                atomically: true, encoding: .utf8)
        }

        UserDefaults.standard.set(true, forKey: "didSeed")
        // Point the singleton at an empty folder before it is first touched — this
        // test can be the one that creates it — so its `init` can neither read nor
        // write the real library. See `testFolderLayoutAndWrites`.
        UserDefaults.standard.set(
            root.appendingPathComponent("unused", isDirectory: true).path,
            forKey: "rootFolderPath"
        )
        let library = Library.shared
        library.setRoot(root)

        let loaded = try XCTUnwrap(library.tasks.first { $0.id == unstamped.id })
        let stamp = try XCTUnwrap(loaded.completed, "the load left a ticked task unstamped")
        XCTAssertTrue(cal.isDate(stamp, inSameDayAs: now),
                      "the stamp is not the day Insert first saw the task done")
        XCTAssertEqual(loaded.updated.timeIntervalSince1970,
                       lastYear.timeIntervalSince1970, accuracy: 1,
                       "stamping a completion is not an edit")

        // On disk too, or every launch stamps it afresh and it never ages.
        library.flushDiskWrites()
        let file = try XCTUnwrap(loaded.fileURL)
        let text = try String(contentsOf: file, encoding: .utf8)
        let onDisk = try XCTUnwrap(MarkdownFiles.decodeTask(from: text, url: file))
        XCTAssertNotNil(onDisk.completed, "the stamp was not written back")

        let purged = await library.purgeCompletedTasks(
            retention: .month, now: now, trashOperation: moveToTestTrash)
        XCTAssertEqual(purged, 1, "the purge took something other than the one old task")
        XCTAssertTrue(library.tasks.contains { $0.id == unstamped.id },
                      "a task ticked off outside Insert was purged on its edit date")

        // It does expire — a month after the day it was seen, not a month after
        // the year-old edit.
        let twoMonthsOn = cal.date(byAdding: .day, value: 60, to: now)!
        let later = await library.purgeCompletedTasks(
            retention: .month, now: twoMonthsOn, trashOperation: moveToTestTrash)
        XCTAssertEqual(later, 1, "the stamped task never expires")
        XCTAssertFalse(library.tasks.contains { $0.id == unstamped.id })
    }

    // MARK: Two files, one id

    /// Two files under one id with the same `updated` are two pieces of writing,
    /// not a duplicate. The loser of the tie used to be trashed on directory
    /// order, which is how a Finder copy whose frontmatter was untouched but whose
    /// body carried the writing was lost — so both files stay now, and the one
    /// that gives up the id is saved under a fresh one.
    @MainActor
    func testAnUpdatedTieKeepsBothFilesUnderDistinctIDs() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-tie-\(UUID().uuidString)", isDirectory: true)
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        let trashBin = root.appendingPathComponent("Test Trash", isDirectory: true)
        for dir in [notes, trashBin] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }
        func mdCount(_ dir: URL) -> Int {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "md" }.count
        }

        let shared = UUID()
        let stamp = Date()
        let original = Note(id: shared, title: "Original", body: "the original",
                            created: stamp, updated: stamp)
        let duplicate = Note(id: shared, title: "Original copy",
                             body: "the copy, carrying the writing",
                             created: stamp, updated: stamp)
        for note in [original, duplicate] {
            try MarkdownFiles.encode(note).write(
                to: notes.appendingPathComponent(MarkdownFiles.noteFilename(note)),
                atomically: true, encoding: .utf8)
        }

        UserDefaults.standard.set(true, forKey: "didSeed")
        // Point the singleton at an empty folder before it is first touched — this
        // test can be the one that creates it — so its `init` can neither read nor
        // write the real library. See `testFolderLayoutAndWrites`.
        UserDefaults.standard.set(
            root.appendingPathComponent("unused", isDirectory: true).path,
            forKey: "rootFolderPath"
        )
        let library = Library.shared
        // A duplicate found while loading has no caller to hand a trash operation
        // to, so the singleton's own is what points at the test bin.
        library.duplicateTrashOperation = { source in
            let destination = trashBin.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        library.setRoot(root)
        library.flushDiskWrites()

        XCTAssertEqual(library.notes.count, 2, "one of the two notes was dropped")
        XCTAssertEqual(Set(library.notes.map(\.id)).count, 2, "the two notes still share an id")
        XCTAssertEqual(library.notes.filter { $0.id == shared }.count, 1,
                       "the id should be kept by exactly one of them")
        XCTAssertEqual(Set(library.notes.map(\.body)),
                       ["the original", "the copy, carrying the writing"],
                       "a body was lost")
        XCTAssertEqual(mdCount(notes), 2, "a file went missing")
        XCTAssertEqual(mdCount(trashBin), 0, "nothing here is a true duplicate")
        for note in library.notes {
            XCTAssertTrue(fm.fileExists(atPath: try XCTUnwrap(note.fileURL).path),
                          "a note's file is not where the index says")
        }

        // The re-identification is a one-off: the second load finds no duplicate,
        // so nothing is re-identified again and no id moves under the UI.
        let ids = Set(library.notes.map(\.id))
        await library.reloadAll()
        library.flushDiskWrites()
        XCTAssertEqual(Set(library.notes.map(\.id)), ids, "a note was re-identified twice")
        XCTAssertEqual(mdCount(notes), 2)
    }

    /// A file that encodes to the same string as one already loaded is a true
    /// duplicate — same id, same `updated`, same content — so there is no writing
    /// in it to save and it still goes to the Trash rather than being kept under
    /// a second id.
    @MainActor
    func testATrueDuplicateIsStillTrashed() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-dupe-\(UUID().uuidString)", isDirectory: true)
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        let trashBin = root.appendingPathComponent("Test Trash", isDirectory: true)
        for dir in [notes, trashBin] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }
        func mdCount(_ dir: URL) -> Int {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "md" }.count
        }

        // A Finder duplicate: one byte-identical file under a second name.
        let note = Note(title: "Meeting notes", body: "one copy of this")
        let encoded = MarkdownFiles.encode(note)
        try encoded.write(to: notes.appendingPathComponent(MarkdownFiles.noteFilename(note)),
                          atomically: true, encoding: .utf8)
        try encoded.write(to: notes.appendingPathComponent("meeting-notes copy.md"),
                          atomically: true, encoding: .utf8)

        UserDefaults.standard.set(true, forKey: "didSeed")
        // Point the singleton at an empty folder before it is first touched — this
        // test can be the one that creates it — so its `init` can neither read nor
        // write the real library. See `testFolderLayoutAndWrites`.
        UserDefaults.standard.set(
            root.appendingPathComponent("unused", isDirectory: true).path,
            forKey: "rootFolderPath"
        )
        let library = Library.shared
        library.duplicateTrashOperation = { source in
            let destination = trashBin.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        library.setRoot(root)
        library.flushDiskWrites()

        XCTAssertEqual(library.notes.count, 1, "a byte-identical duplicate was kept")
        XCTAssertEqual(library.notes.first?.id, note.id,
                       "the duplicate was re-identified instead of trashed")
        XCTAssertEqual(mdCount(notes), 1, "the duplicate is still in the folder")
        XCTAssertEqual(mdCount(trashBin), 1, "the duplicate did not reach the Trash")
        XCTAssertTrue(fm.fileExists(atPath: try XCTUnwrap(library.notes.first?.fileURL).path),
                      "the survivor's file is gone")
    }

    // MARK: Copying a note to the pasteboard

    /// What the ⋯ menu's Copy puts on the pasteboard is the writing — the title
    /// as a heading, a blank line, the body — and specifically *not* `encode`'s
    /// frontmatter, which is Insert's own bookkeeping and means nothing wherever
    /// it is being pasted.
    func testCopyTextIsTheHeadingAndBodyWithoutFrontmatter() {
        var note = Note(title: "Kickoff", body: "- agenda\n  - budget")
        note.typeID = "meeting"
        let text = MarkdownFiles.copyText(note)
        XCTAssertEqual(text, "# Kickoff\n\n- agenda\n  - budget")
        XCTAssertFalse(text.contains(note.id.uuidString))
        XCTAssertFalse(text.contains("type:"))
    }

    /// "Untitled" is a label for a card with no name, not a name to paste, so an
    /// empty title contributes no heading and no blank line above the body.
    func testCopyTextOmitsAnEmptyTitleEntirely() {
        XCTAssertEqual(MarkdownFiles.copyText(Note(title: "  ", body: "just the body")), "just the body")
    }

    /// A title with nothing under it copies as the heading alone — no trailing
    /// blank line to paste.
    func testCopyTextOfATitleOnlyNoteIsTheHeadingAlone() {
        XCTAssertEqual(MarkdownFiles.copyText(Note(title: "Kickoff", body: "")), "# Kickoff")
    }

    /// Nothing to copy is the empty string, which is what disables the menu item.
    func testCopyTextOfAnEmptyNoteIsEmpty() {
        XCTAssertTrue(MarkdownFiles.copyText(Note(title: "", body: "\n  \n")).isEmpty)
    }

    // MARK: Searching

    /// Search is one rule for all three columns, and it is case- *and*
    /// diacritic-insensitive: `range(of:options:)` in place, rather than a
    /// `lowercased()` copy of every record's title and body per keystroke. The
    /// diacritic half is a behaviour gain and it works from both sides — an
    /// unaccented query finds accented writing and the other way about — which is
    /// the whole point on a Spanish keyboard.
    ///
    /// No locale is involved: both options are locale-independent, so this holds
    /// whatever `Locale.current` says. See `Formatting`.
    @MainActor
    func testSearchIsCaseAndDiacriticInsensitiveInAllThreeColumns() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-search-\(UUID().uuidString)", isDirectory: true)
        let notesDir = root.appendingPathComponent("Notes", isDirectory: true)
        let tasksDir = root.appendingPathComponent("Tasks", isDirectory: true)
        for dir in [notesDir, tasksDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }

        try MarkdownFiles.encodeProjects([
            Project(name: "Navegación"),
            Project(name: "Búsqueda"),
        ]).write(to: root.appendingPathComponent("Projects.md"),
                 atomically: true, encoding: .utf8)

        // One note matched by its accented title, one by an unaccented body — so a
        // query in either spelling has to reach both.
        for note in [Note(title: "Navegación de la app", body: "revisar también el menú"),
                     Note(title: "Plain ascii note", body: "navegacion sin tilde")] {
            try MarkdownFiles.encode(note).write(
                to: notesDir.appendingPathComponent(MarkdownFiles.noteFilename(note)),
                atomically: true, encoding: .utf8)
        }
        let task = TaskItem(title: "Arreglar la Navegación", body: "y también el foco")
        try MarkdownFiles.encode(task).write(
            to: tasksDir.appendingPathComponent(MarkdownFiles.taskFilename(task)),
            atomically: true, encoding: .utf8)

        UserDefaults.standard.set(true, forKey: "didSeed")
        UserDefaults.standard.set(
            root.appendingPathComponent("unused", isDirectory: true).path,
            forKey: "rootFolderPath"
        )
        let library = Library.shared
        library.setRoot(root)
        XCTAssertEqual(library.notes.count, 2)
        XCTAssertEqual(library.tasks.count, 1)

        // The toolbar field: every column at once, in four spellings of one query.
        for query in ["Navegación", "navegacion", "NAVEGACION", "NAVEGACIÓN"] {
            let hits = library.search(query)
            XCTAssertEqual(hits.projects.map(\.name), ["Navegación"], "projects, for “\(query)”")
            XCTAssertEqual(hits.notes.count, 2, "notes, for “\(query)”")
            XCTAssertEqual(hits.tasks.count, 1, "tasks, for “\(query)”")
        }

        // A body-only match, and one that is diacritic-insensitive in the other
        // direction: the writing carries the accent, the query does not.
        let alsos = library.search("TAMBIEN")
        XCTAssertEqual(alsos.projects.count, 0)
        XCTAssertEqual(alsos.notes.map(\.title), ["Navegación de la app"])
        XCTAssertEqual(alsos.tasks.count, 1)

        XCTAssertEqual(library.search("BUSQUEDA").projects.map(\.name), ["Búsqueda"])
        XCTAssertTrue(library.search("zzz").isEmpty, "the fold matched something it shouldn't")

        // And the two column queries, which search by the same rule.
        XCTAssertEqual(
            library.notes(forProject: nil, sort: .updatedDesc, typeFilter: nil,
                          search: "  NAVEGACION  ").count,
            2, "the notes column does not fold its query"
        )
        XCTAssertEqual(
            library.tasks(forProject: nil, filter: .all, search: "tambien").map(\.title),
            ["Arreglar la Navegación"], "the tasks column does not fold its query"
        )
    }

    // MARK: Project counts

    /// `counts(forProject:)` answers from a table built in one pass over both
    /// arrays, because the sidebar asks per row on every mutation — including each
    /// debounced save while someone types. The table is only worth having if the
    /// invalidation is complete, so every kind of mutation is walked here: a
    /// create, an update that moves an assignment, a delete, a tick that changes
    /// no assignment at all, a project deletion (which rewrites records in place)
    /// and a full reload.
    ///
    /// The last check is the other half, and it is the one a cache usually gets
    /// wrong: the table is `@ObservationIgnored`, so `counts(forProject:)` has to
    /// register the dependency itself or a sidebar row would draw its number once
    /// and never again.
    @MainActor
    func testProjectCountsFollowEveryMutation() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-counts-\(UUID().uuidString)", isDirectory: true)
        let notesDir = root.appendingPathComponent("Notes", isDirectory: true)
        let tasksDir = root.appendingPathComponent("Tasks", isDirectory: true)
        let trashBin = root.appendingPathComponent("Test Trash", isDirectory: true)
        for dir in [notesDir, tasksDir, trashBin] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }
        let moveToTestTrash: Library.TrashOperation = { source in
            let destination = trashBin.appendingPathComponent(
                "\(UUID().uuidString)-\(source.lastPathComponent)"
            )
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }

        let projectA = UUID(), projectB = UUID()
        try MarkdownFiles.encodeProjects([
            Project(id: projectA, name: "Alpha"),
            Project(id: projectB, name: "Beta"),
        ]).write(to: root.appendingPathComponent("Projects.md"),
                 atomically: true, encoding: .utf8)

        let seedNote = Note(title: "Alpha's note", projectIDs: [projectA])
        try MarkdownFiles.encode(seedNote).write(
            to: notesDir.appendingPathComponent(MarkdownFiles.noteFilename(seedNote)),
            atomically: true, encoding: .utf8)
        let seedTask = TaskItem(title: "Alpha's task", projectIDs: [projectA])
        try MarkdownFiles.encode(seedTask).write(
            to: tasksDir.appendingPathComponent(MarkdownFiles.taskFilename(seedTask)),
            atomically: true, encoding: .utf8)

        UserDefaults.standard.set(true, forKey: "didSeed")
        UserDefaults.standard.set(
            root.appendingPathComponent("unused", isDirectory: true).path,
            forKey: "rootFolderPath"
        )
        let library = Library.shared
        library.setRoot(root)

        // A tuple can't be `Equatable`, so the pair is compared as two numbers.
        func counts(_ id: UUID) -> [Int] {
            let c = library.counts(forProject: id)
            return [c.notes, c.tasks]
        }

        XCTAssertEqual(counts(projectA), [1, 1], "the load's own counts are wrong")
        XCTAssertEqual(counts(projectB), [0, 0])
        XCTAssertEqual(counts(UUID()), [0, 0], "an unknown project should count nothing")

        let extraNote = library.addNote(title: "Second note", projectIDs: [projectA])
        XCTAssertEqual(counts(projectA), [2, 1], "a created note is not counted")
        let extraTask = library.addTask(title: "Second task", projectIDs: [projectA])
        XCTAssertEqual(counts(projectA), [2, 2], "a created task is not counted")

        // Moving an assignment is the in-place `notes[idx] = …` path, which the
        // invalidation has to catch as surely as a whole-array assignment does.
        var moved = try XCTUnwrap(library.notes.first { $0.id == extraNote.id })
        moved.projectIDs = [projectB]
        library.updateNote(moved)
        XCTAssertEqual(counts(projectA), [1, 2], "a reassigned note is still counted under Alpha")
        XCTAssertEqual(counts(projectB), [1, 0], "a reassigned note is not counted under Beta")

        let extraDeleted = await library.deleteNote(
            id: extraNote.id, trashOperation: moveToTestTrash)
        XCTAssertTrue(extraDeleted)
        XCTAssertEqual(counts(projectB), [0, 0], "a deleted note is still counted")

        // Ticking a task changes no assignment, so the same numbers have to come
        // back — through an invalidation that did happen.
        library.toggleTask(id: extraTask.id)
        XCTAssertEqual(counts(projectA), [1, 2], "a tick moved a count")

        // A reload replaces both arrays wholesale and must not answer from the
        // table the mutations above left behind.
        await library.reloadAll()
        XCTAssertEqual(counts(projectA), [1, 2], "the counts did not survive a reload")

        // `deleteProject` unassigns the project from every record, in place.
        library.deleteProject(id: projectA)
        XCTAssertEqual(counts(projectA), [0, 0], "a deleted project's records are still counted")
        await library.reloadAll()
        XCTAssertEqual(counts(projectA), [0, 0],
                       "the unassignment did not reach disk, or the reload read a stale table")

        // Warm the table first: a cache *hit* is the path that could skip the read
        // of `notes`/`tasks` and so register no dependency at all.
        _ = counts(projectB)
        let signal = MutationSignal()
        _ = withObservationTracking {
            library.counts(forProject: projectB)
        } onChange: {
            signal.fire()
        }
        _ = library.addNote(title: "Watched", projectIDs: [projectB])
        XCTAssertTrue(signal.fired,
                      "reading a count registers no @Observable dependency, so a sidebar row would never update")
        XCTAssertEqual(counts(projectB), [1, 0])
    }

    // MARK: Draining the disk queue

    /// `reloadAll` drains the write queue **off** the main actor now — the drain
    /// used to be a `diskQueue.sync {}` as its first statement, so a stalled
    /// iCloud rename held the window, which is the stall the queue was added to
    /// remove. What it gave the block up for has to survive: nothing may be
    /// decoded until every queued write has landed, or the reload reverts the
    /// index to what the disk still says.
    ///
    /// The queue is genuinely occupied here rather than raced against. A Trash
    /// operation runs on the same serial queue every write goes to, so one that
    /// sleeps holds everything enqueued behind it — and the gate is what makes the
    /// ordering a fact rather than a hope: the edit below is only made once the
    /// sleeping block is known to be *running*.
    @MainActor
    func testReloadWaitsForEveryPendingDiskWrite() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-drain-\(UUID().uuidString)", isDirectory: true)
        let notesDir = root.appendingPathComponent("Notes", isDirectory: true)
        let trashBin = root.appendingPathComponent("Test Trash", isDirectory: true)
        for dir in [notesDir, trashBin] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }

        let resident = Note(title: "Resident", body: "as it was on disk")
        try MarkdownFiles.encode(resident).write(
            to: notesDir.appendingPathComponent(MarkdownFiles.noteFilename(resident)),
            atomically: true, encoding: .utf8)

        UserDefaults.standard.set(true, forKey: "didSeed")
        UserDefaults.standard.set(
            root.appendingPathComponent("unused", isDirectory: true).path,
            forKey: "rootFolderPath"
        )
        let library = Library.shared
        library.setRoot(root)

        // A throwaway note, only so that deleting it puts a slow block on the queue.
        let filler = library.addNote(title: "Occupies the queue")
        library.flushDiskWrites()

        let gate = MutationSignal()
        let slowTrash: Library.TrashOperation = { source in
            gate.fire()
            Thread.sleep(forTimeInterval: 0.4)
            let destination = trashBin.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        }
        let deletion = Task { await library.deleteNote(id: filler.id, trashOperation: slowTrash) }

        // Bounded, so a Trash operation that never reaches the queue fails the test
        // rather than hanging it.
        var spins = 0
        while !gate.fired, spins < 100_000 {
            await Task.yield()
            spins += 1
        }
        XCTAssertTrue(gate.fired, "the Trash operation never reached the disk queue")

        // Enqueued behind the sleeping block, so it cannot have landed yet.
        var edited = try XCTUnwrap(library.notes.first { $0.id == resident.id })
        edited.body = "written while the queue was busy"
        library.updateNote(edited)

        await library.reloadAll()
        let reloaded = try XCTUnwrap(library.notes.first { $0.id == resident.id })
        XCTAssertEqual(reloaded.body, "written while the queue was busy",
                       "the reload decoded before the queue had drained")

        let fillerDeleted = await deletion.value
        XCTAssertTrue(fillerDeleted)
        XCTAssertFalse(library.notes.contains { $0.id == filler.id })
    }

}

/// A flag `withObservationTracking`'s `@Sendable` change handler — and a Trash
/// operation running on the disk queue — can raise from off the main actor.
private final class MutationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    func fire() {
        lock.lock()
        raised = true
        lock.unlock()
    }

    var fired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return raised
    }
}
