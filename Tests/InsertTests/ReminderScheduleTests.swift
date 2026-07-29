import XCTest
@testable import Insert

/// Pins the daily reminder's timing. The rest of `TaskReminder` is a timer, a
/// permission prompt and a banner — none of which a test can see — but *when* the
/// reminder is owed is arithmetic, and it is the part with edges: the two minutes
/// either side of the time itself, the grace window that lets a Mac woken late
/// still say something useful, and the once-a-day rule that stops a relaunch
/// mid-morning earning a second notification.
///
/// Every case pins the calendar to UTC, so the suite gives the same answer on a
/// machine in any timezone.
final class ReminderScheduleTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A date written as "2026-07-28 09:00" reads better here than a components
    /// literal, and the reminder deals in whole minutes.
    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 7, day: day, hour: hour, minute: minute
        ))!
    }

    private func isDue(_ now: Date, minutes: Int = 9 * 60, lastNotified: Date? = nil) -> Bool {
        ReminderSchedule.isDue(
            now: now, minutes: minutes, lastNotified: lastNotified, calendar: calendar
        )
    }

    // MARK: The time itself

    /// The whole reason `time(_:on:)` doesn't use
    /// `Calendar.date(bySettingHour:minute:second:of:)`: asked for 09:00 in the
    /// afternoon, that method answers *tomorrow*, and every "not due yet" case
    /// below would then pass for the wrong reason.
    func testTimeStaysOnTheDayItWasAskedAbout() {
        XCTAssertEqual(ReminderSchedule.time(9 * 60, on: date(28, 14, 30), calendar: calendar),
                       date(28, 9, 0))
        XCTAssertEqual(ReminderSchedule.time(9 * 60, on: date(28, 2, 0), calendar: calendar),
                       date(28, 9, 0))
    }

    func testTimeSplitsMinutesIntoHourAndMinute() {
        XCTAssertEqual(ReminderSchedule.time(7 * 60 + 45, on: date(28, 12, 0), calendar: calendar),
                       date(28, 7, 45))
        XCTAssertEqual(ReminderSchedule.time(0, on: date(28, 12, 0), calendar: calendar),
                       date(28, 0, 0))
    }

    // MARK: Due, and not yet due

    func testDueOnTheMinute() {
        XCTAssertTrue(isDue(date(28, 9, 0)))
    }

    func testNotDueAMinuteEarly() {
        XCTAssertFalse(isDue(date(28, 8, 59)))
    }

    func testNotDueEarlierTheSameDay() {
        XCTAssertFalse(isDue(date(28, 3, 0)))
    }

    // MARK: The grace window

    /// A Mac asleep at 09:00 and woken at 09:40 should still be told what the day
    /// holds — this is what the minute-by-minute tick buys over a timer aimed at
    /// the exact minute.
    func testStillDueWithinTheGraceWindow() {
        XCTAssertTrue(isDue(date(28, 10, 59)))
    }

    /// Past the window it stops being a morning reminder and starts being news
    /// about a day already half spent.
    func testNotDueOnceTheGraceWindowHasPassed() {
        XCTAssertFalse(isDue(date(28, 11, 0)))
        XCTAssertFalse(isDue(date(28, 23, 30)))
    }

    /// The window is anchored to the setting, not to the morning.
    func testGraceWindowFollowsTheConfiguredTime() {
        XCTAssertTrue(isDue(date(28, 18, 30), minutes: 18 * 60))
        XCTAssertFalse(isDue(date(28, 17, 59), minutes: 18 * 60))
        XCTAssertFalse(isDue(date(28, 20, 1), minutes: 18 * 60))
    }

    /// A reminder set for the small hours: 23:30 is neither 00:30's due time nor
    /// inside its window, because the window can't reach backwards over midnight.
    func testNoticeAtMidnightDoesNotReachBackIntoTheEvening() {
        XCTAssertTrue(isDue(date(28, 0, 30), minutes: 30))
        XCTAssertFalse(isDue(date(28, 23, 30), minutes: 30))
    }

    // MARK: Once a day

    func testNotDueAgainOnceTodayHasBeenNotified() {
        XCTAssertFalse(isDue(date(28, 9, 30), lastNotified: date(28, 9, 0)))
    }

    /// Earlier the same day still counts — the stamp names a day, not an instant,
    /// which is what keeps a quit-and-relaunch at 09:05 quiet.
    func testNotDueAgainWhateverTimeTodayWasNotifiedAt() {
        XCTAssertFalse(isDue(date(28, 9, 30), lastNotified: date(28, 0, 5)))
    }

    func testDueAgainTheNextDay() {
        XCTAssertTrue(isDue(date(29, 9, 0), lastNotified: date(28, 9, 0)))
    }

    /// A stamp from the future (a clock the user has wound back) leaves the
    /// reminder quiet for that day rather than firing every minute.
    func testATomorrowStampSuppressesOnlyTomorrow() {
        XCTAssertTrue(isDue(date(28, 9, 0), lastNotified: date(29, 9, 0)))
        XCTAssertFalse(isDue(date(29, 9, 0), lastNotified: date(29, 8, 0)))
    }

    // MARK: The times on offer

    /// The list the Settings picker draws: every half hour from 06:00 to 12:00, and
    /// nothing outside it. `through:` rather than `to:` is the edge — 12:00 is meant
    /// to be on the list, and `stride(to:)` would stop at 11:30.
    func testSlotsRunEveryHalfHourFromSixToTwelve() {
        XCTAssertEqual(ReminderSchedule.slots.first, 6 * 60)
        XCTAssertEqual(ReminderSchedule.slots.last, 12 * 60)
        XCTAssertEqual(ReminderSchedule.slots.count, 13)
        XCTAssertEqual(Set(zip(ReminderSchedule.slots, ReminderSchedule.slots.dropFirst())
            .map { $1 - $0 }), [30])
    }

    /// The default has to be one of them, or a fresh install draws a blank picker.
    func testTheDefaultIsOnTheList() {
        XCTAssertTrue(ReminderSchedule.slots.contains(9 * 60))
    }

    /// An install saved while the picker still allowed any minute of any hour can
    /// hold a time that is no longer offered, and a `Picker` whose selection matches
    /// no tag draws blank. Every one of these has to land on the list.
    func testNearestSlotPullsOffGridTimesOntoTheList() {
        XCTAssertEqual(ReminderSchedule.nearestSlot(to: 7 * 60 + 13), 7 * 60)
        XCTAssertEqual(ReminderSchedule.nearestSlot(to: 7 * 60 + 20), 7 * 60 + 30)
        // Outside the range in both directions: clamped to its nearer end.
        XCTAssertEqual(ReminderSchedule.nearestSlot(to: 3 * 60), 6 * 60)
        XCTAssertEqual(ReminderSchedule.nearestSlot(to: 21 * 60), 12 * 60)
        XCTAssertEqual(ReminderSchedule.nearestSlot(to: 0), 6 * 60)
    }

    /// Idempotent on a value already offered — otherwise the snap that runs on every
    /// launch would walk the user's choice somewhere else.
    func testNearestSlotLeavesAnOfferedTimeAlone() {
        for slot in ReminderSchedule.slots {
            XCTAssertEqual(ReminderSchedule.nearestSlot(to: slot), slot)
        }
    }

    /// 24-hour, zero-padded minutes, no leading zero on the hour — and, the point of
    /// writing it out by hand, the same on a machine in any locale. A formatter here
    /// is what made the pane freeze; see `ReminderSchedule.slots`.
    func testLabelsAreLiteralDigits() {
        XCTAssertEqual(ReminderSchedule.label(6 * 60), "6:00")
        XCTAssertEqual(ReminderSchedule.label(9 * 60 + 30), "9:30")
        XCTAssertEqual(ReminderSchedule.label(12 * 60), "12:00")
    }

    // MARK: The sentence

    func testMessageAgreesWithItsCount() {
        XCTAssertEqual(ReminderSchedule.message(taskCount: 1), "You have 1 task for today.")
        XCTAssertEqual(ReminderSchedule.message(taskCount: 3), "You have 3 tasks for today.")
    }

    /// The count comes from the same bucket the menu bar labels "Today": due today,
    /// not done, and overdue work deliberately left out of it.
    ///
    /// Every date here is midday, and has to be: `DateSections` buckets against
    /// `Calendar.current`, so a UTC midnight is the day before in Los Angeles and a
    /// UTC 23:00 is the day after in Madrid. Noon is the same day either way.
    func testTodaysCountIsTheMenuBarsTodayBucket() {
        let now = date(28, 12, 0)
        let tasks = [
            TaskItem(title: "a", due: now),
            TaskItem(title: "b", due: now),
            TaskItem(title: "overdue", due: date(27, 12, 0)),
            TaskItem(title: "tomorrow", due: date(29, 12, 0)),
            TaskItem(title: "undated", due: nil),
            TaskItem(title: "done", done: true, due: now),
        ]
        XCTAssertEqual(DateSections.make(from: tasks, now: now).today.count, 2)
    }
}
