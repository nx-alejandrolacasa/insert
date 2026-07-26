import AppKit
import SwiftUI

/// The center column: every note for the selected project (or all projects)
/// rendered as an expanded, editable Liquid Glass "island". Notes are edited
/// in place — there is no separate detail view — so each card carries its own
/// title / symbol / type / body editors and persists changes back to the
/// `Library` on a short debounce.
///
/// State ownership:
/// - The type filter lives on `AppState` so it survives project switches and
///   stays in sync with the toolbar search; the sort order is a persisted
///   preference (Settings → General) rather than a per-window control.
/// - Per-note draft/editing state lives inside `NoteCardView` and is reset per
///   identity (`.id(note.id)`), which keeps unrelated cards from sharing focus
///   or half-typed edits.
struct NotesPanel: View {
    @Environment(Library.self) private var library
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    /// The most recently created note, so we can scroll to and focus it. Cards
    /// read this to decide whether to grab focus on appear.
    @State private var newlyCreatedID: UUID?

    var body: some View {
        // Sort order is a preference (Settings → General), not a per-window
        // control, which keeps this header down to a title and one button.
        let notes = library.notes(
            forProject: appState.selectedProjectID,
            sort: settings.noteSort,
            typeFilter: appState.noteTypeFilter,
            search: appState.searchText
        )

        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Metrics.panelPadding)
                    .padding(.top, Metrics.panelPadding)
                    .padding(.bottom, 8)

                typeFilterPills
                    .padding(.horizontal, Metrics.panelPadding)
                    .padding(.bottom, Metrics.headerGap)

                if notes.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        // No `GlassEffectContainer` here: with islands a card's
                        // spacing apart, it merges them into one glass slab
                        // instead of blending their edges.
                        LazyVStack(spacing: Metrics.cardSpacing) {
                            ForEach(notes) { note in
                                NoteCardView(
                                    note: note,
                                    showsProjectChips: appState.selectedProjectID == nil
                                )
                                .id(note.id)
                            }
                        }
                        .padding(.horizontal, Metrics.panelPadding)
                        .padding(.bottom, Metrics.panelPadding)
                    }
                }
            }
            // The window menu / ⌘N posts `.newNote`; the local button routes
            // through the same path so both create-and-focus consistently.
            .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in
                createNote(proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            // Always "Notes": the window title already names the selected
            // project, so restating it here just made the column heading
            // flicker on every selection change.
            Text("Notes")
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button {
                // The button needs the scroll proxy to focus the new note, so
                // it re-uses the notification the reader already listens for.
                NotificationCenter.default.post(name: .newNote, object: nil)
            } label: {
                Label("New Note", systemImage: "plus")
                    .fontWeight(.semibold)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .help("Create a new note (⌘N)")
        }
    }

    // MARK: - Type filter pills

    /// A second header row: one pill per note type, tapped to filter the list.
    /// The choices are visible at a glance and each pill wears its type's colour,
    /// so the row doubles as a legend. Single-select, matching the tasks column:
    /// picking a type replaces the previous one, and "All" clears the filter.
    private var typeFilterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterPill(
                    label: "All",
                    symbol: nil,
                    tint: .gray,
                    selected: appState.noteTypeFilter == nil
                ) {
                    appState.noteTypeFilter = nil
                }

                ForEach(settings.noteTypes) { type in
                    FilterPill(
                        label: type.name,
                        symbol: type.symbol,
                        tint: type.tint,
                        selected: appState.noteTypeFilter == type.id
                    ) {
                        appState.noteTypeFilter = type.id
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.headline)
                .foregroundStyle(.secondary)
            if !appState.isSearching && appState.noteTypeFilter == nil {
                Button {
                    NotificationCenter.default.post(name: .newNote, object: nil)
                } label: {
                    Label("New Note", systemImage: "plus").fontWeight(.semibold)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyMessage: String {
        if appState.isSearching { return "No notes match your search" }
        if appState.noteTypeFilter != nil { return "No notes of this type" }
        return "No notes yet"
    }

    // MARK: - Actions

    /// Creates a note in the current project, then scrolls to and focuses it.
    private func createNote(proxy: ScrollViewProxy) {
        let note = library.addNote(
            type: settings.noteType(id: NoteType.noteID),
            projectIDs: appState.selectedProjectID.map { [$0] } ?? []
        )
        newlyCreatedID = note.id
        // Open the new note straight into edit mode so the type pills and the
        // Markdown editor are ready immediately.
        appState.selectedNoteID = note.id
        // Let the list rebuild before scrolling so the target row exists.
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(note.id, anchor: .top)
            }
        }
    }
}

// MARK: - Note card

/// A single note rendered as a Liquid Glass island with two modes:
///
/// - **View mode** (the note isn't selected): the body is shown as *rendered*
///   Markdown and the whole card is a tap target that opens it for editing.
/// - **Edit mode** (the note is selected via `AppState.selectedNoteID`): the
///   symbol, title, **type pills** and the raw Markdown source become editable.
///
/// It owns a mutable `draft` so typing is instant; writes are coalesced onto a
/// ~0.4s debounce and flushed when editing ends or the card goes away.
private struct NoteCardView: View {
    /// The canonical note from the library. Changes here (e.g. an external
    /// Obsidian edit, or our own save bumping `updated`) flow in via `onChange`.
    let note: Note
    /// Only the aggregate view labels a note with the project(s) it belongs to;
    /// inside a project that would repeat the sidebar selection on every card.
    let showsProjectChips: Bool

    @Environment(Library.self) private var library
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var appState

    /// The live, editable copy. Seeded from `note` and re-synced when the
    /// upstream note meaningfully changes.
    @State private var draft: Note
    /// The in-flight debounced save, cancelled and restarted on every edit.
    @State private var saveTask: Task<Void, Never>?

    @State private var showingSymbolPicker = false
    /// Height of the rendered body text, so the editor grows with content
    /// instead of the greedy `TextEditor` filling the whole scroll viewport.
    @State private var measuredBodyHeight: CGFloat = 34
    @FocusState private var titleFocused: Bool
    @FocusState private var bodyFocused: Bool

    init(note: Note, showsProjectChips: Bool) {
        self.note = note
        self.showsProjectChips = showsProjectChips
        _draft = State(initialValue: note)
    }

    private var type: NoteType { settings.noteType(id: draft.typeID) }
    /// This card is the one currently open for editing.
    private var isEditing: Bool { appState.selectedNoteID == note.id }

    var body: some View {
        tappableIsland
        // Adopt upstream changes without clobbering local edits or looping on
        // our own timestamp-only updates: only re-seed when content differs.
        .onChange(of: note) { _, newValue in
            if newValue.title != draft.title
                || newValue.body != draft.body
                || newValue.symbol != draft.symbol
                || newValue.typeID != draft.typeID
                || newValue.projectIDs != draft.projectIDs {
                draft = newValue
            }
        }
        .onChange(of: draft.title) { scheduleSave() }
        .onChange(of: draft.body) { scheduleSave() }
        .onChange(of: draft.symbol) { scheduleSave() }
        .onChange(of: draft.typeID) { scheduleSave() }
        .onChange(of: draft.projectIDs) { scheduleSave() }
        .onAppear { if isEditing { focusForEntry() } }
        // Focus on entering edit; flush the pending save on leaving it (e.g.
        // when another note is selected).
        .onChange(of: isEditing) { _, editing in
            if editing { focusForEntry() } else { flushSave() }
        }
        .onDisappear { flushSave() }
    }

    /// The card island. In view mode the whole island is a tap target that opens
    /// edit mode; in edit mode no container gesture is attached, so taps reach
    /// the title / body fields normally.
    @ViewBuilder
    private var tappableIsland: some View {
        let island = VStack(alignment: .leading, spacing: 8) {
            titleRow
            if isEditing {
                // Pills sit *under* the editor: between title and body they cut
                // the note in half and pushed the text you're writing down the
                // card.
                bodyEditor
                typePills
                projectRow
            } else {
                bodyView
                if showsProjectChips { projectRow }
            }
            footer
        }
        .padding(12)
        .island(tint: type.tint)
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: Metrics.islandRadius, style: .continuous)
                    .strokeBorder(type.tint.accent.opacity(0.55), lineWidth: 1.5)
            }
        }

        if isEditing {
            island
        } else {
            island
                .contentShape(RoundedRectangle(cornerRadius: Metrics.islandRadius, style: .continuous))
                .onTapGesture { enterEdit() }
        }
    }

    // MARK: Title row

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 10) {
            // Emoji and title read as one unit, so they sit closer together than
            // the row's other gaps.
            HStack(alignment: .center, spacing: 4) {
                if isEditing {
                    symbolButton
                    // `#project` tags a project and is stripped from the title,
                    // same as in the task composer.
                    ProjectHashField(
                        placeholder: "Title  (type # to tag a project)",
                        text: $draft.title,
                        assigned: $draft.projectIDs,
                        font: .title3.weight(.bold),
                        onEscape: { exitEdit() },
                        focused: $titleFocused
                    )
                } else {
                    Image(systemName: draft.symbol)
                        .font(.system(size: 15))
                        .foregroundStyle(type.tint.deep)
                        .frame(width: 26, height: 26)
                    Text(draft.displayTitle)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if isEditing {
                Button("Done") { exitEdit() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }

            actionsMenu
        }
    }

    private var symbolButton: some View {
        Button {
            showingSymbolPicker = true
        } label: {
            Image(systemName: draft.symbol)
                .font(.system(size: 15))
                .foregroundStyle(type.tint.deep)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Stone.surface)
                )
        }
        .buttonStyle(.plain)
        .help("Change symbol")
        .popover(isPresented: $showingSymbolPicker, arrowEdge: .bottom) {
            SymbolPicker(selection: draft.symbol, tint: type.tint) { picked in
                draft.symbol = picked
                showingSymbolPicker = false
            }
            .frame(width: 320)
        }
    }

    // MARK: Project assignments

    /// The projects this note belongs to. While editing, the chips are removable
    /// (double-click) and a ＋ adds more, exactly as on a task row; in view mode
    /// it's a read-only label, with "Unassigned" spelled out so a stray note is
    /// easy to spot in the aggregate list.
    @ViewBuilder
    private var projectRow: some View {
        if isEditing {
            HStack(spacing: 6) {
                ForEach(draft.projectIDs, id: \.self) { id in
                    if let project = library.project(id: id) {
                        ProjectChip(project: project) {
                            draft.projectIDs.removeAll { $0 == id }
                        }
                    }
                }
                AddProjectMenu(assigned: draft.projectIDs) { draft.projectIDs.append($0) }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 6) {
                if draft.projectIDs.isEmpty {
                    projectLabel("Unassigned", symbol: "circle.dashed", tint: .gray)
                } else {
                    ForEach(draft.projectIDs, id: \.self) { id in
                        if let project = library.project(id: id) {
                            projectLabel(project.name, symbol: project.symbol, tint: project.tint)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func projectLabel(_ name: String, symbol: String, tint: Tint) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(tint.deep)
            Text(name)
        }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.chip))
    }

    // MARK: Type pills

    /// One pill per configured type; the selected one is filled with its accent.
    /// Doubles as the "pick a type" affordance for a freshly created note and as
    /// a way to re-categorize an existing one later.
    private var typePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(settings.noteTypes) { pillType in
                    let selected = pillType.id == draft.typeID
                    Button {
                        selectType(pillType)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: pillType.symbol)
                            Text(pillType.name)
                        }
                            .font(.caption.weight(selected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            // Constant wash, accented border for the current
                            // type — same language as the filter pills above
                            // (see `FilterPill`).
                            .background(Capsule().fill(pillType.tint.chip))
                            .overlay(
                                Capsule().strokeBorder(
                                    selected ? pillType.tint.deep.opacity(0.45) : Stone.line,
                                    lineWidth: selected ? 1 : 0.5
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(selected ? "\(pillType.name) (current type)" : "Mark as \(pillType.name)")
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// Switching type also swaps the symbol when the note still uses the previous
    /// type's default, so untouched icons track the category.
    private func selectType(_ newType: NoteType) {
        guard newType.id != draft.typeID else { return }
        let previous = settings.noteType(id: draft.typeID)
        if draft.symbol == previous.symbol {
            draft.symbol = newType.symbol
        }
        draft.typeID = newType.id
    }

    // MARK: Body — view mode

    /// Rendered Markdown shown when the note isn't being edited.
    @ViewBuilder
    private var bodyView: some View {
        if draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Empty note — tap to write")
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            MarkdownText(markdown: draft.body)
        }
    }

    // MARK: Body — edit mode

    /// A plain Markdown text editor that grows with its content (a hidden text
    /// proxy drives the height) so notes read as fully expanded, not boxed.
    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            // Invisible sizing proxy (same font/insets as the editor). It stays
            // in the layout so the ZStack height tracks the wrapped text; the
            // editor is then pinned to that height rather than growing greedily.
            Text(draft.body.isEmpty ? " " : draft.body)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 5)
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    measuredBodyHeight = $0
                }

            if draft.body.isEmpty && !bodyFocused {
                Text("Write in Markdown…")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 9)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $draft.body)
                .font(.body)
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($bodyFocused)
                .frame(height: max(34, measuredBodyHeight))
                // Esc leaves the Markdown editor, matching the title field.
                .onKeyPress(.escape) {
                    exitEdit()
                    return .handled
                }
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text(note.updated, format: .dateTime.month().day().year().hour().minute())
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    /// The "⋯" actions menu. Offers Edit in view mode and Delete everywhere.
    private var actionsMenu: some View {
        Menu {
            if !isEditing {
                Button { enterEdit() } label: { Label("Edit", systemImage: "pencil") }
            }
            Button(role: .destructive) {
                saveTask?.cancel()
                if isEditing { appState.selectedNoteID = nil }
                library.deleteNote(id: draft.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Note actions")
    }

    // MARK: Mode

    private func enterEdit() { appState.selectedNoteID = note.id }

    private func exitEdit() {
        flushSave()
        if isEditing { appState.selectedNoteID = nil }
    }

    /// Put the cursor where it's most useful: the title for a brand-new note,
    /// otherwise straight into the body.
    private func focusForEntry() {
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            titleFocused = true
        } else {
            bodyFocused = true
        }
    }

    // MARK: Persistence

    /// Restart the debounce: persist ~0.4s after the last edit. The snapshot is
    /// captured by value so a later keystroke can't mutate what we're saving.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = draft
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            library.updateNote(snapshot)
            saveTask = nil
        }
    }

    /// Persist immediately, cancelling any pending debounce (used when editing
    /// ends so nothing is lost).
    private func flushSave() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        library.updateNote(draft)
    }
}
