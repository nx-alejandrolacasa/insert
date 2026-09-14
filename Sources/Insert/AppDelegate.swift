import AppKit
import SwiftUI

/// Classic AppKit application delegate. Keeps the app a regular (Dock-visible)
/// app, applies the saved appearance and starts the storage housekeeping.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keeps housekeeping honest in a window that stays open for days: without it,
    /// it would only ever happen at launch.
    private var housekeepingTimer: Timer?

    /// Re-renders the themed Dock icon when the effective appearance flips —
    /// the system turning over in Auto, or the Mode picker — since the icon is
    /// drawn once under the appearance in effect (see `ThemedAppIcon`). A theme
    /// *change* re-applies from `SettingsStore.theme` instead.
    private var appearanceObservation: NSKeyValueObservation?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before anything measures or draws in a bundled face — Grotesk is the
        // default for a new install, and an unregistered family resolves to the
        // system font, so a late registration would have the first frame laid
        // out in the wrong metrics.
        BundledFonts.register()
        // Before any window exists, so the split view restores the corrected value
        // and the first frame drawn is already the right width.
        Self.sanitizeSidebarWidth()
        // Same reason: set the appearance before the first frame, or a Light /
        // Dark override lands as a visible flash on every launch.
        SettingsStore.shared.applyAppearance()
        // Insert is a one-window app: nothing here opens a second main window,
        // so AppKit's automatic window tabbing only contributed "Show Tab Bar"
        // / "Show All Tabs" to the View menu — commands with nothing to do.
        // Turning tabbing off is also what removes them from the menu.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // After the activation policy, so the Dock tile exists to take it.
        ThemedAppIcon.apply(SettingsStore.shared.theme)
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in ThemedAppIcon.apply(SettingsStore.shared.theme) }
        }
        MarkdownReturn.install()
        // A no-op unless the `layoutProbe` default is set — see `LayoutProbe`.
        LayoutProbe.start()
        TaskReminder.shared.start()
        DayClock.shared.start()
        Self.runHousekeeping()
        Self.normalizeSidebarWidth()
        // Quiet daily update check; if a newer release exists, the menu-bar
        // dropdown and Settings → About offer the update.
        Task { await UpdateChecker.shared.checkAutomatically() }

        housekeepingTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in Self.runHousekeeping() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        housekeepingTimer?.invalidate()
        // Disk writes are queued off the main thread; a quit must not outrun them.
        Library.shared.flushDiskWrites()
    }

    /// Where the split view is policed and the focused editor is told whether to
    /// check spelling, once per update cycle.
    ///
    /// It has to be *repeated*, not done once at launch: AppKit resets the split
    /// view item as columns collapse and on a second window. (The toolbar's glass
    /// was flattened and its title re-fonted here too, until the toolbar went in
    /// September 2026.)
    ///
    /// `applicationDidUpdate` fires after each event, so this is on the hot path.
    /// It's kept cheap by stopping the sidebar walk at the first split view — which
    /// sits just inside the content view — and by touching nothing already
    /// constrained.
    ///
    /// Spell checking rides the same tick for a related reason: focus moves
    /// between a card's title and its body, and between one card and the next,
    /// with no notification to hang it on — see `SpellChecking`, which reads the
    /// first responder and writes only what's about to change.
    func applicationDidUpdate(_ notification: Notification) {
        Self.configureSplitViews()
        SpellChecking.applyToFocusedEditors()
    }

    /// The windows `applicationDidUpdate` may reach into: **the app's own, and no
    /// other.** One predicate, so a second pass can't get it wrong — which is what
    /// had happened when the toolbar pass gated on the toolbar alone.
    ///
    /// A title bar is what separates the document window from the chromeless ones —
    /// the menu-bar extra's window, every popover, the command palette — which have
    /// no column split view to police and which `splitView(in:)` would otherwise
    /// visit in full before answering nil, per event. It used to be the toolbar,
    /// and the main window has none since September 2026. Settings is titled and
    /// is excluded by name, since its form is not the column split view.
    @MainActor
    private static var restylableWindows: [NSWindow] {
        NSApp.windows.filter {
            $0.styleMask.contains(.titled) && !SettingsWindowController.shared.owns($0)
        }
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
    /// only widths *outside* the range are corrected, so a divider the user drags
    /// stays where they put it. Out-of-range is now both ends: a build before
    /// `constrainSidebarWidth(in:)` could autosave a sidebar dragged to 1,100pt, and
    /// letting that restore would give a correct window one wrong first frame.
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

            // Too narrow goes back to the default; too wide is clamped to the
            // maximum instead, because a wide sidebar is a width someone chose and
            // only the excess needs taking off.
            let corrected: Double
            if firstRun || width < Metrics.minSidebarWidth {
                corrected = Metrics.idealSidebarWidth
            } else if width > Metrics.maxSidebarWidth {
                corrected = Metrics.maxSidebarWidth
            } else {
                continue
            }
            guard width != corrected else { continue }

            fields[2] = String(format: "%f", corrected)
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
    /// scene's window isn't guaranteed to exist yet at
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

    /// Holds the sidebar's resize range on the live split view, because the
    /// `min:`/`max:` of `navigationSplitViewColumnWidth` don't police the *divider*.
    ///
    /// Observed: with `min: 200, ideal: 200, max: 460` on `ProjectsSidebar`, the
    /// divider could still be dragged out to most of the window's width, leaving the
    /// notes and tasks columns a few characters wide. The `min:` is already known not
    /// to police a restored width (`sanitizeSidebarWidth()`); this is the same gap
    /// met from the other side, and the modifier stays because it is still what sets
    /// the *ideal*. Why SwiftUI's values don't reach the divider is untested — don't
    /// repeat a mechanism for it.
    ///
    /// `NSSplitViewItem`'s two thicknesses are the AppKit lever, and they're the
    /// right kind of one: they become layout constraints, so a drag *stops* at the
    /// bound instead of snapping back from past it.
    ///
    /// It rides `applicationDidUpdate` — AppKit gives no notification for any of
    /// this — so a second window, or a SwiftUI update that resets the item, is
    /// covered without needing to know when either happens. Whether once would do was not
    /// established. It's idempotent by comparison rather than by remembering, since
    /// assigning a thickness re-runs the split view's layout.
    @MainActor
    private static func constrainSidebarWidth(in split: NSSplitView) {
        guard let controller = split.delegate as? NSSplitViewController,
              let sidebar = controller.splitViewItems.first,
              // Nothing to police while the column is away: there is no divider to
              // drag, and the next update tick re-asserts the range as it reopens,
              // long before anyone can reach for one. What that buys is that our
              // writes stay out of the collapse, where assigning a thickness
              // re-runs the split view's layout underneath AppKit's own peek — see
              // `disableSidebarPeek(in:)`.
              !sidebar.isCollapsed
        else { return }

        if sidebar.minimumThickness != Metrics.minSidebarWidth {
            sidebar.minimumThickness = Metrics.minSidebarWidth
        }
        if sidebar.maximumThickness != Metrics.maxSidebarWidth {
            sidebar.maximumThickness = Metrics.maxSidebarWidth
        }
    }

    /// The split view's two corrections, so the hot path walks for it once.
    ///
    /// "Once" now means once per *window*, not once per tick: only the main
    /// window has a column split view to police, and `splitView(in:)` visits
    /// **every** view of a window that has none — the Settings form, the
    /// menu-bar extra, each open popover — before answering nil, per event.
    /// `restylableWindows` drops all of those, and a found split view is
    /// remembered weakly so the walk doesn't repeat while it lives.
    @MainActor
    private static func configureSplitViews() {
        for window in restylableWindows {
            guard let split = columnSplitView(in: window) else { continue }
            constrainSidebarWidth(in: split)
            disableSidebarPeek(in: split)
        }
    }

    /// Weak on both sides, so neither a closed window nor a torn-down split view
    /// is kept alive by the memo. Validated against the window before use — a
    /// split view SwiftUI has replaced answers `window == nil` and is re-found.
    @MainActor
    private static let splitViews = NSMapTable<NSWindow, NSSplitView>.weakToWeakObjects()

    @MainActor
    private static func columnSplitView(in window: NSWindow) -> NSSplitView? {
        if let cached = splitViews.object(forKey: window), cached.window === window {
            return cached
        }
        guard let found = splitView(in: window.contentView) else { return nil }
        splitViews.setObject(found, forKey: window)
        return found
    }

    /// AppKit's own accessor for the invisible view that watches the collapsed
    /// sidebar's edge. Private, so it is asked for rather than assumed.
    private static let collapsedInteractionsView = Selector(("_leadingCollapsedInteractionsView"))

    /// Takes AppKit's hover-**peek** off the collapsed sidebar, because *cancelling*
    /// one segfaults.
    ///
    /// 0.13.0 crashed on open → close → open of the projects column, with no frame
    /// of Insert's on the stack: `-[_NSSplitViewCollapsedInteractionsView
    /// mouseExited:]` → `-[NSSplitView _cancelProactivePeek]`, `EXC_BAD_ACCESS` at
    /// 0x59. The faulting instruction is `ldrb w8, [x0, #0x59]` with x0 nil — a BOOL
    /// read off a pointer the call before it handed back nil for — and three
    /// instructions earlier AppKit *had* nil-checked the peek state it loaded
    /// (`cbz x0`). So the peek existed and one of its parts was already gone; `x15`
    /// held `NSSplitViewPeekingViewParams`, which is the part.
    ///
    /// What makes it an ordinary gesture rather than an exotic one: the peek's
    /// sensitive zone is the window's leading edge, which is where the "show" button
    /// sits. Hovering it starts a peek, clicking it expands the column for real and
    /// supersedes that peek, and the pointer leaving afterwards is what cancels a
    /// peek whose params have gone. That sequence is a reading of the trace and the
    /// repro, not something instrumented — don't repeat the ordering as fact.
    ///
    /// Nothing on our side can make AppKit's nil-deref safe, and there is no public
    /// API for any of the peek (`_beginProactivePeekAtLocation:`,
    /// `_proactivePeekParams`, `_canDoSidebarProactivePeek` are all private), so the
    /// path is removed instead: `mouseExited:` arrives through an `NSTrackingArea`,
    /// and a view with none gets no enter or exit at all. **The cost is deliberate**
    /// — hovering the leading edge no longer slides the collapsed projects column
    /// out. Insert has a header glyph, a menu item and ⌘§ for that, and a crash on
    /// the third click of a common gesture is worth more than an affordance.
    ///
    /// It rides `applicationDidUpdate` because AppKit posts nothing for it: it
    /// builds the interactions view as a column collapses and re-adds its tracking
    /// areas from `updateTrackingAreas`, so this is repeated rather than done once.
    /// And it asks the split view for the view rather than matching a private class
    /// name down the hierarchy, so an AppKit that no longer has one is a no-op —
    /// the same trade every reach past the public API here makes.
    @MainActor
    private static func disableSidebarPeek(in split: NSSplitView) {
        guard split.responds(to: collapsedInteractionsView),
              let peek = split.perform(collapsedInteractionsView)?.takeUnretainedValue() as? NSView,
              !peek.trackingAreas.isEmpty
        else { return }

        for area in peek.trackingAreas { peek.removeTrackingArea(area) }
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
        Task {
            await Library.shared.purgeCompletedTasks(
                retention: SettingsStore.shared.doneTaskRetention
            )
        }
    }

    /// The red button closes the window, not the app: Insert lives on in the
    /// menu bar (and the Dock), and the SwiftUI lifecycle would otherwise
    /// terminate on the last window closing. Quit stays where it is — ⌘Q and
    /// the menu-bar extra's own item.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
