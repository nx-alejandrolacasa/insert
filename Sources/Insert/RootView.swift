import AppKit
import SwiftUI

/// The main window: a collapsible projects sidebar on the left, then the notes
/// and tasks panels sharing the remaining width 50/50. A global search field in
/// the toolbar filters all three panels at once.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(Library.self) private var library

    @State private var keyMonitor: Any?

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
            // No separator lines anywhere: the columns are told apart by their
            // headers and the glass islands inside them, not by rules.
            GeometryReader { geo in
                HStack(spacing: 0) {
                    NotesPanel()
                        .frame(width: geo.size.width / 2)
                    TasksPanel()
                        .frame(maxWidth: .infinity)
                }
            }
            .toolbar {
                // Only "show" lives out here; the sidebar carries its own "hide"
                // button once it's open (Safari's arrangement). It stays in the
                // toolbar a little longer than the sidebar is closed so it can
                // fade with the column rather than blink — see `syncShowButton`.
                if showButtonPresent {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            toggleSidebar()
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        // The button brings its own glass because the capsule the
                        // toolbar would wrap it in is AppKit's, drawn outside our
                        // view and so beyond the reach of the fade below: it would
                        // pop in and out around a dissolving glyph.
                        .buttonStyle(.glass)
                        // …and its own shape with it: left to itself `.glass`
                        // draws the capsule it would use anywhere else, where the
                        // toolbar rounds a lone icon into a circle.
                        .buttonBorderShape(.circle)
                        .help("Show projects (⌘§)")
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
                        .scaleEffect(showButtonOpacity)
                        .frame(width: showButtonWidth * showButtonOpacity)
                        // At nothing wide the item is still holding the toolbar's
                        // gap to its neighbour; take that back too, or the title
                        // keeps a smaller version of the same jump.
                        .padding(.trailing, -Self.toolbarItemSpacing * (1 - showButtonOpacity))
                        .opacity(showButtonOpacity)
                        // Nothing to click while it's on its way out.
                        .allowsHitTesting(showButtonOpacity > 0.5)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                // The selected project's icon (or the inbox tray for Everything),
                // beside the title. `sharedBackgroundVisibility(.hidden)` is what
                // makes this read as part of the title rather than as another
                // button: without it macOS wraps the item in its own glass
                // capsule, and interpolating the image into `navigationTitle`
                // instead gets flattened away entirely.
                ToolbarItem(placement: .navigation) {
                    Image(systemName: titleSymbol)
                        .foregroundStyle(titleTint.deep)
                        // Toolbar items are spaced for buttons; this one is really
                        // part of the title, so pull the gap in.
                        .padding(.trailing, -8)
                }
                .sharedBackgroundVisibility(.hidden)
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

    /// Bridges the app's simple `sidebarVisible` flag to the split view's
    /// three-state column visibility.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { appState.sidebarVisible ? .all : .detailOnly },
            set: { appState.sidebarVisible = ($0 != .detailOnly) }
        )
    }

    /// The icon shown beside the window title: the selected project's symbol, or
    /// the same inbox tray the sidebar's "Everything" row wears.
    private var titleSymbol: String {
        if let id = appState.selectedProjectID, let project = library.project(id: id) {
            return project.symbol
        }
        return SymbolCatalog.everything
    }

    /// The selected project's colour, or blue for Everything.
    private var titleTint: Tint {
        if let id = appState.selectedProjectID, let project = library.project(id: id) {
            return project.tint
        }
        return .blue
    }

    /// Stays a plain `String`: a `Text` with an interpolated `Image` gets
    /// flattened for the window title, which drops the glyph and leaves the bar
    /// empty on first render — hence the separate toolbar item above.
    private var navigationTitle: String {
        if let id = appState.selectedProjectID, let project = library.project(id: id) {
            return project.displayName
        }
        return "Everything"
    }

    /// How long the column takes to slide. The "show" button's fade rides the
    /// same curve and length, so the two read as one movement.
    private static let slide = Animation.easeInOut(duration: 0.25)
    private static let slideDuration = Duration.milliseconds(250)

    /// The gap the toolbar leaves between two items — the same one the title
    /// icon pulls back with a negative inset.
    private static let toolbarItemSpacing: CGFloat = 8

    /// Animated so the column slides, as a real macOS sidebar does — a bare
    /// mutation makes `NavigationSplitView` pop the column in and out. Every
    /// route in (⌘§, the menu, either button) lands here, so the animation is
    /// defined once.
    private func toggleSidebar() {
        withAnimation(Self.slide) {
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
    /// has already faded out, which puts the un-animatable half of the change
    /// where there is nothing left to see.
    private func syncShowButton(sidebarVisible: Bool) {
        showButtonRemoval?.cancel()
        showButtonRemoval = nil

        guard sidebarVisible else {
            showButtonPresent = true
            withAnimation(Self.slide) { showButtonOpacity = 1 }
            return
        }

        withAnimation(Self.slide) { showButtonOpacity = 0 }
        showButtonRemoval = Task { @MainActor in
            try? await Task.sleep(for: Self.slideDuration)
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
