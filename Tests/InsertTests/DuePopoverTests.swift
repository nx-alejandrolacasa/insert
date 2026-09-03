import XCTest
@testable import Insert

/// Pins which preset pill the due popover lights up, and that the answer is a
/// function of an injected *today* rather than of whenever it happens to be
/// asked.
///
/// The highlight is the popover's one comparison against the current day: the
/// pills say "Today", "Tomorrow", "End of week" and "Next week", so the same
/// due date lights a different pill on either side of midnight. It read
/// `Date()` where the panel elsewhere passes `clock.today` — which registers
/// no `DayClock` dependency, so a popover left open across midnight kept
/// lighting yesterday's pill. `firstMatch(for:now:weekStyle:)` is the pure
/// half, and `now` being a parameter is what makes the boundary testable at
/// all: the alternative is waiting until tomorrow to find out.
final class DuePopoverTests: XCTestCase {
    private let calendar = Calendar.current

    /// Mid-afternoon, so a slip from whole days to "instants minus 24h" lands
    /// on the wrong day and fails — `TaskFilterTests`' reason.
    private func day(_ offset: Int, from reference: Date) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: reference))!
    }

    /// A Wednesday, so "End of week" (Friday, work week) and "Next week"
    /// (Monday) are three distinct days from today and tomorrow.
    private var wednesday: Date {
        let components = DateComponents(year: 2026, month: 9, day: 2, hour: 15, minute: 30)
        let date = calendar.date(from: components)!
        XCTAssertEqual(calendar.component(.weekday, from: date), 4, "the fixture is a Wednesday")
        return date
    }

    private func match(
        due: Date?, now: Date, weekStyle: WeekStyle = .work
    ) -> DuePreset? {
        DuePreset.firstMatch(for: due, now: now, weekStyle: weekStyle)
    }

    // MARK: Nothing is lit for nothing

    /// An undated task has no preset — the row of pills is an offer, not a
    /// report, and the same claim the month grid must not make either.
    func testAnUndatedTaskLightsNoPill() {
        XCTAssertNil(match(due: nil, now: wednesday))
    }

    /// A date none of the four names leaves the row dark rather than falling
    /// back to the nearest one.
    func testADateNoPresetNamesLightsNoPill() {
        let now = wednesday
        // Thursday next week: past "Next week"'s Monday, and no preset's day.
        XCTAssertNil(match(due: day(8, from: now), now: now))
    }

    // MARK: Each pill for its own day

    func testDueTodayLightsToday() {
        let now = wednesday
        XCTAssertEqual(match(due: day(0, from: now), now: now), .today)
    }

    func testDueTomorrowLightsTomorrow() {
        let now = wednesday
        XCTAssertEqual(match(due: day(1, from: now), now: now), .tomorrow)
    }

    func testDueFridayLightsEndOfWorkWeek() {
        let now = wednesday
        XCTAssertEqual(match(due: day(2, from: now), now: now), .endOfWeek)
    }

    func testDueSundayLightsEndOfFullWeek() {
        let now = wednesday
        XCTAssertEqual(match(due: day(4, from: now), now: now, weekStyle: .full), .endOfWeek)
    }

    func testDueNextMondayLightsNextWeek() {
        let now = wednesday
        XCTAssertEqual(match(due: day(5, from: now), now: now), .nextWeek)
    }

    /// The time of day the due date carries is irrelevant — a due date is a
    /// whole day (`yyyy-MM-dd`) and the comparison is `inSameDayAs`.
    func testTheTimeOnTheDueDateDoesNotMatter() {
        let now = wednesday
        let lateTomorrow = calendar.date(byAdding: .hour, value: 23, to: day(1, from: now))!
        XCTAssertEqual(match(due: lateTomorrow, now: now), .tomorrow)
    }

    // MARK: The day boundary

    /// The point of the whole suite: one due date, two "todays", two pills.
    /// This is what a stale `Date()` inside the view could never do — the
    /// popover kept lighting "Today" on a task that had become due yesterday,
    /// or "Tomorrow" on one that had become due today.
    func testCrossingMidnightMovesTheHighlight() {
        let now = wednesday
        let thursday = day(1, from: now)

        XCTAssertEqual(match(due: thursday, now: now), .tomorrow)
        XCTAssertEqual(match(due: thursday, now: thursday), .today)
        // A day further on and no pill names a date already past.
        XCTAssertNil(match(due: thursday, now: day(2, from: now)))
    }

    /// The same boundary read off the other end: "Next week"'s Monday becomes
    /// "Today" when that Monday arrives, and the following Monday takes the
    /// pill over.
    func testNextWeekMovesOnWithTheWeek() {
        let now = wednesday
        let monday = day(5, from: now)

        XCTAssertEqual(match(due: monday, now: now), .nextWeek)
        XCTAssertEqual(match(due: monday, now: monday), .today)
        XCTAssertEqual(match(due: day(12, from: now), now: monday), .nextWeek)
    }

    // MARK: Collisions

    /// Presets collide — on a Thursday in work-week mode, "Tomorrow" and "End
    /// of week" are both Friday — and only the first match may light, or one
    /// date lights two pills.
    func testACollisionLightsOnlyTheFirstPill() {
        let thursday = day(1, from: wednesday)
        XCTAssertEqual(calendar.component(.weekday, from: thursday), 5, "the fixture is a Thursday")

        let friday = day(1, from: thursday)
        XCTAssertEqual(
            DuePreset.endOfWeek.date(now: thursday, weekStyle: .work),
            calendar.startOfDay(for: friday),
            "the collision the assertion below is about"
        )
        XCTAssertEqual(match(due: friday, now: thursday), .tomorrow)
    }

    /// On the end of the week itself, "End of week" means today — so "Today"
    /// takes it, and the row still lights exactly one pill.
    func testTheEndOfTheWeekOnTheDayItselfLightsToday() {
        let friday = day(2, from: wednesday)
        XCTAssertEqual(
            DuePreset.endOfWeek.date(now: friday, weekStyle: .work),
            calendar.startOfDay(for: friday),
            "end of week is today on a Friday"
        )
        XCTAssertEqual(match(due: friday, now: friday), .today)
    }

    // MARK: The month grid

    /// Every cell the grid draws for the month it opens on, and which of them
    /// it fills — the two questions asked of the values rather than of a view.
    private func chosenCells(due: Date?, today: Date) -> (cells: Int, chosen: [Date]) {
        let grid = DueMonth.opening(due: due, today: today, calendar: calendar)
        let cells = MonthGrid.days(for: grid.month, calendar: calendar)
        return (
            cells.count,
            cells.filter { MonthGrid.isChosen($0, selection: grid.selectedDay, calendar: calendar) }
        )
    }

    /// The fix: an undated task's popover opens on **this** month with
    /// **nothing** filled. Substituting today for the missing date claimed the
    /// task was due today while "Clear due date" — correctly — stayed disabled,
    /// so the popover made two contradictory claims at once.
    ///
    /// Asserted over all 42 cells rather than over today's alone, because the
    /// defect it replaces was a *date* standing in for "no date": any single
    /// cell filled anywhere is the same lie about a different day.
    func testAnUndatedTaskHighlightsNoDayInTheCurrentMonth() {
        let now = wednesday
        let grid = DueMonth.opening(due: nil, today: now, calendar: calendar)

        XCTAssertNil(grid.selectedDay, "nothing is chosen until a day is picked")
        XCTAssertEqual(
            grid.month,
            MonthGrid.startOfMonth(for: now, calendar: calendar),
            "the month still opens on the one today falls in"
        )

        let drawn = chosenCells(due: nil, today: now)
        XCTAssertEqual(drawn.cells, 42, "six weeks, as the grid always draws")
        XCTAssertEqual(drawn.chosen, [], "no cell is filled")
    }

    /// A dated task fills its due date, and only that — the month follows the
    /// date rather than today, so opening the popover on a task due in March
    /// shows March.
    func testADatedTaskHighlightsItsDueDate() {
        let now = wednesday
        let due = day(40, from: now)
        let grid = DueMonth.opening(due: due, today: now, calendar: calendar)

        XCTAssertEqual(grid.selectedDay, calendar.startOfDay(for: due))
        XCTAssertEqual(
            grid.month,
            MonthGrid.startOfMonth(for: due, calendar: calendar),
            "the grid opens on the due date's month, not on this one"
        )
        XCTAssertEqual(chosenCells(due: due, today: now).chosen, [calendar.startOfDay(for: due)])
    }

    /// The time on the due date is dropped on the way in, so a date stored with
    /// an afternoon component still matches its own cell — the cells are
    /// midnights.
    func testTheDueDatesTimeIsDroppedForTheHighlight() {
        let now = wednesday
        let lateToday = calendar.date(byAdding: .hour, value: 22, to: day(0, from: now))!
        XCTAssertEqual(
            chosenCells(due: lateToday, today: now).chosen,
            [calendar.startOfDay(for: now)]
        )
    }

    /// The month an undated task opens on is a comparison against today, which
    /// is why the panel passes `clock.today` and not `Date()`: with the day
    /// rolled into the next month, the grid has to follow.
    func testTheMonthAnUndatedTaskOpensOnFollowsToday() {
        let now = wednesday
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now)!

        XCTAssertNotEqual(
            DueMonth.opening(due: nil, today: now, calendar: calendar).month,
            DueMonth.opening(due: nil, today: nextMonth, calendar: calendar).month
        )
        XCTAssertEqual(
            DueMonth.opening(due: nil, today: nextMonth, calendar: calendar).month,
            MonthGrid.startOfMonth(for: nextMonth, calendar: calendar)
        )
    }
}
