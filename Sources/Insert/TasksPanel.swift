import AppKit
import SwiftUI

/// The right column: a quick-capture composer on top, then every task for the
/// selected project (or all projects) rendered as editable Liquid Glass rows.
///
/// State ownership mirrors `NotesPanel`:
/// - The state/search filter lives on `AppState` so it survives project
///   switches and stays in sync with the toolbar search field.
/// - Per-task draft/editing state lives inside `TaskCardView`, reset per
///   identity (`.id(task.id)`), so unrelated rows never share focus or
///   half-typed edits.
///
/// The composer is the trickiest surface: it supports inline `#project`
/// autocomplete (Tab / Return / click to accept, arrows to move) and
/// double-click-to-remove assignment chips, so it lives in its own private
/// `TaskComposer` view below.
struct TasksPanel: View {
    @Environment(Library.self) private var library
    @Environment(AppState.self) private var appState

    /// Whether the quick-capture composer is on screen. Opened by "New Task"
    /// (⌘⇧N, the menu, the header button), closed by Esc.
    @State private var composerVisible = false

    var body: some View {
        // Two-way binding for the segmented state filter.
        @Bindable var appState = appState

        let tasks = library.tasks(
            forProject: appState.selectedProjectID,
            filter: appState.taskFilter,
            search: appState.searchText
        )

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

            // The composer sits above the list so newly captured tasks appear
            // right below where they were typed. Like "New Note", it only shows
            // up once asked for — a permanent capture field made the column look
            // busy next to the notes one.
            if composerVisible {
                TaskComposer(onDismiss: hideComposer)
                    .padding(.horizontal, Metrics.panelPadding)
                    .padding(.bottom, Metrics.headerGap)
                    // Float the composer (and its autocomplete dropdown) above
                    // the list that follows.
                    .zIndex(1)
                    .transition(.opacity)
            }

            if tasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Metrics.cardSpacing) {
                        ForEach(tasks) { task in
                            TaskCardView(
                                task: task,
                                showsProjectChips: appState.selectedProjectID == nil
                            )
                            .id(task.id)
                        }
                    }
                    .padding(.horizontal, Metrics.panelPadding)
                    .padding(.bottom, Metrics.panelPadding)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // ⌘⇧N / the menu / the header button post `.newTask`. The composer's own
        // listener can't catch it while it's off screen, so opening it lives
        // here; the composer focuses its field when it appears.
        .onReceive(NotificationCenter.default.publisher(for: .newTask)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) { composerVisible = true }
        }
    }

    private func hideComposer() {
        withAnimation(.easeInOut(duration: 0.18)) { composerVisible = false }
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
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .help("Create a new task")
        }
    }

    // MARK: - State filter pills

    /// All / Pending / Done as capsule pills, matching the notes column's type
    /// filter. Grey means "All" in both rows; pending is warm, done is green.
    private var stateFilterPills: some View {
        HStack(spacing: 6) {
            ForEach(TaskFilter.allCases) { filter in
                FilterPill(
                    label: filter.label,
                    tint: filter.tint,
                    selected: appState.taskFilter == filter
                ) {
                    appState.taskFilter = filter
                }
            }
            Spacer(minLength: 0)
        }
        // The notes column's pills sit in a scroll view that pads itself by a
        // point; match it so the two rows share a baseline.
        .padding(.vertical, 1)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyMessage: String {
        if appState.isSearching { return "No tasks match your search" }
        switch appState.taskFilter {
        case .done: return "Nothing completed yet"
        case .pending: return "No pending tasks — all clear"
        case .all: return "No tasks yet"
        }
    }
}

// MARK: - Composer

/// The quick-capture field. Owns everything about the create flow:
/// the title (with `#project` autocomplete), an optional body, an optional due
/// date, and the set of assigned projects shown as removable chips.
///
/// Autocomplete design: as the user types, the trailing whitespace-delimited
/// "token" is inspected. If it begins with `#`, a dropdown of matching projects
/// is shown. Accepting a project *removes* the `#token` from the text (it was
/// only ever a command, never part of the title) and adds the project to the
/// assigned set. Keyboard: Tab accepts the first match, Return the highlighted
/// one, ↑/↓ move the highlight, Esc dismisses — all handled via `onKeyPress`
/// so they only fire while the dropdown is open and otherwise fall through to
/// normal text editing / submit.
private struct TaskComposer: View {
    /// Called when the composer asks to be put away (Esc).
    let onDismiss: () -> Void

    @Environment(Library.self) private var library
    @Environment(AppState.self) private var appState
    @Environment(SettingsStore.self) private var settings

    @State private var title = ""
    @State private var body_ = ""
    @State private var assignedProjectIDs: [UUID] = []
    /// The chosen due date, or `nil` for no due date. Driven by the quick pills.
    @State private var dueDate: Date?
    /// Backing date for the "Other" calendar popover.
    @State private var customDate = Calendar.current.startOfDay(for: Date())
    @State private var showCalendar = false

    @State private var showBody = false

    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldRow
                // Keep the field (and its autocomplete dropdown) above the rows
                // that follow.
                .zIndex(1)

            dueRow

            if !assignedProjectIDs.isEmpty {
                chipsRow
            }

            if showBody {
                bodyEditor
            }
        }
        .padding(10)
        .island(radius: Metrics.rowRadius)
        // Seed the assignment from the current project when the composer first
        // appears, and whenever the sidebar selection changes while the
        // composer is still empty (so it tracks the active project). Appearing
        // *is* the create gesture now, so the field takes focus straight away.
        .onAppear {
            seedFromSelection()
            titleFocused = true
        }
        .onChange(of: appState.selectedProjectID) { _, _ in
            if title.isEmpty && body_.isEmpty { seedFromSelection() }
        }
        // ⌘⇧N / the menu / the header button post `.newTask`: focus the field
        // and re-seed so the create flow always starts clean and assigned.
        .onReceive(NotificationCenter.default.publisher(for: .newTask)) { _ in
            seedFromSelection()
            titleFocused = true
        }
    }

    // MARK: Title field

    private var fieldRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 16))

            ProjectHashField(
                placeholder: "Add a task…  (type # to tag a project)",
                text: $title,
                assigned: $assignedProjectIDs,
                onSubmit: submit,
                // Esc on a closed dropdown puts the whole composer away.
                onEscape: {
                    titleFocused = false
                    onDismiss()
                },
                focused: $titleFocused
            )

            // Toggles the optional multi-line body editor.
            Button {
                showBody.toggle()
            } label: {
                Image(systemName: "note.text")
                    .foregroundStyle(showBody ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(showBody ? "Hide notes" : "Add notes")

            Button("Add", action: submit)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: Chips

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(assignedProjectIDs, id: \.self) { id in
                    if let project = library.project(id: id) {
                        ProjectChip(project: project) {
                            assignedProjectIDs.removeAll { $0 == id }
                        }
                    }
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: Due date

    /// The quick due-date pills offered while composing: Today / Tomorrow /
    /// End of week / Next week, plus an "Other" pill that opens a calendar.
    /// Tapping the selected pill again clears the due date.
    private var dueRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(DuePreset.allCases) { preset in
                DuePill(label: preset.label, selected: isSelected(preset)) {
                    toggle(preset)
                }
            }

            DuePill(label: customLabel, systemImage: "calendar", selected: isCustomSelected) {
                customDate = dueDate ?? Calendar.current.startOfDay(for: Date())
                showCalendar = true
            }
            .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                VStack(spacing: 12) {
                    MonthCalendar(selection: $customDate)
                    HStack {
                        Button("Clear") { dueDate = nil; showCalendar = false }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                        Spacer()
                        Button("Set") {
                            dueDate = Calendar.current.startOfDay(for: customDate)
                            showCalendar = false
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(14)
                .frame(width: 300)
            }

            Spacer(minLength: 0)
        }
    }

    private func presetDate(_ preset: DuePreset) -> Date {
        preset.date(now: Date(), weekStyle: settings.weekStyle)
    }

    /// Presets can collide — on a Thursday in work-week mode, "Tomorrow" and
    /// "End of week" are both Friday. Highlight only the first (leftmost)
    /// match so two pills never light up for one date.
    private func isSelected(_ preset: DuePreset) -> Bool {
        guard let due = dueDate else { return false }
        let cal = Calendar.current
        let firstMatch = DuePreset.allCases.first { cal.isDate(due, inSameDayAs: presetDate($0)) }
        return firstMatch == preset
    }

    /// True when a due date is set that doesn't match any preset (a custom pick).
    private var isCustomSelected: Bool {
        guard let due = dueDate else { return false }
        return !DuePreset.allCases.contains { Calendar.current.isDate(due, inSameDayAs: presetDate($0)) }
    }

    /// The "Other" pill shows the picked date once a custom one is chosen.
    private var customLabel: String {
        if isCustomSelected, let due = dueDate {
            return due.formatted(.dateTime.month(.abbreviated).day())
        }
        return "Other"
    }

    private func toggle(_ preset: DuePreset) {
        let date = presetDate(preset)
        if let due = dueDate, Calendar.current.isDate(due, inSameDayAs: date) {
            dueDate = nil
        } else {
            dueDate = date
        }
    }

    // MARK: Body

    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            if body_.isEmpty {
                Text("Notes (Markdown)…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $body_)
                .font(.callout)
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: 60)
        }
    }

    // MARK: Actions

    private func seedFromSelection() {
        assignedProjectIDs = appState.selectedProjectID.map { [$0] } ?? []
    }

    /// Create the task, then reset the composer (re-seeding the current project)
    /// and keep focus so the user can keep capturing.
    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let task = library.addTask(
            title: trimmed,
            projectIDs: assignedProjectIDs,
            due: dueDate
        )
        // `addTask` doesn't take a body, so apply any composed notes with a
        // follow-up update.
        let bodyTrimmed = body_.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bodyTrimmed.isEmpty {
            var t = task
            t.body = body_
            library.updateTask(t)
        }

        title = ""
        body_ = ""
        showBody = false
        dueDate = nil
        seedFromSelection()
        titleFocused = true
    }
}

// MARK: - Task card

/// A single task rendered as an editable Liquid Glass row. Like `NoteCardView`
/// it owns a mutable `draft` so typing is instant, and coalesces writes onto a
/// ~0.4s debounce (each `updateTask` rewrites a file and bumps `updated`).
private struct TaskCardView: View {
    /// The canonical task from the library. External edits and our own saves
    /// flow back in via `onChange`.
    let task: TaskItem
    /// Only the aggregate view shows which project(s) a task belongs to.
    let showsProjectChips: Bool

    @Environment(Library.self) private var library

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

    @FocusState private var titleFocused: Bool
    @FocusState private var bodyFocused: Bool

    init(task: TaskItem, showsProjectChips: Bool) {
        self.task = task
        self.showsProjectChips = showsProjectChips
        _draft = State(initialValue: task)
    }

    private var hasBody: Bool {
        !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Only worth a chevron when there's more to reveal than the one line on
    /// show — or when we're expanded and it's the way back.
    private var showsChevron: Bool {
        expanded || (hasBody && fullBodyHeight > previewHeight + 1)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            checkbox

            VStack(alignment: .leading, spacing: 8) {
                // The ⋯ menu rides the title row, as it does on a note card.
                HStack(alignment: .center, spacing: 8) {
                    TextField("Task", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.body.weight(.medium))
                        .foregroundStyle(draft.done ? Color.secondary : Color.primary)
                        .strikethrough(draft.done)
                        .focused($titleFocused)

                    actionsMenu
                }

                // Body, then the chips / due row — same order as a note card,
                // where the pills sit under the text you're writing.
                bodySection

                metaRow
            }
        }
        .padding(12)
        .island(radius: Metrics.rowRadius)
        .opacity(draft.done ? 0.7 : 1)
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
        .onDisappear {
            // Flush any pending edit so nothing is lost when the row scrolls out
            // or the project changes.
            if saveTask != nil {
                saveTask?.cancel()
                saveTask = nil
                library.updateTask(draft)
            }
        }
    }

    // MARK: Checkbox

    private var checkbox: some View {
        Button(action: toggleDone) {
            Image(systemName: draft.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(draft.done ? Color.accentColor : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(draft.done ? "Mark as not done" : "Mark as done")
    }

    /// Flip the done state via the library. Any in-flight text edit is flushed
    /// and the debounce cancelled first, so a stale snapshot can't later revert
    /// the toggle; `draft` is kept in sync immediately to avoid a flash.
    private func toggleDone() {
        if saveTask != nil {
            saveTask?.cancel()
            saveTask = nil
            library.updateTask(draft)
        }
        library.toggleTask(id: draft.id)
        draft.done.toggle()
    }

    // MARK: Meta row (chips + due badge)

    private var metaRow: some View {
        HStack(spacing: 6) {
            if showsProjectChips {
                ForEach(draft.projectIDs, id: \.self) { id in
                    if let project = library.project(id: id) {
                        ProjectChip(project: project) {
                            draft.projectIDs.removeAll { $0 == id }
                            persistNow()
                        }
                    }
                }
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
                Text(draft.due == nil ? "Due" : DueFormat.relative(draft.due))
            }
            .font(.caption)
            .foregroundStyle(dueColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(dueColor.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help("Set due date")
        .popover(isPresented: $showDuePopover, arrowEdge: .bottom) {
            duePopover
        }
    }

    /// Red once overdue, blue for today, secondary otherwise / undated.
    private var dueColor: Color {
        guard let due = draft.due, !draft.done else { return .secondary }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let day = cal.startOfDay(for: due)
        if day < today { return .red }
        if day == today { return .blue }
        return .secondary
    }

    private var duePopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            MonthCalendar(
                selection: Binding(
                    get: { draft.due ?? Calendar.current.startOfDay(for: Date()) },
                    set: { draft.due = $0; persistNow() }
                )
            )

            Button(role: .destructive) {
                draft.due = nil
                persistNow()
                showDuePopover = false
            } label: {
                Label("Clear due date", systemImage: "xmark.circle")
            }
            .buttonStyle(.plain)
            .disabled(draft.due == nil)
        }
        .padding(14)
        // Wide enough that the month grid gets room to breathe — the calendar
        // stretches to fill it.
        .frame(width: 300)
    }

    // MARK: Body

    /// A growing Markdown editor, revealed by the disclosure control. Mirrors
    /// `NoteCardView`'s sizing-proxy approach so the row expands to fit rather
    /// than scrolling internally.
    /// Collapsed: the body's first line, ellipsised, tappable to open. Expanded:
    /// the editor. The chevron lives here rather than in the corner, next to the
    /// text it reveals, and only appears when there's something hidden.
    @ViewBuilder
    private var bodySection: some View {
        if expanded || hasBody {
            HStack(alignment: .top, spacing: 6) {
                if expanded {
                    bodyEditor
                } else {
                    bodyPreview
                }

                if showsChevron {
                    Button {
                        expanded.toggle()
                        if expanded { bodyFocused = true }
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(expanded ? "Collapse notes" : "Expand notes")
                }
            }
        }
    }

    private var bodyPreview: some View {
        Text(draft.body)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
            // Tapping the preview opens the editor, so a one-line body — which
            // gets no chevron — is still editable.
            .onTapGesture {
                expanded = true
                bodyFocused = true
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
            .background(alignment: .topLeading) {
                // The same text laid out unbounded: taller means the preview is
                // truncating, which is what the chevron is for.
                Text(draft.body)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullBodyHeight = $0 }
            }
    }

    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            Text(draft.body.isEmpty ? " " : draft.body)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 5)
                .opacity(0)

            if draft.body.isEmpty && !bodyFocused {
                Text("Notes (Markdown)…")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 9)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $draft.body)
                .font(.callout)
                .textEditorStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($bodyFocused)
        }
        .frame(minHeight: 28)
    }

    // MARK: Trailing controls

    private var actionsMenu: some View {
        Menu {
            if !expanded {
                Button {
                    expanded = true
                    bodyFocused = true
                } label: {
                    Label(hasBody ? "Show Notes" : "Add Notes", systemImage: "note.text")
                }
            }
            Button(role: .destructive) {
                saveTask?.cancel()
                library.deleteTask(id: draft.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Task actions")
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

    /// Persist an immediate, structural change (done/due/projects). Cancels the
    /// text debounce and flushes the whole draft so nothing is lost and no stale
    /// snapshot can revert what we just set.
    private func persistNow() {
        saveTask?.cancel()
        saveTask = nil
        library.updateTask(draft)
    }
}

// MARK: - Due-date pills

/// The quick relative due-date options offered in the composer.
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

/// A capsule due-date pill. Prominent glass when selected, plain glass
/// otherwise — matching the macOS 26 control language.
private struct DuePill: View {
    let label: String
    var systemImage: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        if selected {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(label)
            }
            .font(.caption.weight(selected ? .semibold : .regular))
        }
        .controlSize(.small)
        .buttonBorderShape(.capsule)
    }
}
