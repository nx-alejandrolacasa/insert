import AppKit
import SwiftUI

/// The panes of the Settings window, in sidebar order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, notes, tasks, accessibility, storage

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .notes: "Notes"
        case .tasks: "Tasks"
        case .accessibility: "Accessibility"
        case .storage: "Storage"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .notes: "note.text"
        case .tasks: "checklist"
        case .accessibility: "accessibility"
        case .storage: "externaldrive"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .notes: .purple
        case .tasks: .blue
        case .accessibility: .teal
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
            case .accessibility: AccessibilitySettingsTab()
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
                // Not `LabeledContent`: with a two-row grid for content it
                // parked the label oddly against the row's corner. Top-aligned
                // by hand, with the label padded down to the same inset the
                // Accent row's centred label lands at (its 30pt swatch line
                // centres a ~16pt label ≈ 7pt in), so the two rows read as one
                // margin.
                HStack(alignment: .top) {
                    Text("Tint")
                        .padding(.top, 7)
                    Spacer()
                    BackdropPicker(selection: settings.backdrop) { settings.backdrop = $0 }
                }
            } header: {
                Text("Background")
            } footer: {
                Text("A flat, low-chroma tint on the window surface — no gradient. Each one has a Light and Dark value, so it follows the theme above.")
            }

            Section {
                // A plain HStack centres the label on the swatches, which
                // `LabeledContent` didn't.
                HStack {
                    Text("Highlight colour")
                    Spacer()
                    AccentPicker(selection: settings.accent) { settings.accent = $0 }
                }
            } header: {
                Text("Accent")
            }

            Section {
                TypefacePicker(selection: settings.typeface) { settings.typeface = $0 }
            } header: {
                Text("Typeface")
            } footer: {
                Text("The face notes and tasks are written in — titles and bodies, both while reading and while editing. The rest of the window keeps the system font, and code blocks stay monospaced.")
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
                // "morning" is in the label, not just the footer: it's what makes
                // the times on offer stopping at midday read as the point of the
                // feature rather than as a missing half of the clock.
                Toggle("Daily morning reminder", isOn: $settings.dailyReminder)
                    .onChange(of: settings.dailyReminder) { _, on in
                        // Ask for permission on the way in, not at launch — see
                        // `TaskReminder.requestAuthorization()`.
                        if on { TaskReminder.shared.requestAuthorization() }
                        TaskReminder.shared.reschedule()
                    }

                if settings.dailyReminder {
                    // A list of half hours, not a time field: a `DatePicker` here
                    // froze this pane for seconds, and a morning reminder has no use
                    // for the rest of the clock anyway. Both reasons, and the
                    // measurements behind the first, are on `ReminderSchedule.slots`.
                    // No `.environment(\.locale, …)` either — the labels are literal
                    // digits, so there is no date being formatted to get wrong.
                    Picker("Time", selection: $settings.reminderMinutes) {
                        ForEach(ReminderSchedule.slots, id: \.self) { minutes in
                            Text(ReminderSchedule.label(minutes)).tag(minutes)
                        }
                    }
                    // No `onChange` here: the reminder's clock re-reads the time on
                    // every tick, so a new one needs nothing re-aimed. Only the
                    // toggle above starts and stops anything.
                }
            } footer: {
                Text("One notification each morning, counting the tasks due that day — “You have 3 tasks for today”. The times on offer stop at midday because a count of the day's work is only worth having before the day starts. Nothing is sent on a day with nothing due, and it never names a task. Insert has to be running to send it.")
            }

            Section {
                Picker("Preview lines", selection: $settings.taskPreviewLines) {
                    ForEach(PreviewLines.allCases) { lines in
                        Text(lines.label).tag(lines)
                    }
                }
            } footer: {
                Text("How much of a task's notes shows before it's folded: so many lines, fading out at the cut, with a chevron to reveal the rest. Editing a task always shows all of it.")
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
                Picker("Preview lines", selection: $settings.notePreviewLines) {
                    ForEach(PreviewLines.allCases) { lines in
                        Text(lines.label).tag(lines)
                    }
                }
            } footer: {
                Text("How much of a note shows before it's folded: so many lines, fading out at the cut, with a chevron to reveal the rest. Editing a note always shows all of it.")
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

    init(type: NoteType) {
        self.type = type
        _name = State(initialValue: type.name)
    }

    var body: some View {
        HStack(spacing: 12) {
            // The type's colour dot, the same mark it wears on the cards' meta
            // rows and in the filter track. (A symbol well sat here until the
            // type symbols were removed from notes wholesale.)
            Circle()
                .fill(type.tint.accent)
                .frame(width: 10, height: 10)

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
        if !type.isLocked {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            updated.name = trimmed
        }
        settings.updateNoteType(updated)
    }
}

/// The inline form for creating a new custom type. Kept deliberately minimal:
/// name, tint, and an "Add" button that no-ops on an empty name.
private struct AddNoteTypeForm: View {
    private let settings = SettingsStore.shared

    @State private var name = ""
    @State private var tint: Tint = .blue

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        // Same column rhythm as the rows above, so the add form lines up with
        // the list it appends to.
        HStack(spacing: 12) {
            Circle()
                .fill(tint.accent)
                .frame(width: 10, height: 10)

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
        // The default symbol, unpicked: nothing shows type symbols any more,
        // but the frontmatter field survives, so new types still get a sane
        // one for anything reading the files elsewhere.
        settings.addNoteType(name: trimmedName, symbol: SymbolCatalog.defaultNote, tint: tint)
        // Reset for the next entry.
        name = ""
        tint = .blue
    }
}

// `SymbolWell` — the round tinted symbol-picker button each type row led with —
// lived here until the type symbols were removed from notes wholesale (main
// view, edit mode and this pane, July 2026, maintainer's request). Projects
// keep their symbols and their own `SymbolPicker` flow; only the note types
// lost theirs.

// MARK: - Accessibility

/// In-app versions of the three system Accessibility switches the interface
/// honours. Each is OR-ed with its system counterpart wherever that one was
/// already read — turning one on here quiets Insert without asking the whole
/// Mac to change, and a system setting that's on always applies regardless.
private struct AccessibilitySettingsTab: View {
    @Bindable var settings = SettingsStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Reduce motion", isOn: $settings.appReduceMotion)
            } footer: {
                Text("Cards, the sidebar and the filter selection change in one step instead of travelling.")
            }

            Section {
                Toggle("Reduce transparency", isOn: $settings.appReduceTransparency)
            } footer: {
                Text("Translucent surfaces become opaque: the filter rows' glass selection pill, the # project dropdown, and popovers like the due-date calendar.")
            }

            Section {
                Toggle("Increase contrast", isOn: $settings.appIncreaseContrast)
            } footer: {
                Text("Colours deepen, metadata darkens, and every hairline border firms up, so text and controls stand further off their backgrounds.")
            }

            Section {
            } footer: {
                Text("Each switch works alongside its system-wide setting: turning one on here changes Insert alone, and a system setting that is on always applies.")
            }
        }
        .formStyle(.grouped)
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
