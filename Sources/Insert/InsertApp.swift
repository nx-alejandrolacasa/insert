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

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(library)
                .environment(appState)
                .environment(settings)
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
        } label: {
            MenuBarLabel()
                .environment(library)
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
