import SwiftUI

/// The timestamp line at the foot of a note or task card:
///
///     ✦ 12 Jun 2025 • 09:14  ·  ✎ 15:02
///
/// Which stamps appear is a `CardDates` setting, one per card kind (Settings →
/// Notes / Tasks). Icons rather than prose — "Created on X · Updated on Y" says
/// the same thing in four more words per card — with the wording kept for the
/// spoken label, where the glyphs don't reach. ✦ (sparkles) is "newly made",
/// ✎ the edit.
///
/// Each stamp is **as compact as its date allows**: today is the time alone
/// ("17:39"), this year drops the year ("28 Jul · 17:39"), and only another
/// year spells it out ("25 Dec 2025 · 9:30").
struct CardDatesFooter: View {
    enum Kind { case note, task }

    let kind: Kind
    let created: Date
    let updated: Date

    @Environment(SettingsStore.self) private var settings
    /// Read so "today" stays today: the compaction below is a comparison against
    /// the current day, and without this a card left on screen overnight kept
    /// yesterday's stamps in today's shorthand. See `DayClock`.
    @Environment(DayClock.self) private var clock

    var body: some View {
        if showCreated || showUpdated {
            HStack(spacing: 4) {
                if showCreated {
                    segment(icon: "sparkles", date: created)
                }
                if showCreated && showUpdated {
                    Text("·")
                }
                if showUpdated {
                    segment(icon: "pencil", date: updated)
                }
            }
            // Mono (see `Mono`), because a timestamp is a *value*: the minute
            // ticks over under you, and in a proportional face "11:59" is
            // narrower than "12:00", so the whole footer shuffles sideways as
            // it changes. The same face draws the band's counts and the type
            // labels, for the same reason.
            //
            // The **format is unchanged**, deliberately, and this is the one
            // place the plan was not followed: it specifies `DD.MM HH:mm`, which
            // would undo the footer's own compaction — today is the time alone,
            // this year drops the year, another year spells it out — and lose
            // the year on an old note entirely. The mono face was the part of
            // that spec that was about the face; the rest was about a format
            // this app had already solved (see `dayPart(of:now:)` and
            // `CardDateCompactionTests`).
            .font(Mono.font(.caption2))
            // The theme's metadata colour, not `.tertiary`: a timestamp is
            // metadata, and the refresh's floor for text under 14px is 4.5:1
            // against the card it's painted on (CLAUDE.md decision 5) — tertiary
            // label colour is nowhere near it. Themed, because the card ground
            // is: it is the page hue at 50% L in Light and 70% in Dark, solved
            // on the face it lands on (`AppTheme.metaText`).
            .foregroundStyle(settings.theme.metaText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
        }
    }

    private var display: CardDates {
        switch kind {
        case .note: settings.noteCardDates
        case .task: settings.taskCardDates
        }
    }

    /// "Edited" is judged at the minute the footer displays, so a card whose
    /// timestamps differ only by the save that created it still counts as fresh.
    private var edited: Bool { abs(updated.timeIntervalSince(created)) >= 60 }

    private var showCreated: Bool { display.showsCreated(edited: edited) }
    private var showUpdated: Bool { display.showsUpdated(edited: edited) }

    private func segment(icon: String, date: Date) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            if let day = Self.dayPart(of: date, now: clock.today) {
                // A plain `·` between date and time — the lists' drawn dot was
                // tried here and read too heavy at this size (the opposite
                // verdict from the lists' own: a bullet leads a line, a
                // separator should disappear into one).
                Text("\(day) · \(date, format: Self.timeFormat)")
            } else {
                Text(date, format: Self.timeFormat)
            }
        }
    }

    /// The date half of a stamp: `nil` for today (the time alone says it),
    /// day-and-month within the current year, the year added beyond it.
    /// `now` is injectable so the two boundaries — midnight and New Year —
    /// are testable; the view passes `DayClock`'s day, so crossing either
    /// re-renders. Pinned by `CardDateCompactionTests`.
    static func dayPart(of date: Date, now: Date = Date()) -> String? {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return nil }
        let sameYear = cal.component(.year, from: date) == cal.component(.year, from: now)
        return date.formatted(sameYear ? dayFormat : dayYearFormat)
    }

    /// Spoken in full whatever the compaction shows: "edited at 17:39" without
    /// the day only works when you can see which card today's stamps sit on.
    private var spokenLabel: String {
        var parts: [String] = []
        if showCreated { parts.append("Created \(created.formatted(Self.fullFormat))") }
        if showUpdated { parts.append("Edited \(updated.formatted(Self.fullFormat))") }
        return parts.joined(separator: ", ")
    }

    // All through the app's English locale — never `Locale.current`.
    private static let timeFormat: Date.FormatStyle = .dateTime
        .hour().minute().locale(Formatting.locale)
    private static let dayFormat: Date.FormatStyle = .dateTime
        .day().month().locale(Formatting.locale)
    private static let dayYearFormat: Date.FormatStyle = .dateTime
        .day().month().year().locale(Formatting.locale)
    private static let fullFormat: Date.FormatStyle = .dateTime
        .month().day().year().hour().minute().locale(Formatting.locale)
}
