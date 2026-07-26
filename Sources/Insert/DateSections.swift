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
    static func relative(_ due: Date?, now: Date = Date()) -> String {
        guard let due else { return "" }
        let cal = Calendar.current
        let dueDay = cal.startOfDay(for: due)
        let today = cal.startOfDay(for: now)
        let diff = cal.dateComponents([.day], from: today, to: dueDay).day ?? 0
        switch diff {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: break
        }
        let f = DateFormatter()
        if diff > 1 && diff < 7 { f.dateFormat = "EEE"; return f.string(from: due) }
        if diff < -1 && diff > -7 { f.dateFormat = "EEE"; return "Last " + f.string(from: due) }
        f.dateFormat = "MMM d"
        return f.string(from: due)
    }
}
