import AppKit

/// Classic AppKit application delegate. Keeps the app a regular (Dock-visible)
/// app and starts the completed-task housekeeping.
///
/// Nothing here touches `NSApp.appearance`: Insert follows the system appearance
/// and no longer offers a per-app override (see `GeneralSettingsTab`).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keeps the completed-task cleanup honest in a window that stays open for
    /// days: without it, housekeeping would only ever happen at launch.
    private var housekeepingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        purgeCompletedTasks()

        housekeepingTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in
                Library.shared.purgeCompletedTasks(retention: SettingsStore.shared.doneTaskRetention)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        housekeepingTimer?.invalidate()
    }

    @MainActor
    private func purgeCompletedTasks() {
        Library.shared.purgeCompletedTasks(retention: SettingsStore.shared.doneTaskRetention)
    }

    /// Re-open the main window when the Dock icon is clicked with no windows.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
