import AppKit

/// Classic AppKit application delegate. Keeps the app a regular (Dock-visible)
/// app and starts the storage housekeeping.
///
/// Nothing here touches `NSApp.appearance`: Insert follows the system appearance
/// and no longer offers a per-app override (see `GeneralSettingsTab`).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keeps housekeeping honest in a window that stays open for days: without it,
    /// it would only ever happen at launch.
    private var housekeepingTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before any window exists, so the split view restores the corrected value
        // and the first frame drawn is already the right width.
        Self.sanitizeSidebarWidth()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Self.runHousekeeping()
        Self.normalizeSidebarWidth()

        housekeepingTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in Self.runHousekeeping() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        housekeepingTimer?.invalidate()
    }

    /// Set once this install's sidebar has been moved to the current default width,
    /// so that only ever happens on one launch.
    ///
    /// The width is *in the key* so it invalidates itself: change
    /// `idealSidebarWidth` and every install normalizes once more to the new value,
    /// which is what "the default moved" should mean. A fixed key would have to be
    /// renamed by hand each time, and silently does nothing if you forget.
    private static var sidebarWidthNormalizedKey: String {
        "sidebarWidthNormalized-\(Int(Metrics.idealSidebarWidth))"
    }

    /// Corrects an autosaved sidebar width, so a window reopens at
    /// `Metrics.idealSidebarWidth` rather than at whatever an older build left.
    ///
    /// `NavigationSplitView` persists its column widths through AppKit's split-view
    /// autosave, under `NSSplitView Subview Frames <window>, <split view>`, and that
    /// restored width *wins* over the `min:` of `navigationSplitViewColumnWidth`.
    /// Which is how a 158pt sidebar came back on every launch and truncated project
    /// names to "Everyt…" while the `min:` never got a say. So the saved value is
    /// where this has to be fixed; raising the `min:` alone changes nothing.
    ///
    /// Rewriting the width rather than deleting the key is the deliberate half:
    /// what AppKit restores is the sidebar's width, and it recomputes the detail
    /// column regardless (the stale entry here claimed 900pt of a 900pt window), so
    /// writing the width we want is exactly as reliable as the bug was.
    ///
    /// It runs in two modes, and the reason is that the default moved. On the launch
    /// after a new `idealSidebarWidth` ships, every saved width is reset; afterwards
    /// only widths below the minimum are corrected, so a divider the user drags
    /// stays where they put it.
    ///
    /// This is the *first* half of the fix and not the reliable one — see
    /// `normalizeSidebarWidth()`, which sets the flag.
    private static func sanitizeSidebarWidth() {
        let defaults = UserDefaults.standard
        let firstRun = !defaults.bool(forKey: sidebarWidthNormalizedKey)

        for (key, value) in defaults.dictionaryRepresentation()
        where key.hasPrefix("NSSplitView Subview Frames") {
            // One "x, y, w, h, collapsed, ?" string per column; sidebar first.
            guard var frames = value as? [String], let sidebar = frames.first else { continue }

            var fields = sidebar.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard fields.count >= 4, let width = Double(fields[2]) else { continue }
            guard firstRun || width < Metrics.minSidebarWidth else { continue }
            guard width != Metrics.idealSidebarWidth else { continue }

            fields[2] = String(format: "%f", Metrics.idealSidebarWidth)
            frames[0] = fields.joined(separator: ", ")
            defaults.set(frames, forKey: key)
        }
    }

    /// The second half: set the width on the live split view, and only then record
    /// that this install has been normalized.
    ///
    /// `sanitizeSidebarWidth()` alone loses a race that `./build.sh run` runs into
    /// every time. It `pkill`s the old copy and waits for the process to leave the
    /// process list, but a terminating AppKit app flushes its split-view autosave
    /// through `cfprefsd` asynchronously — so the *old* instance's width can land
    /// after the new instance has already written the corrected one, and the new
    /// window comes up at the old width regardless. Which is exactly what happened:
    /// the flag was set, and the sidebar still reopened at 340pt.
    ///
    /// The view can't be raced. So the defaults write stays (it makes the first
    /// frame correct, with no visible jump) and this backs it up (it makes the width
    /// correct, full stop). AppKit then autosaves what it finds, so the two agree
    /// from the next launch on.
    ///
    /// The flag is set here rather than in the pre-pass so that a launch which never
    /// finds a window doesn't count — it'll be retried next time instead of leaving
    /// the sidebar wrong forever. `attemptsLeft` exists because a SwiftUI
    /// `WindowGroup` window isn't guaranteed to exist yet at
    /// `applicationDidFinishLaunching`.
    @MainActor
    private static func normalizeSidebarWidth(attemptsLeft: Int = 20) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: sidebarWidthNormalizedKey) else { return }

        if let split = NSApp.windows.lazy.compactMap({ splitView(in: $0.contentView) }).first {
            let sidebar = split.arrangedSubviews[0]
            if abs(sidebar.frame.width - Metrics.idealSidebarWidth) > 0.5 {
                split.setPosition(Metrics.idealSidebarWidth, ofDividerAt: 0)
            }
            defaults.set(true, forKey: sidebarWidthNormalizedKey)
            return
        }

        guard attemptsLeft > 0 else {
            // No window ever appeared to correct. Take the pre-pass's word for it
            // rather than retrying on every future launch, which would fight the
            // user's own divider forever.
            defaults.set(true, forKey: sidebarWidthNormalizedKey)
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            normalizeSidebarWidth(attemptsLeft: attemptsLeft - 1)
        }
    }

    /// The window's column split view: the first one with something on both sides of
    /// a divider, so a lone `NSSplitView` wrapping one pane can't match.
    @MainActor
    private static func splitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let split = view as? NSSplitView, split.arrangedSubviews.count >= 2 { return split }
        for subview in view.subviews {
            if let found = splitView(in: subview) { return found }
        }
        return nil
    }

    /// Clears out completed tasks that have outlived the retention setting.
    @MainActor
    private static func runHousekeeping() {
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
