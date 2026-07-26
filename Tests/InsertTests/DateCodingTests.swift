import Foundation
import XCTest
@testable import Insert

/// Pins `DateCoding` against the two formatters it used to build per call.
///
/// This is the on-disk format for every note and task, so "faster" is worthless
/// unless it is also byte-identical: a mismatch would silently rewrite timestamps
/// across the whole library, or read back dates that were never written. Both the
/// hand-rolled fast path and the format-style fallback are compared against
/// `ISO8601DateFormatter` / `DateFormatter` directly, over a spread of dates chosen
/// to cover the civil-days arithmetic's edges.
final class DateCodingTests: XCTestCase {

    /// The formatters exactly as `DateCoding` used to construct them.
    private func referenceISO() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    private func referenceDay() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// The old two-step: try RFC-3339, then fall back to a bare day. This — not the
    /// raw formatter — is the behaviour that has to be preserved.
    private func referenceDateCoding(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        return referenceISO().date(from: s) ?? referenceDay().date(from: s)
    }

    /// Leap years, century non-leap years, DST boundaries, the epoch, pre-epoch,
    /// end-of-year — plus a long run of consecutive days, so an off-by-one in the
    /// days-from-civil arithmetic shows up instead of hiding between the edge cases.
    private var samples: [Date] {
        let iso = referenceISO()
        var dates = [
            "1970-01-01T00:00:00Z", "1969-07-20T20:17:00Z", "1900-03-01T12:00:00Z",
            "1999-12-31T23:59:59Z", "2000-01-01T00:00:00Z", "2000-02-29T06:00:00Z",
            "2024-02-29T23:00:00Z", "2026-03-29T01:30:00Z", "2026-10-25T02:30:00Z",
            "2026-07-24T10:00:00Z", "2100-02-28T00:00:00Z", "2100-03-01T00:00:00Z",
            "2400-12-31T18:45:01Z",
        ].compactMap { iso.date(from: $0) }
        let start = iso.date(from: "2015-01-01T07:13:29Z")!
        for i in 0..<4_000 {
            dates.append(start.addingTimeInterval(Double(i) * 86_400))
        }
        return dates
    }

    func testTimestampsMatchTheOldFormatter() {
        let iso = referenceISO()
        for date in samples {
            let expected = iso.string(from: date)
            XCTAssertEqual(DateCoding.string(date), expected, "formatting \(expected)")
            // And the fast path reads back exactly what the old formatter wrote.
            XCTAssertEqual(
                DateCoding.date(expected).map { iso.string(from: $0) }, expected,
                "round-tripping \(expected)"
            )
        }
    }

    func testDaysMatchTheOldFormatter() {
        let day = referenceDay()
        for date in samples {
            let expected = day.string(from: date)
            XCTAssertEqual(DateCoding.dayString(date), expected, "formatting \(expected)")
            XCTAssertEqual(DateCoding.day(expected), day.date(from: expected),
                           "parsing \(expected)")
        }
    }

    /// Nothing the old reader accepted may now parse differently, and nothing it
    /// accepted may be rejected. These are shapes a person could leave behind
    /// hand-editing frontmatter in Obsidian, and none is what the fast path takes.
    func testMatchesTheOldReaderOnEverythingItAccepted() {
        for input in [
            "2026-07-24T10:00:00Z",         // canonical — the fast path
            "  2026-07-24T10:00:00Z  ",     // padded
            "2026-07-24T12:00:00+02:00",    // an explicit zone offset
            "2026-07-24T10:00:00-05:00",
            "2026-02-30T00:00:00Z",         // the old formatter rolled this over
            "2026-07-24",                   // a timestamp field holding a bare day
            "1969-07-20T20:17:00Z",         // pre-epoch
            "", "   ", "not a date", "2026-13-01T00:00:00Z", "20260724T100000Z",
        ] {
            XCTAssertEqual(DateCoding.date(input), referenceDateCoding(input),
                           "reading \(input.debugDescription)")
        }
    }

    /// Where the new reader is *more* forgiving than the old one. Every difference
    /// runs this way — it accepts more, never less — which for a format people edit
    /// by hand is the direction you want. Asserted so the leniency stays deliberate
    /// rather than becoming something that quietly regresses either way.
    func testAcceptsMoreThanTheOldReader() {
        // Fractional seconds: the old formatter had no `.withFractionalSeconds`.
        // The fraction is kept, not dropped, so compare the interval — the two
        // `Date`s print identically because `description` stops at seconds.
        let whole = DateCoding.date("2026-07-24T10:00:00Z")
        let fractional = DateCoding.date("2026-07-24T10:00:00.500Z")
        XCTAssertEqual(fractional?.timeIntervalSince(whole ?? .distantPast), 0.5)
        XCTAssertNil(referenceDateCoding("2026-07-24T10:00:00.500Z"))

        // A leap second, which is legal RFC-3339 and the old formatter refused.
        XCTAssertNotNil(DateCoding.date("2016-12-31T23:59:60Z"))
        XCTAssertNil(referenceDateCoding("2016-12-31T23:59:60Z"))

        // An out-of-range hour rolls over rather than failing outright.
        XCTAssertEqual(DateCoding.date("2026-07-24T25:00:00Z"),
                       DateCoding.date("2026-07-25T01:00:00Z"))
        XCTAssertNil(referenceDateCoding("2026-07-24T25:00:00Z"))
    }

    func testDayRejectsWhatItCannotRead() {
        for junk in ["", "2026-7-4", "2026-13-01", "2026-07-32", "garbage"] {
            XCTAssertNil(DateCoding.day(junk), "should reject \(junk.debugDescription)")
        }
    }
}
