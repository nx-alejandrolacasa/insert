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
///   preference (Settings → Notes) rather than a per-window control.
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

    /// The system switch OR-ed with the Accessibility menu's in-app one.
    private var motionReduced: Bool { reduceMotion || settings.appReduceMotion }

    var body: some View {
        // Sort order is a preference (Settings → Notes), not a per-window
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
                // The heading, the count, "New Note" and the type filter, all
                // inside the themed band — see `ColumnHeaderBand`.
                ColumnHeaderBand(
                    title: "Notes",
                    count: notes.count,
                    primaryTitle: "New Note",
                    primarySymbol: "plus",
                    primaryHelp: "Create a new note (⌘N)",
                    // The button needs the scroll proxy to focus the new note,
                    // so it re-uses the notification the reader already listens
                    // for.
                    primaryAction: {
                        NotificationCenter.default.post(name: .newNote, object: nil)
                    },
                    filters: { typeFilter }
                )

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
                        // The gap to the band is **inside** the scroller, so it
                        // scrolls away with the first card instead of holding a
                        // permanent strip of window colour under the band. It
                        // sat outside while the header was a loose heading that
                        // needed separating from the list; the band separates
                        // itself, so the space belongs to the content.
                        .padding(.top, Metrics.headerGap)
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

    // MARK: - Type filter

    /// The band's second row: the type filter as one segmented track — "All",
    /// then a segment per note type, each carrying its type's colour dot so
    /// the row ties to the capsule mark on the cards it selects. Single-
    /// select, matching the tasks column. Still inside a horizontal scroller:
    /// types are user-extensible, and a track wider than the column should
    /// slide rather than crush its segments.
    ///
    /// The dots take **`Tint.accent`**, the same vivid value every other dot in the
    /// app wears — the project chips on a card, the tasks track's own Pending and
    /// Done dots, the type swatches in Settings — and the same value the capsule
    /// mark on a card draws in, so the row and the cards it selects agree. Not a
    /// theme value: the four types are the same four in every theme, and not `ink`
    /// either, which is the *text* value (see `Tint.accent` for the split).
    private var typeFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            SegmentedFilter<String?>(
                segments: [SegmentedFilter.Segment(id: nil, label: "All")]
                    + settings.noteTypes.map {
                        SegmentedFilter.Segment(
                            id: $0.id,
                            label: $0.name,
                            dot: $0.tint.accent)
                    },
                selection: appState.noteTypeFilter,
                onSelect: { appState.noteTypeFilter = $0 }
            )
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
            withAnimation(motionReduced ? nil : .easeInOut(duration: 0.25)) {
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
    /// Holds every save path closed while the Trash move is being confirmed.
    @State private var deleting = false

    /// Height of the rendered body text, so the editor grows with content
    /// instead of the greedy `TextEditor` filling the whole scroll viewport.
    @State private var measuredBodyHeight: CGFloat = 34
    /// Whether a collapsible body is currently shown in full. Only meaningful
    /// with a "Preview lines" choice set and a body taller than its cap; owned
    /// here rather than by `CollapsibleMarkdown` so the card's height animation
    /// can be value-scoped to it.
    @State private var expanded = false
    /// The ⋯ menu's box, which the expand chevron takes as its own so the two sit
    /// flush on one trailing axis — the task row's arrangement, seeded with the
    /// same measured value so the first layout is already right.
    @State private var actionsSize = CGSize(width: 20, height: 14)
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
    /// The system switch OR-ed with the Accessibility menu's in-app one.
    private var motionReduced: Bool { reduceMotion || settings.appReduceMotion }

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
            if editing {
                focusForEntry()
            } else {
                // Stay open. The editor showed the whole note, so folding it
                // back to a preview the moment editing ends takes away the text
                // someone was just reading — and it happens on the same frame
                // the card is already resizing, so it reads as the note
                // shrinking away from them. Expanding is a state the reader can
                // undo with the chevron; collapsing is one they have to.
                expanded = true
                finishEditing()
            }
        }
        .onDisappear {
            guard !deleting else {
                saveTask?.cancel()
                return
            }
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
                // The title's `@project` dropdown drops over the body editor
                // below; without this the editor — a later sibling — would sit
                // on top of it and take its clicks.
                .zIndex(1)
            // The chips row sits *under* the body: between title and body it cut
            // the note in half and pushed the text you're writing down the card.
            bodyArea
            if isEditing {
                projectRow
                footer
            } else {
                // View mode collapses type, projects and timestamp onto one
                // meta line (CLAUDE.md decision 3).
                metaRow
            }
        }
        .padding(12)
        // Plain paper, whatever the type: the type is the title's capsule mark
        // and the meta row's label, so body-text contrast is the same on every
        // card and nothing on the face fights the chips inside it.
        .island()
        .overlay {
            if isEditing {
                // The theme's ring, not the type's colour: this means "open for
                // editing", which is an interactive state, and interactive is
                // the primary's one job (CLAUDE.md decision 4). At full
                // strength, not the 0.55 the accent wore — `ring` is already
                // solved as an outline (it is where Neon's mint deepens a step
                // in Light and Dark Owl's violet lifts one in Dark), and
                // fading it was compensating for a colour that wasn't.
                RoundedRectangle(cornerRadius: Metrics.islandRadius, style: .continuous)
                    .strokeBorder(settings.theme.ring, lineWidth: 1.5)
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
            motionReduced ? nil : .smooth(duration: Metrics.cardModeDuration),
            value: isEditing
        )
        // Collapsing or expanding the body is the same kind of change as opening
        // the card — this card grows, the cards below travel — so it eases the
        // same way, for the same duration. Value-scoped, like the task row's,
        // so this and the mode change can't drive each other.
        .animation(
            motionReduced ? nil : .smooth(duration: Metrics.cardModeDuration),
            value: expanded
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
            if isEditing {
                // `@project` tags a project and is stripped from the title,
                // same as in the task composer.
                ProjectMentionField(
                    placeholder: "Title  (type @ to tag a project)",
                    text: $draft.title,
                    assigned: $draft.projectIDs,
                    font: Card.font(.title3, weight: .bold),
                    // The colour the view-mode title draws in, so the flip into
                    // edit mode changes the face's weight and nothing else.
                    color: settings.theme.titleText,
                    onEscape: { exitEdit() },
                    onTab: { focusBody() },
                    focused: $titleFocused
                )
            } else {
                // No type glyph in either mode: the capsule mark and the meta
                // row's label already say the type twice, and the symbols were
                // removed from notes outright. The mark costs the title 11pt of
                // leading inset that the editor doesn't have, which is the one
                // place the two modes no longer start at the same x — accepted,
                // because the alternative is indenting the editor to match and
                // losing a line of writing width to a decoration.
                TypeMarkTitle(
                    text: draft.displayTitle,
                    mark: type.tint.accent)
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
                // The expand chevron under a collapsed body wears this control's
                // box so the two share a trailing axis — and a borderless `Menu`
                // sizes itself, so it's measured rather than assumed. Same as
                // the task row.
                .onGeometryChange(for: CGSize.self) { $0.size } action: { actionsSize = $0 }
        }
        // Floored like the task card's title row, and needed for the same
        // reason since the symbols went: the 26pt symbol well used to set this
        // height as a side effect, and without a floor the row is title-height
        // closed and Done-height open, sliding the body as the card opens. See
        // `Metrics.cardTitleRowHeight`.
        .frame(minHeight: Metrics.cardTitleRowHeight)
    }

    // MARK: Project assignments

    /// The edit-mode projects row: removable chips, a ＋ for more, and the type
    /// dropdown on the trailing edge — exactly as on a task row.
    private var projectRow: some View {
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
    }

    // MARK: Meta row — view mode

    /// One line under the body: type · projects · timestamp (CLAUDE.md
    /// decision 3). The type label always leads; the chips appear only in the
    /// aggregate view, as they always have, held to two plus an overflow so
    /// the card's height doesn't grow with its assignments; the dates footer
    /// keeps its own Settings choice and sits right-aligned.
    private var metaRow: some View {
        HStack(spacing: 9) {
            TypeCapsLabel(type: type)

            if showsProjectChips {
                // The hairline between the type and the chips, so the two
                // reads don't run together.
                Rectangle()
                    .fill(Stone.line)
                    .frame(width: 1, height: 11)

                if draft.projectIDs.isEmpty {
                    // Actionable where "Unassigned" was inert: the same pill
                    // flags the stray note *and* fixes it.
                    AddProjectMenu(assigned: draft.projectIDs) { draft.projectIDs.append($0) }
                } else {
                    ProjectChipsRow(projects: draft.projectIDs.compactMap { library.project(id: $0) })
                }
            }

            Spacer(minLength: 0)

            footer
        }
    }

    // MARK: Type menu

    /// The note's type as a pill-shaped dropdown, wearing that type's `deep` fill
    /// with a chevron — a pop-up button drawn as one of the app's own pills, not
    /// a `Picker`, which would redraw it in system chrome and lose the colour.
    ///
    /// It replaced a row of one filter pill per type, which is what the tint's
    /// `deep`-and-white here is borrowed from: the *selected* state of that
    /// retired row, since this control shows exactly one type and it is always
    /// the current one. The row cost a whole line of the card and grew with every type added
    /// in Settings, where the note being edited is what should have the space;
    /// the dropdown costs a badge. Nothing is lost but the second glance —
    /// which type is set is still on show, only the alternatives moved behind a
    /// click.
    ///
    /// It is the one place a type's colour is **not** `Tint.ink`, and that is a
    /// floor rather than an oversight: `ink` is a *foreground*, solved against the
    /// card faces, so several of them are bright values that could not carry white
    /// type as a fill. `Tint.deep` is the role solved for exactly this — a fill
    /// under white at 4.5:1 — so the dropdown keeps it, and the divergence only
    /// shows while a card is open.
    private var typeMenu: some View {
        Menu {
            // Plain buttons rather than a `Picker`: the pill itself says which
            // type is current. Names alone — the type symbols were removed
            // from notes wholesale.
            ForEach(settings.noteTypes) { menuType in
                Button {
                    selectType(menuType)
                } label: {
                    Text(menuType.name)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(type.name)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            // The same padding the tasks column's date dropdown uses, so the
            // two menus are the same pill at the same size.
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

    /// Switching type still swaps the symbol when the note carries the previous
    /// type's default: nothing *shows* symbols any more, but the frontmatter
    /// keeps the field, and a file whose symbol tracks its type stays coherent
    /// for whatever reads it in Obsidian.
    private func selectType(_ newType: NoteType) {
        guard newType.id != draft.typeID else { return }
        let previous = settings.noteType(id: draft.typeID)
        if draft.symbol == previous.symbol {
            draft.symbol = newType.symbol
        }
        draft.typeID = newType.id
    }

    // MARK: Body — view mode

    /// Rendered Markdown shown when the note isn't being edited — folded to the
    /// "Preview lines" choice (Settings → Notes) when the body runs past it.
    /// The folding, the fades and the chevron all live in `CollapsibleMarkdown`,
    /// one view shared with the task row; the editor always shows everything.
    @ViewBuilder
    private var bodyView: some View {
        if draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // "Click", not "tap": this is a pointer-driven Mac.
            Text("Empty note — click to write")
                .font(Card.font(.body))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 5)
        } else {
            CollapsibleMarkdown(
                markdown: draft.body,
                previewLines: settings.notePreviewLines.lines,
                expanded: $expanded,
                chevronBox: actionsSize,
                expandLabel: "Show the whole note",
                collapseLabel: "Collapse note"
            )
            // `labelColor` in every theme (Dracula, the one exception, is gone).
            // On the container, so every block inherits it and the runs that set
            // their own colour (code, the quote bar) still win.
            .foregroundStyle(settings.theme.bodyText)
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
                .font(Card.font(.body))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 5)
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    measuredBodyHeight = $0
                }

            if draft.body.isEmpty && !bodyFocused {
                Text("Write in Markdown…")
                    .font(Card.font(.body))
                    .foregroundStyle(.tertiary)
                    // (5, 0): the editor's first line starts at the very top of
                    // its frame, 5pt in — the placeholder sits on the caret.
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }

            MarkdownEditor(
                text: $draft.body,
                font: Card.nsFont(.body),
                textColor: NSColor(settings.theme.bodyText),
                onBacktab: { focusTitle() },
                // Esc leaves the Markdown editor, matching the title field. A
                // hook rather than `.onKeyPress`: the editor is an `NSTextView`
                // and answers the key itself.
                onEscape: { exitEdit() },
                focused: $bodyFocused,
                selection: $bodySelection
            )
                .frame(height: max(34, measuredBodyHeight))
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
            // The writing, not the file: title as a heading, then the body, with
            // the frontmatter left behind (`MarkdownFiles.copyText`). No ⌘C on
            // it — a menu item's shortcut is live for as long as the item's view
            // is, so every card on screen would claim ⌘C at once and take it off
            // the text selection in whichever card is open.
            let copyText = MarkdownFiles.copyText(draft)
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(copyText, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(copyText.isEmpty)
            Button(role: .destructive) {
                if isEditing {
                    saveTask?.cancel()
                    saveTask = nil
                    library.updateNote(draft)
                }
                deleting = true
                if isEditing { appState.selectedNoteID = nil }
                Task {
                    if !(await library.deleteNote(id: draft.id)) {
                        deleting = false
                    }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                // The theme's metadata colour: this is the card's quietest
                // control, and an interactive glyph needs 4:1 where text needs
                // 4.5 (CLAUDE.md decision 5), so the value already solved for
                // the timestamps beside it clears it with room.
                .foregroundStyle(settings.theme.metaText)
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
        guard !deleting else { return }
        let blank = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if blank {
            library.updateNote(draft)
            deleting = true
            saveTask?.cancel()
            saveTask = nil
            Task {
                if !(await library.deleteNote(id: draft.id)) {
                    deleting = false
                }
            }
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

    /// Tab traversal between the card's two fields, and the two directions are
    /// **not** symmetrical — see `CardFocus` for what was tried in SwiftUI first
    /// and what is actually known about why the arriving `@FocusState` write is
    /// dropped going the other way.
    ///
    /// Each direction still clears the other field's flag before setting its own:
    /// the two fields are two separate `@FocusState<Bool>`s, so setting one true
    /// doesn't make the other false — nothing enforces "one of two".
    ///
    /// Body → title, the direction that has always worked: the editor reports its
    /// own resignation, so clearing `bodyFocused` and setting `titleFocused` is
    /// enough. Written directly, without `focusForEntry()`'s one-turn delay —
    /// both fields already exist.
    private func focusTitle() {
        bodyFocused = false
        titleFocused = true
    }

    /// Title → body, the direction that needed AppKit. `CardFocus` makes the
    /// card's editor first responder, which the editor then reports back into
    /// `bodyFocused`; the `@FocusState` pair is the fallback for a hierarchy this
    /// can't read. See `CardFocus` for what was tried first and what is actually
    /// known about why it failed.
    private func focusBody() {
        // Before the focus, since the editor applies the selection as it arrives;
        // alongside a programmatic focus is the one place it may be written.
        bodySelection = TextSelection(insertionPoint: draft.body.endIndex)
        if CardFocus.moveToEditorBesideCurrentField() { return }
        titleFocused = false
        bodyFocused = true
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
