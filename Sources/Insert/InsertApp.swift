import SwiftUI

/// The app entry point.
///
/// Insert is a regular windowed app (Dock icon + main window) that *also* adds a
/// menu-bar extra for pending tasks at a glance. The shared stores are created
/// once and injected into the environment so every scene observes the same
/// state.
@main
struct InsertApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var library = Library.shared
    @State private var appState = AppState.shared
    @State private var settings = SettingsStore.shared
    @State private var clock = DayClock.shared

    var body: some Scene {
        // A `Window`, not a `WindowGroup`: Insert is a one-window app — the
        // stores are shared singletons, so two windows fight over one selection.
        // A group nonetheless allowed a second instance, and 0.14.2 was seen
        // running two windows of the same data, with closing one crashing the
        // app (see `WindowProbe.publishGeometry`). How the second window came to
        // exist wasn't established — state restoration after a crash and
        // File → New Window are both routes a group leaves open. A `Window`
        // scene is one instance by construction, so it closes every such route.
        Window("Insert", id: "main") {
            RootView()
                .environment(library)
                .environment(appState)
                .environment(settings)
                // Today, so the date labels re-render when it turns over rather
                // than waiting for an unrelated edit to rebuild the column.
                .environment(clock)
                // The theme's primary, threaded through SwiftUI's own
                // channel so controls that resolve the *tint* — selection
                // fills, `.glassProminent` confirm buttons — follow the Theme
                // setting without naming it. Note `Color.accentColor` does
                // NOT read this (it is the app/system accent), which is why
                // the checkbox and the `@project` dropdown read the setting
                // directly. AppKit's focus ring stays the system accent; that
                // one has no supported override.
                .tint(settings.theme.primary)
                // The heavy hammer the in-app Increase Contrast needs: the
                // high-contrast variants live inside dynamic `NSColor`
                // providers, and SwiftUI caches resolved colours per view —
                // a subtree whose inputs didn't change never re-resolves, so
                // flipping the flag left most of the window on its old
                // colours. Changing the root's identity rebuilds everything
                // with fresh resolutions. Costs transient UI state (an open
                // card closes, scroll positions reset) on a switch that's
                // flipped rarely; the *system* setting never needs this,
                // because it swaps the effective appearance, which is its own
                // full refresh.
                .id(settings.appIncreaseContrast)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            // Settings lives in an AppKit window (full-height sidebar, see
            // SettingsWindowController), so ⌘, opens that instead of a scene.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindowController.shared.show() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Note") { NotificationCenter.default.post(name: .newNote, object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Task") { NotificationCenter.default.post(name: .newTask, object: nil) }
                    .keyboardShortcut("t", modifiers: .command)
                Button("New Project") { NotificationCenter.default.post(name: .newProject, object: nil) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra(isInserted: $settings.showMenuBar) {
            MenuBarContent()
                .environment(library)
                .environment(appState)
                .environment(clock)
        } label: {
            MenuBarLabel()
                .environment(library)
                .environment(clock)
        }
        .menuBarExtraStyle(.menu)

        // No `Settings` scene: the Settings window is an AppKit split view so
        // its sidebar can run the full height of the window.
    }
}

/// Cross-scene notifications for the global "New …" menu commands.
extension Notification.Name {
    static let newNote = Notification.Name("insert.newNote")
    static let newTask = Notification.Name("insert.newTask")
    static let newProject = Notification.Name("insert.newProject")
    static let toggleSidebar = Notification.Name("insert.toggleSidebar")
}
