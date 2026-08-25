import Foundation
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
    func testFolderLayoutAndWrites() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("insert-storage-\(UUID().uuidString)", isDirectory: true)
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        let tasks = root.appendingPathComponent("Tasks", isDirectory: true)
        for dir in [notes, tasks] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }

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
        library.reloadAll()
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
        check("purged", library.purgeCompletedTasks(retention: .month, now: now), 20)
        library.flushDiskWrites()
        check("Tasks/Done/ on disk", mdCount(library.tasksDoneDir), 10)
        check("tasks left in memory", library.tasks.count, 20)

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
    func testParallelLoadIsCompleteAndOrdered() throws {
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
            library.reloadAll()
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
    func testProjectsReorderByDragAndPersist() throws {
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
        library.reloadAll()
        XCTAssertEqual(order(), ["Alpha", "Beta", "Delta", "Gamma"], "the order did not persist")
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

}
