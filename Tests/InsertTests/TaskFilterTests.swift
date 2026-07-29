import XCTest
@testable import Insert

/// Pins which tasks the two filter axes select — the state trio (All /
/// Pending / Done) and the date trio (Overdue / Today / Tomorrow), which
/// combine: Pending + Today is the day's remaining work, Done + Overdue is
/// what got finished late. The interesting part is arithmetic over day
/// boundaries — a due date is a whole day (`yyyy-MM-dd`), not an instant —
/// and that the date axis reads the due date *alone*: done-ness belongs to
/// the state axis, which is what makes the combinations mean anything.
final class TaskFilterTests: XCTestCase {

    /// Mid-afternoon, so a boundary slip toward "instants minus 24h" (rather
    /// than whole days) would land on the wrong day and fail.
    private let now = Calendar.current.date(
        bySettingHour: 15, minute: 30, second: 0, of: Date()
    )!

    private func task(dueInDays days: Int? = nil, done: Bool = false) -> TaskItem {
        let due = days.map {
            Calendar.current.date(byAdding: .day, value: $0, to: Calendar.current.startOfDay(for: now))!
        }
        return TaskItem(title: "t", done: done, due: due)
    }

    private func dateFilters(matching task: TaskItem) -> Set<TaskDateFilter> {
        Set(TaskDateFilter.allCases.filter { $0.matches(task, now: now) })
    }

    private func stateFilters(matching task: TaskItem) -> Set<TaskFilter> {
        Set(TaskFilter.allCases.filter { $0.matches(task) })
    }

    // MARK: The date axis

    func testDueYesterdayIsOverdue() {
        XCTAssertEqual(dateFilters(matching: task(dueInDays: -1)), [.overdue])
    }

    func testDueTodayIsToday() {
        XCTAssertEqual(dateFilters(matching: task(dueInDays: 0)), [.today])
    }

    func testDueTomorrowIsTomorrow() {
        XCTAssertEqual(dateFilters(matching: task(dueInDays: 1)), [.tomorrow])
    }

    /// The day after tomorrow is the far edge: upcoming, but no pill's business.
    func testDueLaterMatchesNoDateFilter() {
        XCTAssertEqual(dateFilters(matching: task(dueInDays: 2)), [])
    }

    func testUndatedMatchesNoDateFilter() {
        XCTAssertEqual(dateFilters(matching: task()), [])
    }

    /// Ticking a task does not move it between date windows — the axis reads
    /// the due date alone, so Done + Overdue can mean "finished late". (The
    /// menu bar's buckets keep the old pending-only rule; that's
    /// `DateSections`, not this.)
    func testDoneKeepsItsDateWindow() {
        XCTAssertEqual(dateFilters(matching: task(dueInDays: -1, done: true)), [.overdue])
        XCTAssertEqual(dateFilters(matching: task(dueInDays: 0, done: true)), [.today])
    }

    // MARK: The state axis

    func testStateReadsDoneAlone() {
        XCTAssertEqual(stateFilters(matching: task(dueInDays: -1)), [.all, .pending])
        XCTAssertEqual(stateFilters(matching: task(dueInDays: -1, done: true)), [.all, .done])
    }

    // MARK: Combined

    /// The list ANDs the two axes, so a task finished late is Done + Overdue's
    /// business and no longer Pending + Overdue's.
    func testAxesCombine() {
        let finishedLate = task(dueInDays: -1, done: true)
        XCTAssertTrue(TaskFilter.done.matches(finishedLate)
            && TaskDateFilter.overdue.matches(finishedLate, now: now))
        XCTAssertFalse(TaskFilter.pending.matches(finishedLate))
    }
}
