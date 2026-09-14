import AppKit
import SwiftUI

/// The command palette: ⌘K anywhere but a Markdown body, the magnifier in the
/// sidebar header, or Edit → Search…. It replaced the toolbar's search field in
/// September 2026, and the toolbar went with it — see CLAUDE.md.
///
/// One borderless panel for the app, attached to the main window as a child so
/// it travels with it, and **key** while open so the field takes typing. A
/// window rather than an overlay for `FormattingBarPanel`'s reason: the card
/// previews and titles are platform views, which draw above anything SwiftUI
/// paints in the same hosting view, so an overlay would come up under them.
///
/// Typing lists what matches — commands, projects, notes and tasks in that
/// order — and Return opens the highlighted row: a project is selected, a note
/// or task is revealed in its column with whatever filter was hiding it cleared
/// first. With nothing typed the palette lists the commands alone. The columns
/// themselves no longer filter while a search is typed; the palette is the
/// search.
@MainActor
final class CommandPalette {
    static let shared = CommandPalette()

    let model = CommandPaletteModel()

    private let panel: PalettePanel
    private let host: NSHostingView<AnyView>
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []

    private(set) var isOpen = false

    static let width: CGFloat = 560

    private init() {
        host = NSHostingView(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        panel = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // **The one shadow in the app**, by request: without it the palette
        // read as diluted into the columns it floats over. It is a transient
        // window over the content rather than a surface *of* the window, which
        // is the line "no shadows anywhere" draws — that rule is about the
        // window's own flat surfaces, and this is the same lifted object a menu
        // is. The system's own window shadow, not a `.shadow(…)` of ours.
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.contentView = host
    }

    func toggle() {
        if isOpen { close() } else { open() }
    }

    func open() {
        guard !isOpen, let window = Self.mainWindow else { return }
        isOpen = true
        model.reset()
        host.rootView = AnyView(
            CommandPaletteView(model: model) { [weak self] size in self?.fit(to: size) }
                .environment(Library.shared)
                .environment(AppState.shared)
                .environment(SettingsStore.shared)
                .tint(SettingsStore.shared.theme.primary)
        )
        place(in: window, height: panel.frame.height)
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        focusField()
        installMonitor()
        observe(window)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        let parent = panel.parent
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        host.rootView = AnyView(EmptyView())
        parent?.makeKey()
    }

    // MARK: - Placement

    /// The app's one document window: titled, and not Settings.
    private static var mainWindow: NSWindow? {
        NSApp.windows.first {
            $0.isVisible && $0.styleMask.contains(.titled) && !SettingsWindowController.shared.owns($0)
        }
    }

    /// Centred on the window, its top a little way under the titlebar — where a
    /// palette is expected, and clear of the traffic lights.
    private func place(in window: NSWindow, height: CGFloat) {
        let content = window.convertToScreen(window.contentLayoutRect)
        let top = content.maxY - Self.topInset
        let x = (content.midX - Self.width / 2).rounded()
        panel.setFrame(NSRect(x: x, y: top - height, width: Self.width, height: height), display: true)
    }

    private static let topInset: CGFloat = 48

    /// The content reports its natural height; the panel follows, top edge held.
    private func fit(to size: CGSize) {
        guard isOpen, let window = panel.parent, size.height > 0,
              abs(size.height - panel.frame.height) > 0.5 else { return }
        place(in: window, height: size.height)
    }

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isOpen else { return }
                    self.place(in: window, height: self.panel.frame.height)
                }
            })
        }
        // A click anywhere else takes the keyboard away, and a palette without
        // the keyboard is a stale list over the window — so it goes.
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
    }

    // MARK: - Keys

    /// ↑/↓ move the highlight, Return opens it, Esc closes — answered here rather
    /// than in the field, whose editor would otherwise keep the arrows for the
    /// caret. Only events aimed at the panel; the main window's are left alone.
    private func installMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let keyCode = event.keyCode
            let handled = MainActor.assumeIsolated {
                switch keyCode {
                case 126: self.model.move(-1)
                case 125: self.model.move(1)
                case 36, 76: self.activateHighlighted()
                case 53: self.close()
                default: return false
                }
                return true
            }
            return handled ? nil : event
        }
    }

    func activateHighlighted() {
        guard let entry = model.highlightedEntry else { return }
        activate(entry)
    }

    /// Closes first, so the column receiving the reveal is in the window that
    /// has the keyboard back when it focuses the card.
    func activate(_ entry: CommandPaletteModel.Entry) {
        close()
        model.perform(entry)
    }

    /// `@FocusState` from `onAppear` usually lands; this is the AppKit half for
    /// when it doesn't, since the panel has only just become key.
    private func focusField() {
        DispatchQueue.main.async { [panel, host] in
            guard let field = Self.textField(in: host) else { return }
            panel.makeFirstResponder(field)
        }
    }

    private static func textField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = textField(in: subview) { return field }
        }
        return nil
    }
}

/// A borderless panel that can take the keyboard, which a bare `NSPanel` with
/// no title bar declines to.
private final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Model

/// What the palette lists for the query, and what choosing a row does. Kept
/// off the view so the key monitor and the rows drive one highlight.
@MainActor
@Observable
final class CommandPaletteModel {
    var query = "" {
        didSet { if query != oldValue { highlighted = 0 } }
    }
    var highlighted = 0

    func reset() {
        query = ""
        highlighted = 0
    }

    struct Command: Identifiable, Hashable {
        let id: String
        let title: String
        let symbol: String
        let shortcut: String?
    }

    enum Entry: Identifiable, Hashable {
        case command(Command)
        case project(Project)
        case note(Note)
        case task(TaskItem)

        var id: String {
            switch self {
            case .command(let c): "command.\(c.id)"
            case .project(let p): "project.\(p.id.uuidString)"
            case .note(let n): "note.\(n.id.uuidString)"
            case .task(let t): "task.\(t.id.uuidString)"
            }
        }
    }

    struct Section: Identifiable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    /// How many of each kind are listed. Enough to find the one meant without
    /// the list becoming a fourth column.
    static let perSection = 8

    var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var sections: [Section] {
        var result: [Section] = []
        let commands = matchingCommands
        if !commands.isEmpty { result.append(Section(title: "Commands", entries: commands.map(Entry.command))) }
        guard hasQuery else { return result }
        let found = Library.shared.search(query)
        if !found.projects.isEmpty {
            result.append(Section(title: "Projects", entries: found.projects.prefix(Self.perSection).map(Entry.project)))
        }
        if !found.notes.isEmpty {
            result.append(Section(title: "Notes", entries: found.notes.prefix(Self.perSection).map(Entry.note)))
        }
        if !found.tasks.isEmpty {
            result.append(Section(title: "Tasks", entries: found.tasks.prefix(Self.perSection).map(Entry.task)))
        }
        return result
    }

    var entries: [Entry] { sections.flatMap(\.entries) }

    var highlightedEntry: Entry? {
        let all = entries
        return all.indices.contains(highlighted) ? all[highlighted] : nil
    }

    func move(_ delta: Int) {
        let count = entries.count
        guard count > 0 else { return }
        highlighted = (highlighted + delta + count) % count
    }

    // MARK: Commands

    private var commands: [Command] {
        [
            Command(id: "newNote", title: "New Note", symbol: "square.and.pencil", shortcut: "⌘N"),
            Command(id: "newTask", title: "New Task", symbol: "checkmark.circle", shortcut: "⌘T"),
            Command(id: "newProject", title: "New Project", symbol: "folder.badge.plus", shortcut: "⇧⌘N"),
            Command(
                id: "toggleSidebar",
                title: AppState.shared.sidebarVisible ? "Hide Projects" : "Show Projects",
                symbol: "sidebar.left",
                shortcut: "⌘§"
            ),
            Command(id: "settings", title: "Settings…", symbol: "gearshape", shortcut: "⌘,"),
        ]
    }

    private var matchingCommands: [Command] {
        guard hasQuery else { return commands }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return commands.filter {
            $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    // MARK: Actions

    func perform(_ entry: Entry) {
        let appState = AppState.shared
        let library = Library.shared
        switch entry {
        case .command(let command):
            switch command.id {
            case "newNote": NotificationCenter.default.post(name: .newNote, object: nil)
            case "newTask": NotificationCenter.default.post(name: .newTask, object: nil)
            case "newProject": NotificationCenter.default.post(name: .newProject, object: nil)
            case "toggleSidebar": NotificationCenter.default.post(name: .toggleSidebar, object: nil)
            case "settings": SettingsWindowController.shared.show()
            default: break
            }

        case .project(let project):
            appState.selectedProjectID = project.id
            library.touchProject(id: project.id)

        case .note(let note):
            // Whatever would hide it steps aside: another project, another type.
            if let selected = appState.selectedProjectID, !note.projectIDs.contains(selected) {
                appState.selectedProjectID = nil
            }
            if let type = appState.noteTypeFilter, type != note.typeID {
                appState.noteTypeFilter = nil
            }
            NotificationCenter.default.post(name: .revealNote, object: note.id)

        case .task(let task):
            if let selected = appState.selectedProjectID, !task.projectIDs.contains(selected) {
                appState.selectedProjectID = nil
            }
            if !appState.taskFilter.matches(task) { appState.taskFilter = .all }
            if let window = appState.taskDateFilter, !window.matches(task, now: DayClock.shared.today) {
                appState.taskDateFilter = nil
            }
            NotificationCenter.default.post(name: .revealTask, object: task.id)
        }
    }
}

// MARK: - View

/// The palette's face: the field, then the sections. **Opaque**, on the theme's
/// card face with a firm edge, where the `@project` dropdown is glass: it
/// floats over two columns of cards, and glass over cards read as washed into
/// them (reported as "diluted"). A card over the cards is the right reading —
/// the same object, lifted, with the panel's shadow doing the separating.
struct CommandPaletteView: View {
    @Bindable var model: CommandPaletteModel
    let onSize: (CGSize) -> Void

    @Environment(SettingsStore.self) private var settings
    @Environment(Library.self) private var library
    @FocusState private var focused: Bool
    @State private var listHeight: CGFloat = 0

    private static let maxListHeight: CGFloat = 380
    private static let radius: CGFloat = 12

    var body: some View {
        let sections = model.sections
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Search notes, projects & tasks", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if !sections.isEmpty {
                Rectangle().fill(Stone.line).frame(height: 0.5)
                results(sections)
            } else if model.hasQuery {
                Rectangle().fill(Stone.line).frame(height: 0.5)
                Text("No matches")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            }
        }
        .frame(width: CommandPalette.width)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .fill(settings.theme.cardFace)
        }
        .overlay {
            // A full point at 18% rather than the cards' half-point hairline:
            // the edge is the one line between this surface and cards of the
            // same colour, so it has to be seen.
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(.primary.opacity(0.18), lineWidth: 1)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .onAppear { focused = true }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func results(_ sections: [CommandPaletteModel.Section]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(sections) { section in
                        Text(section.title.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(settings.theme.metaText)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 3)
                        ForEach(section.entries) { entry in
                            row(entry)
                        }
                    }
                }
                .padding(8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(listHeight, Self.maxListHeight))
            .onChange(of: model.highlighted) { _, index in
                guard let entry = model.entries[safe: index] else { return }
                proxy.scrollTo(entry.id)
            }
        }
    }

    private func row(_ entry: CommandPaletteModel.Entry) -> some View {
        let index = model.entries.firstIndex(of: entry) ?? -1
        let lit = index == model.highlighted
        return Button {
            CommandPalette.shared.activate(entry)
        } label: {
            HStack(spacing: 10) {
                icon(entry)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(entry))
                        .font(.body)
                        .lineLimit(1)
                    if let sub = subtitle(entry) {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if case .command(let command) = entry, let shortcut = command.shortcut {
                    // A keycap rather than grey text: the shortcut is the thing
                    // worth learning from this list, so it reads at full
                    // strength on its own small ground.
                    Text(shortcut)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(.primary.opacity(0.08))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(.primary.opacity(0.14), lineWidth: 0.5)
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(settings.theme.primary.opacity(lit ? 0.22 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .id(entry.id)
        .onHover { if $0, index >= 0 { model.highlighted = index } }
    }

    @ViewBuilder
    private func icon(_ entry: CommandPaletteModel.Entry) -> some View {
        switch entry {
        case .command(let command):
            Image(systemName: command.symbol).foregroundStyle(.secondary)
        case .project(let project):
            Image(systemName: project.symbol).foregroundStyle(project.tint.accent)
        case .note(let note):
            Circle().fill(settings.noteType(id: note.typeID).tint.accent).frame(width: 8, height: 8)
        case .task(let task):
            Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.done ? AnyShapeStyle(.secondary) : AnyShapeStyle(settings.theme.primary))
        }
    }

    private func title(_ entry: CommandPaletteModel.Entry) -> String {
        switch entry {
        case .command(let c): c.title
        case .project(let p): p.displayName
        case .note(let n): n.displayTitle
        case .task(let t): t.displayTitle
        }
    }

    private func subtitle(_ entry: CommandPaletteModel.Entry) -> String? {
        switch entry {
        case .command: return nil
        case .project(let project):
            let notes = library.notes.filter { $0.projectIDs.contains(project.id) }.count
            let tasks = library.tasks.filter { $0.projectIDs.contains(project.id) }.count
            return "\(notes) notes · \(tasks) tasks"
        case .note(let note):
            return [settings.noteType(id: note.typeID).name, projectNames(note.projectIDs)]
                .compactMap { $0 }.joined(separator: " · ")
        case .task(let task):
            return [task.done ? "Done" : nil, projectNames(task.projectIDs)]
                .compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        }
    }

    private func projectNames(_ ids: [UUID]) -> String? {
        let names = ids.compactMap { library.project(id: $0)?.displayName }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
