import AppKit
import SwiftUI

/// The main window: a collapsible projects sidebar on the left, then the notes
/// and tasks panels sharing the remaining width — 50/50 by default, resizable
/// via a hover-revealed handle between them (see `ColumnDivider`). A global
/// search field in the toolbar filters all three panels at once.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(Library.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Read for the theme's window surface and for Reduce Motion.
    @Environment(SettingsStore.self) private var settings

    @State private var keyMonitor: Any?

    /// Notes column's share of the detail width. Persisted, like the split
    /// view's own sidebar width, so the arrangement survives relaunches.
    @AppStorage("notesTasksSplit") private var notesSplit: Double = 0.5

    /// The detail toolbar's "show sidebar" button, tracked as presence *and*
    /// opacity rather than straight off `appState.sidebarVisible` — see
    /// `syncShowButton`. Both start closed because the sidebar starts open and
    /// its visibility isn't persisted across launches.
    @State private var showButtonPresent = false
    @State private var showButtonOpacity: Double = 0
    /// The pending "now actually take the button out of the toolbar" step,
    /// cancelled if the sidebar is toggled again mid-fade.
    @State private var showButtonRemoval: Task<Void, Never>?
    /// The button's natural width, measured rather than hard-coded so the width
    /// the animation opens up stays whatever `.glass` decides a circular toolbar
    /// button is. Seeded with a plausible one for the frame before the first
    /// measurement lands.
    @State private var showButtonWidth: CGFloat = 30

    var body: some View {
        @Bindable var appState = appState

        // NavigationSplitView (rather than a hand-rolled HStack) so the sidebar
        // is a *real* macOS sidebar: full window height, with the traffic
        // lights floating over it instead of a strip cutting across its top.
        NavigationSplitView(columnVisibility: columnVisibility) {
            ProjectsSidebar()
                .navigationSplitViewColumnWidth(
                    min: Metrics.minSidebarWidth,
                    ideal: Metrics.idealSidebarWidth,
                    max: Metrics.maxSidebarWidth
                )
                // We supply our own toggle (with the ⌘§ hint), so drop the
                // duplicate system one.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            columns
            .toolbar {
                // Only "show" lives out here; the sidebar carries its own "hide"
                // button once it's open (Safari's arrangement). It stays in the
                // toolbar a little longer than the sidebar is closed so it can
                // fade with the column rather than blink — see `syncShowButton`.
                //
                // It is the *only* navigation item, and the window title beside
                // it is AppKit's own. A project icon sat between the two for a
                // while and is gone: spacing it evenly took a negative inset,
                // which failed three ways (see CLAUDE.md), and drawing the title
                // ourselves to fix that — `.toolbar(removing: .title)` plus a
                // `Text` — cost the search field its trailing pin, since the
                // title item is what holds the space between the two ends.
                if showButtonPresent {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            toggleSidebar()
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        // The button brings its own background because the capsule
                        // the toolbar would wrap it in is AppKit's, drawn outside
                        // our view and so beyond the reach of the fade below: it
                        // would pop in and out around a dissolving glyph.
                        //
                        // Flat rather than `.glass`, and circular because that's
                        // what the toolbar rounds a lone icon to — glass drew a
                        // drop shadow under it, the last one left in the window
                        // once the search field's platter was flattened. See
                        // `FlatButtonStyle`.
                        .buttonStyle(.toolbarGlyph)
                        .help("Show projects (⌘§)")
                        .accessibilityLabel("Show projects")
                        // Keeps the button at its natural size whatever the frame
                        // below proposes, so the measurement is of the button and
                        // not of the animation measuring itself.
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                            if width > 0, abs(width - showButtonWidth) > 0.5 { showButtonWidth = width }
                        }
                        // Grow out of the gap rather than drop into one. The
                        // toolbar reserves the item's full width the moment the
                        // item exists, so fading alone shoved the title sideways
                        // in a single step while the glyph was still arriving.
                        // Width, scale and opacity all run off the same 0→1, so
                        // the space and the thing filling it turn up together.
                        //
                        // The scale is floored, never 0: a zero scale is a
                        // singular transform, and `convertRect:fromView:` aborts
                        // rather than declining when it cannot invert one — see
                        // `minButtonScale`.
                        .scaleEffect(max(showButtonOpacity, Self.minButtonScale))
                        .frame(width: showButtonWidth * showButtonOpacity)
                        // At nothing wide the item is still holding the toolbar's
                        // gap to its neighbour; take that back too, or the title
                        // keeps a smaller version of the same jump. It is safe on
                        // a button only because it reaches full size at the end of
                        // the fade, when there is nothing left to click: a
                        // negative inset shrinks the frame while the glyph keeps
                        // drawing at its own size, and the click target goes with
                        // the frame.
                        .padding(.trailing, -Self.toolbarItemSpacing * (1 - showButtonOpacity))
                        .opacity(showButtonOpacity)
                        // Nothing to click while it's on its way out.
                        .allowsHitTesting(showButtonOpacity > 0.5)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                // Pin the search field to the trailing edge. Left to itself the
                // toolbar tucks it in beside the sidebar toggle; the plan wants
                // sidebar control on the left, search on the right.
                DefaultToolbarItem(kind: .search, placement: .primaryAction)
            }
            .searchable(text: $appState.searchText, placement: .toolbar, prompt: "Search notes, projects & tasks")
            .navigationTitle(navigationTitle)
        }
        .navigationSplitViewStyle(.balanced)
        // Let the sidebar's material run the full height of the window instead
        // of starting below a title-bar strip: drop the toolbar's background
        // and make the title bar itself transparent (see WindowConfigurator),
        // so the traffic lights float over the sidebar.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(WindowConfigurator())
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in toggleSidebar() }
        // Watched rather than driven from `toggleSidebar`, so the button keeps up
        // with the column however it moved — including a drag of the split view's
        // own divider, which never goes through our toggle.
        .onChange(of: appState.sidebarVisible) { _, visible in
            syncShowButton(sidebarVisible: visible)
        }
    }

    /// The two detail columns and the page they sit on. Split out of `body`
    /// rather than written inline because the type-checker gave up on the whole
    /// expression once the page ground moved in here.
    private var columns: some View {
        // No separator lines anywhere: the columns are told apart by their
        // headers and the islands inside them, not by rules. The boundary
        // between them is still draggable — a hover-revealed handle floats over
        // it.
        GeometryReader { geo in
            let notesWidth = notesWidth(in: geo.size.width)
            HStack(spacing: 0) {
                NotesPanel()
                    .frame(width: notesWidth)
                TasksPanel()
                    .frame(maxWidth: .infinity)
            }
            .overlay(alignment: .leading) {
                ColumnDivider(
                    fraction: $notesSplit,
                    notesWidth: notesWidth,
                    totalWidth: geo.size.width
                )
                .offset(x: notesWidth - ColumnDivider.hitWidth / 2)
            }
        }
        // The theme's **page ground** (see `AppTheme`), and it is painted here —
        // on the detail side — rather than as a `containerBackground` across the
        // whole window, which is what it was until the sidebar was made properly
        // transparent. A window-wide background sits *behind the sidebar too*,
        // and a `.behindWindow` material with the app's own opaque paint
        // underneath it has nothing to show: see `SidebarVibrancy`. So the page
        // stops at the columns that are made of pages, and the sidebar is left
        // with the desktop behind it.
        //
        // `ignoresSafeArea` because the toolbar is transparent and the ground has
        // to run up under it, which the container background did for free.
        //
        // Applied **unconditionally** — no `if` on the theme. Branching here
        // would give the two cases different identities and tear down
        // `NavigationSplitView`, and with it the autosaved column widths, on
        // every change of the picker. Every theme brings a page ground, so there
        // is no unthemed case left to branch on.
        .background(settings.theme.windowFill.ignoresSafeArea())
    }

    /// The notes column's width for the stored split, with both columns held
    /// to a generous minimum so neither can be dragged into a sliver. In a
    /// window too narrow to honour both minimums, fall back to an even split.
    private func notesWidth(in total: CGFloat) -> CGFloat {
        let floor = Metrics.minPanelWidth
        guard total > floor * 2 else { return total / 2 }
        return max(floor, min(total - floor, total * notesSplit))
    }

    /// Bridges the app's simple `sidebarVisible` flag to the split view's
    /// three-state column visibility.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.sidebarVisible ? .all : .detailOnly },
            set: { appState.sidebarVisible = ($0 != .detailOnly) }
        )
    }

    /// A plain `String`, drawn by AppKit. Two ways of dressing it up have been
    /// tried and undone: interpolating an `Image` into it is flattened away, and
    /// removing the drawn title to lay out an icon and a `Text` of our own moved
    /// the search field off the trailing edge, because that title item is what
    /// holds the space between the toolbar's two ends.
    private var navigationTitle: String {
        if let id = appState.selectedProjectID, let project = library.project(id: id) {
            return project.displayName
        }
        return "Everything"
    }

    /// How long the column takes to slide. The "show" button's fade rides the
    /// same curve and length, so the two read as one movement.
    private static let slideCurve = Animation.easeInOut(duration: 0.25)
    private static let slideDuration = Duration.milliseconds(250)

    /// How much of the slide the show button's exit takes. Short enough that the
    /// title's un-animatable step lands mid-travel, long enough that the glyph
    /// still reads as fading rather than blinking out.
    private static let exitFraction = 0.4
    private static let exitCurve = Animation.easeOut(duration: 0.25 * exitFraction)
    private static let exitDuration = Duration.milliseconds(Int(250 * exitFraction))

    /// The system switch OR-ed with the Accessibility menu's in-app one.
    private var motionReduced: Bool { reduceMotion || settings.appReduceMotion }

    /// The slide, dropped entirely when Reduce Motion is on: the column and the
    /// button then change state in one step instead of travelling. `nil` is a
    /// valid argument to `withAnimation`, so every call site below is unchanged.
    private var slide: Animation? {
        motionReduced ? nil : Self.slideCurve
    }

    /// The button's exit, dropped entirely with Reduce Motion for the same
    /// reason `slide` is.
    private var exit: Animation? {
        motionReduced ? nil : Self.exitCurve
    }

    /// How long to wait before taking the faded-out button out of the toolbar.
    /// With no fade to wait for, that's immediately.
    private var slideDuration: Duration {
        motionReduced ? .zero : Self.slideDuration
    }

    /// The gap the toolbar leaves between two items, which the show button hands
    /// back as it leaves.
    private static let toolbarItemSpacing: CGFloat = 8

    /// The smallest the show button is scaled to on its way out. Anything
    /// times zero is a matrix AppKit cannot invert, and it aborts rather than
    /// declining — see `scaleEffect` above.
    private static let minButtonScale: Double = 0.01

    /// Animated so the column slides, as a real macOS sidebar does — a bare
    /// mutation makes `NavigationSplitView` pop the column in and out. Every
    /// route in (⌘§, the menu, either button) lands here, so the animation is
    /// defined once.
    private func toggleSidebar() {
        withAnimation(slide) {
            appState.sidebarVisible.toggle()
        }
    }

    /// Keeps the toolbar's "show" button in step with the sidebar it opens.
    ///
    /// SwiftUI won't animate a toolbar item in or out: it blinks into place the
    /// moment the condition around it flips, which left the button snapping in
    /// while the column was still sliding away — and vanishing before it had
    /// finished coming back. So presence and opacity are tracked separately. The
    /// button joins the toolbar *before* fading in, and only leaves it once it
    /// has already faded out.
    ///
    /// **The exit is deliberately faster than the slide, and that is about the
    /// title rather than the button.** The toolbar holds the item's slot at its
    /// natural width whatever width we animate underneath — the same reservation
    /// that made a negative inset useless on the title icon — so the shrinking
    /// glyph moves nothing, and the title travels its last ~36pt in **one step**
    /// when the item is finally removed. That step can't be animated away; it can
    /// only be put somewhere it doesn't read as a jump. At the full slide length
    /// it landed at the exact moment the column stopped, with the whole window
    /// still — the worst possible frame for it. Ending the fade at
    /// `exitFraction` of the slide lands it while the column is still travelling
    /// and the title is already moving with it, so the step is absorbed by a
    /// movement the eye is already following.
    private func syncShowButton(sidebarVisible: Bool) {
        showButtonRemoval?.cancel()
        showButtonRemoval = nil

        guard sidebarVisible else {
            showButtonPresent = true
            withAnimation(slide) { showButtonOpacity = 1 }
            return
        }

        withAnimation(exit) { showButtonOpacity = 0 }
        showButtonRemoval = Task { @MainActor in
            // With Reduce Motion there is no fade to wait for, and a slot held
            // open for a button nobody can see is just a later jump.
            try? await Task.sleep(for: motionReduced ? .zero : Self.exitDuration)
            guard !Task.isCancelled else { return }
            showButtonPresent = false
        }
    }

    // The plan asks for ⌘ + the key left of the number row (§ / º / ` depending
    // on layout). Matching by *physical* key code covers every keyboard:
    // ANSI grave = 50, ISO section = 10.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command), event.keyCode == 50 || event.keyCode == 10 {
                Task { @MainActor in toggleSidebar() }
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// The draggable boundary between the notes and tasks columns. Invisible at
/// rest — the columns are told apart by their content, not by rules — it
/// reveals a small capsule handle on hover (the resize cursor with it) and
/// drags the split, with both columns held to `Metrics.minPanelWidth`.
private struct ColumnDivider: View {
    /// Width of the invisible hit strip straddling the boundary.
    static let hitWidth: CGFloat = 11

    /// The stored split (notes' share of the width), written as the drag moves.
    @Binding var fraction: Double
    /// The notes column's *rendered* width — the clamped value, which is what
    /// a drag starts from, not whatever stale fraction is on disk.
    let notesWidth: CGFloat
    let totalWidth: CGFloat

    @State private var hovering = false
    @State private var dragging = false
    /// `notesWidth` captured when the drag began, so each move is absolute.
    @State private var dragBase: CGFloat?

    var body: some View {
        Color.clear
            .frame(width: Self.hitWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(Stone.surface)
                    // Fill plus hairline, no drop shadow: the window is shadowless
                    // throughout (see the `@project` dropdown), and a 5pt capsule
                    // that only appears under the pointer doesn't need lifting to
                    // be found.
                    .overlay(Capsule().strokeBorder(Stone.line, lineWidth: 0.5))
                    .frame(width: 5, height: 48)
                    .opacity(hovering || dragging ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onHover { inside in
                withAnimation(.easeInOut(duration: 0.12)) { hovering = inside }
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        dragging = true
                        if dragBase == nil { dragBase = notesWidth }
                        let proposed = (dragBase ?? notesWidth) + value.translation.width
                        let floor = Metrics.minPanelWidth
                        let clamped = max(floor, min(totalWidth - floor, proposed))
                        fraction = clamped / totalWidth
                    }
                    .onEnded { _ in
                        dragging = false
                        dragBase = nil
                    }
            )
            // Dragging is pointer-only; give assistive tech a real control.
            .accessibilityElement()
            .accessibilityLabel("Resize columns")
            .accessibilityValue("Notes \(Int((notesWidth / max(totalWidth, 1)) * 100)) percent")
            .accessibilityAdjustableAction { direction in
                let floor = Metrics.minPanelWidth / max(totalWidth, 1)
                switch direction {
                case .increment: fraction = min(1 - floor, fraction + 0.05)
                case .decrement: fraction = max(floor, fraction - 0.05)
                @unknown default: break
                }
            }
    }
}

/// Reaches the hosting `NSWindow` to make its title bar transparent and let
/// content (the sidebar's material) run underneath it — the AppKit half of the
/// full-height-sidebar look. SwiftUI still keeps a safe-area inset for the
/// toolbar, so nothing collides with the traffic lights.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowProbe() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowProbe)?.publishGeometry()
    }
}

/// Does the AppKit half of the job: styles the window once, then republishes its
/// title-bar geometry on *every* layout pass. A one-shot measurement raced the
/// window's own layout — the traffic lights weren't positioned yet, so the
/// sidebar's buttons aligned to a stale guess and sat visibly low.
private final class WindowProbe: NSView {
    private var configured = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
        publishGeometry()
    }

    override func layout() {
        super.layout()
        publishGeometry()
    }

    private func configureWindow() {
        guard !configured, let window else { return }
        configured = true
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        // The sidebar is transparent to the *desktop* (`SidebarVibrancy`), and a
        // window that fills itself with an opaque colour first leaves its
        // `.behindWindow` material nothing to sample. So the window paints
        // nothing of its own: every region of it is covered by something that
        // does — the detail's page ground on one side, the sidebar's material on
        // the other — and where the sidebar is, what's underneath is the desktop.
        // Both lines are needed; `isOpaque` alone still fills with
        // `backgroundColor`.
        window.isOpaque = false
        window.backgroundColor = .clear
        // Note: *don't* touch `titleVisibility`. SwiftUI drives it from
        // `navigationTitle`, and forcing `.hidden` here (after the first layout)
        // left the toolbar with no title and the search field stretched across
        // the leading edge until the next title change.
    }

    /// Publishes the band's height — which the sidebar header reserves, keeping
    /// all three column titles on one baseline — and the traffic lights' own
    /// centre line, which the sidebar's buttons align to. The two differ: a
    /// unified toolbar makes the band taller than the lights' row.
    func publishGeometry() {
        guard let window, let contentView = window.contentView else { return }

        let titlebar = contentView.bounds.height - window.contentLayoutRect.height
        if titlebar > 0, abs(titlebar - AppState.shared.titlebarHeight) > 0.5 {
            AppState.shared.titlebarHeight = titlebar
        }

        guard let close = window.standardWindowButton(.closeButton) else { return }
        let rect = close.convert(close.bounds, to: contentView)
        // Don't assume a flip direction: the content view is AppKit's, the
        // hosting views inside it are flipped.
        let centre = contentView.isFlipped ? rect.midY : contentView.bounds.height - rect.midY
        // Ignore anything outside the band — a bad read here once dumped the
        // sidebar's buttons at the bottom of the window.
        guard centre > 0, centre < max(titlebar, Metrics.titlebarHeight) else { return }
        if abs(centre - AppState.shared.trafficLightCenterY) > 0.5 {
            AppState.shared.trafficLightCenterY = centre
        }

    }
}
