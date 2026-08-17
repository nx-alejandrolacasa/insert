import XCTest
@testable import Insert

/// Pins the two pure functions the surface refreshes left behind: the one-time
/// setting migration onto a theme, and the card footer's date compaction.
///
/// The migration matters because it runs against strings from an old install
/// **exactly once** — get it wrong and a user's chosen colour silently resets,
/// with nothing on screen to say why, and no second chance to get it right. It
/// also folds *two* retired settings into one, which is the part that can go
/// wrong quietly: the tint has to win where there is one and the accent has to
/// win where there isn't, and neither may reach Dracula. The compaction matters
/// at its two boundaries, midnight and New Year, which is where "today" and
/// "this year" quietly disagree with "within 24 hours" and "within 365 days".
final class ThemeMigrationTests: XCTestCase {
    func testEveryRetiredTintMapsToItsFamily() {
        // The near-neutral to Bone, the warm ones to Ember, pink to Rosewood,
        // green to Moss, violet to Indigo.
        XCTAssertEqual(AppTheme.migrated(tint: "mist", accent: ""), .bone)
        XCTAssertEqual(AppTheme.migrated(tint: "linen", accent: ""), .ember)
        XCTAssertEqual(AppTheme.migrated(tint: "clay", accent: ""), .ember)
        XCTAssertEqual(AppTheme.migrated(tint: "blush", accent: ""), .rosewood)
        XCTAssertEqual(AppTheme.migrated(tint: "sage", accent: ""), .moss)
        XCTAssertEqual(AppTheme.migrated(tint: "lilac", accent: ""), .indigo)
        // Seafoam postdates the plan's table and is mapped by family rather
        // than by the company it was added in: it is a green, so it follows
        // sage instead of the cool near-whites.
        XCTAssertEqual(AppTheme.migrated(tint: "seafoam", accent: ""), .moss)
    }

    /// A tint that was actually chosen outranks the accent, since it was the
    /// colour of the *window* and so the louder of the two choices.
    func testTintWinsOverAccent() {
        XCTAssertEqual(AppTheme.migrated(tint: "sage", accent: "orange"), .moss)
        XCTAssertEqual(AppTheme.migrated(tint: "blush", accent: "blue"), .rosewood)
    }

    /// With the tint left at Plain there was no window colour, so the accent is
    /// the only thing the user picked and it decides instead.
    func testPlainFallsThroughToTheAccent() {
        XCTAssertEqual(AppTheme.migrated(tint: "plain", accent: "green"), .moss)
        XCTAssertEqual(AppTheme.migrated(tint: "plain", accent: "orange"), .ember)
        XCTAssertEqual(AppTheme.migrated(tint: "plain", accent: "lilac"), .indigo)
        // Blue was the accent's own default, so it says nothing about what the
        // user wanted — it lands on the theme default like an absent value.
        XCTAssertEqual(AppTheme.migrated(tint: "plain", accent: "blue"), .default)
        // A grey accent goes to the one theme with no hue in it: Bone's accent
        // is ink, so "I chose no colour" is answered rather than overridden.
        XCTAssertEqual(AppTheme.migrated(tint: "plain", accent: "gray"), .bone)
        // The two greys that were themselves retired onto Gray before this.
        XCTAssertEqual(AppTheme.migrated(tint: "plain", accent: "graphite"), .bone)
        XCTAssertEqual(AppTheme.migrated(tint: "plain", accent: "lightGray"), .bone)
    }

    /// An install that never opened Settings, and one holding a value from a
    /// build nobody has: both land on the default rather than nowhere, so
    /// "never chose" and "chose the default" agree.
    func testUnknownAndAbsentValuesLandOnTheDefault() {
        XCTAssertEqual(AppTheme.migrated(tint: "", accent: ""), .default)
        XCTAssertEqual(AppTheme.migrated(tint: "neon", accent: "chartreuse"), .default)
    }

    /// The picker's order and the default are **two different things** in this
    /// set, unlike the one before it: `allCases` runs muted → hued → identity,
    /// so Bone leads, while a new install opens on Indigo. Pinned because
    /// reordering the enum for any other reason would silently move either.
    func testBoneLeadsThePickerAndIndigoIsTheDefault() {
        XCTAssertEqual(AppTheme.allCases.first, .bone)
        XCTAssertEqual(AppTheme.allCases.last, .dracula)
        XCTAssertEqual(AppTheme.default, .indigo)
        XCTAssertEqual(AppTheme.migrated(tint: "", accent: ""), .indigo)
    }

    /// Dracula is an identity, not a shade — it has to be picked, so no input
    /// may arrive there. Written as a sweep over every value either setting
    /// ever held, because the risk is a *new* mapping accidentally pointing at
    /// it, not the ones above.
    func testNothingMigratesToDracula() {
        let tints = ["", "plain", "linen", "clay", "blush", "sage", "seafoam", "mist", "lilac",
                     "cloud", "stone", "dawn", "dusk", "grove", "neon",
                     // The first theme set's own names, which a locally saved
                     // `theme` key can still hold: they aren't tints, so they
                     // fall through — but they must not fall through to here.
                     "slate", "graphite", "pine", "amber"]
        let accents = ["", "blue", "green", "orange", "lilac", "gray", "graphite", "lightGray"]
        for tint in tints {
            for accent in accents {
                XCTAssertNotEqual(
                    AppTheme.migrated(tint: tint, accent: accent), .dracula,
                    "tint \"\(tint)\" + accent \"\(accent)\" migrated to Dracula"
                )
            }
        }
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
