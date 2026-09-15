import AppKit
import SwiftUI

/// The main window: a collapsible projects sidebar on the left, then the notes
/// and tasks panels sharing the remaining width — 50/50 by default, resizable
/// via a hover-revealed handle between them (see `ColumnDivider`). There is no
/// toolbar: ⌘K opens the command palette (`CommandPalette`), which is the search.
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
                // The toolbar is **empty, and it stays** (September 2026). The
                // title and the search field are gone — search is the command
                // palette, "show projects" sits in the notes band while the
                // sidebar is away — but hiding the toolbar itself
                // (`.toolbarVisibility(.hidden, for: .windowToolbar)`) was tried
                // and took the title-bar row with it: the traffic lights
                // disappeared and the sidebar pane dropped below an empty strip.
                // A spacer is a real item, so AppKit keeps the toolbar, and with
                // it the row the traffic lights and the sidebar glyphs share.
                // **Fixed and at the trailing edge, not flexible**: a flexible
                // spacer's item view spanned the detail's whole title-bar width
                // and took every click meant for the band's heading row under
                // it — "the elements in the header are not clickable". A fixed
                // one is a few points wide at the far right, over nothing.
                .toolbar {
                    ToolbarSpacer(.fixed, placement: .primaryAction)
                }
                .toolbar(removing: .title)
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
        // Watched rather than driven from `toggleSidebar`, so the pin keeps up
        // with the column however it moved — including a drag of the split view's
        // own divider, which never goes through our toggle.
        .onChange(of: appState.sidebarVisible) { _, _ in
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
        // `ignoresSafeArea` because the title bar is transparent and the ground has
        // to run up under it, which the container background did for free.
        //
        // Applied **unconditionally** — no `if` on the theme. Branching here
        // would give the two cases different identities and tear down
        // `NavigationSplitView`, and with it the autosaved column widths, on
        // every change of the picker. Every theme brings a page ground, so there
        // is no unthemed case left to branch on.
        .background(settings.theme.windowFill.ignoresSafeArea())
        // The columns run up under the (empty) toolbar, so each band's one row
        // sits on the title-bar line rather than under a blank strip — see
        // `ColumnHeaderBand`.
        .ignoresSafeArea(.container, edges: .top)
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

    /// How long the column takes to slide. The notes band's "show" glyph fades
    /// in the same transaction, so the two read as one movement.
    private static let slideCurve = Animation.easeInOut(duration: 0.25)
    private static let slideDuration = Duration.milliseconds(250)

    /// The system switch OR-ed with the Accessibility menu's in-app one.
    private var motionReduced: Bool { reduceMotion || settings.appReduceMotion }

    /// The slide, dropped entirely when Reduce Motion is on: the column and the
    /// button then change state in one step instead of travelling. `nil` is a
    /// valid argument to `withAnimation`, so every call site below is unchanged.
    private var slide: Animation? {
        motionReduced ? nil : Self.slideCurve
    }

    /// How long the reference width is held after a toggle. With no slide to
    /// wait for, that's immediately.
    private var slideDuration: Duration {
        motionReduced ? .zero : Self.slideDuration
    }

    /// Animated so the column slides, as a real macOS sidebar does — a bare
    /// mutation makes `NavigationSplitView` pop the column in and out. Every
    /// route in (⌘§, the menu, either button) lands here, so the animation is
    /// defined once.
    private func toggleSidebar() {
        withAnimation(slide) {
            appState.sidebarVisible.toggle()
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
                // editors, not `MarkdownTextView`s, so they keep the palette.
                let editing = MainActor.assumeIsolated {
                    MarkdownResponder.focusedMarkdownBody() != nil
                }
                if editing { return event }
                Task { @MainActor in CommandPalette.shared.toggle() }
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
            // **Global coordinates, and it is load-bearing.** The divider moves
            // with every event of its own drag — it is offset by the tasks width
            // it is changing — so a translation measured in its *local* space
            // is read against a view that has just shifted under the pointer:
            // each event undid the last and the handle shook back and forth
            // around the cursor, with 250–550ms of layout churn per turn behind
            // it (`LayoutProbe`, September 2026). The sidebar's reorder drag
            // hit the same wall and is `.global` for the same reason.
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
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
        // Note: *don't* touch `titleVisibility`. The toolbar removes the title
        // item itself (`.toolbar(removing: .title)`); the Window menu keeps it.
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
