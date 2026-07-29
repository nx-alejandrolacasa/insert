import AppKit
import SwiftUI

/// The right column: every task for the selected project (or all projects)
/// rendered as editable Liquid Glass rows.
///
/// State ownership mirrors `NotesPanel`:
/// - The state/search filter lives on `AppState` so it survives project
///   switches and stays in sync with the toolbar search field.
/// - Per-task draft/editing state lives inside `TaskCardView`, reset per
///   identity (`.id(task.id)`), so unrelated rows never share focus or
///   half-typed edits. Which task is *open* for editing lives on
///   `AppState.selectedTaskID`, same as notes, so only one edits at a time.
///
/// Creating works exactly like notes: "New Task" (⌘⇧N, the menu, the header
/// button) adds a real task straight away and opens it for editing — typing is
/// saving, so there's no separate composer and no "Add" step. A task left with
/// no text is discarded when editing ends (see `TaskCardView.finishEditing`).
struct TasksPanel: View {
    @Environment(Library.self) private var library
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A row whose due date or done state you change keeps the place it had, so it
    /// doesn't leave under the cursor. Held until the list is rebuilt for another
    /// reason. See `TaskPins`.
    @State private var pins = TaskPins()

    var body: some View {
        // Two-way binding for the segmented state filter.
        @Bindable var appState = appState

        let tasks = library.tasks(
            forProject: appState.selectedProjectID,
            filter: appState.taskFilter,
            search: appState.searchText,
            pinned: pins
        )

        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header(appState: appState)
                    .padding(.horizontal, Metrics.panelPadding)
                    .padding(.top, Metrics.panelPadding)
                    .padding(.bottom, 8)

                // A pill row mirroring the notes column's type filter, so both
                // columns present their filters identically.
                stateFilterPills
                    .padding(.horizontal, Metrics.panelPadding)
                    // Same gap as the notes column, so both headers sit at an
                    // identical distance from their first row of content.
                    .padding(.bottom, Metrics.headerGap)

                if tasks.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: Metrics.cardSpacing) {
                            ForEach(tasks) { task in
                                TaskCardView(
                                    task: task,
                                    showsProjectChips: appState.selectedProjectID == nil,
                                    pins: $pins
                                )
                                .id(task.id)
                            }
                        }
                        .padding(.horizontal, Metrics.panelPadding)
                        .padding(.bottom, Metrics.panelPadding)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .newTask)) { _ in
                createTask(proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The list re-sorts when you change what it's showing, and only then — the
        // same rule the notes column follows: on those frames it is being rebuilt
        // from scratch anyway, so a task taking its new place is invisible rather
        // than a row leaving under your cursor. There is no task sort setting, so
        // these three are the whole list.
        .onChange(of: appState.selectedProjectID) { pins = TaskPins() }
        .onChange(of: appState.taskFilter) { pins = TaskPins() }
        .onChange(of: appState.searchText) { pins = TaskPins() }
    }

    /// Creates a task in the current project, then scrolls to and opens it —
    /// the same flow as `NotesPanel.createNote`. An undated pending task sorts
    /// below the dated ones, so the scroll matters.
    private func createTask(proxy: ScrollViewProxy) {
        // Anything that would hide the new task gets out of the way first — it
        // starts pending and undated, so every filter but All and Pending would.
        if appState.taskFilter != .all && appState.taskFilter != .pending {
            appState.taskFilter = .all
        }
        appState.searchText = ""

        let task = library.addTask(
            projectIDs: appState.selectedProjectID.map { [$0] } ?? []
        )
        appState.selectedTaskID = task.id
        // Let the list rebuild before scrolling so the target row exists.
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                proxy.scrollTo(task.id, anchor: .top)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(appState: AppState) -> some View {
        HStack(spacing: 10) {
            Text("Tasks")
                .font(.title2.weight(.bold))
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                // Route through the same notification ⌘⇧N / the menu posts, so
                // the local button and the global command open-and-focus
                // identically.
                NotificationCenter.default.post(name: .newTask, object: nil)
            } label: {
                Label("New Task", systemImage: "plus").fontWeight(.semibold)
            }
            // See "New Note" in `NotesPanel` for why neither the accent fill nor
            // glass survived. These two are one control in two columns; they change
            // together or not at all.
            .buttonStyle(.actionCapsule)
            .controlSize(.large)
            .help("Create a new task")
        }
    }

    // MARK: - State filter pills

    /// The state pills (All / Pending / Done) anchored left and the date pills
    /// (Overdue / Today / Tomorrow) anchored right, while the column is wide
    /// enough for both groups plus a gap between them. When it isn't, the six
    /// pills join into one line that scrolls sideways together, the same way
    /// the notes column's type pills do — never two rows, and never a gap that
    /// crushes to nothing. Grey still means "All", matching the notes row.
    private var stateFilterPills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                pills(TaskFilter.stateCases)
                Spacer(minLength: 16)
                pills(TaskFilter.dateCases)
            }
            .padding(.vertical, 1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    pills(TaskFilter.allCases)
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func pills(_ filters: [TaskFilter]) -> some View {
        ForEach(filters) { filter in
            FilterPill(
                label: filter.label,
                tint: filter.tint,
                selected: appState.taskFilter == filter
            ) {
                appState.taskFilter = filter
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                // Regular rather than Light, matching the notes column.
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(emptyMessage)
                .font(.headline)
                .foregroundStyle(.secondary)
            // A blank panel should say what to do next. Only on the unfiltered
            // list: "all clear" and "nothing completed yet" are answers, not
            // dead ends, so they don't need prompting.
            if !appState.isSearching && appState.taskFilter == .all {
                Button {
                    NotificationCenter.default.post(name: .newTask, object: nil)
                } label: {
                    Label("New Task", systemImage: "plus").fontWeight(.semibold)
                }
                .buttonStyle(.actionCapsule)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyMessage: String {
        if appState.isSearching { return "No tasks match your search" }
        switch appState.taskFilter {
        case .done: return "Nothing completed yet"
        case .pending: return "No pending tasks — all clear"
        case .overdue: return "Nothing overdue"
        case .today: return "Nothing due today"
        case .tomorrow: return "Nothing due tomorrow"
        case .all: return "No tasks yet"
        }
    }
}

// MARK: - Task card

/// A single task rendered as a Liquid Glass row with two modes, mirroring
/// `NoteCardView`:
///
/// - **View mode**: the title and a one-line body preview, with a chevron to
///   unfold the full (rendered) notes in place. The whole row is a tap target
///   that opens it for editing.
/// - **Edit mode** (the task is selected via `AppState.selectedTaskID`): the
///   title becomes a `#project` field, the notes become a Markdown editor with
///   a "Notes…" placeholder, and the assignment chips grow a ＋.
///
/// Like `NoteCardView` it owns a mutable `draft` so typing is instant, and
/// coalesces writes onto a ~0.4s debounce (each `updateTask` rewrites a file
/// and bumps `updated`).
private struct TaskCardView: View {
    /// The canonical task from the library. External edits and our own saves
    /// flow back in via `onChange`.
    let task: TaskItem
    /// Only the aggregate view shows which project(s) a task belongs to.
    let showsProjectChips: Bool
    /// The column's sort pins, written to before this row changes its own due date
    /// or done state so it keeps the place it is being looked at in.
    @Binding var pins: TaskPins

    @Environment(Library.self) private var library
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draft: TaskItem
    /// The in-flight debounced save, cancelled and restarted on every edit.
    @State private var saveTask: Task<Void, Never>?
    @State private var expanded = false
    @State private var showDuePopover = false
    /// Height of the collapsed (one-line) body preview, and of the same text laid
    /// out in full. When the second is taller the preview is truncated, which is
    /// the only case that earns an expand chevron.
    @State private var previewHeight: CGFloat = 0
    @State private var fullBodyHeight: CGFloat = 0
    /// The ⋯ menu's box, which the expand chevron takes as its own so the two line
    /// up. Seeded with what a borderless `Menu` was measured at, so the first layout
    /// is already right and nothing slides when the real value lands.
    @State private var actionsSize = CGSize(width: 20, height: 14)
    /// Height of the notes editor's sizing proxy, so it grows with its content.
    @State private var measuredBodyHeight: CGFloat = 28

    @FocusState private var titleFocused: Bool
    @FocusState private var bodyFocused: Bool
    /// The notes editor's caret/selection, held here so `focusForEntry()` can
    /// place it; the editor writes the user's own selection back through it.
    @State private var bodySelection: TextSelection?

    init(task: TaskItem, showsProjectChips: Bool, pins: Binding<TaskPins>) {
        self.task = task
        self.showsProjectChips = showsProjectChips
        _pins = pins
        _draft = State(initialValue: task)
    }

    /// This card is the one currently open for editing.
    private var isEditing: Bool { appState.selectedTaskID == task.id }

    private var hasBody: Bool {
        !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Only worth a chevron when there's more to reveal than the one line on
    /// show — or when we're expanded and it's the way back.
    private var showsChevron: Bool {
        expanded || (hasBody && fullBodyHeight > previewHeight + 1)
    }

    var body: some View {
        tappableCard
        // Adopt upstream changes without clobbering local edits or looping on
        // our own timestamp-only updates: only re-seed when content differs.
        .onChange(of: task) { _, newValue in
            if newValue.title != draft.title
                || newValue.body != draft.body
                || newValue.done != draft.done
                || newValue.due != draft.due
                || newValue.projectIDs != draft.projectIDs {
                draft = newValue
            }
        }
        .onChange(of: draft.title) { scheduleSave() }
        .onChange(of: draft.body) { scheduleSave() }
        .onChange(of: draft.projectIDs) { scheduleSave() }
        .onAppear { if isEditing { focusForEntry() } }
        // Focus on entering edit; persist-or-discard on leaving it (e.g. when
        // another task is opened).
        .onChange(of: isEditing) { _, editing in
            if editing { focusForEntry() } else { finishEditing() }
        }
        .onDisappear {
            // Settle any pending edit so nothing is lost when the row scrolls
            // out or the project changes — including mid-edit, where an empty
            // task must still be discarded rather than flushed.
            if isEditing { finishEditing() } else { flushSave() }
        }
    }

    /// The row island. In view mode the whole island is a tap target that opens
    /// edit mode; while editing the gesture is switched off, so taps reach the
    /// title / notes fields normally.
    ///
    /// **One view, both modes**, and that matters for more than tidiness: this
    /// was `if isEditing { card } else { card.onTapGesture… }`, which is a
    /// `_ConditionalContent` — two branches, two identities. Entering edit mode
    /// was therefore a teardown and a rebuild, not a resize, so there was no
    /// height *change* for an `.animation` to interpolate and the row snapped to
    /// its new size however it was animated. Switching the gesture off with
    /// `isEnabled:` keeps the one identity, and the height then eases.
    private var tappableCard: some View {
        // Baseline, not `.top`: the checkbox is a 17pt glyph in a 28pt target, so
        // top-aligning the two boxes sat it 7pt below the title's capitals. See
        // `centredOnTextCap()`.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            checkbox

            VStack(alignment: .leading, spacing: 8) {
                // The ⋯ menu rides the title row, as it does on a note card.
                titleRow
                    // The title's `#project` dropdown drops over the notes
                    // editor below; without this the editor — a later sibling —
                    // would sit on top of it and take its clicks.
                    .zIndex(1)

                // Body, then the chips / due row — same order as a note card,
                // where the pills sit under the text you're writing.
                bodyArea

                metaRow

                footer
            }
        }
        .padding(12)
        // Optionally wash the row in its due colour (Settings → Tasks); the
        // badge and the background then tell the same story. `dueTint` is nil for
        // undated and done rows — and for every row with the setting off — which
        // leaves those on plain white paper (see `island`).
        .island(radius: Metrics.rowRadius, tint: settings.dueTintedTasks ? dueTint : nil)
        .opacity(draft.done ? 0.7 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
        .gesture(TapGesture().onEnded { enterEdit() }, isEnabled: !isEditing)
        // A bare tap gesture is pointer-only; the container action and the ⋯
        // menu's "Edit" cover assistive tech and the keyboard. The action is
        // declared in a builder so it can be dropped while editing without the
        // card itself becoming a different view.
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if !isEditing {
                Button("Edit task") { enterEdit() }
            }
        }
        // Opening and closing a row changes its height — the editor replaces the
        // one-line preview, Done appears, the chips row grows a ＋. Ease that the
        // same way typing into the editor eases, only a touch slower: this is a
        // mode change rather than a line appearing, and the rows below travel
        // further.
        .animation(
            reduceMotion ? nil : .smooth(duration: Metrics.cardModeDuration),
            value: isEditing
        )
        // Expanding the notes is the same kind of change as opening the card — the
        // row grows, the rows below travel — so it eases the same way and for the
        // same duration. Value-scoped, so this and the mode change can't drive each
        // other: a card opened while expanded resizes once, not twice.
        .animation(
            reduceMotion ? nil : .smooth(duration: Metrics.cardModeDuration),
            value: expanded
        )
    }

    // MARK: Title row

    @ViewBuilder
    private var titleRow: some View {
        // Baseline again, so the ⋯ — and Done, and the title — sit on one line
        // whatever box each of them brings.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if isEditing {
                // `#project` tags a project and is stripped from the title,
                // same as in the composer.
                ProjectHashField(
                    placeholder: "Task  (type # to tag a project)",
                    text: $draft.title,
                    assigned: $draft.projectIDs,
                    font: Card.font(.body, weight: .medium),
                    // Return commits the quick-capture flow: type, Return, done.
                    onSubmit: { exitEdit() },
                    onEscape: { exitEdit() },
                    focused: $titleFocused
                )

                // Twin of the note card's Done — same reasons, and these two
                // change together or not at all.
                Button("Done") { exitEdit() }
                    .buttonStyle(.actionCapsule)
                    .controlSize(.small)
            } else {
                Text(draft.title.isEmpty ? "Untitled" : draft.title)
                    .font(Card.font(.body, weight: .medium))
                    .foregroundStyle(draft.done ? Color.secondary : Color.primary)
                    .strikethrough(draft.done)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            actionsMenu
                // The chevron below wears this control's box, and a borderless
                // `Menu` sizes itself — so it's measured rather than assumed (see
                // `bodySection`).
                .onGeometryChange(for: CGSize.self) { $0.size } action: { actionsSize = $0 }
        }
        // Floored so the row is the same height whether or not Done is in it —
        // otherwise the title and the body both drop as a card opens. See
        // `Metrics.cardTitleRowHeight`.
        .frame(minHeight: Metrics.cardTitleRowHeight)
    }

    // MARK: Checkbox

    private var checkbox: some View {
        Button(action: toggleDone) {
            Image(systemName: draft.done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                // Padded out to a comfortable target; the glyph keeps its size.
                .frame(width: 28, height: 28)
                .foregroundStyle(draft.done ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .centredOnTextCap()
        .buttonStyle(.plain)
        .help(draft.done ? "Mark as not done" : "Mark as done")
        // Done-ness was conveyed by glyph and colour only. Announce it as a
        // checkbox with a state so VoiceOver reads the task's status, and the
        // strikethrough isn't the sole non-visual cue.
        .accessibilityLabel("Done")
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(draft.done ? "On" : "Off")
    }

    /// Flip the done state via the library. Any in-flight text edit is flushed
    /// and the debounce cancelled first, so a stale snapshot can't later revert
    /// the toggle; `draft` is kept in sync immediately to avoid a flash.
    private func toggleDone() {
        // Before the flip, so the pin records the place the row is in now.
        pins.pin(task)
        flushSave()
        library.toggleTask(id: draft.id)
        draft.done.toggle()
    }

    // MARK: Meta row (chips + due badge)

    private var metaRow: some View {
        HStack(spacing: 6) {
            // Edit mode always shows the assignments (that's where they're
            // managed); otherwise only the aggregate view labels rows.
            if isEditing || showsProjectChips {
                ForEach(draft.projectIDs, id: \.self) { id in
                    if let project = library.project(id: id) {
                        ProjectChip(project: project) {
                            draft.projectIDs.removeAll { $0 == id }
                        }
                    }
                }
            }
            // Unassigned: the full "＋ Add project" pill, always on show like
            // "Add due" across the row. Once assigned, adding *another* is an
            // edit-mode affair — a bare ＋ beside the chips it extends.
            if draft.projectIDs.isEmpty {
                AddProjectMenu(assigned: draft.projectIDs) { draft.projectIDs.append($0) }
            } else if isEditing {
                AddProjectMenu(assigned: draft.projectIDs, compact: true) { draft.projectIDs.append($0) }
            }

            Spacer(minLength: 0)

            dueBadge
        }
    }

    // MARK: Due badge

    private var dueBadge: some View {
        Button {
            showDuePopover = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                // Undated, the badge is an affordance, so it says what it does.
                Text(draft.due == nil ? "Add due" : DueFormat.relative(draft.due))
            }
            .font(.caption)
            .foregroundStyle(dueForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .chipHeight()
            .background(Capsule().fill(dueBackground))
        }
        .buttonStyle(.plain)
        .help("Set due date")
        // Overdue vs today vs upcoming is carried by colour alone (orange /
        // green / purple), which some people can't tell apart — so it goes in
        // the spoken label as words.
        .accessibilityLabel(dueLabel)
        .popover(isPresented: $showDuePopover, arrowEdge: .bottom) {
            duePopover
        }
    }

    /// Spoken form of the due badge, spelling out the state the colour encodes.
    private var dueLabel: String {
        guard let due = draft.due else { return "Set due date" }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: due)
        // `DueFormat.relative` already reads as a phrase ("Yesterday", "3 days
        // ago"), so don't put "due" in front of it — "Due 3 days ago" is clumsy
        // where "Overdue, 3 days ago" isn't.
        let date = DueFormat.relative(due)
        if draft.done { return date }
        if day < today { return "Overdue, \(date)" }
        return "Due \(date)"
    }

    /// Orange once overdue, green for today, purple for anything upcoming —
    /// a *dated* badge is never grey, so it can't be confused with the grey
    /// "Add due" / "Add project" affordances beside it. `nil` (grey) is only
    /// the undated affordance and the muted done state.
    private var dueTint: Tint? {
        guard let due = draft.due, !draft.done else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: due)
        if day < today { return .orange }
        if day == today { return .green }
        return .purple
    }

    private var dueForeground: Color { dueTint?.ink ?? .secondary }

    private var dueBackground: Color {
        dueTint?.chip ?? Color.secondary.opacity(0.14)
    }

    private var duePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The quick presets the composer used to offer, so the common
            // cases stay one click away of the badge. One row at the same 6pt
            // as every other pill row: a `Grid` sized both columns to the
            // widest label, so "Today" carried "End of week"'s width and the
            // four pills read as a sparse table rather than a pill row.
            HStack(spacing: 6) {
                ForEach(DuePreset.allCases) { presetPill($0) }
            }

            MonthCalendar(
                selection: Binding(
                    get: { draft.due ?? Calendar.current.startOfDay(for: Date()) },
                    set: { setDue($0) }
                )
            )

            Button(role: .destructive) {
                setDue(nil)
                showDuePopover = false
            } label: {
                Label("Clear due date", systemImage: "xmark.circle")
            }
            .buttonStyle(.plain)
            .disabled(draft.due == nil)
        }
        .padding(14)
        // Wide enough that the month grid gets room to breathe — the calendar
        // stretches to fill it — and that the four presets fit on one line:
        // they measure 299pt with the selected one bold, so anything under
        // ~330 puts a label back on a second row or truncates it.
        .frame(width: 332)
    }

    private func presetPill(_ preset: DuePreset) -> some View {
        DuePill(label: preset.label, selected: firstMatchingPreset == preset) {
            setDue(preset.date(now: Date(), weekStyle: settings.weekStyle))
            showDuePopover = false
        }
    }

    /// Sets (or clears) the due date and writes it straight through.
    ///
    /// The pin comes first, and it is what makes the preset pills usable: due date
    /// is the list's main sort key, so an undated task given a date used to leave
    /// the tail of the list on the same click that dismissed the popover. The row
    /// that then sat under the cursor was a *different* task, still undated, so the
    /// pills read as setting the wrong date — or none — where the month grid, which
    /// leaves the popover open, looked fine. See `TaskPins`.
    private func setDue(_ date: Date?) {
        pins.pin(task)
        draft.due = date
        persistNow()
    }

    /// Presets can collide — on a Thursday in work-week mode, "Tomorrow" and
    /// "End of week" are both Friday. Highlight only the first match so two
    /// pills never light up for one date.
    private var firstMatchingPreset: DuePreset? {
        guard let due = draft.due else { return nil }
        return DuePreset.allCases.first {
            Calendar.current.isDate(due, inSameDayAs: $0.date(now: Date(), weekStyle: settings.weekStyle))
        }
    }

    // MARK: Body — the swap between modes

    /// The notes: the editor while editing, the read-only preview otherwise —
    /// changed over in **one frame**, never cross-faded.
    ///
    /// The text changes over in **one frame**, both ways; the row's height is the
    /// only thing that animates. `.transition(.identity)` is what says so — the
    /// default for replacing one view with another is a **cross**-fade, and that
    /// was the same paragraph in two forms, each half-transparent, sliding through
    /// the other mid-resize.
    ///
    /// Two attempts at softening it are worth not repeating, both variations on
    /// fading the preview out and the editor in as separate steps so that no frame
    /// holds both. Run alongside the resize it flashes; run *after* it, with the
    /// preview held on show until the row has finished growing, it stops being a
    /// transition and becomes a wait. Nothing needs to bridge this: the swap is
    /// legible because the row around it is already moving.
    private var bodyArea: some View {
        modeSwappedBody
            // The editor's sizing proxy lives here, outside both modes, for two
            // reasons. It doesn't size its host — a background never does — which
            // is what lets the editor's height be one animatable number instead
            // of a stack that resizes in a single frame. And measuring in *view*
            // mode too means the row already knows how tall the editor will be
            // when it opens: with the proxy inside `bodyEditor` the first open of
            // a long task grew twice, once to the 28pt floor and again when the
            // real height arrived, and the text swapped in mid-way through.
            .background(alignment: .topLeading) { bodySizingProxy }
            // Matches the gap the body has *above* it, so the two read as one
            // margin. See `titleRowSlack`.
            .padding(.bottom, titleRowSlack)
    }

    /// The slack the floored title row carries below its title, which the body's gap
    /// upward is made of — that slack plus the stack's spacing — and which is
    /// therefore what the gap *downward* is missing.
    ///
    /// Derived from the two numbers that create it rather than written down, because
    /// one of them moves: the title's line height is read off the card face, and a
    /// serif or monospaced card measures differently from a rounded one. `max(0, …)`
    /// because a face taller than the floor has no slack to repeat.
    private var titleRowSlack: CGFloat {
        let title = Card.nsFont(.body, weight: .medium)
        let line = title.ascender - title.descender + title.leading
        return max(0, (Metrics.cardTitleRowHeight - line) / 2)
    }

    @ViewBuilder
    private var modeSwappedBody: some View {
        if isEditing {
            bodyEditor.transition(.identity)
        } else {
            bodySection.transition(.identity)
        }
    }

    // MARK: Body — view mode

    /// Collapsed: the body's first line, ellipsised. Expanded: the notes as
    /// *rendered* Markdown, read-only — editing happens in edit mode. The
    /// chevron lives here rather than in the corner, next to the text it
    /// reveals, and only appears when there's something hidden.
    @ViewBuilder
    private var bodySection: some View {
        if hasBody {
            // Baseline, not `.top`: the chevron is a caption glyph in a 28pt target,
            // so top-aligning the boxes sat it 8pt below the line of text it belongs
            // to. Same rule as the checkbox and the ⋯ a row above —
            // `centredOnTextCap()`, at `.callout` because that is what the notes are
            // set in.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // `.transition(.identity)` on both, for the reason the mode swap
                // above documents: SwiftUI's default is a cross-fade, and these two
                // are the same first line with and without the rest of the body
                // under it, so fading them through each other shows the same words
                // twice at half opacity while the row is still resizing. The row's
                // height is what animates; the text is legible because of it.
                if expanded {
                    // `.callout`, matching this card's editor — the note card's
                    // is `.body`, and a preview that changes size on the way in
                    // is the thing `textStyle` exists to prevent.
                    MarkdownText(markdown: draft.body, textStyle: .callout)
                        .padding(.horizontal, 5)
                        .transition(.identity)
                } else {
                    bodyPreview
                        .transition(.identity)
                }

                if showsChevron {
                    Button {
                        expanded.toggle()
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            // The glyph turns over rather than cutting: the same
                            // symbol in two directions is exactly what `.replace`
                            // is for, and it reads as the row's own movement.
                            .contentTransition(.symbolEffect(.replace))
                            // **The ⋯'s box, both dimensions.** The width is what
                            // puts the two on one vertical axis: both are flush to
                            // the same trailing edge, so equal widths is all it
                            // takes, and this was 28 against the borderless menu's
                            // own 20 — 4pt to its left. The *height* matters for a
                            // different reason: a 28pt box centred on a 15pt line
                            // sticks out above it, and since the row is
                            // baseline-aligned that raised the row's top and pushed
                            // the preview 5pt *below* the editor's first line —
                            // trading one misalignment for its mirror image. At the
                            // menu's own 14pt the box sits inside the line box and
                            // pushes nothing. Both measured, because those numbers
                            // are AppKit's rather than ours.
                            .frame(width: actionsSize.width, height: actionsSize.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .centredOnTextCap(.callout)
                    .help(expanded ? "Collapse notes" : "Expand notes")
                    .accessibilityLabel(expanded ? "Collapse notes" : "Expand notes")
                }
            }
        }
    }

    /// The teaser is **rendered**, not source. A task's notes are Markdown exactly
    /// as a note's body is, and this row printed them raw — so `**Ship it**` read
    /// as asterisks, and because the chevron only appears when there's more than
    /// one line to reveal, a short body had no way to ever be seen rendered at all.
    /// `MarkdownParser.lead(_:)` drops the block marker and
    /// `MarkdownText.inline(_:)` draws the rest, which is the same pair of steps
    /// the expanded view takes per block.
    private var bodyPreview: some View {
        MarkdownText.inline(MarkdownParser.lead(draft.body), in: Card.nsFont(.callout))
            .font(Card.font(.callout))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 5)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
            .background(alignment: .topLeading) {
                // What expanding would actually show, laid out unbounded: taller
                // than the one line on show means there's something to reveal.
                // Measured as the *render* rather than as the source, because that
                // is what the chevron promises — the parser joins hard-wrapped
                // lines into one paragraph, so a two-line source can render as one
                // line and used to earn a chevron that revealed nothing.
                MarkdownText(markdown: draft.body, textStyle: .callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullBodyHeight = $0 }
            }
    }

    // MARK: Body — edit mode

    /// A growing Markdown editor, always on show while editing so the notes
    /// affordance is visible — a "Notes…" placeholder marks the spot when the
    /// task has none yet. Mirrors `NoteCardView`'s sizing-proxy approach so the
    /// row expands to fit rather than scrolling internally.
    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            // Shown whenever the notes are empty — the field takes focus on
            // entry, and hiding the placeholder then would leave nothing saying
            // what the empty space is for.
            if draft.body.isEmpty {
                Text("Notes…")
                    .font(Card.font(.callout))
                    .foregroundStyle(.tertiary)
                    // (5, 0): the editor's first line starts at the very top of
                    // its frame, 5pt in — the placeholder sits on the caret.
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }

            MarkdownEditor(
                text: $draft.body,
                font: Card.font(.callout),
                focused: $bodyFocused,
                selection: $bodySelection
            )
                // Esc leaves the editor, matching the title field.
                .onKeyPress(.escape) {
                    exitEdit()
                    return .handled
                }
        }
        // One number is the row's height, and it eases. Wrapping a line used to
        // resize the card in a single frame, which — because the rows below move
        // with it — read as the list flinching every time a sentence got long
        // enough to wrap.
        .frame(height: max(28, measuredBodyHeight))
        .animation(reduceMotion ? nil : .smooth(duration: 0.18), value: measuredBodyHeight)
    }

    /// The editor's text laid out at the row's width with the editor's own font
    /// and insets, hidden — how tall the notes *want* to be. `fixedSize`
    /// vertically because a background is proposed its host's height, and the
    /// host's height is precisely what this is measuring: without it the proxy
    /// would report the animated height back to itself.
    private var bodySizingProxy: some View {
        Text(draft.body.isEmpty ? " " : draft.body)
            .font(Card.font(.callout))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 5)
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                measuredBodyHeight = $0
            }
    }

    // MARK: Footer

    private var footer: some View {
        CardDatesFooter(kind: .task, created: task.created, updated: task.updated)
    }

    // MARK: Trailing controls

    private var actionsMenu: some View {
        Menu {
            if !isEditing {
                Button { enterEdit() } label: { Label("Edit", systemImage: "pencil") }
            }
            Button(role: .destructive) {
                saveTask?.cancel()
                if isEditing { appState.selectedTaskID = nil }
                library.deleteTask(id: draft.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // A borderless `Menu` adds insets of its own around the label, so what
        // the row has to align is the height it ends up with, not the 28pt frame
        // above — which is exactly what the guide measures.
        .centredOnTextCap()
        .help("Task actions")
        .accessibilityLabel("Task actions")
    }

    // MARK: Mode

    private func enterEdit() { appState.selectedTaskID = task.id }

    /// Just clears the selection — `onChange(of: isEditing)` runs
    /// `finishEditing()`, so every way out of edit mode settles the same way.
    private func exitEdit() {
        if isEditing { appState.selectedTaskID = nil }
    }

    /// Put the cursor where it's most useful: the title for a brand-new task,
    /// otherwise the end of the notes.
    ///
    /// Deferred by one main-actor turn for the reason spelled out on
    /// `NoteCardView.focusForEntry()` — the fields are created by the very
    /// update that calls this, so an immediate `@FocusState` write is dropped and
    /// the row opens with no caret and no Esc.
    private func focusForEntry() {
        Task { @MainActor in
            guard isEditing else { return }
            if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleFocused = true
            } else {
                bodySelection = TextSelection(insertionPoint: draft.body.endIndex)
                bodyFocused = true
            }
        }
    }

    /// Ending an edit either persists the draft or, when the task was left
    /// with no text at all, discards it — a task *is* its text, so there's
    /// nothing to keep. This is also how "New Task" gets cancelled: blur the
    /// empty card and it's gone.
    private func finishEditing() {
        let blank = draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if blank {
            saveTask?.cancel()
            saveTask = nil
            library.deleteTask(id: draft.id)
        } else {
            flushSave()
        }
    }

    // MARK: Persistence

    /// Restart the debounce for text edits: persist ~0.4s after the last change.
    /// The snapshot is captured by value so a later keystroke can't mutate what
    /// we're saving.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = draft
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            library.updateTask(snapshot)
            saveTask = nil
        }
    }

    /// Persist an immediate, structural change (done/due). Cancels the text
    /// debounce and flushes the whole draft so nothing is lost and no stale
    /// snapshot can revert what we just set.
    private func persistNow() {
        saveTask?.cancel()
        saveTask = nil
        library.updateTask(draft)
    }

    /// Flush a pending debounced save, if any (editing ended or the row is
    /// going away).
    private func flushSave() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        library.updateTask(draft)
    }
}

// MARK: - Due-date pills

/// The quick relative due-date options offered in the due-date popover.
private enum DuePreset: String, CaseIterable, Identifiable {
    case today, tomorrow, endOfWeek, nextWeek

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .endOfWeek: "End of week"
        case .nextWeek: "Next week"
        }
    }

    /// Resolve to a concrete day (start-of-day) relative to `now`.
    ///
    /// "End of week" depends on `weekStyle` — Sunday for a full week, Friday
    /// for a work week — and "Next week" is the coming Monday. Both are
    /// computed from explicit weekdays rather than the calendar's week
    /// interval, so they mean the same thing whatever the locale's first
    /// weekday happens to be.
    func date(now: Date, weekStyle: WeekStyle) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        switch self {
        case .today:
            return start
        case .tomorrow:
            return cal.date(byAdding: .day, value: 1, to: start)!
        case .endOfWeek:
            return Self.next(weekday: weekStyle.endWeekday, from: start, orToday: true, cal: cal)
        case .nextWeek:
            return Self.next(weekday: 2, from: start, orToday: false, cal: cal) // Monday
        }
    }

    /// The next occurrence of `weekday` (Sunday = 1 … Saturday = 7). When
    /// `orToday` is true and today already is that weekday, today is returned.
    private static func next(weekday: Int, from start: Date, orToday: Bool, cal: Calendar) -> Date {
        let current = cal.component(.weekday, from: start)
        var delta = (weekday - current + 7) % 7
        if delta == 0 && !orToday { delta = 7 }
        return cal.date(byAdding: .day, value: delta, to: start)!
    }
}

/// A capsule due-date pill.
///
/// Speaks `FilterPill`'s language — filled when selected, a quiet wash when not —
/// rather than the Liquid Glass it used to wear. Two reasons. These sit in the
/// *content* layer, where HIG asks for standard materials and reserves glass for
/// controls and navigation. And the selected one used `.glassProminent`, which
/// paints the accent colour behind the label: with the column's "New Task" button
/// already doing that, picking a due date put several coloured backgrounds on
/// screen at once, against "refrain from adding color to the background of
/// multiple controls".
///
/// Not literally a `FilterPill`, because that takes a `Tint` per option — its
/// options *are* colour-coded categories. A date preset has no inherent colour,
/// so the resting state is the neutral `Stone` and only selection is tinted. The
/// padding matches `FilterPill` so the due row lines up with the filter row above.
private struct DuePill: View {
    let label: String
    var systemImage: String? = nil
    let selected: Bool
    let action: () -> Void

    /// The same blue the month grid below fills its selected day with — a pill
    /// and a day cell in one popover both mean "this is the due date", so they
    /// can't be two different colours. `MonthCalendar`'s default `tint`.
    private static let tint = Tint.blue

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(label)
            }
            .font(.caption.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .chipHeight()
            .background(
                Capsule().fill(selected ? AnyShapeStyle(Self.tint.deep) : AnyShapeStyle(Stone.chip))
            )
            .overlay {
                if !selected {
                    Capsule().strokeBorder(Stone.line, lineWidth: 0.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
