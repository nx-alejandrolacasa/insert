import XCTest
@testable import Insert

/// Pins the two pure functions the surface refreshes left behind: the one-time
/// setting migration onto a theme, and the card footer's date compaction.
///
/// The migration matters because it runs against strings from an old install
/// **exactly once** — get it wrong and a user's chosen colour silently resets,
/// with nothing on screen to say why, and no second chance to get it right. It
/// now folds *three* generations of setting into one key, which is the part that
/// can go wrong quietly: a theme name from the first set of six has to win over
/// a tint, a tint over an accent, and none of the three may reach Dracula.
///
/// The first of those three is the one this pass added, and it is the dangerous
/// one: a saved `theme` of `"indigo"` no longer decodes, so without a mapping it
/// is indistinguishable from an install that never chose a theme at all — the
/// user's choice would reset to the default with nothing to point at.
///
/// The compaction matters at its two boundaries, midnight and New Year, which is
/// where "today" and "this year" quietly disagree with "within 24 hours" and
/// "within 365 days".
final class ThemeMigrationTests: XCTestCase {
    /// The first set of six, mapped by what the new set replaces: the neutrals to
    /// System, Moss and Pine to Tokyo Night, the warm ones to Kanagawa, Indigo to
    /// Dark Owl, Rosewood to Rosé Pine.
    func testEveryRetiredThemeMapsToItsReplacement() {
        XCTAssertEqual(AppTheme.migrated(theme: "bone", tint: "", accent: ""), .system)
        XCTAssertEqual(AppTheme.migrated(theme: "slate", tint: "", accent: ""), .system)
        XCTAssertEqual(AppTheme.migrated(theme: "graphite", tint: "", accent: ""), .system)
        XCTAssertEqual(AppTheme.migrated(theme: "moss", tint: "", accent: ""), .tokyoNight)
        XCTAssertEqual(AppTheme.migrated(theme: "pine", tint: "", accent: ""), .tokyoNight)
        XCTAssertEqual(AppTheme.migrated(theme: "ember", tint: "", accent: ""), .kanagawa)
        XCTAssertEqual(AppTheme.migrated(theme: "amber", tint: "", accent: ""), .kanagawa)
        XCTAssertEqual(AppTheme.migrated(theme: "indigo", tint: "", accent: ""), .darkOwl)
        XCTAssertEqual(AppTheme.migrated(theme: "rosewood", tint: "", accent: ""), .rosePine)
    }

    /// Dracula is the one name that survived the swap, so it never reaches the
    /// migration at all — it decodes. Pinned because renaming that case would
    /// send every Dracula install through a function that deliberately refuses to
    /// answer with it.
    func testDraculaStillDecodesRatherThanMigrating() {
        XCTAssertEqual(AppTheme(rawValue: "dracula"), .dracula)
    }

    func testEveryRetiredTintMapsToItsFamily() {
        // The near-neutral to System, the warm ones to Kanagawa, pink to Rosé
        // Pine, green to Tokyo Night, violet to Dark Owl.
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "mist", accent: ""), .system)
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "linen", accent: ""), .kanagawa)
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "clay", accent: ""), .kanagawa)
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "blush", accent: ""), .rosePine)
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "sage", accent: ""), .tokyoNight)
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "lilac", accent: ""), .darkOwl)
        // Seafoam postdates the plan's table and is mapped by family rather
        // than by the company it was added in: it is a green, so it follows
        // sage instead of the cool near-whites.
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "seafoam", accent: ""), .tokyoNight)
    }

    /// The three are tried in the order of how deliberate a choice each was: a
    /// theme outranks a tint, and a tint outranks the accent, since a tint was
    /// the colour of the *window* and so the louder of those two.
    func testTheMoreDeliberateChoiceWins() {
        XCTAssertEqual(AppTheme.migrated(theme: "moss", tint: "blush", accent: "orange"), .tokyoNight)
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "sage", accent: "orange"), .tokyoNight)
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "blush", accent: "blue"), .rosePine)
    }

    /// With the tint left at Plain there was no window colour, so the accent is
    /// the only thing the user picked and it decides instead.
    func testPlainFallsThroughToTheAccent() {
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "plain", accent: "green"), .tokyoNight)
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "plain", accent: "orange"), .kanagawa)
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "plain", accent: "lilac"), .darkOwl)
        // Blue goes to Dark Owl, which is a change of mind: the previous
        // migration read it as the accent's own default and sent it to the theme
        // default instead. An install that never chose an accent has no key, so
        // the two cases still separate — on the key's presence, not its value.
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "plain", accent: "blue"), .darkOwl)
        // A grey accent goes to the one theme with no hue of its own.
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "plain", accent: "gray"), .system)
        // The two greys that were themselves retired onto Gray before this.
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "plain", accent: "graphite"), .system)
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "plain", accent: "lightGray"), .system)
    }

    /// An install that never opened Settings, and one holding a value from a
    /// build nobody has: both land on the default rather than nowhere, so
    /// "never chose" and "chose the default" agree.
    func testUnknownAndAbsentValuesLandOnTheDefault() {
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "", accent: ""), .default)
        XCTAssertEqual(AppTheme.migrated(theme: "neon", tint: "neon", accent: "chartreuse"), .default)
    }

    /// The picker's order and the default are the **same** thing again in this
    /// set, unlike the one before it: System leads `allCases` and a new install
    /// opens on it. Pinned because reordering the enum for any other reason would
    /// silently move both.
    func testSystemLeadsThePickerAndIsTheDefault() {
        XCTAssertEqual(AppTheme.allCases.first, .system)
        XCTAssertEqual(AppTheme.allCases.last, .dracula)
        XCTAssertEqual(AppTheme.default, .system)
        XCTAssertEqual(AppTheme.migrated(theme: "", tint: "", accent: ""), .system)
    }

    /// Dracula is an identity, not a shade — it has to be picked, so no input may
    /// arrive there. Written as a sweep over every value any of the three keys
    /// ever held, because the risk is a *new* mapping accidentally pointing at
    /// it, not the ones above.
    func testNothingMigratesToDracula() {
        let themes = ["", "bone", "moss", "ember", "rosewood", "indigo",
                      "slate", "graphite", "pine", "amber", "neon"]
        let tints = ["", "plain", "linen", "clay", "blush", "sage", "seafoam", "mist", "lilac",
                     "cloud", "stone", "dawn", "dusk", "grove", "neon"]
        let accents = ["", "blue", "green", "orange", "lilac", "gray", "graphite", "lightGray"]
        for theme in themes {
            for tint in tints {
                for accent in accents {
                    XCTAssertNotEqual(
                        AppTheme.migrated(theme: theme, tint: tint, accent: accent), .dracula,
                        """
                        theme "\(theme)" + tint "\(tint)" + accent "\(accent)" \
                        migrated to Dracula
                        """
                    )
                }
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
