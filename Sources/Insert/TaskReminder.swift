import AppKit
import UserNotifications
import os

private let log = Logger(subsystem: "com.alejandrolacasa.insert", category: "Reminder")

/// When the daily reminder is due, and what it says — date arithmetic and one
/// sentence, with nothing around them.
///
/// Split out from `TaskReminder` for the same reason `MarkdownFormatting` is split
/// out of the editors: the interesting part is a decision over dates, and a
/// decision over dates can be tested at any hour of any day without a notification
/// centre, a timer or a granted permission. `ReminderScheduleTests` pins it.
enum ReminderSchedule {
    /// How late the reminder may still arrive.
    ///
    /// A reminder is only worth having if it lands in the morning, but the machine
    /// it runs on sleeps: a Mac woken at 09:40 should still say what the day holds,
    /// and one woken at 16:00 should not — by then the day is the thing being
    /// reminded about. Two hours is the line, and it is the only reason `isDue`
    /// takes `now` rather than firing on a timer aimed at the exact minute.
    static let grace: TimeInterval = 2 * 3600

    /// The reminder's moment on the day `now` falls in.
    ///
    /// Built from explicit components rather than
    /// `Calendar.date(bySettingHour:minute:second:of:)`, which resolves the *next*
    /// matching time and would answer "tomorrow at 09:00" for a `now` of 14:00 —
    /// exactly the case `isDue` has to answer "not due" for.
    static func time(_ minutes: Int, on now: Date, calendar: Calendar = .current) -> Date? {
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        parts.second = 0
        return calendar.date(from: parts)
    }

    /// Whether the reminder for `now`'s day is owed: the time has come, it hasn't
    /// come and gone (see `grace`), and today hasn't been reminded about already.
    ///
    /// `lastNotified` is a date rather than a flag so the comparison is "is that the
    /// same day as this", which is the only thing that makes an app relaunched
    /// mid-morning stay quiet. It is stamped whether or not a notification went
    /// out — see `TaskReminder.check()`.
    static func isDue(
        now: Date,
        minutes: Int,
        lastNotified: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let due = time(minutes, on: now, calendar: calendar) else { return false }
        guard now >= due, now.timeIntervalSince(due) < grace else { return false }
        if let lastNotified, calendar.isDate(lastNotified, inSameDayAs: now) { return false }
        return true
    }

    /// The reminder's one line. Deliberately says nothing about *which* tasks:
    /// a notification is read on a lock screen and over someone's shoulder, and a
    /// count is the most it can say that is always safe to show.
    ///
    /// Written as a ternary rather than with Foundation's `^[…](inflect: true)`
    /// markup, which needs a `Text` or a localized string to resolve and would
    /// otherwise reach the user verbatim. The app is English only, so agreeing one
    /// noun by hand costs nothing (see `Formatting`).
    static func message(taskCount count: Int) -> String {
        count == 1 ? "You have 1 task for today." : "You have \(count) tasks for today."
    }
}

/// The daily "you have N tasks for today" notification.
///
/// **It only arrives while Insert is running**, and that is the deliberate half of
/// the design rather than a limitation to fix later. The alternative is a
/// `UNCalendarNotificationTrigger`, which the system delivers whether the app is
/// running or not — but a trigger's *content* is fixed when the request is added,
/// so the count would be however many tasks were due when it was scheduled. Two
/// things make that unfixable rather than merely stale: a task due tomorrow becomes
/// a task due today at midnight, with nothing happening in the app to re-schedule
/// on, and a reminder that overstates the day's work is worse than no reminder.
/// So the count is computed at the moment it is delivered, which means someone has
/// to be there to compute it. Insert is a menu-bar app that stays open; that's the
/// trade.
///
/// The timer therefore ticks every minute and *asks* whether the reminder is owed,
/// rather than being aimed at the reminder's exact minute. A timer aimed at 09:00
/// has to be re-aimed on wake from sleep, on a timezone change and on a clock
/// change; a comparison against `Date()` is right through all three by
/// construction, and a minute's granularity is invisible on a morning reminder.
///
/// **Not verified: that a self-signed build can post at all.** `build.sh` signs
/// with a self-signed certificate, falling back to ad-hoc, and notification
/// authorization is one of the things the system can decline on that basis. Nothing
/// here assumes it works — a refused authorization or a rejected `add` is logged and
/// the app is otherwise unaffected — but if the reminder never appears, the
/// signature is the first thing to rule out, not this file.
@MainActor
final class TaskReminder: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TaskReminder()

    /// One identifier for every reminder, so today's replaces yesterday's rather
    /// than stacking up in Notification Center. A message that is only true on the
    /// day it was sent shouldn't be readable a week later.
    private static let identifier = "daily-task-reminder"

    /// Where "today has been reminded about" is kept. In `UserDefaults` rather than
    /// in `SettingsStore`, which is for settings — this is bookkeeping, and it has
    /// to survive a relaunch or quitting the app at 09:05 would earn a second
    /// notification (same reasoning as `AppDelegate`'s sidebar-width flag).
    private static let lastNotifiedKey = "lastTaskReminderDate"

    private let center = UNUserNotificationCenter.current()
    private var timer: Timer?

    /// Call once at launch. Installs the delegate — needed for the banner to appear
    /// while Insert is the frontmost app, which a morning reminder often finds it —
    /// and starts the clock.
    func start() {
        center.delegate = self
        reschedule()
    }

    /// Starts or stops the clock from the current settings.
    ///
    /// Only the on/off setting needs this — `check()` reads the *time* fresh on every
    /// tick, so changing it re-aims nothing.
    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard SettingsStore.shared.dailyReminder else { return }

        check()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in TaskReminder.shared.check() }
        }
        // Nothing here needs a punctual minute; let the system coalesce the wake-up.
        timer.tolerance = 15
        self.timer = timer
    }

    /// Asks for permission, which macOS only prompts for once per install — so this
    /// is called when the setting is switched on rather than at launch, where an
    /// install that never wants reminders would still be asked.
    func requestAuthorization() {
        Task {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                log.error("Notification authorization failed: \(error.localizedDescription)")
            }
        }
    }

    /// One tick: is the reminder owed, and if so does the day have anything in it.
    private func check() {
        let settings = SettingsStore.shared
        guard settings.dailyReminder else { return }
        guard ReminderSchedule.isDue(
            now: Date(),
            minutes: settings.reminderMinutes,
            lastNotified: lastNotified
        ) else { return }

        // Only tasks due *today*, which is the same bucket the menu bar labels
        // "Today" — overdue work is deliberately not counted in, so the sentence
        // says exactly what it means. `make` skips completed tasks.
        let count = DateSections.make(from: Library.shared.tasks).today.count

        // Stamped even when the day is clear, so this is a reminder that happened
        // and had nothing to say rather than one still waiting to fire. Without it,
        // dating a task for today at 10:30 would earn an unprompted notification
        // seconds later, from a feature the user thinks of as a morning thing.
        lastNotified = Date()
        guard count > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Today’s tasks"
        content.body = ReminderSchedule.message(taskCount: count)
        content.sound = .default

        // `trigger: nil` delivers immediately. The timing was decided above; the
        // notification centre is only being used to draw the banner.
        let request = UNNotificationRequest(
            identifier: Self.identifier, content: content, trigger: nil
        )
        Task {
            do {
                try await center.add(request)
            } catch {
                log.error("Couldn't post the daily reminder: \(error.localizedDescription)")
            }
        }
    }

    private var lastNotified: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastNotifiedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastNotifiedKey) }
    }

    // MARK: - UNUserNotificationCenterDelegate

    // `nonisolated` because the protocol's requirements are: it predates Swift
    // concurrency and carries no actor annotation, so a `@MainActor` method can't
    // witness one. Neither implementation needs the main actor for anything but the
    // window work, which hops for itself.

    /// Show the banner even when Insert is frontmost. The system suppresses
    /// notifications for the active app by default, which for a reminder that
    /// arrives first thing would mean the days it is most likely to be missed are
    /// the days Insert was left open overnight.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Clicking the reminder brings the window forward — the same thing the Dock
    /// icon does with no windows open (see `applicationShouldHandleReopen`), since
    /// the notification is an invitation to come and look at the list.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
