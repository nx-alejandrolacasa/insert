import Foundation

/// The locale Insert *presents* in, which is English regardless of the system
/// language.
///
/// Every string in the UI is an English literal, so letting Foundation format
/// dates in the system locale produced interfaces in two languages at once: on a
/// Spanish Mac the due badge read "Last vie" and a note titled in English was
/// stamped "25 jul 2026". Anything user-facing formats through here instead.
///
/// `en_GB` rather than `en_US`: English month and weekday names, but day-first
/// dates and Monday-first weeks, which is both what the surrounding region
/// expects and what the rest of the app already assumes — see `WeekStyle`, where
/// a full week ends on Sunday.
///
/// Deliberately **not** used for anything written to disk. `DateCoding` pins
/// `en_US_POSIX` and the Gregorian calendar itself, so the Markdown stays
/// byte-stable whatever this says; changing the value here must never rewrite a
/// file.
enum Formatting {
    static let locale = Locale(identifier: "en_GB")

    /// The user's calendar with the UI locale applied: month and weekday names
    /// come out in English, while the arithmetic and time zone stay theirs.
    ///
    /// Assigning the locale is what re-languages `veryShortWeekdaySymbols`; it
    /// leaves `firstWeekday` alone, and en_GB is Monday-first in any case, so the
    /// calendar grid still starts where people here expect.
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        return calendar
    }
}
