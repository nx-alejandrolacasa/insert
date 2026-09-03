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

    /// The split while the divider is mid-drag. Local state, not the
    /// `@AppStorage` above: a drag moves at pointer rate, and writing the stored
    /// value per event hit `UserDefaults` sixty-plus times a second for a value
    /// only the last event of the drag decides. `ColumnDivider` commits it into
    /// `notesSplit` when the drag ends.
    @State private var liveSplit: Double?

    /// The detail area's current width, and the width it last had with the
    /// sidebar open and still. Hiding the sidebar hands the width it frees to
    /// **notes alone** — see `referenceWidth(in:)`.
    @State private var detailWidth: CGFloat = 0
    @State private var openDetailWidth: CGFloat?

    /// True while the sidebar's column is mid-slide, and its **only** job is to
    /// keep a width measured mid-slide from being pinned: the frames of a slide
    /// are on their way somewhere, and the pin has to be a width the columns
    /// settled at. It is deliberately not consulted by `referenceWidth(in:)`,
    /// which cannot afford to — the flag is set from `onChange`, a beat after
    /// `sidebarVisible` itself flips.
    @State private var sidebarSliding = false
    @State private var sidebarSettle: Task<Void, Never>?

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
        .alert(
            "Couldn’t Move to Trash",
            isPresented: Binding(
                get: { library.deletionFailure != nil },
                set: { shown in if !shown { library.clearDeletionFailure() } }
            )
        ) {
            Button("OK") { library.clearDeletionFailure() }
        } message: {
            Text(library.deletionFailure?.message ?? "")
        }
        // Watched rather than driven from `toggleSidebar`, so the button keeps up
        // with the column however it moved — including a drag of the split view's
        // own divider, which never goes through our toggle.
        .onChange(of: appState.sidebarVisible) { _, visible in
            syncShowButton(sidebarVisible: visible)
            holdReferenceWidth()
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
            let tasksWidth = tasksWidth(in: geo.size.width)
            HStack(spacing: 0) {
                // **Notes is the elastic column**, and which of the two carries
                // the fixed width is not cosmetic. Through the sidebar's slide
                // the tasks width is a constant, so a fixed frame here has
                // nothing to interpolate and the animating container width all
                // lands in notes. The other way round, `.frame(width:)` on notes
                // animated *itself* toward a target the container width was
                // moving at the same time — two curves for one movement, and the
                // frame lagged: the tasks column came out reduced on open and
                // grew back over the slide.
                NotesPanel()
                    .frame(maxWidth: .infinity)
                TasksPanel()
                    .frame(width: tasksWidth)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                guard width > 0, abs(width - detailWidth) > 0.5 else { return }
                detailWidth = width
                // Only a width the columns have settled at is worth pinning: the
                // frames of a slide are on their way somewhere, and pinning one
                // of those is the vibration all over again.
                if appState.sidebarVisible, !sidebarSliding { openDetailWidth = width }
            }
            .overlay(alignment: .trailing) {
                ColumnDivider(
                    fraction: $notesSplit,
                    liveFraction: $liveSplit,
                    tasksWidth: tasksWidth,
                    totalWidth: geo.size.width,
                    referenceWidth: referenceWidth(in: geo.size.width)
                )
                // Measured in from the trailing edge for the frame's reason
                // above: off the tasks width, the offset is a constant through
                // the slide as well.
                .offset(x: -(tasksWidth - ColumnDivider.hitWidth / 2))
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

    /// The tasks column's width for the stored split, with both columns held
    /// to a generous minimum so neither can be dragged into a sliver. In a
    /// window too narrow to honour both minimums, fall back to an even split.
    ///
    /// The split sizes **this** column and notes takes whatever is left: with
    /// the sidebar hidden the two columns share a wider detail area, and the
    /// width it freed belongs to the column the writing is in. So a collapse
    /// grows notes and leaves tasks exactly where it was.
    private func tasksWidth(in total: CGFloat) -> CGFloat {
        let floor = Metrics.minPanelWidth
        guard total > floor * 2 else { return total / 2 }
        let tasks = referenceWidth(in: total) * (1 - (liveSplit ?? notesSplit))
        return max(floor, min(total - floor, tasks))
    }

    /// The width the split is a share of: the detail area with the sidebar open.
    /// The **narrower** of the pinned width and the current one, and neither
    /// `sidebarVisible` nor `sidebarSliding` is consulted — a detail area wider
    /// than the pin is one the sidebar has vacated, whichever of the two flags
    /// happens to say so yet, and one narrower than the pin is a window that has
    /// shrunk since, which can't hand tasks more than there is.
    ///
    /// Reading the flags is what put the glitch in the *reopen*: `sidebarVisible`
    /// flips before `onChange` has set `sidebarSliding`, so two layout passes ran
    /// with the split read against the still-collapsed width — 587pt where the
    /// tasks column was 496 — and that wrong value landed inside the slide's own
    /// animated transaction, which then animated the correction back over 250ms.
    private func referenceWidth(in total: CGFloat) -> CGFloat {
        min(openDetailWidth ?? total, total)
    }

    /// Bridges the app's simple `sidebarVisible` flag to the split view's
    /// three-state column visibility.
    ///
    /// The setter compares before it writes, the rule `DayClock.tick()` follows:
    /// `@Observable` publishes on write rather than on change, and this
    /// particular write is made from inside `NavigationSplitView`'s own layout
    /// resolution — so a value that says nothing new still invalidates every
    /// view reading `sidebarVisible`.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.sidebarVisible ? .all : .detailOnly },
            set: { newValue in
                let visible = newValue != .detailOnly
                guard visible != appState.sidebarVisible else { return }
                appState.sidebarVisible = visible
            }
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

    /// Holds the reference width still until the column has stopped moving, then
    /// takes the settled width as the new pin — which is what keeps a window
    /// resized while the sidebar was away from collapsing against a stale one.
    /// The wait is the slide's own length plus a frame of grace, because the
    /// flag clearing before the last frame lands is the jump it exists to
    /// prevent; with Reduce Motion there is no slide, so it is the grace alone.
    private func holdReferenceWidth() {
        sidebarSettle?.cancel()
        sidebarSliding = true
        sidebarSettle = Task { @MainActor in
            try? await Task.sleep(for: slideDuration + .milliseconds(50))
            guard !Task.isCancelled else { return }
            sidebarSliding = false
            if appState.sidebarVisible, detailWidth > 0 { openDetailWidth = detailWidth }
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
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers?.lowercased() == "k" {
                // In a Markdown body ⌘K means "insert link" — `MarkdownTextView`
                // answers it as a key equivalent — so the monitor stands down
                // and lets the event reach the editor. Card titles are field
                // editors, not `MarkdownTextView`s, so they keep the search.
                let editing = MainActor.assumeIsolated {
                    MarkdownResponder.focusedMarkdownBody() != nil
                }
                if editing { return event }
                Task { @MainActor in focusSearch() }
                return nil
            }
            return event
        }
    }

    /// ⌘K puts the caret in the toolbar's search field, ready to type into.
    /// The field is the system's search toolbar item, and its own
    /// `beginSearchInteraction()` both focuses it and expands it if the
    /// toolbar has collapsed it to a button.
    private func focusSearch() {
        guard let toolbar = NSApp.keyWindow?.toolbar else { return }
        let searchItem = toolbar.items.compactMap { $0 as? NSSearchToolbarItem }.first
        searchItem?.beginSearchInteraction()
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

    /// The stored split (notes' share of the width), written when the drag
    /// ends — and directly by the accessibility actions, which are discrete
    /// steps rather than a stream.
    @Binding var fraction: Double
    /// The split while a drag is in flight, cleared on release. What the columns
    /// lay out from, so the stored value is written once per drag instead of
    /// once per pointer event.
    @Binding var liveFraction: Double?
    /// The tasks column's *rendered* width — the clamped value, which is what
    /// a drag starts from, not whatever stale fraction is on disk. Tasks rather
    /// than notes because that is the column the split sizes.
    let tasksWidth: CGFloat
    let totalWidth: CGFloat
    /// The width `fraction` is a share of — the detail area with the sidebar
    /// open, and so equal to `totalWidth` whenever it is. They differ only while
    /// the sidebar is collapsed, where a drag has to be written down as the
    /// tasks width it chose rather than as a share of the wider area.
    let referenceWidth: CGFloat

    @State private var hovering = false
    @State private var dragging = false
    /// `tasksWidth` captured when the drag began, so each move is absolute.
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
                        if dragBase == nil { dragBase = tasksWidth }
                        // Leftwards widens tasks, so the translation subtracts.
                        let proposed = (dragBase ?? tasksWidth) - value.translation.width
                        let floor = Metrics.minPanelWidth
                        // The drag can only choose a tasks width the split can
                        // hold, since that is what is stored: while the sidebar
                        // is collapsed the ceiling is the reference width rather
                        // than the wider detail area the columns are sharing.
                        let ceiling = min(totalWidth - floor, referenceWidth - floor)
                        let clamped = max(floor, min(ceiling, proposed))
                        liveFraction = min(1, max(0, 1 - clamped / max(referenceWidth, 1)))
                    }
                    .onEnded { _ in
                        if let liveFraction { fraction = liveFraction }
                        liveFraction = nil
                        dragging = false
                        dragBase = nil
                    }
            )
            // Dragging is pointer-only; give assistive tech a real control.
            .accessibilityElement()
            .accessibilityLabel("Resize columns")
            .accessibilityValue("Notes \(Int(((totalWidth - tasksWidth) / max(totalWidth, 1)) * 100)) percent")
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

    /// The last values *scheduled*, which is what a new measurement has to be
    /// compared against. Comparing against `AppState`'s own while the write is
    /// deferred defeated the coalescing it exists for: through a live resize
    /// nothing had landed yet, so every pass read the same stale value, found it
    /// different and scheduled another write. They are never cleared — once the
    /// deferred write lands they agree with `AppState`, and until it does they
    /// are the more recent of the two.
    private var scheduledTitlebarHeight: CGFloat?
    private var scheduledTrafficLightCenterY: CGFloat?

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
    ///
    /// Measured now, written a turn later: this runs from `layout()` — the
    /// window's own display cycle — and from `updateNSView`, a SwiftUI view
    /// update, and an `@Observable` write belongs in neither. 0.14.2 crashed on
    /// closing one of two open windows, and the trace is exactly that shape: an
    /// observation mutation applied while an `NSHostingView` laid out, whose
    /// invalidation reached `setNeedsUpdateConstraints` on a window mid-flush —
    /// which macOS 26 answers with an NSException that `+[NSApplication
    /// _crashOnException:]` makes fatal. That *this* write was the mutation in
    /// that trace was not instrumented; it is the one write the app makes from a
    /// layout pass, and with two windows both probes wrote this one shared
    /// `AppState`. The deferral costs the labels one frame on the rare tick the
    /// geometry actually changes; the comparisons stay synchronous, so the
    /// common pass schedules nothing.
    func publishGeometry() {
        guard let window, let contentView = window.contentView else { return }

        let titlebar = contentView.bounds.height - window.contentLayoutRect.height
        let publishedTitlebar = scheduledTitlebarHeight ?? AppState.shared.titlebarHeight
        if titlebar > 0, abs(titlebar - publishedTitlebar) > 0.5 {
            scheduledTitlebarHeight = titlebar
            Task { @MainActor in AppState.shared.titlebarHeight = titlebar }
        }

        guard let close = window.standardWindowButton(.closeButton) else { return }
        let rect = close.convert(close.bounds, to: contentView)
        // Don't assume a flip direction: the content view is AppKit's, the
        // hosting views inside it are flipped.
        let centre = contentView.isFlipped ? rect.midY : contentView.bounds.height - rect.midY
        // Ignore anything outside the band — a bad read here once dumped the
        // sidebar's buttons at the bottom of the window.
        guard centre > 0, centre < max(titlebar, Metrics.titlebarHeight) else { return }
        let publishedCentre = scheduledTrafficLightCenterY ?? AppState.shared.trafficLightCenterY
        if abs(centre - publishedCentre) > 0.5 {
            scheduledTrafficLightCenterY = centre
            Task { @MainActor in AppState.shared.trafficLightCenterY = centre }
        }
    }
}
