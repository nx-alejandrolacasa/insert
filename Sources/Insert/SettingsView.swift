import AppKit
import SwiftUI

/// The panes of the Settings window, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, notes, tasks, storage

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .notes: "Notes"
        case .tasks: "Tasks"
        case .storage: "Storage"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .notes: "note.text"
        case .tasks: "checklist"
        case .storage: "externaldrive"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .notes: .purple
        case .tasks: .blue
        case .storage: .orange
        }
    }
}

/// The sidebar column of the Settings window. Its background stays clear so the
/// AppKit sidebar material behind it (see `SettingsWindowController`) shows
/// through — that material is what runs to the top of the window, under the
/// traffic lights.
struct SettingsSidebar: View {
    @Bindable var model: SettingsWindowModel

    var body: some View {
        List(SettingsPane.allCases, selection: $model.pane) { pane in
            SettingsPaneLabel(pane: pane)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
}

/// The detail column: just the selected pane's form. The back/forward chevrons
/// and the pane title live in the window's real toolbar (see
/// `SettingsWindowController`), because that band belongs to AppKit — a SwiftUI
/// header drawn into it from here ends up either stranded below the title bar or
/// hidden underneath it.
struct SettingsDetail: View {
    let model: SettingsWindowModel

    var body: some View {
        Group {
            switch model.pane {
            case .general: GeneralSettingsTab()
            case .notes: NotesSettingsTab()
            case .tasks: TasksSettingsTab()
            case .storage: StorageSettingsTab()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The toolbar's contents for the detail side: history chevrons, then the pane
/// name a fixed gap away. Hosted as a single `NSToolbarItem` so AppKit places it
/// in the title bar next to the traffic lights, System Settings style.
struct SettingsPaneHeader: View {
    let model: SettingsWindowModel

    var body: some View {
        HStack(spacing: 10) {
            historyChevrons

            Text(model.pane.title)
                .font(.headline)
                .lineLimit(1)
                .fixedSize()

            Spacer(minLength: 0)
        }
        // A fixed width, leading-aligned: the toolbar item is sized to its
        // content, so letting it shrink with the pane name ("Tasks" vs "Storage")
        // slid the chevrons sideways on every selection.
        .frame(width: Metrics.settingsHeaderWidth, alignment: .leading)
    }

    /// One glass capsule split by a hairline, as in System Settings: back on the
    /// left, forward on the right, each dimmed when there's nowhere to go. The
    /// halves are near-square so the capsule reads as round, not as a flat pill.
    private var historyChevrons: some View {
        HStack(spacing: 0) {
            chevron("chevron.left", help: "Back", enabled: model.canGoBack) { model.goBack() }
            Divider().frame(height: 16).opacity(0.5)
            chevron("chevron.right", help: "Forward", enabled: model.canGoForward) { model.goForward() }
        }
        .glassEffect(.regular, in: Capsule())
    }

    private func chevron(
        _ symbol: String,
        help: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 31, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A sidebar row in the System Settings style: the pane name next to a small
/// white symbol on a rounded colored tile.
private struct SettingsPaneLabel: View {
    let pane: SettingsPane

    var body: some View {
        Label {
            Text(pane.title)
        } icon: {
            Image(systemName: pane.icon)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 23, height: 23)
                .background(pane.tint.gradient, in: RoundedRectangle(cornerRadius: 6))
                // The Label's text names the pane; the tile is decoration.
                .accessibilityHidden(true)
        }
    }
}

// MARK: - General

/// The app-wide preferences. Anything specific to notes or tasks lives in their
/// own pane.
private struct GeneralSettingsTab: View {
    // The Settings window is hosted by AppKit (see SettingsWindowController),
    // so there is no injected environment here — read the shared store directly.
    @Bindable var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                BackdropPicker(selection: settings.backdrop) { settings.backdrop = $0 }
            } header: {
                Text("Background")
            } footer: {
                Text("A gradient behind the main window. Each one has a light and a dark version, so it follows the theme above — the swatches show whichever is in use right now.")
            }

            Section {
                Toggle("Show menu-bar item", isOn: $settings.showMenuBar)
            } footer: {
                Text("The menu-bar item summarizes tasks that are past due, due today, and coming up.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tasks

/// Everything task-specific: what "End of week" means for a due date, and how
/// long completed tasks stick around.
private struct TasksSettingsTab: View {
    @Bindable var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Picker("Week ends on", selection: $settings.weekStyle) {
                    ForEach(WeekStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
            } footer: {
                Text("A full week ends on Sunday, a work week on Friday — this is what a task's “End of week” due date means.")
            }

            Section {
                Toggle("Daily reminder", isOn: $settings.dailyReminder)
                    .onChange(of: settings.dailyReminder) { _, on in
                        // Ask for permission on the way in, not at launch — see
                        // `TaskReminder.requestAuthorization()`.
                        if on { TaskReminder.shared.requestAuthorization() }
                        TaskReminder.shared.reschedule()
                    }

                if settings.dailyReminder {
                    DatePicker(
                        "Time",
                        selection: $settings.reminderTime,
                        displayedComponents: .hourAndMinute
                    )
                    // The one place in Settings that shows a time, so it takes the
                    // same locale as every other date in the app — 24-hour, in
                    // English — rather than the system's. See `Formatting`.
                    .environment(\.locale, Formatting.locale)
                    // No `onChange` here: the reminder's clock re-reads the time on
                    // every tick, so a new one needs nothing re-aimed. Only the
                    // toggle above starts and stops anything.
                }
            } footer: {
                Text("One notification a day, counting the tasks due that day — “You have 3 tasks for today”. Nothing is sent on a day with nothing due, and it never names a task. Insert has to be running to send it.")
            }

            Section {
                Toggle("Color tasks by due date", isOn: $settings.dueTintedTasks)
            } footer: {
                Text("Task backgrounds take their due badge's color — orange when overdue, green due today, purple upcoming. Undated tasks keep the neutral background.")
            }

            Section {
                Picker("Show dates", selection: $settings.taskCardDates) {
                    ForEach(CardDates.allCases) { dates in
                        Text(dates.label).tag(dates)
                    }
                }
            } footer: {
                Text("Stamped at the foot of each task — a sparkle marks when it was created, a pencil when it was last edited. “Most recent” shows the last edit, or the creation date if it has never been edited.")
            }

            Section {
                Picker("Remove completed tasks", selection: $settings.doneTaskRetention) {
                    ForEach(DoneTaskRetention.allCases) { retention in
                        Text(retention.label).tag(retention)
                    }
                }
                // Apply the new rule at once, so the choice has a visible
                // effect rather than waiting for the next launch.
                .onChange(of: settings.doneTaskRetention) { _, retention in
                    Library.shared.purgeCompletedTasks(retention: retention)
                }
            } footer: {
                Text(retentionFooter)
            }
        }
        .formStyle(.grouped)
    }

    /// Spells out what the current retention actually does — including where
    /// the files go, since this is the one setting that removes things on its
    /// own.
    private var retentionFooter: String {
        switch settings.doneTaskRetention {
        case .never:
            "Completed tasks are kept for as long as you want them."
        default:
            "Tasks completed longer ago than this are cleared out at launch and hourly while Insert runs. Their Markdown files are moved to the Trash, so you can always get them back."
        }
    }
}

// MARK: - Notes

/// Everything note-specific: the default sort order, then the type editor — an
/// editable list of existing types plus an inline "add" form. Every mutation
/// routes through `SettingsStore`, which keeps the locked base "Note" type
/// intact regardless of what the UI sends.
private struct NotesSettingsTab: View {
    @Bindable private var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Picker("Sort notes by", selection: $settings.noteSort) {
                    ForEach(NoteSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
            }

            Section {
                Picker("Show dates", selection: $settings.noteCardDates) {
                    ForEach(CardDates.allCases) { dates in
                        Text(dates.label).tag(dates)
                    }
                }
            } footer: {
                Text("Stamped at the foot of each note — a sparkle marks when it was created, a pencil when it was last edited. “Most recent” shows the last edit, or the creation date if it has never been edited.")
            }

            Section {
                ForEach(settings.noteTypes) { type in
                    NoteTypeRow(type: type)
                }
            } header: {
                Text("Types")
            } footer: {
                Text("Types color and label your notes. The built-in “Note” type can be recolored but not renamed or removed.")
            }

            Section("Add a Type") {
                AddNoteTypeForm()
            }
        }
        .formStyle(.grouped)
    }
}

/// One editable row. Holds its own draft copy so typing stays smooth, then
/// pushes each committed change back through `updateNoteType`. The locked base
/// type disables its name field and drops the delete control.
private struct NoteTypeRow: View {
    private let settings = SettingsStore.shared

    let type: NoteType

    @State private var name: String
    @State private var symbol: String

    init(type: NoteType) {
        self.type = type
        _name = State(initialValue: type.name)
        _symbol = State(initialValue: type.symbol)
    }

    var body: some View {
        HStack(spacing: 12) {
            // The symbol sits in a round well tinted with the type's colour, so
            // the row reads as "this swatch + this name".
            SymbolWell(symbol: symbol, tint: type.tint) { picked in
                symbol = picked
                commit()
            }

            // A fixed width keeps every name field the same size down the list.
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 150)
                .disabled(type.isLocked)
                .onSubmit(commit)
                // Commit renames when focus leaves too, not only on Return.
                .onChange(of: name) { _, _ in commit() }

            TintPicker(selection: type.tint) { newTint in
                var updated = type
                updated.tint = newTint
                settings.updateNoteType(updated)
            }

            Spacer(minLength: 4)

            if type.isLocked {
                // Explains, unobtrusively, why this row can't be renamed/removed.
                Image(systemName: "lock.fill")
                    .foregroundStyle(.tertiary)
                    .help("The built-in “Note” type is always available.")
                    .accessibilityLabel("Locked")
            } else {
                Button(role: .destructive) {
                    settings.removeNoteType(id: type.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this type")
                // Every row's button would otherwise be an identical unnamed
                // control; name it after the row it belongs to.
                .accessibilityLabel("Delete the \(type.name) type")
            }
        }
        // `Form` labels any bare control in a row; an empty label keeps the
        // stray "Name" text out of every row.
        .labelsHidden()
        .padding(.vertical, 2)
    }

    /// Persists the current draft. Ignores empty names for the (renameable)
    /// custom types; the locked type's name is enforced by the store anyway.
    private func commit() {
        var updated = type
        updated.symbol = symbol
        if !type.isLocked {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            updated.name = trimmed
        }
        settings.updateNoteType(updated)
    }
}

/// The inline form for creating a new custom type. Kept deliberately minimal:
/// name, symbol, tint, and an "Add" button that no-ops on an empty name.
private struct AddNoteTypeForm: View {
    private let settings = SettingsStore.shared

    @State private var name = ""
    @State private var symbol = "tag"
    @State private var tint: Tint = .blue

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        // Same column rhythm as the rows above, so the add form lines up with
        // the list it appends to.
        HStack(spacing: 12) {
            SymbolWell(symbol: symbol, tint: tint) { symbol = $0 }

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 150)
                .onSubmit(add)

            TintPicker(selection: tint) { tint = $0 }

            Spacer(minLength: 4)

            Button("Add", action: add)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(trimmedName.isEmpty)
        }
        .labelsHidden()
        .padding(.vertical, 2)
    }

    private func add() {
        guard !trimmedName.isEmpty else { return }
        settings.addNoteType(name: trimmedName, symbol: symbol, tint: tint)
        // Reset for the next entry.
        name = ""
        symbol = "tag"
        tint = .blue
    }
}

/// The type's symbol as a round, tinted well: a circular swatch that opens the
/// searchable symbol picker, so each row leads with a consistent colour dot
/// rather than a boxy field.
private struct SymbolWell: View {
    let symbol: String
    let tint: Tint
    let onPick: (String) -> Void

    @State private var showingPicker = false

    private static let size: CGFloat = 32

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint.ink)
                .frame(width: Self.size, height: Self.size)
                .background(Circle().fill(tint.chip))
                .overlay(Circle().strokeBorder(tint.accent.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Set this type's symbol")
        .accessibilityLabel("Set this type's symbol")
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            SymbolPicker(selection: symbol, tint: tint) { picked in
                onPick(picked)
                showingPicker = false
            }
            .frame(width: 320)
        }
    }
}

// MARK: - Storage

/// Where the markdown lives. Lets the user relocate the folder or reveal it in
/// Finder, and explains that everything is plain files editable elsewhere.
private struct StorageSettingsTab: View {
    private let library = Library.shared

    /// A folder the user picked but hasn't committed to yet — the
    /// move-or-just-switch choice is on screen.
    @State private var pendingFolder: URL?
    /// What the last relocation did. Reported inline rather than in an alert:
    /// it's information, not a problem to dismiss. A `Text` rather than a
    /// `String` so the file count can carry inflection markup (see `move`).
    @State private var status: Text?

    var body: some View {
        Form {
            Section {
                LabeledContent("Location") {
                    Text(library.rootURL.path)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Change…", action: changeFolder)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([library.rootURL])
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                }

                if let status {
                    status
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Notes, projects, and tasks are stored as plain Markdown files. You can browse and edit them directly in any text or Markdown editor, and Insert will pick up outside changes automatically.")
            }
        }
        .formStyle(.grouped)
        // Changing the folder is two different intentions — take my files with
        // me, or open a library that's already over there — so ask instead of
        // guessing. Only shown when there is something to migrate.
        .confirmationDialog(
            "Move your Markdown to the new folder?",
            isPresented: dialogBinding,
            titleVisibility: .visible,
            presenting: pendingFolder
        ) { folder in
            Button("Move Files") { move(to: folder) }
            Button("Switch Without Moving") { switchOnly(to: folder) }
            Button("Cancel", role: .cancel) { pendingFolder = nil }
        } message: { folder in
            Text("Insert can move your notes, tasks and project list into “\(folder.lastPathComponent)”, or just read whatever is already there and leave the current folder untouched.")
        }
    }

    private var dialogBinding: Binding<Bool> {
        Binding(get: { pendingFolder != nil }, set: { if !$0 { pendingFolder = nil } })
    }

    /// Presents a directory-only open panel. `runModal` is safe to call here
    /// because SwiftUI view bodies run on the main actor.
    private func changeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the folder where Insert should store your Markdown."
        panel.directoryURL = library.rootURL

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL != library.rootURL.standardizedFileURL else { return }

        // With an empty library there's nothing to move, so skip the question.
        if library.isEmpty {
            switchOnly(to: url)
        } else {
            pendingFolder = url
        }
    }

    private func switchOnly(to url: URL) {
        pendingFolder = nil
        library.setRoot(url)
        status = Text("Now reading from this folder. Nothing was moved.")
    }

    private func move(to url: URL) {
        pendingFolder = nil
        do {
            let result = try library.moveRoot(to: url)
            // `file\(n == 1 ? "" : "s")` is English-only and unlocalizable;
            // `^[…](inflect: true)` has Foundation agree the noun with the count.
            let moved = Text("Moved ^[\(result.moved) file](inflect: true) here.")
            status = result.skipped > 0
                ? Text("\(moved) \(result.skipped) stayed behind — the new folder already had a file with the same name.")
                : moved
        } catch {
            status = Text("Couldn’t move the files: \(error.localizedDescription)")
        }
    }
}
