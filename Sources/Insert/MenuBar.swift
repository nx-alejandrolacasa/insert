import AppKit
import SwiftUI

// MARK: - Menu-bar status label

/// The status-bar item shown in the system menu bar.
///
/// Unlike `MenuBarContent`, this view is NOT rendered inside a `.menu`-style
/// dropdown — it *is* the status item — so a normal `HStack` of `Image` + `Text`
/// renders correctly here. We keep it deliberately compact: just the state
/// glyph when there is nothing pressing, plus a short count only when there are
/// overdue or due-today tasks (mirroring TXTodo's "glance" behaviour).
struct MenuBarLabel: View {
    /// Only the task list is needed to derive the badge; the label never mutates.
    @Environment(Library.self) private var library
    /// …and the day it is bucketed against, which changes on its own. See `DayClock`.
    @Environment(DayClock.self) private var clock

    var body: some View {
        // Recomputed on every render; SwiftUI re-renders when `library.tasks` or
        // the day changes, because both are `@Observable`.
        let sections = DateSections.make(from: library.tasks, now: clock.today)
        let summary = sections.menuBarTitle

        // Show the at-a-glance summary sentence ("1 overdue · 1 today") right in
        // the menu bar, next to the icon. When everything is clear the summary is
        // empty, so we fall back to just the icon to keep the footprint minimal.
        if summary.isEmpty {
            Image(systemName: Self.glyph(overdue: !sections.overdue.isEmpty))
                // Without this VoiceOver announces the status item as an unnamed
                // menu; the glyph alone carries the "no pending tasks" state.
                .accessibilityLabel("\(Self.appName) — no pending tasks")
        } else {
            HStack(spacing: 4) {
                Image(systemName: Self.glyph(overdue: !sections.overdue.isEmpty))
                    .accessibilityHidden(true)
                Text(summary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(Self.appName) — \(summary)")
        }
    }

    /// A hammer for the dev build, so two menu-bar items are telling apart
    /// without clicking either.
    ///
    /// Otherwise the glyph itself reports the one state worth noticing at a
    /// glance: `checkmark.circle` while nothing is late, and the
    /// `trianglebadge.exclamationmark` variant the moment something is overdue.
    /// The two differ by a badge in a corner rather than by stroke weight, which
    /// is what makes them distinguishable at menu-bar size — the failing of the
    /// near-identical `checklist` variants this replaced.
    private static func glyph(overdue: Bool) -> String {
        if BuildVariant.isDev { return "hammer.fill" }
        return overdue ? "checkmark.circle.trianglebadge.exclamationmark" : "checkmark.circle"
    }

    private static var appName: String {
        "Insert\(BuildVariant.titleSuffix)"
    }
}

// MARK: - Menu-bar dropdown

/// The dropdown shown when the status item is clicked.
///
/// The scene uses `.menuBarExtraStyle(.menu)`, so this view may only contain
/// menu-native controls (`Button`, `Text`, `Divider`, `Section`, `Label`,
/// `Toggle`, nested `Menu`). Custom-styled containers do not render in that
/// style, so everything below sticks to those primitives.
struct MenuBarContent: View {
    @Environment(Library.self) private var library
    @Environment(AppState.self) private var appState
    @Environment(DayClock.self) private var clock
    @Environment(\.openWindow) private var openWindow

    private var updater: UpdateChecker { UpdateChecker.shared }

    /// Max task rows rendered per section before collapsing the remainder into
    /// a single "+ K more…" affordance — keeps the menu short and scannable.
    private let sectionCap = 6

    var body: some View {
        // Single snapshot so every section below sees a consistent bucketing.
        let sections = DateSections.make(from: library.tasks, now: clock.today)

        // Summary line: the compact TXTodo-style sentence, or an all-clear note.
        // Rendered as a disabled Button so it reads as a non-interactive header
        // while still being a valid `.menu` control.
        Text(summaryLine(sections))

        Divider()

        if sections.totalPending == 0 {
            // Nothing pending at all — a friendly confirmation instead of blanks.
            Text("All clear")
        } else {
            taskSection(title: "Overdue", tasks: sections.overdue)
            taskSection(title: "Today", tasks: sections.today)
            taskSection(title: "Up Next", tasks: sections.upNext)
            taskSection(title: "Unscheduled", tasks: sections.unscheduled)
        }

        Divider()

        // Surfaced by the quiet launch-time check — most users never open
        // Settings → About, so the update offer has to live where they look.
        if updater.phase == .available, let release = updater.latest {
            Button {
                Task { await updater.installLatest() }
            } label: {
                Label("Update to \(release.version)…", systemImage: "arrow.down.circle")
            }
            Divider()
        }

        Section {
            // Named for the variant, so a dev menu doesn't offer to open what
            // looks like the real app.
            Button("Open Insert\(BuildVariant.titleSuffix)") { openMainWindow() }
            Button("New Task") {
                // Bring the window forward first, then ask it to start a new task.
                openMainWindow()
                NotificationCenter.default.post(name: .newTask, object: nil)
            }
            // Settings is an AppKit window (full-height sidebar), so open it
            // directly rather than through `SettingsLink`.
            Button("Settings…") { SettingsWindowController.shared.show() }
            Divider()
            Button("Quit Insert\(BuildVariant.titleSuffix)") { NSApplication.shared.terminate(nil) }
        }
    }

    // MARK: Sections

    /// Renders one due-date bucket as a titled section, or nothing when empty.
    /// Caps the visible rows and offers a "+ K more…" jump into the app.
    @ViewBuilder
    private func taskSection(title: String, tasks: [TaskItem]) -> some View {
        if !tasks.isEmpty {
            Section("\(title) · \(tasks.count)") {
                ForEach(tasks.prefix(sectionCap)) { task in
                    taskButton(task)
                }
                let overflow = tasks.count - sectionCap
                if overflow > 0 {
                    Button("+ \(overflow) more…") { openMainWindow() }
                }
            }
        }
    }

    /// A single task row: clicking it quick-completes (toggles) the task, exactly
    /// like ticking it off from the menu bar. Instead of a generic checkbox we
    /// lead with the symbol of the task's (first) assigned project, so the list
    /// reads at a glance.
    private func taskButton(_ task: TaskItem) -> some View {
        Button {
            library.toggleTask(id: task.id)
        } label: {
            Label {
                Text(rowTitle(task))
            } icon: {
                Image(systemName: leadingSymbol(task))
            }
        }
    }

    /// The symbol of the task's first assigned project, falling back to a plain
    /// circle for an unassigned task.
    private func leadingSymbol(_ task: TaskItem) -> String {
        for id in task.projectIDs {
            if let project = library.project(id: id) {
                return project.symbol
            }
        }
        return "circle.dashed"
    }

    // MARK: Text helpers

    /// The header sentence: prefer `DateSections`' compact phrasing, falling back
    /// to an explicit all-clear message when there is genuinely nothing pending.
    private func summaryLine(_ sections: DateSections) -> String {
        // Plain words: the decorative glyph this used to carry was read aloud by
        // VoiceOver as "sextile".
        let title = sections.menuBarTitle
        return title.isEmpty ? "All clear" : title
    }

    /// Builds a task row title: "Title — Due (Project)". The due suffix is added
    /// only when the task has a date, and the project suffix only when assigned.
    private func rowTitle(_ task: TaskItem) -> String {
        var line = task.displayTitle
        let due = DueFormat.relative(task.due, now: clock.today)
        if !due.isEmpty { line += " — \(due)" }
        if let project = task.projectIDs.lazy.compactMap({ library.project(id: $0) }).first {
            line += " (\(project.name))"
        }
        return line
    }

    // MARK: Window

    /// Opens (or focuses) the single main window and brings the app forward,
    /// since a menu-bar-triggered action would otherwise leave it in the back.
    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
