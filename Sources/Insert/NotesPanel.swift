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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The most recently created note, so we can scroll to and focus it. Cards
    /// read this to decide whether to grab focus on appear.
    @State private var newlyCreatedID: UUID?

    /// A note opened for editing keeps the `updated` it had at that moment, so
    /// its debounced saves don't slide the card out from under the cursor. Held
    /// until the list is rebuilt for another reason. See `NotePins`.
    @State private var pins = NotePins()

    var body: some View {
        // Sort order is a preference (Settings → General), not a per-window
        // control, which keeps this header down to a title and one button.
        let notes = library.notes(
            forProject: appState.selectedProjectID,
            sort: settings.noteSort,
            typeFilter: appState.noteTypeFilter,
            search: appState.searchText,
            pinned: pins
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
        // One choke point for every route into edit mode — a tap on a card, ⌘N,
        // the ⋯ menu — since they all go through `selectedNoteID`.
        .onChange(of: appState.selectedNoteID) { _, id in
            if let note = library.notes.first(where: { $0.id == id }) { pins.pin(note) }
        }
        // The list re-sorts when you change what it's showing, and only then: on
        // those frames it is being rebuilt from scratch anyway, so a note taking
        // its new place is invisible rather than a card jumping under your eye.
        .onChange(of: appState.selectedProjectID) { pins = NotePins() }
        .onChange(of: appState.noteTypeFilter) { pins = NotePins() }
        .onChange(of: appState.searchText) { pins = NotePins() }
        .onChange(of: settings.noteSort) { pins = NotePins() }
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
            // Not `.glassProminent` (it paints the system accent) and no longer
            // plain `.glass` either (glass casts a drop shadow, and this window
            // doesn't) — see `FlatButtonStyle` for both arguments. The
            // semibold label is what carries "primary action" now; it doesn't need
            // a colour to.
            .buttonStyle(.actionCapsule)
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
                // Regular, not Light: HIG calls out Ultralight/Thin/Light as hard
                // to see, and at `.secondary` this glyph was already faint.
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(emptyMessage)
                .font(.headline)
                .foregroundStyle(.secondary)
            if !appState.isSearching && appState.noteTypeFilter == nil {
                Button {
                    NotificationCenter.default.post(name: .newNote, object: nil)
                } label: {
                    Label("New Note", systemImage: "plus").fontWeight(.semibold)
                }
                .buttonStyle(.actionCapsule)
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
        // Anything that would hide the new note gets out of the way first: it
        // is born as the default type, so any other type filter would swallow
        // it, and an empty note matches no search.
        if appState.noteTypeFilter != nil && appState.noteTypeFilter != NoteType.noteID {
            appState.noteTypeFilter = nil
        }
        appState.searchText = ""

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
            // Reduce Motion means jump straight there rather than scroll.
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    /// The body editor's caret/selection, held here so `focusForEntry()` can
    /// place it. Left alone otherwise — the editor writes the user's own
    /// selection back through it.
    @State private var bodySelection: TextSelection?

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
        // Focus on entering edit; persist-or-discard on leaving it (e.g. when
        // another note is selected).
        .onChange(of: isEditing) { _, editing in
            if editing { focusForEntry() } else { finishEditing() }
        }
        .onDisappear {
            // Settle any pending edit — including mid-edit, where an empty
            // note must still be discarded rather than flushed.
            if isEditing { finishEditing() } else { flushSave() }
        }
    }

    /// The card island. In view mode the whole island is a tap target that opens
    /// edit mode; while editing the gesture is switched off, so taps reach the
    /// title / body fields normally.
    ///
    /// One view for both modes, not `if isEditing { island } else { island.… }`:
    /// see `TaskCardView.tappableCard` for why that conditional had to go —
    /// two branches are two identities, so entering edit mode replaced the card
    /// instead of resizing it and its height could not be animated.
    private var tappableIsland: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow
                // The title's `#project` dropdown drops over the body editor
                // below; without this the editor — a later sibling — would sit
                // on top of it and take its clicks.
                .zIndex(1)
            // The chips row sits *under* the body: between title and body it cut
            // the note in half and pushed the text you're writing down the card.
            bodyArea
            if isEditing || showsProjectChips { projectRow }
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
        .contentShape(RoundedRectangle(cornerRadius: Metrics.islandRadius, style: .continuous))
        .gesture(TapGesture().onEnded { enterEdit() }, isEnabled: !isEditing)
        // A bare tap gesture is invisible to VoiceOver, Switch Control and Voice
        // Control, so opening a note was pointer-only. The card becomes a
        // container carrying the same command as an action; the ⋯ menu's "Edit"
        // covers the keyboard. In a builder so it can go while editing without
        // splitting the card into two views.
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if !isEditing {
                Button("Edit note") { enterEdit() }
            }
        }
        // Same curve as a task row's: opening a card swaps rendered Markdown for
        // the editor and adds a row of chips, and the cards below it move by that
        // difference.
        .animation(
            reduceMotion ? nil : .smooth(duration: Metrics.cardModeDuration),
            value: isEditing
        )
    }

    /// The body: the editor while editing, rendered Markdown otherwise, changed
    /// over in one frame with only the card's height animating. See
    /// `TaskCardView.bodyArea` for what `.transition(.identity)` is keeping out
    /// and what was tried in its place.
    @ViewBuilder
    private var bodyArea: some View {
        if isEditing {
            bodyEditor.transition(.identity)
        } else {
            bodyView.transition(.identity)
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
                        .font(.title3)
                        .foregroundStyle(type.tint.ink)
                        .frame(width: 26, height: 26)
                        // The type pills below name the category; this glyph is
                        // decoration on top of the title beside it.
                        .accessibilityHidden(true)
                    Text(draft.displayTitle)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if isEditing {
                // Flat, like "New Note" above it: glass drew its own drop
                // shadow, and one lifted button inside a flat card was the only
                // thing in the window casting light. `.small` keeps the size it
                // had — `.actionCapsule` pads off `.controlSize`, and the
                // capsule is the style's own shape, so no `buttonBorderShape`.
                Button("Done") { exitEdit() }
                    .buttonStyle(.actionCapsule)
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
                .font(.title3)
                .foregroundStyle(type.tint.ink)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Stone.surface)
                )
        }
        .buttonStyle(.plain)
        .help("Change symbol")
        .accessibilityLabel("Change symbol")
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
                // Bare ＋ beside chips it extends; the full wording only when
                // it stands alone.
                AddProjectMenu(assigned: draft.projectIDs, compact: !draft.projectIDs.isEmpty) {
                    draft.projectIDs.append($0)
                }
                Spacer(minLength: 0)
                // Trailing, the way a task row hangs its due badge off the end
                // of the same chips row: the type is one value, so it belongs
                // on the fixed edge rather than drifting rightwards as chips
                // are added.
                typeMenu
            }
        } else {
            HStack(spacing: 6) {
                if draft.projectIDs.isEmpty {
                    // Actionable where "Unassigned" was inert: the same pill
                    // flags the stray note *and* fixes it.
                    AddProjectMenu(assigned: draft.projectIDs) { draft.projectIDs.append($0) }
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
                .foregroundStyle(tint.ink)
            Text(name)
        }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .chipHeight()
            .background(Capsule().fill(tint.chip))
    }

    // MARK: Type menu

    /// The note's type as a pill-shaped dropdown, wearing that type's `deep` fill
    /// with a chevron — a pop-up button drawn as one of the app's own pills, not
    /// a `Picker`, which would redraw it in system chrome and lose the colour.
    ///
    /// It replaced a row of one `FilterPill` per type, which is what the tint's
    /// `deep`-and-white here is borrowed from: the *selected* state of that row,
    /// since this control shows exactly one type and it is always the current
    /// one. The row cost a whole line of the card and grew with every type added
    /// in Settings, where the note being edited is what should have the space;
    /// the dropdown costs a badge. Nothing is lost but the second glance —
    /// which type is set is still on show, only the alternatives moved behind a
    /// click.
    private var typeMenu: some View {
        Menu {
            // Plain buttons rather than a `Picker`: the pill itself says which
            // type is current, so a menu carrying checkmarks would only mean
            // giving up each type's own symbol to show it.
            ForEach(settings.noteTypes) { menuType in
                Button {
                    selectType(menuType)
                } label: {
                    Label(menuType.name, systemImage: menuType.symbol)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if !type.symbol.isEmpty { Image(systemName: type.symbol) }
                Text(type.name)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            // The same padding a `FilterPill` uses, so the dropdown and the
            // filter row above it are the same pill at the same size.
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .chipHeight()
            .background(Capsule().fill(type.tint.deep))
            .contentShape(Capsule())
        }
        // See `AddProjectMenu`: `.button` + plain keeps the label as drawn,
        // where `.borderlessButton` would drop the capsule.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Change note type")
        .accessibilityLabel("Note type: \(type.name)")
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
            // "Click", not "tap": this is a pointer-driven Mac.
            Text("Empty note — click to write")
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
                    // (5, 0): the editor's first line starts at the very top of
                    // its frame, 5pt in — the placeholder sits on the caret.
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }

            MarkdownEditor(text: $draft.body, focused: $bodyFocused, selection: $bodySelection)
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
        CardDatesFooter(kind: .note, created: note.created, updated: note.updated)
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
                // 26×22 was under a comfortable click target; the glyph is
                // unchanged, only the area around it grew.
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Note actions")
        .accessibilityLabel("Note actions")
    }

    // MARK: Mode

    private func enterEdit() { appState.selectedNoteID = note.id }

    /// Just clears the selection — `onChange(of: isEditing)` runs
    /// `finishEditing()`, so every way out of edit mode settles the same way.
    private func exitEdit() {
        if isEditing { appState.selectedNoteID = nil }
    }

    /// Ending an edit either persists the draft or, when the note was left
    /// with no text at all, discards it — which is also how a just-created
    /// note is cancelled: blur the empty card and it's gone.
    private func finishEditing() {
        let blank = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if blank {
            saveTask?.cancel()
            saveTask = nil
            library.deleteNote(id: draft.id)
        } else {
            flushSave()
        }
    }

    /// Put the cursor where it's most useful: the title for a brand-new note,
    /// otherwise the end of the body, ready to keep writing.
    ///
    /// **The one-turn delay is the point.** Called straight from
    /// `onChange(of: isEditing)` this wrote focus into fields that did not exist
    /// yet — the same update swaps the rendered Markdown for the editor, and a
    /// `@FocusState` write naming a field SwiftUI hasn't registered is dropped
    /// silently. That was the first click doing nothing visible: the card opened
    /// with no caret, and Esc — which the editor answers through `onKeyPress` —
    /// never reached it either, because nothing was focused to receive the key.
    /// The second click then focused the field the AppKit way and both worked.
    /// Deferring to the next main-actor turn puts the write after the editor is
    /// in the hierarchy (and after the click's own responder handling, which is
    /// the other thing that can take focus straight back).
    private func focusForEntry() {
        Task { @MainActor in
            guard isEditing else { return }
            if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleFocused = true
            } else {
                // The caret would otherwise land at offset 0, in front of the
                // text, which reads as an editor that isn't ready.
                bodySelection = TextSelection(insertionPoint: draft.body.endIndex)
                bodyFocused = true
            }
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
