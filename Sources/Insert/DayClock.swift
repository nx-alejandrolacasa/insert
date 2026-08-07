import AppKit

/// Today, as observable state.
///
/// Several labels in the app are a comparison against *now* made while a view
/// renders: the due badge's "Today" / "Yesterday" / "3 days ago" and the red it
/// turns when a task is genuinely overdue, the card footer's compaction of a
/// stamp to the time alone, and the tasks column's Overdue / Today / Tomorrow
/// window. Nothing about the passage of time reaches SwiftUI, so all of them
/// were only as fresh as the last unrelated edit — a task due yesterday still
/// read "Today" the morning after, until typing in some other card rebuilt the
/// column.
///
/// So the day itself becomes state. The functions behind those labels already
/// take an injectable `now` (it is how they're tested); the views stop letting
/// it default to `Date()` and pass `clock.today` instead, which registers the
/// read and re-renders them the moment the day turns over.
@MainActor
@Observable
final class DayClock {
    static let shared = DayClock()

    /// The start of the current day.
    ///
    /// A day rather than an instant, and that is what makes this cheap: every
    /// label it feeds reduces `now` to `startOfDay` anyway, so publishing the
    /// minute would re-render every card on screen sixty times an hour to say
    /// exactly the same words.
    private(set) var today = Calendar.current.startOfDay(for: Date())

    private var timer: Timer?

    /// Starts the clock. Called once at launch.
    func start() {
        guard timer == nil else { return }
        tick()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in DayClock.shared.tick() }
        }
        // Nothing here needs a punctual minute; let the system coalesce the wake-up.
        timer.tolerance = 15
        self.timer = timer

        // …and catch up the moment someone comes back to look, rather than
        // leaving the minute the tick is worth on screen at exactly the moment
        // it is being read. Both cases are the one this was reported from: a Mac
        // that spent the night with Insert open, met again in the morning. The
        // window is *not* the granularity — a lid opened on a frontmost Insert
        // activates nothing, so the workspace's wake is what covers it, and an
        // app switched to from another one is what activation covers.
        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
    }

    /// The tick is idempotent and guarded, so an extra source of them costs a
    /// comparison and can never double-publish.
    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        center.addObserver(forName: name, object: nil, queue: nil) { _ in
            Task { @MainActor in DayClock.shared.tick() }
        }
    }

    /// Asks whether the day has turned over — every minute, and again whenever the
    /// app is activated or the machine wakes — rather than being aimed at midnight — `TaskReminder`'s argument, for the same three
    /// reasons: a timer aimed at a moment has to be re-aimed on wake from sleep,
    /// on a timezone change and on a clock change, where a comparison against
    /// `Date()` is right through all three by construction.
    ///
    /// The assignment is guarded because `@Observable` publishes on write, not on
    /// change: without it every minute would re-render every card in the window.
    /// With it, the 1,439 ticks a day that aren't midnight cost one comparison.
    private func tick() {
        let start = Calendar.current.startOfDay(for: Date())
        if start != today { today = start }
    }
}
