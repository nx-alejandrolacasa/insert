import XCTest
@testable import Insert

/// Pins the July 2026 refresh's three pure functions: the two one-time
/// setting migrations (a saved gradient onto its nearest tint, a retired grey
/// accent onto Gray) and the card footer's date compaction. The migrations
/// matter because they run against a string from an old install exactly once
/// — get one wrong and a user's chosen backdrop silently resets, with nothing
/// on screen to say why. The compaction matters at its two boundaries,
/// midnight and New Year, which is where "today" and "this year" quietly
/// disagree with "within 24 hours" and "within 365 days".
final class RefreshMigrationTests: XCTestCase {
    func testEveryGradientMapsToItsFamily() {
        XCTAssertEqual(Backdrop.migratedFromGradient("cloud"), .mist)
        XCTAssertEqual(Backdrop.migratedFromGradient("stone"), .linen)
        XCTAssertEqual(Backdrop.migratedFromGradient("dawn"), .blush)
        XCTAssertEqual(Backdrop.migratedFromGradient("dusk"), .clay)
        XCTAssertEqual(Backdrop.migratedFromGradient("grove"), .sage)
    }

    func testCurrentAndUnknownValuesDoNotMigrate() {
        // A current raw value never reaches the migration (rawValue init wins),
        // but it must not map anywhere if it does; unknown strings fall through
        // to the default.
        XCTAssertNil(Backdrop.migratedFromGradient("plain"))
        XCTAssertNil(Backdrop.migratedFromGradient("mist"))
        XCTAssertNil(Backdrop.migratedFromGradient(""))
        XCTAssertNil(Backdrop.migratedFromGradient("neon"))
    }

    func testRetiredGreysCollapseOntoGray() {
        XCTAssertEqual(AccentColor.migratedFromRetired("graphite"), .gray)
        XCTAssertEqual(AccentColor.migratedFromRetired("lightGray"), .gray)
        XCTAssertNil(AccentColor.migratedFromRetired("blue"))
        XCTAssertNil(AccentColor.migratedFromRetired(""))
    }
}

final class CardDateCompactionTests: XCTestCase {
    /// A fixed moment to stand for "now": mid-afternoon, mid-year.
    private let now = date(2026, 7, 31, 15, 0)

    func testTodayIsTimeAlone() {
        XCTAssertNil(CardDatesFooter.dayPart(of: date(2026, 7, 31, 0, 1), now: now))
        XCTAssertNil(CardDatesFooter.dayPart(of: now, now: now))
    }

    func testYesterdayIsNotToday() {
        // 23:59 the day before is sixty-one minutes from `now`'s midnight and
        // still yesterday — the boundary is the calendar day, not a duration.
        XCTAssertEqual(CardDatesFooter.dayPart(of: date(2026, 7, 30, 23, 59), now: now), "30 Jul")
    }

    func testThisYearDropsTheYear() {
        XCTAssertEqual(CardDatesFooter.dayPart(of: date(2026, 1, 1, 9, 30), now: now), "1 Jan")
    }

    func testAnotherYearSpellsItOut() {
        // 25 Dec 2025 is closer to `now` than some same-year dates — the
        // boundary is the year component, not a distance.
        XCTAssertEqual(CardDatesFooter.dayPart(of: date(2025, 12, 25, 9, 30), now: now), "25 Dec 2025")
    }
}

/// A concrete local date, spelled as it reads.
private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    Calendar.current.date(from: DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute))!
}
