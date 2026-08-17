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
    /// It's kept cheap by walking only the titlebar for the glass and the title (a
    /// few dozen views, and the content view is skipped outright), by stopping the
    /// sidebar walk at the first split view — which sits just inside the content
    /// view — and by touching nothing already flat, already fonted or already
    /// constrained.
    ///
    /// Spell checking rides the same tick for a related reason: focus moves
    /// between a card's title and its body, and between one card and the next,
    /// with no notification to hang it on — see `SpellChecking`, which reads the
    /// first responder and writes only what's about to change.
    func applicationDidUpdate(_ notification: Notification) {
        Self.flattenToolbarGlass()
        Self.restyleWindowTitle()
        Self.constrainSidebarWidth()
        SpellChecking.applyToFocusedEditors()
    }

    /// Draws the toolbar's title — the selected project's name — in the chosen
    /// card face, so the three column headings and the window's own title agree.
    ///
    /// It has to happen out here because that title is **not ours to style**:
    /// `RootView` supplies it as a `String` through `.navigationTitle`, and AppKit
    /// draws it in the titlebar. There is no SwiftUI modifier for its font, and the
    /// obvious workarounds are both worse — hiding it and adding a `Text` in a
    /// toolbar item costs the window its real title (menus, Window menu, Mission
    /// Control, and the `titleVisibility` trap `RootView.WindowProbe` documents),
    /// while interpolating the name into a toolbar item alongside gives two titles.
    /// Re-fonting the field AppKit already made keeps the title a title.
    ///
    /// It rides `applicationDidUpdate` for the same reason `flattenToolbarGlass()`
    /// does: AppKit rebuilds the titlebar as the toolbar lays out, the search field
    /// expands and the title changes with the selection, and there is no
    /// notification for any of it. Kept cheap the same way too — the content view
    /// is skipped, so this walks a few dozen views, and it assigns nothing that is
    /// already right.
    ///
    /// Three things keep it from touching what it shouldn't. **Search fields are
    /// excluded** (`NSSearchField` is an `NSTextField` subclass, so it would
    /// otherwise match, and the search field is meant to stay the system's — the
    /// same exclusion `SpellChecking` makes for the same reason). **The Settings
    /// window is excluded**, since its toolbar has a pane name of its own that is
    /// chrome, not content. And **only the size is preserved, never set**: the
    /// weight is read off the font AppKit chose and handed back, so this changes
    /// the face and nothing else. If no field matches, nothing happens and the
    /// title keeps the system font — benign, like the glass coming back.
    ///
    /// Nothing here is contractual, and that is the trade `flattenToolbarGlass()`
    /// already makes: it matches on `NSTextField`, which is at least the class a
    /// label is, and assumes no depth. If a macOS release draws the title some
    /// other way, the title simply stays on the system font.
    @MainActor
    private static func restyleWindowTitle() {
        let face = SettingsStore.shared.typeface
        for window in NSApp.windows where window.toolbar != nil {
            guard !SettingsWindowController.shared.owns(window),
                  let frame = window.contentView?.superview
            else { continue }
            restyleTitles(in: frame, skipping: window.contentView, typeface: face)
        }
    }

    @MainActor
    private static func restyleTitles(
        in view: NSView,
        skipping content: NSView?,
        typeface: Typeface
    ) {
        if view === content { return }
        if let field = view as? NSTextField, !(field is NSSearchField) {
            apply(typeface, to: field)
        }
        for subview in view.subviews {
            restyleTitles(in: subview, skipping: content, typeface: typeface)
        }
    }

    /// Swaps one label's family, keeping its size and weight.
    ///
    /// Idempotent by **comparing the resolved font to the one already set**, not by
    /// remembering what has been done: the fields are AppKit's and get rebuilt, so
    /// there is nothing durable to mark. Assigning on every tick would re-invalidate
    /// the titlebar sixty times a second, so the comparison is what makes riding
    /// `applicationDidUpdate` affordable.
    ///
    /// It settles after one pass for every option. Under a *system design* the
    /// second pass resolves the design from the face it just set and gets the same
    /// font back; under **Standard** it resolves to the plain system font, which is
    /// what is already there, so the title is left alone — meaning Standard's one
    /// stylistic difference from the chrome (the one-storey `a`) doesn't reach the
    /// title. That is the right trade rather than a gap: the alternative is
    /// assigning a same-named font forever to change one glyph in one short string.
    @MainActor
    private static func apply(_ typeface: Typeface, to field: NSTextField) {
        guard let current = field.font else { return }
        // The weight AppKit picked, read back off the descriptor rather than
        // guessed: the window title is not the plain system weight, and resolving
        // it as regular would make the title lighter as well as differently faced.
        let traits = current.fontDescriptor.object(forKey: .traits)
            as? [NSFontDescriptor.TraitKey: Any]
        let weight = (traits?[.weight] as? CGFloat).map(NSFont.Weight.init(rawValue:))
        let resolved = Card.nsFont(
            size: current.pointSize, weight: weight, typeface: typeface, base: current)
        if resolved.fontName != current.fontName {
            field.font = resolved
        }
    }

    /// Replaces the Liquid Glass platter behind the toolbar's search field with a
    /// flat capsule, because the glass draws an elevation the window has nowhere
    /// else (see the shadows note in CLAUDE.md).
    ///
    /// **This was the first of the three places in the app that reach past the
    /// public API** — the others being `restyleWindowTitle()` above and
    /// `SidebarVibrancy`, both of which borrow the reasoning below — and
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
    /// only widths *outside* the range are corrected, so a divider the user drags
    /// stays where they put it. Out-of-range is now both ends: a build before
    /// `constrainSidebarWidth()` could autosave a sidebar dragged to 1,100pt, and
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
    /// It rides `applicationDidUpdate` for the reason `flattenToolbarGlass()` does —
    /// so a second window, or a SwiftUI update that resets the item, is covered
    /// without needing to know when either happens. Whether once would do was not
    /// established. It's idempotent by comparison rather than by remembering, since
    /// assigning a thickness re-runs the split view's layout.
    @MainActor
    private static func constrainSidebarWidth() {
        for window in NSApp.windows {
            guard let split = splitView(in: window.contentView),
                  let controller = split.delegate as? NSSplitViewController,
                  let sidebar = controller.splitViewItems.first
            else { continue }

            if sidebar.minimumThickness != Metrics.minSidebarWidth {
                sidebar.minimumThickness = Metrics.minSidebarWidth
            }
            if sidebar.maximumThickness != Metrics.maxSidebarWidth {
                sidebar.maximumThickness = Metrics.maxSidebarWidth
            }
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
