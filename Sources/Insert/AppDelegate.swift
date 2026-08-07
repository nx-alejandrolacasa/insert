import AppKit
import SwiftUI

/// The flat capsule that stands in for the search field's glass platter — the same
/// `Stone.control` fill and `Stone.line` hairline as `FlatButtonStyle`, so the
/// toolbar's field and the window's flat buttons read as one material, which is
/// what they were meant to do as glass.
///
/// Drawn in `draw(_:)` rather than set as a `layer.backgroundColor` so the colours
/// resolve against the *current* appearance every time: a `CGColor` is a resolved
/// shade and would need re-setting on every Light/Dark switch.
private final class FlatToolbarCapsule: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let capsule = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                                  xRadius: radius, yRadius: radius)
        NSColor(Stone.control).setFill()
        capsule.fill()
        NSColor(Stone.line).setStroke()
        capsule.lineWidth = 0.5
        capsule.stroke()
    }
}

/// Classic AppKit application delegate. Keeps the app a regular (Dock-visible)
/// app, applies the saved appearance and starts the storage housekeeping.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Keeps housekeeping honest in a window that stays open for days: without it,
    /// it would only ever happen at launch.
    private var housekeepingTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
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
        MarkdownReturn.install()
        TaskReminder.shared.start()
        DayClock.shared.start()
        Self.runHousekeeping()
        Self.normalizeSidebarWidth()

        housekeepingTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in Self.runHousekeeping() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        housekeepingTimer?.invalidate()
    }

    /// Where the toolbar's glass is flattened and the focused editor is told
    /// whether to check spelling, once per update cycle.
    ///
    /// It has to be *repeated*, not done once at launch: AppKit rebuilds the platter
    /// behind a toolbar item as the item changes — the search field expanding,
    /// taking and losing focus — and on an appearance change or a second window.
    ///
    /// `applicationDidUpdate` fires after each event, so this is on the hot path.
    /// It's kept cheap by walking only the titlebar (a few dozen views, and the
    /// content view is skipped outright) and by touching nothing already flat.
    ///
    /// Spell checking rides the same tick for a related reason: focus moves
    /// between a card's title and its body, and between one card and the next,
    /// with no notification to hang it on — see `SpellChecking`, which reads the
    /// first responder and writes only what's about to change.
    func applicationDidUpdate(_ notification: Notification) {
        Self.flattenToolbarGlass()
        SpellChecking.applyToFocusedEditors()
    }

    /// Replaces the Liquid Glass platter behind the toolbar's search field with a
    /// flat capsule, because the glass draws an elevation the window has nowhere
    /// else (see the shadows note in CLAUDE.md).
    ///
    /// **This is the one place in the app that reaches past the public API**, and
    /// what's worth knowing is *why it has to*. `NSGlassEffectView` is public in
    /// macOS 26 and offers `cornerRadius`, `tintColor` and a `style` — and nothing
    /// about elevation. The shadow isn't a `CALayer` shadow either: dumping the whole
    /// titlebar's view *and* layer tree turned up no `shadowOpacity` anywhere in it
    /// (the only shadowed layers in the app belong to the menu-bar extra's window),
    /// so it's painted inside the glass renderer and there is nothing to switch off.
    /// An earlier pass that zeroed every layer shadow in the titlebar therefore did
    /// exactly nothing, which is how this got here.
    ///
    /// What makes it tractable is that the glass is a **platter behind the field, not
    /// the field's background**: `NSToolbarPlatterView` holds the
    /// `NSGlassEffectView`, while the field itself lives in a separate
    /// `NSSearchToolbarItemView` under its own item viewer. So the platter can be
    /// hidden and a flat capsule put in its place without touching the field, which
    /// stays the system's — and keeps ⌘F, Escape-to-clear and the search item's
    /// collapse behaviour that a hand-built `TextField` would have cost.
    ///
    /// The trade: **nothing here is contractual.** It matches on `NSGlassEffectView`,
    /// which is at least public, and assumes no depth — but if a macOS release stops
    /// putting a glass view behind the field, or renders the platter some other way,
    /// the capsule simply doesn't get installed. That failure is visible and benign:
    /// the glass, and its shadow, come back. Nothing crashes and nothing is lost.
    ///
    /// **The content view is skipped**, which is load-bearing rather than an
    /// optimisation: the projects sidebar is Liquid Glass too, and it's meant to stay
    /// glass. Only the titlebar band is touched.
    @MainActor
    private static func flattenToolbarGlass() {
        for window in NSApp.windows where window.toolbar != nil {
            // The frame view owns both the titlebar container and the content view;
            // start there and skip the latter.
            guard let frame = window.contentView?.superview else { continue }
            flattenGlass(in: frame, skipping: window.contentView)
        }
    }

    @MainActor
    private static func flattenGlass(in view: NSView, skipping content: NSView?) {
        if view === content { return }
        if let glass = view as? NSGlassEffectView {
            replace(glass)
            // Its subviews are the platter's own content holder, never the field's,
            // so there's nothing below this worth walking.
            return
        }
        for subview in view.subviews { flattenGlass(in: subview, skipping: content) }
    }

    /// Hides one glass platter and puts a `FlatToolbarCapsule` in its place, once.
    ///
    /// The capsule is a sibling rather than a subview of the glass: a hidden view
    /// doesn't draw its children either, so anything parented to the platter would
    /// go with it.
    @MainActor
    private static func replace(_ glass: NSGlassEffectView) {
        guard let host = glass.superview else { return }
        if !glass.isHidden { glass.isHidden = true }

        if let existing = host.subviews.first(where: { $0 is FlatToolbarCapsule }) {
            // The platter is re-laid-out as the field resizes; follow it. (The
            // autoresizing mask covers the common case, this covers the rest.)
            if existing.frame != glass.frame { existing.frame = glass.frame }
            return
        }

        let capsule = FlatToolbarCapsule(frame: glass.frame)
        capsule.autoresizingMask = [.width, .height]
        host.addSubview(capsule, positioned: .below, relativeTo: glass)
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
