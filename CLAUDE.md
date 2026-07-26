# CLAUDE.md

Insert — a native macOS **projects / notes / tasks** app written in Swift/SwiftUI
(macOS 26, Liquid Glass). Three columns: projects sidebar, notes, tasks. Data is
Obsidian-style Markdown on disk. A menu-bar extra shows pending tasks at a glance.

## Build & run

- **No Xcode project** — this is a Swift Package (Command Line Tools + SwiftPM).
- `./build.sh` — compile + assemble `build/Insert.app`.
- `./build.sh run` — build + (re)launch it.
- `./build.sh install` — build + install into `/Applications` and relaunch.
- `./build.sh release` — build signed with the *release* identity; what CI runs.
- `./build.sh icon` — regenerate `Resources/AppIcon.icns` from `tools/IconGenerator.swift`.
- `./dmg.sh [version]` — package the built app as `build/Insert[-version].dmg`.
- `swift build --disable-sandbox` to just compile (`--disable-sandbox` is required
  inside agent/CI shells; harmless otherwise).

Releasing: push a `vX.Y.Z` tag and `.github/workflows/release.yml` builds on a
`macos-26` runner, packages the DMG and publishes a GitHub Release. Two stable
self-signed certs keep macOS's Documents-folder grant from resetting — `Insert
Dev` locally, `Insert Release` for `release`/`install` and CI (imported there from
the `INSERT_CERT_P12` / `INSERT_CERT_PASSWORD` secrets; absent them the build
falls back to ad-hoc). See README → "Sign once, grant once".

## Data model & storage

Everything lives under a root folder (default `~/Documents/Insert`, changeable in
Settings → Storage):

```
root/
  Notes/        one <slug>-<id>.md per note  (YAML frontmatter + Markdown body)
  Tasks/        one <slug>-<id>.md per task
  Projects.md   frontmatter list of projects
```

Frontmatter is a tiny YAML subset (see `Frontmatter.swift`) — `key: value`
scalars, flow arrays (`[a, b]`), and flow maps (`- {k: v}`) for the projects
list. Timestamps are RFC-3339; task `due` dates are plain `yyyy-MM-dd`. Files are
plain Markdown so they can be edited in Obsidian; a `DirectoryWatcher` reloads
the in-memory index when the folder changes externally.

## Layout

```
Package.swift                 SwiftPM manifest (executable target, macOS 26)
Resources/Info.plist          bundle metadata (regular app + menu-bar extra)
build.sh                      build + bundle + sign
dmg.sh                        package build/Insert.app into a distributable DMG
.github/workflows/release.yml tag-triggered build → DMG → GitHub Release
Sources/Insert/
  InsertApp.swift             @main App: WindowGroup + MenuBarExtra + Settings
  AppDelegate.swift           regular activation policy + appearance
  RootView.swift              3-column layout, toolbar, search, ⌘§ sidebar toggle
  ProjectsSidebar.swift       left column: projects list, sort, add/edit/delete
  NotesPanel.swift            center: note islands, type pills, sort/filter, edit
  TasksPanel.swift            right: tasks, checkboxes, # project autocomplete
  MenuBar.swift               menu-bar extra: pending tasks at a glance
  SettingsView.swift          General / Note Types / Storage
  Library.swift               @Observable store: load/index/CRUD/search + watcher
  AppState.swift              transient window UI state (selection, filters…)
  SettingsStore.swift         persisted settings (appearance, note types…)
  Models.swift                Project / Note / TaskItem / NoteType + sort enums
  Frontmatter.swift           YAML-subset frontmatter reader/writer + date coding
  MarkdownFiles.swift         model <-> Markdown + filename conventions
  DirectoryWatcher.swift      debounced FS watcher (external edits)
  DateSections.swift          overdue/today/upNext buckets for the menu bar
  MarkdownText.swift          compact Markdown renderer for bodies
  Theme.swift                 Tint palette, spacing tokens, .island()
  Appearance.swift            Auto/Light/Dark
tools/IconGenerator.swift     draws the app icon (CoreGraphics)
Resources/AppIcon.icns        generated app icon
```

## Design intent

Behaviour that isn't obvious from the code, and shouldn't drift:

- **Layout** — the projects sidebar is collapsible (toolbar button or ⌘ + the
  leftmost key of the number row: ANSI grave, keyCode 50, or ISO section,
  keyCode 10). With it hidden, notes and tasks split the window 50/50.
- **Search** — the toolbar field filters all three columns at once (projects,
  notes and tasks), not just the focused one.
- **Projects** — each row shows its emoji, name and a live `X notes · Y tasks`
  subtitle. Sorting is latest-used or A–Z.
- **Notes** — with no project selected, all notes are shown and each island
  displays the project it belongs to. Default types are Note (📝, blue),
  Meeting (🤝🏻, yellow), Feedback (💬, purple) and Staffing (👥, green); users
  can add/edit/remove types in Settings, except **Note**, which is locked
  (`NoteType.isLocked`) because it is the fallback type.
- **Tasks** — a new task inherits the selected project, or stays unassigned. A
  task can be assigned to several projects. Typing `#` opens a project
  autocomplete; Tab picks the first match; the `#word` is *not* kept in the
  task text, it only adds the assignment. Assignments appear as chips below and
  are removed by double-clicking them.
- **Icon** — minimal stacked cards on a pastel lilac → warm apricot gradient
  with a purple/orange badge. Keep it soft and modern; palette lives at the top
  of `tools/IconGenerator.swift`.

Two of the author's own apps are the reference points: **prtscn** for project
structure and SwiftUI patterns, and **TXTodo** for the menu-bar extra's
at-a-glance pending-task behaviour.

## Conventions

- Pure native, **no third-party dependencies** — system frameworks only.
- Shared state is `@MainActor @Observable` (`Library`, `AppState`, `SettingsStore`),
  created once in `InsertApp` and injected via `.environment(…)`; views read them
  with `@Environment(Type.self)`.
- Settings persist to `UserDefaults`; notes/tasks/projects persist to Markdown.
- Swift 6 strict concurrency: no shared non-Sendable globals (date formatters are
  built per-call; the FS watcher confines its state to a serial queue).
