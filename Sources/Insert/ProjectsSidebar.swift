import AppKit
import SwiftUI

/// The left column of the main window: a native macOS sidebar listing every
/// project, plus a pinned "Everything" entry that clears the filter.
///
/// Selection here is the single source of truth for *what the notes and tasks
/// panels show* — it drives `AppState.selectedProjectID` (nil = All). Because a
/// project's `lastUsed` powers the "Latest used" sort, selecting a project also
/// `touch`es it so the thing you just opened floats to the top next time.
///
/// The header carries the affordances the plan calls "paths the user can take":
/// sorting, adding, and (via row context menus) renaming / deleting. Add and
/// rename share one editor popover so the symbol-picker experience is identical
/// wherever a project is created or changed.
struct ProjectsSidebar: View {
    @Environment(Library.self) private var library
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    /// Whether the "new project" editor popover is open (anchored to the ＋).
    @State private var showingAdd = false
    /// The project being edited, if any. Held at the sidebar level rather than on
    /// the row: a popover attached to a `List` row goes with the row when the list
    /// re-lays out, which left the editor unreachable.
    @State private var editing: Project?
    /// The project queued for deletion, surfaced through a confirmation dialog.
    @State private var deletionCandidate: Project?
    /// Top of the header's title-bar band in window coordinates (see `header`).
    @State private var bandTop: CGFloat = 0

    var body: some View {
        // Two-way access to AppState is only legal through @Bindable inside body.
        @Bindable var appState = appState

        VStack(spacing: 0) {
            header

            // No `selection:` on purpose. SwiftUI paints the selection highlight
            // in the *system* accent and offers no way to recolour or suppress it,
            // so covering it with an opaque fill only worked while our inset and
            // radius matched its own. Instead the rows are buttons and the
            // highlight is entirely ours; arrow keys are handled below.
            List {
                everythingRow

                if visibleProjects.isEmpty {
                    emptyState
                } else {
                    ForEach(visibleProjects) { project in
                        projectRow(project)
                    }
                    // Manual drag-and-drop ordering. Disabled while searching,
                    // where the visible rows don't line up with the full list.
                    .onMove { offsets, destination in
                        guard !appState.isSearching else { return }
                        library.moveProjects(fromOffsets: offsets, toOffset: destination)
                    }
                }
            }
            .listStyle(.sidebar)
            // The column's frosting is applied below, over the window's
            // backdrop; without this the List paints its own opaque sidebar
            // background on top of it and the gradient stops at the divider.
            .scrollContentBackground(.hidden)
            // ↑/↓ walk the same list the rows show, so keyboard and mouse agree
            // even while a search is filtering it.
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .up: moveSelection(by: -1)
                case .down: moveSelection(by: 1)
                default: break
                }
            }
        }
        // Reclaim the title-bar strip: the sidebar's content runs to the very
        // top of the window so the "Projects" header sits level with the
        // traffic lights rather than in a band below them. `header` insets
        // itself past the lights.
        .ignoresSafeArea(.container, edges: .top)
        // Liquid Glass over the window's backdrop, so the column refracts the
        // gradient instead of merely dimming it — the same treatment the toolbar's
        // search field wears, which is what the two large glass surfaces in this
        // window need to have in common. With no backdrop there's nothing of ours
        // to refract, so this drops out entirely and AppKit's own sidebar material
        // (and its desktop translucency) is left alone.
        //
        // The `if` lives *inside* the background builder on purpose. Branching
        // around the column itself would give the `List` a new identity every time
        // the setting changed, which tears down the split view's autosaved widths
        // — the same trap `Backdrop.windowStyle` documents. Here only the
        // background layer is rebuilt.
        .background {
            if settings.backdrop.frostsSidebar {
                // `.ignoresSafeArea()` is the whole reason this reads as one
                // column. The sidebar's content already ignores the top safe area
                // so the header can sit level with the traffic lights, but the
                // *background* layer doesn't inherit that: left alone it starts
                // below the toolbar's inset, and the titlebar band above it ends
                // up with one fewer glass layer than everything below. The join
                // showed as a hard horizontal seam right under the traffic lights
                // — which reads as two stacked panels, not as a sidebar.
                Color.clear
                    .glassEffect(.regular, in: Rectangle())
                    .ignoresSafeArea()
            }
        }
        // The "New Project" menu command (⌘N) posts this; open the same flow.
        .onReceive(NotificationCenter.default.publisher(for: .newProject)) { _ in
            showingAdd = true
        }
        // Same for the editor: sidebar level, so reordering or filtering the row
        // underneath can't take it down mid-edit.
        .popover(item: $editing, arrowEdge: .trailing) { project in
            ProjectEditorPopover(
                title: "Edit Project",
                confirmTitle: "Save",
                name: project.name,
                symbol: project.symbol,
                tint: project.tint,
                onConfirm: { name, symbol, tint in
                    update(project, name: name, symbol: symbol, tint: tint)
                },
                onCancel: { editing = nil }
            )
        }
        // Delete confirmation lives at the sidebar level so it survives the row
        // being reordered or filtered out while the dialog is up.
        .confirmationDialog(
            "Delete \(deletionCandidate?.name ?? "project")?",
            isPresented: deletionDialogBinding,
            titleVisibility: .visible,
            presenting: deletionCandidate
        ) { project in
            Button("Delete", role: .destructive) { delete(project) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The project is removed and unassigned from its notes and tasks. The notes and tasks themselves are kept.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title-bar line: ＋ and the collapse control at the sidebar's
            // trailing edge, as in Safari — "hide" belongs to the sidebar it
            // hides, while "show" waits in the detail toolbar. These can't be
            // real toolbar items: declared on the sidebar column, SwiftUI lays
            // them out in the *detail* region and keeps them there when the
            // sidebar collapses, doubling up with the "show" button. So they're
            // content, centred on the traffic lights' measured centre line — the
            // same line AppKit puts the window title and search field on. The
            // spacer's minimum keeps them clear of the lights at any width.
            ZStack(alignment: .topLeading) {
                // Where this band actually starts, in the window's own
                // coordinates. It is *not* the top of the window: the sidebar is a
                // floating panel inset by a few points, which is exactly how much
                // the buttons were sitting low — the centre line is measured from
                // the window, so the offset has to be measured there too.
                Color.clear
                    .frame(height: appState.titlebarHeight)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                        if abs(top - bandTop) > 0.5 { bandTop = top }
                    }

                HStack(spacing: 2) {
                    Spacer(minLength: Metrics.trafficLightInset)
                    addButton
                    hideButton
                }
                .padding(.top, buttonRowInset)
            }

            // The heading proper, aligned with the rows it introduces. The top
            // inset matches the notes/tasks panels' own `panelPadding`, so all
            // three column titles share one baseline.
            Text("Projects")
                .font(.title2.weight(.bold))
                .padding(.leading, Metrics.sidebarTextInset)
                .padding(.top, Metrics.panelPadding)
                // Same 8pt gap the notes/tasks headers leave below their titles,
                // so the three columns breathe identically.
                .padding(.bottom, 8)
        }
        .padding(.trailing, Metrics.panelPadding)
    }

    /// A row as a button, wearing the selection pill in its own colour. A button
    /// rather than a tap gesture: gestures on `List` rows swallow clicks.
    private func selectableRow(
        tint: Tint,
        selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Button(action: action) {
            content()
                // The system used to whiten a selected row's text for us; with our
                // own pill we set it, and `.secondary` in the subtitle derives from
                // it so both lines stay legible on the fill.
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.deep)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        // The pill is a colour-only cue, so state it outright for VoiceOver.
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        // The pill *is* the selection indicator. Without this, clicking or
        // right-clicking a row also gave it the system focus ring, which traces
        // the row's full width at its own inset and radius — a blue rectangle
        // floating a few points outside our fill. Keyboard navigation is handled
        // by the List's own focus (see `onMoveCommand`), not by these buttons.
        .focusEffectDisabled()
        .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
        .listRowSeparator(.hidden)
    }

    /// Whether the row for `projectID` (nil = "Everything") is the selected one.
    private func isSelected(_ projectID: UUID?) -> Bool {
        appState.selectedProjectID == projectID
    }

    /// Sinks the button row to the traffic lights' centre line, measuring both in
    /// the window's coordinate space so the sidebar panel's own inset cancels out.
    private var buttonRowInset: CGFloat {
        max(0, appState.trafficLightCenterY - bandTop - Metrics.headerButtonSize / 2)
    }

    /// Collapses the sidebar. Same glyph and shortcut as the detail toolbar's
    /// "show", so the pair reads as one control that moves with the sidebar —
    /// plain rather than a glass circle: it sits on the sidebar's own material,
    /// where a second surface would fight it.
    private var hideButton: some View {
        Button {
            // Routed through the notification so the collapse animates exactly
            // like ⌘§ and the menu item (see `RootView.toggleSidebar`).
            NotificationCenter.default.post(name: .toggleSidebar, object: nil)
        } label: {
            Image(systemName: "sidebar.left")
                // `.title3` *is* 15pt on macOS, so this looks identical while
                // tracking the system text size instead of ignoring it.
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: Metrics.headerButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Hide projects (⌘§)")
        // `.help` becomes an accessibility *hint*, not a label — without this the
        // button is announced with no name at all.
        .accessibilityLabel("Hide projects")
    }

    /// Add. Matches `hideButton` beside it — two glyphs of one weight, the way
    /// Safari pairs its own sidebar controls.
    private var addButton: some View {
        Button {
            showingAdd = true
        } label: {
            Image(systemName: "plus")
                // `.title3` *is* 15pt on macOS, so this looks identical while
                // tracking the system text size instead of ignoring it.
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: Metrics.headerButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New project")
        .accessibilityLabel("New project")
        .popover(isPresented: $showingAdd, arrowEdge: .bottom) {
            ProjectEditorPopover(
                title: "New Project",
                confirmTitle: "Add",
                onConfirm: { name, symbol, tint in add(name: name, symbol: symbol, tint: tint) },
                onCancel: { showingAdd = false }
            )
        }
    }

    // MARK: - Rows

    private var everythingRow: some View {
        // Grey, not a project colour: "Everything" is the absence of a filter,
        // and the neutral keeps it in the same stone family as the task rows.
        selectableRow(tint: .gray, selected: isSelected(nil)) {
            select(nil)
        } content: {
            rowLabel(
                leading: {
                    Image(systemName: SymbolCatalog.everything)
                        .font(.body)
                        // White on the highlight, its own colour off it.
                        .foregroundStyle(isSelected(nil)
                            ? AnyShapeStyle(.white)
                            : AnyShapeStyle(Tint.gray.ink))
                        .frame(width: 22)
                        // Decorative: the row's title says the same thing.
                        .accessibilityHidden(true)
                },
                title: "Everything",
                subtitle: everythingSubtitle
            )
        }
    }

    private func projectRow(_ project: Project) -> some View {
        let counts = library.counts(forProject: project.id)
        return selectableRow(tint: project.tint, selected: isSelected(project.id)) {
            select(project.id)
        } content: {
            rowLabel(
                leading: {
                    Image(systemName: project.symbol)
                        .font(.body)
                        .foregroundStyle(isSelected(project.id)
                            ? AnyShapeStyle(.white)
                            : AnyShapeStyle(project.tint.ink))
                        .frame(width: 22)
                        .accessibilityHidden(true)
                },
                title: project.name,
                subtitle: countsLabel(notes: counts.notes, tasks: counts.tasks)
            )
        }
        // Right-click to edit name / symbol / colour. Ours rather than
        // `.contextMenu` — see `rightClickMenu`. Deliberately *no* tap gesture
        // here either: any `onTapGesture` on a `List` row swallows the click the
        // list needs for selection, which made picking a project unreliable.
        .rightClickMenu([
            .command(title: "Edit…", action: { editing = project }),
            .separator,
            .command(title: "Delete…", action: { deletionCandidate = project }),
        ])
        // `rightClickMenu` is an AppKit overlay that only answers a right- or
        // control-click, so editing and deleting were reachable by pointer alone.
        // These expose the same two commands to VoiceOver's actions rotor.
        .accessibilityAction(named: "Edit") { editing = project }
        .accessibilityAction(named: "Delete") { deletionCandidate = project }
    }

    /// Shared row scaffold: a leading glyph, the name, and a dimmed subtitle.
    private func rowLabel(
        @ViewBuilder leading: () -> some View,
        title: String,
        subtitle: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 10) {
            leading()
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: appState.isSearching ? "magnifyingglass" : "square.stack.3d.up.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
                // Decorative — the two lines below carry the message.
                .accessibilityHidden(true)
            Text(appState.isSearching ? "No matching projects" : "No projects yet")
                .font(.callout.weight(.medium))
            Text(appState.isSearching
                 ? "Try a different search."
                 : "Create your first project with the ＋ button above.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: - Derived data

    /// Projects in their manual (drag-and-drop) order, narrowed to the live
    /// search when active.
    private var visibleProjects: [Project] {
        let ordered = library.projects
        guard appState.isSearching else { return ordered }
        let query = appState.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ordered.filter { $0.name.lowercased().contains(query) }
    }

    private var everythingSubtitle: LocalizedStringKey {
        countsLabel(notes: library.notes.count, tasks: library.tasks.count)
    }

    /// "3 notes · 1 task", pluralized by Foundation's inflection engine rather
    /// than by hand: `word == 1 ? "note" : "notes"` only ever works in English,
    /// and languages with more than two plural forms can't be expressed that way
    /// at all. `^[…](inflect: true)` agrees the noun with the number it follows
    /// and is what a translator will localize.
    private func countsLabel(notes: Int, tasks: Int) -> LocalizedStringKey {
        "^[\(notes) note](inflect: true) · ^[\(tasks) task](inflect: true)"
    }

    // MARK: - Bindings

    /// Maps the enum-tagged List selection onto `AppState.selectedProjectID`,
    /// touching a project as it becomes selected so "Latest used" stays honest.
    /// Select a project (or "Everything" with `nil`). Selecting a project also
    /// `touch`es it, so "Latest used" sorting floats what you just opened.
    private func select(_ projectID: UUID?) {
        appState.selectedProjectID = projectID
        if let projectID { library.touchProject(id: projectID) }
    }

    /// Move the selection `offset` rows through the *visible* list, "Everything"
    /// included, clamped at both ends.
    private func moveSelection(by offset: Int) {
        let rows: [UUID?] = [nil] + visibleProjects.map { $0.id }
        let current = rows.firstIndex(of: appState.selectedProjectID) ?? 0
        let next = min(max(current + offset, 0), rows.count - 1)
        guard next != current else { return }
        select(rows[next])
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { deletionCandidate != nil },
            set: { isShown in if !isShown { deletionCandidate = nil } }
        )
    }

    // MARK: - Mutations

    private func add(name: String, symbol: String, tint: Tint) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let project = library.addProject(name: trimmed, symbol: symbol, tint: tint)
        appState.selectedProjectID = project.id
        showingAdd = false
    }

    private func update(_ project: Project, name: String, symbol: String, tint: Tint) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = project
        updated.name = trimmed
        updated.symbol = symbol
        updated.tint = tint
        library.updateProject(updated)
        editing = nil
    }

    private func delete(_ project: Project) {
        library.deleteProject(id: project.id)
        // Don't strand the user on a project that no longer exists.
        if appState.selectedProjectID == project.id {
            appState.selectedProjectID = nil
        }
        deletionCandidate = nil
    }
}

// MARK: - Right-click menu

/// One entry of a `rightClickMenu(_:)`: a command, or a divider between them.
/// No destructive role: macOS contextual menus don't tint destructive items, so
/// there is nothing to carry across.
enum RowMenuEntry {
    case command(title: String, action: () -> Void)
    case separator
}

extension View {
    /// A contextual menu that is *not* SwiftUI's `.contextMenu`.
    ///
    /// On a `List` row, `.contextMenu` goes through AppKit's table view, which
    /// rings the whole row in the accent colour for as long as the menu is up —
    /// the blue rectangle sitting a few points outside our selection pill, drawn
    /// at the row's width and its own corner radius. Nothing restyles or
    /// suppresses it (`.focusEffectDisabled()` only covers the *focus* ring a
    /// click leaves behind), so the right-click is ours instead: an otherwise
    /// invisible overlay claims it and pops the same system menu, leaving the
    /// pill as the row's only highlight.
    func rightClickMenu(_ entries: [RowMenuEntry]) -> some View {
        overlay(RightClickMenu(entries: entries))
    }
}

private struct RightClickMenu: NSViewRepresentable {
    let entries: [RowMenuEntry]

    func makeNSView(context: Context) -> RightClickView { RightClickView() }

    func updateNSView(_ view: RightClickView, context: Context) {
        view.entries = entries
    }
}

/// Transparent to every event except the right- (or control-) click it exists
/// for, which AppKit answers by asking for `menu(for:)` and popping it itself.
final class RightClickView: NSView {
    var entries: [RowMenuEntry] = []

    /// Actions of the menu currently on screen, indexed by item tag: an
    /// `NSMenuItem` can only target an object and a selector, and the SwiftUI
    /// closures aren't objects.
    private var actions: [() -> Void] = []

    /// Claim the clicks this view handles and no others. Answering a plain left
    /// click would put this overlay in front of the button underneath and
    /// swallow row selection.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return super.hitTest(point)
        case .leftMouseDown, .leftMouseUp:
            // Control-click is the trackpad-friendly way to the same menu.
            return event.modifierFlags.contains(.control) ? super.hitTest(point) : nil
        default:
            return nil
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        actions = []
        let menu = NSMenu()
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case let .command(title, action):
                let item = NSMenuItem(title: title, action: #selector(invoke), keyEquivalent: "")
                item.target = self
                item.tag = actions.count
                actions.append(action)
                menu.addItem(item)
            }
        }
        return menu.items.isEmpty ? nil : menu
    }

    @objc private func invoke(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}

// MARK: - Selection model

/// The sidebar's selectable identity. Modelling "All" as a distinct case (rather
/// than an absent selection) lets the pinned row highlight like any other.
// MARK: - Project editor popover

/// The shared create/rename surface: a name field, a colour, and the searchable
/// symbol grid. Keeping its own draft state means the caller only hears the final values
/// on confirm, and empty names are rejected here too so the primary button can't
/// commit nothing.
private struct ProjectEditorPopover: View {
    let title: String
    let confirmTitle: String
    let onConfirm: (String, String, Tint) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var symbol: String
    @State private var tint: Tint
    @FocusState private var nameFocused: Bool

    init(
        title: String,
        confirmTitle: String,
        name: String = "",
        symbol: String = SymbolCatalog.defaultProject,
        tint: Tint = .blue,
        onConfirm: @escaping (String, String, Tint) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _name = State(initialValue: name)
        _symbol = State(initialValue: symbol)
        _tint = State(initialValue: tint)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)

            // The chosen symbol sits beside the name, as it will in the sidebar.
            // The name gets the whole line: sharing it with the colour swatches
            // squeezed the field until its placeholder was clipped.
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(tint.ink)
                    .frame(width: 30, height: 26)
                    .background(Capsule().fill(tint.chip))

                TextField("Project name", text: $name)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit(commit)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Stone.chip))
                    .overlay(Capsule().strokeBorder(Stone.line, lineWidth: 0.5))
            }

            TintPicker(selection: tint) { tint = $0 }

            SymbolPicker(selection: symbol, tint: tint) { symbol = $0 }
                // The picker brings its own padding and width; the popover's are
                // applied once, below.
                .padding(-12)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: commit)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { nameFocused = true }
    }

    private func commit() {
        guard !trimmedName.isEmpty else { return }
        onConfirm(trimmedName, symbol, tint)
    }
}
