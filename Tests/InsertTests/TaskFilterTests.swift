import XCTest
@testable import Insert

/// Pins which tasks the Overdue / Today / Tomorrow pills select. The
/// interesting part is arithmetic over day boundaries — a due date is a whole
/// day (`yyyy-MM-dd`), not an instant — and the rule the date filters share
/// with the menu bar's buckets (`DateSections`): they show only pending, dated
/// work, so a ticked task due today is nobody's "today".
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

    private func filters(matching task: TaskItem) -> Set<TaskFilter> {
        Set(TaskFilter.allCases.filter { $0.matches(task, now: now) })
    }

    func testDueYesterdayIsOverdue() {
        XCTAssertEqual(filters(matching: task(dueInDays: -1)), [.all, .pending, .overdue])
    }

    func testDueTodayIsToday() {
        XCTAssertEqual(filters(matching: task(dueInDays: 0)), [.all, .pending, .today])
    }

    func testDueTomorrowIsTomorrow() {
        XCTAssertEqual(filters(matching: task(dueInDays: 1)), [.all, .pending, .tomorrow])
    }

    /// The day after tomorrow is the far edge: upcoming, but no pill's business.
    func testDueLaterMatchesNoDateFilter() {
        XCTAssertEqual(filters(matching: task(dueInDays: 2)), [.all, .pending])
    }

    func testUndatedMatchesNoDateFilter() {
        XCTAssertEqual(filters(matching: task()), [.all, .pending])
    }

    /// Ticking a task removes it from every date filter, however dated — the
    /// pills answer "what still needs doing", not "what was scheduled".
    func testDoneMatchesNoDateFilterWhateverTheDate() {
        XCTAssertEqual(filters(matching: task(dueInDays: -1, done: true)), [.all, .done])
        XCTAssertEqual(filters(matching: task(dueInDays: 0, done: true)), [.all, .done])
    }
}
