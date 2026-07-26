import Foundation

/// Buckets pending tasks by due date into Overdue / Today / Up Next /
/// Unscheduled — the model behind the menu-bar "at a glance" summary. Mirrors
/// TXTodo's `sectionsByDate`.
struct DateSections {
    var overdue: [TaskItem] = []
    var today: [TaskItem] = []
    var upNext: [TaskItem] = []
    var unscheduled: [TaskItem] = []

    /// Only pending (not done) tasks are considered.
    static func make(from tasks: [TaskItem], now: Date = Date()) -> DateSections {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        var s = DateSections()
        for task in tasks where !task.done {
            guard let due = task.due else { s.unscheduled.append(task); continue }
            let dueStart = cal.startOfDay(for: due)
            if dueStart < todayStart { s.overdue.append(task) }
            else if dueStart == todayStart { s.today.append(task) }
            else { s.upNext.append(task) }
        }
        let byDue: (TaskItem, TaskItem) -> Bool = { a, b in
            (a.due ?? .distantFuture) < (b.due ?? .distantFuture)
        }
        s.overdue.sort(by: byDue)
        s.today.sort(by: byDue)
        s.upNext.sort(by: byDue)
        s.unscheduled.sort { $0.created > $1.created }
        return s
    }

    var totalPending: Int { overdue.count + today.count + upNext.count + unscheduled.count }

    /// The compact menu-bar title, e.g. "2 overdue · 3 today".
    var menuBarTitle: String {
        if !overdue.isEmpty && !today.isEmpty { return "\(overdue.count) overdue · \(today.count) today" }
        if !overdue.isEmpty { return "\(overdue.count) overdue" }
        if !today.isEmpty { return "\(today.count) today" }
        if upNext.count > 0 { return "\(upNext.count) upcoming" }
        if totalPending > 0 { return "\(totalPending) to do" }
        return ""
    }
}

/// Human-friendly relative due label ("Today", "Tomorrow", "Mon", "Aug 3").
enum DueFormat {
    /// A short due label, with every word coming from Foundation rather than
    /// from a literal here.
    ///
    /// This used to concatenate an English `"Last "` onto a locale-formatted
    /// weekday, so a Spanish system read `Last vie`, and it hardcoded
    /// "Today" / "Tomorrow" / "Yesterday" beside that. The day arithmetic was
    /// right, though, and is kept: due dates are whole days (`yyyy-MM-dd`), and
    /// the *instant*-based relative styles are no use for them — asked about a
    /// date at midnight today, they answer "17 hours ago".
    /// `RelativeDateTimeFormatter.localizedString(from:)` takes explicit
    /// components instead, so `day: 0` really is "Today".
    ///
    /// The words come out in `Formatting.locale`, not the system language: the
    /// rest of the UI is English literals, and half-translated labels were the
    /// original complaint.
    static func relative(_ due: Date?, now: Date = Date()) -> String {
        guard let due else { return "" }
        let cal = Calendar.current
        let diff = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: now),
                                      to: cal.startOfDay(for: due)).day ?? 0

        let label = switch diff {
        case -6...1:
            // Named phrasing for anything overdue, today, or tomorrow. Some
            // locales have words English doesn't — Spanish answers "anteayer"
            // for -2 and "pasado mañana" for +2 — which is exactly the reason
            // not to assemble these by hand. Overdue reads as "3 days ago"
            // rather than a bare weekday, which carries the urgency and needs
            // no qualifier to tell it from an upcoming one.
            relativeDays(diff)
        case 2...6:
            // Inside the coming week a weekday is the most scannable, and a
            // future weekday can't be mistaken for a past one.
            due.formatted(.dateTime.weekday(.abbreviated).locale(Formatting.locale))
        default:
            // Beyond that, a date. `.dateTime` orders the components for the
            // locale, which a hardcoded "MMM d" pattern doesn't.
            due.formatted(.dateTime.month(.abbreviated).day().locale(Formatting.locale))
        }
        return sentenceCased(label)
    }

    /// Formatters are built per call: a shared one isn't safe to hold under
    /// Swift 6 strict concurrency.
    private static func relativeDays(_ days: Int) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Formatting.locale
        f.dateTimeStyle = .named
        return f.localizedString(from: DateComponents(day: days))
    }

    /// Lifts the first character the way the locale would.
    ///
    /// Applied to every branch so the badges match each other: Foundation hands
    /// back lowercase relative words ("ayer"), and plenty of locales lowercase
    /// weekday and month names too ("mié"), which looked untidy next to a capped
    /// "Hoy". `MonthCalendar`'s month heading caps itself for the same reason.
    private static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased(with: Formatting.locale) + text.dropFirst()
    }
}
