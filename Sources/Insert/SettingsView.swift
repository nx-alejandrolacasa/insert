import AppKit
import SwiftUI

/// The panes of the Settings window, in sidebar order.
///
/// **Appearance is its own pane and Storage is not a pane at all**, which is one
/// change rather than two. General had grown into the window's junk drawer —
/// appearance, theme, typeface, spelling, the menu-bar item — and the typeface
/// section ends in a footer three paragraphs long, because the OFL requires the
/// licence notice to travel with the fonts. Anything under that footer was
/// effectively hidden: you had to scroll past the legal text to find the two
/// toggles. So the three chrome controls moved out together, which also settled a
/// smaller annoyance — the word "Appearance" printed twice in one form, once as a
/// section header and once as the row label under it. The pane's name says it now:
/// the section header is gone and the row that switches Auto / Light / Dark is
/// labelled **"Mode"**, so the word appears once per screen.
///
/// That left General with two toggles, so **Storage folded into it** and its pane
/// went: one folder path, two buttons and a footer was never a pane's worth of
/// settings on its own, and "where the files live" is as general as a setting
/// gets. Nothing persists the selected pane, so no migration was needed for the
/// case that disappeared.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, notes, tasks, accessibility, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .notes: "Notes"
        case .tasks: "Tasks"
        case .accessibility: "Accessibility"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .notes: "note.text"
        case .tasks: "checklist"
        case .accessibility: "accessibility"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .pink
        case .notes: .purple
        case .tasks: .blue
        case .accessibility: .teal
        case .about: .indigo
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
            case .appearance: AppearanceSettingsTab()
            case .notes: NotesSettingsTab()
            case .tasks: TasksSettingsTab()
            case .accessibility: AccessibilitySettingsTab()
            case .about: AboutSettingsTab()
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

/// The app-wide preferences that aren't chrome: spelling, the menu-bar item, and
/// **where the Markdown lives** — the last of which was its own pane until the
/// appearance controls moved out and left this one with two toggles (see
/// `SettingsPane`).
private struct GeneralSettingsTab: View {
    // The Settings window is hosted by AppKit (see SettingsWindowController),
    // so there is no injected environment here — read the shared store directly.
    @Bindable var settings = SettingsStore.shared

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
                Toggle("Show menu-bar item", isOn: $settings.showMenuBar)
            } footer: {
                Text("The menu-bar item summarizes tasks that are past due, due today, and coming up.")
            }

            Section {
                Toggle("Check spelling while typing", isOn: $settings.checkSpelling)
            } footer: {
                Text("Underlines misspelled words while you write a note or a task — title and body both — in the spelling language your Mac is set to. Control-click a word for its corrections. Nothing is ever changed for you: autocorrect and grammar checking stay off.")
            }

            // The old Storage pane, unchanged apart from gaining a header: with
            // its own pane gone, the group needs a name, and "Location" beside
            // the path is a label for the row rather than for the section.
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
            } header: {
                Text("Storage")
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

// MARK: - Appearance

/// How the window looks: light or dark, which theme, and the face cards are
/// written in. The three that used to sit at the top of General, and the reason
/// they are here is in `SettingsPane` — the typeface footer's licence text buried
/// everything under it.
///
/// **The Auto / Light / Dark row is labelled "Mode", not "Appearance".** The pane
/// is Appearance — in the sidebar and in the title bar — so a row of the same name
/// under it printed the word three times on one screen, which is what this split
/// was partly meant to fix; the section header went with it, since the pane's name
/// already does that job and a bare segmented picker only needs the row label.
///
/// **"Mode" moves, "Theme" stays**, and that is the cheaper direction: the
/// palettes below *are* named themes (Neon, Kanagawa), which is what a user
/// already calls them, and it is what the type is called in the code (`AppTheme`)
/// and throughout CLAUDE.md. Naming the light/dark switch "Theme" and the palettes
/// "Colour scheme" was the other option and would have renamed the better-known of
/// the two. `Appearance` keeps its name as a *type*; only its label is "Mode".
private struct AppearanceSettingsTab: View {
    @Bindable var settings = SettingsStore.shared

    /// Which bundled licence the sheet is showing, or `nil` for closed.
    @State private var licence: FontLicence?

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                // Not `LabeledContent`: with a grid for content it parked the
                // label oddly against the row's corner. Top-aligned by hand,
                // padded down to where a centred label would land on the first
                // row of swatches.
                //
                // No section header, for the reason above and the one this
                // originally had: the row's own label already says "Theme".
                HStack(alignment: .top) {
                    Text("Theme")
                        .padding(.top, 9)
                    Spacer()
                    ThemePicker(selection: settings.theme) { settings.theme = $0 }
                }
            } footer: {
                Text("The theme colours the column headers, the window behind the cards, the primary buttons and the note-type marks. Light and dark values are built in — Mode decides which you see.")
            }

            // Between Theme and Typeface, which is the order the three
            // questions are asked in: what colour, what size, what face. Both
            // rows are steppers rather than sliders because both values are
            // discrete and small — a slider would offer a precision neither has
            // and hide the number, which is the thing being chosen.
            Section {
                LabeledContent("Text size") {
                    ValueStepper(
                        value: settings.cardFontSize,
                        bounds: CardTextSize.range,
                        text: "\(settings.cardFontSize)",
                        widest: "\(CardTextSize.range.upperBound)",
                        decreaseLabel: "Smaller text",
                        increaseLabel: "Larger text"
                    ) {
                        settings.cardFontSize -= 1
                    } onIncrease: {
                        settings.cardFontSize += 1
                    }
                }
                LabeledContent("Line height") {
                    ValueStepper(
                        value: settings.cardLineHeight,
                        bounds: CardLineHeight.range,
                        text: CardLineHeight.label(settings.cardLineHeight),
                        widest: CardLineHeight.label(CardLineHeight.range.upperBound),
                        decreaseLabel: "Tighter lines",
                        increaseLabel: "Looser lines"
                    ) {
                        settings.cardLineHeight -= CardLineHeight.step
                    } onIncrease: {
                        settings.cardLineHeight += CardLineHeight.step
                    }
                }
            } footer: {
                Text("The size notes and tasks are read and written at, and how far apart their lines sit — a line height of 1.0 is the spacing the typeface itself sets. Both reach a card's title and body, reading and editing alike; the window around them keeps the system's size.")
            }

            // Last in the pane, deliberately: its footer is three paragraphs and
            // ends in the two licence links, so anything under it reads as an
            // afterthought — which is exactly what happened to General's toggles.
            Section {
                TypefacePicker(selection: settings.typeface) { settings.typeface = $0 }
            } header: {
                Text("Typeface")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The face notes and tasks are written in — titles and bodies, both while reading and while editing. Column headings follow it too; the rest of the window keeps the system font, and code blocks stay monospaced.")
                    // The OFL requires the copyright notice and licence to
                    // travel with the fonts, so the bundled text is reachable
                    // from the pane that offers them rather than only from the
                    // files inside the bundle.
                    //
                    // The two links sit on their **own line under** the
                    // sentence, not beside it: in one `HStack` they took half the
                    // footer's width and wrapped the paragraph into a five-line
                    // column against a single line of links. A footer is prose
                    // with an action after it, so it reads as one.
                    Text("Grotesk is Space Grotesk; counts and timestamps are IBM Plex Mono. Both are used under the SIL Open Font License 1.1.")
                    // A middot between them, not just a gap: two blue phrases
                    // side by side read as one long link with a space in it,
                    // where a separator says they are two — the same job the
                    // interpunct does in a card's meta row.
                    HStack(spacing: 6) {
                        ForEach(Array(FontLicence.allCases.enumerated()), id: \.element) { index, item in
                            if index > 0 {
                                Text("·")
                            }
                            Button(item.button) { licence = item }
                                .buttonStyle(.link)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $licence) { item in
            FontLicenceSheet(licence: item) { licence = nil }
        }
    }
}

/// The two bundled faces, for the licence sheet.
enum FontLicence: String, CaseIterable, Identifiable {
    case spaceGrotesk = "SpaceGrotesk-OFL"
    case plexMono = "IBMPlexMono-OFL"

    var id: Self { self }

    var title: String {
        switch self {
        case .spaceGrotesk: "Space Grotesk"
        case .plexMono: "IBM Plex Mono"
        }
    }

    /// The link's wording, short because two of them sit inline in a footer.
    var button: String {
        switch self {
        case .spaceGrotesk: "Space Grotesk licence"
        case .plexMono: "IBM Plex Mono licence"
        }
    }
}

/// One bundled font licence, in full.
///
/// The text is **read from the bundled file** rather than pasted into a Swift
/// literal, so the licence shipped and the licence shown cannot drift apart —
/// which is the whole obligation. Monospaced and selectable, because a licence
/// is a document to be copied, not prose to be styled.
private struct FontLicenceSheet: View {
    let licence: FontLicence
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(licence.title)
                .font(.headline)

            ScrollView {
                Text(BundledFonts.licence(licence.rawValue))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 520, height: 320)

            HStack {
                Spacer()
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
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
                    Task {
                        await Library.shared.purgeCompletedTasks(retention: retention)
                    }
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
/// The width shared by every name field in this pane — the type rows and the add
/// form below them, so the two line up as one column.
///
/// It is a number rather than a flexible frame because the Settings window is a
/// fixed 700pt and **not resizable** (`SettingsWindowController`), so this row's
/// budget is known: ~440pt of content, of which the tint swatches take 198 (nine
/// 22pt targets) and the spacings 60. At 150 that left 30pt for the "Add" button,
/// which came out as a capsule reading “A…”. 110 pays for the capsule with room
/// to spare and still holds the longest default name — and the button is
/// `fixedSize` besides, so a label can never again be the thing that gives.
private let noteTypeNameWidth: CGFloat = 110

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
                .frame(width: noteTypeNameWidth)
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
                .frame(width: noteTypeNameWidth)
                .onSubmit(add)

            TintPicker(selection: tint) { tint = $0 }

            Spacer(minLength: 4)

            Button("Add", action: add)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                // The label is not negotiable: in a row this full, SwiftUI's
                // answer was to truncate it to “A…” rather than take space from
                // anything else. `fixedSize` makes the button ask for the width
                // its word needs, so the row is short of room somewhere visible
                // instead of quietly unreadable here.
                .fixedSize()
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

// MARK: - About

/// The stand-in for the standard About panel, prtscn's arrangement: icon, name,
/// version, author and copyright, all read from the bundle so the dev variant
/// shows its own identity automatically — plus the update controls, since this
/// is where "what version am I on?" gets asked.
private struct AboutSettingsTab: View {
    private let updater = UpdateChecker.shared

    /// True for the dev variant, which opens the release page instead of
    /// self-installing — mirror that in the button label.
    private var isDevBuild: Bool { BuildVariant.isDev }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Insert"
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 Alejandro G. Lacasa"
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)

            Text(appName)
                .font(.title3.weight(.semibold))
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)

            updateControls
                .padding(.top, 8)

            Text("Projects, notes and tasks — plain Markdown on disk.")
                .font(.callout)
                .padding(.top, 10)

            Spacer(minLength: 0)

            Text("Created by Alejandro G. Lacasa")
                .font(.callout)
            Text(copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
    }

    /// One line of update state under the version: a check button, progress,
    /// the install offer, or an error with retry.
    @ViewBuilder
    private var updateControls: some View {
        switch updater.phase {
        case .idle:
            Button("Check for Updates…") { Task { await updater.check() } }
                .controlSize(.small)
        case .checking:
            progressLine("Checking…")
        case .upToDate:
            Text("You're up to date.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .available:
            HStack(spacing: 8) {
                Text("Version \(updater.latest?.version ?? "?") is available.")
                    .font(.caption)
                Button(isDevBuild ? "View on GitHub…" : "Install Update") {
                    Task { await updater.installLatest() }
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        case .downloading:
            progressLine("Downloading update…")
        case .installing:
            progressLine("Installing… the app will relaunch.")
        case .failed(let message):
            HStack(spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Try Again") { Task { await updater.check() } }
                    .controlSize(.small)
            }
        }
    }

    private func progressLine(_ label: String) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
