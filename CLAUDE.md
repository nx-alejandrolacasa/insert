# CLAUDE.md

Insert — a native macOS **projects / notes / tasks** app written in Swift/SwiftUI
(macOS 26, Liquid Glass). Three columns: projects sidebar, notes, tasks. Data is
Obsidian-style Markdown on disk. A menu-bar extra shows pending tasks at a glance.

## Build & run

- **No Xcode project** — this is a Swift Package (Command Line Tools + SwiftPM).
- `./build.sh` — compile + assemble the **dev** variant, `build/Insert Dev.app`.
- `./build.sh run` — build the dev app + (re)launch it.
- `./build.sh install` — build the **release** variant + install into
  `/Applications` and relaunch.
- `./build.sh release` — build the release variant signed with the *release*
  identity; what CI runs before `dmg.sh`.
- `./build.sh icon` — regenerate `Resources/AppIcon.icon` (layered) and
  `Resources/AppIcon.icns` (flat fallback) from `tools/IconGenerator.swift`.
- `./dmg.sh [version]` — package the built app as `build/Insert[-version].dmg`.
- `swift build --disable-sandbox` to just compile (`--disable-sandbox` is required
  inside agent/CI shells; harmless otherwise).

Two variants, so the copy you use daily and a work-in-progress build coexist —
the same split prtscn uses. `install`/`release` produce `Insert.app`
(`com.alejandrolacasa.insert`); anything else produces `Insert Dev.app`
(`…insert.dev`). macOS keys UserDefaults and the Documents grant to the bundle id,
so each keeps its own settings and asks for access once. Because the dev build has
its own defaults it never inherits the real saved folder and defaults to
`~/Documents/Insert Dev` (`BuildVariant`), which keeps test deletions and the
retention sweep away from real notes. It also wears a hammer in the menu bar
instead of the checklist.

Releasing: push a `vX.Y.Z` tag and `.github/workflows/release.yml` builds on a
`macos-26` runner, packages the DMG and publishes a GitHub Release. Two stable
self-signed certs keep macOS's Documents-folder grant from resetting — `Insert
Dev` locally, `Insert Release` for `release`/`install` and CI (imported there from
the `INSERT_CERT_P12` / `INSERT_CERT_PASSWORD` secrets; absent them the build
falls back to ad-hoc). See README → "Sign once, grant once".

Insert is deliberately **not** Developer ID signed, notarized or sandboxed — a
settled decision, not an oversight. HIG asks for all three when shipping outside
the App Store, so this is a knowing departure, on the grounds that the DMG exists
for the author's own machines: Developer ID needs a paid Apple Developer account,
and App Sandbox would mean reworking how the storage folder is reached, since a
sandboxed app can't reopen an arbitrary path from a stored string across launches
and would need a security-scoped bookmark instead. The cost is that anyone else
meets Gatekeeper on first launch, which README → "Download" already tells them how
to get past. Worth revisiting only if the Release is genuinely aimed at other
people.

## Data model & storage

Everything lives under a root folder (default `~/Documents/Insert`, changeable in
Settings → Storage):

```
root/
  Notes/           one <slug>-<id>.md per note  (YAML frontmatter + Markdown body)
  Tasks/           one <slug>-<id>.md per task, pending
    Done/          completed tasks
  Projects.md      frontmatter list of projects
```

**Everything is loaded, always** — every note and task, on every load, with the
decode spread across the cores (`Library.decoded(_:)`). No window, no threshold,
nothing deferred, so every list is complete and every count exact whatever shape the
library is. `Tasks/Done/` is organisational only: it keeps a large vault navigable
and `reconcileTaskFolders` keeps the folder in step with each task's `done:` flag in
both directions. See "Loading" under Design intent — including why the archive
folder that used to live here is gone.

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
  AppDelegate.swift           regular activation policy + task housekeeping
  RootView.swift              3-column layout, toolbar, search, ⌘§ sidebar toggle
  ProjectsSidebar.swift       left column: projects list, sort, add/edit/delete
  NotesPanel.swift            center: note islands, type pills, sort/filter, edit
  TasksPanel.swift            right: tasks, checkboxes, # project autocomplete
  MenuBar.swift               menu-bar extra: pending tasks at a glance
  SettingsView.swift          General / Note Types / Storage
  Library.swift               @Observable store: lazy load/index/CRUD/search + watcher
  AppState.swift              transient window UI state (selection, filters…)
  SettingsStore.swift         persisted settings (note types, sort, retention…)
  Models.swift                Project / Note / TaskItem / NoteType + sort enums
  Frontmatter.swift           YAML-subset frontmatter reader/writer + date coding
  MarkdownFiles.swift         model <-> Markdown + filename conventions
  DirectoryWatcher.swift      debounced FS watcher (external edits)
  DateSections.swift          overdue/today/upNext buckets for the menu bar
  Formatting.swift            the locale the UI presents in (English)
  BuildVariant.swift          dev vs release build, and what differs
  MarkdownText.swift          compact Markdown renderer for bodies
  Theme.swift                 Tint palette (roles + contrast), tokens, .island()
tools/IconGenerator.swift     draws the app icon (SVG layers + CoreGraphics)
Resources/AppIcon.icon/       generated layered icon (icon.json + SVG layers)
Resources/AppIcon.icns        generated flat icon, the fallback
Tests/InsertTests/            the one test target — see below
```

`swift test --disable-sandbox` runs two suites. `StorageLayoutTests` drives the real
`Library` against a throwaway root — the legacy-flat-layout migration, filing tasks
under `Done/`, writes that must not lose a file, the retention purge, and that the
parallel load is complete and ordered. `DateCodingTests` pins the date reader and
writer against the two formatters it replaced, over 4,013 dates, because that is the
on-disk format for every record and "faster" is worthless if it isn't identical.

Both exist because this code moves the user's Markdown around, where a mistake is
data loss rather than a wrong pixel; between them they caught three real bugs that
reading the code had not. `swift build` skips the test target, so neither `build.sh`
nor CI is affected.

## Design intent

Behaviour that isn't obvious from the code, and shouldn't drift:

- **Layout** — the projects sidebar is collapsible (toolbar button or ⌘ + the
  leftmost key of the number row: ANSI grave, keyCode 50, or ISO section,
  keyCode 10). With it hidden, notes and tasks split the window 50/50.
  Its width comes from `Metrics.{min,ideal,max}SidebarWidth` — 200pt on open, which
  is where a project name and its `X notes · Y tasks` subtitle both fit and nothing
  more, since the rest belongs to notes and tasks. But **the `min:` you pass
  `navigationSplitViewColumnWidth` does not police a restored width**: AppKit
  autosaves the column widths under `NSSplitView Subview Frames …` and hands that
  value back whatever the minimum says, which had the sidebar reopening at 158pt
  with project names truncated to "Everyt…". Two things in `AppDelegate` fix it, and
  it takes both: `sanitizeSidebarWidth()` rewrites the saved width before the first
  window lays out (so there's no visible jump), and `normalizeSidebarWidth()` sets it
  on the live `NSSplitView` once a window exists (so it's actually right). The
  defaults write alone loses a race to the *previous* instance — `./build.sh run`
  `pkill`s it and waits for the process to go, but its autosave flushes through
  `cfprefsd` afterwards and overwrites ours, which is why a corrected width still
  came back at the old value. Both run once per install per default width, keyed on
  `sidebarWidthNormalized-<width>`, which self-invalidates when
  `idealSidebarWidth` changes; after that only widths below the minimum are
  corrected, so a divider the user drags stays put. **Changing the constant is
  therefore enough** — but expect the *first* launch after it to be the one that
  moves an existing window, not the build itself.
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
  are removed by double-clicking them (or via the chip's context menu — the
  double-click is deliberately hard to trigger, so it can't be the only route).
- **Loading — read it all, and don't get clever.** `reloadAll` parses every note and
  every task, every time. That is the design, not a placeholder: it's what makes
  each list complete, each count exact and search honest, with no thresholds to
  tune and nothing distribution-dependent. It costs about **110 µs per note** — of
  which 18 µs is reading the file — and `Library.decoded(_:)` divides the work
  across the cores above 256 files, so a thousand notes is a few tens of
  milliseconds. Measured: 1,000 notes parse in 103 ms serially, 41 ms across ten
  cores; 10,000 in 1.1 s / 411 ms; 50,000 in 10.7 s / 2.0 s. **Around 10,000
  records is where you'd start to feel it and 50,000 where eager loading stops
  being viable** — if the app ever gets there, measure before reaching for
  laziness, and read the next bullet first.
- **The laziness that was here, and why it went.** Insert briefly had a
  `Notes/Archive/` folder, an age setting, a note-count threshold, per-folder
  modification-date windows, `loadArchivedNotes`/`loadDoneTasks`/`loadEverything`,
  and a "+N archived" tail in the sidebar. It was deleted, for two reasons worth
  keeping written down. It was **inconsistent**: the age window was global, so what
  a project showed depended on other projects' activity, and no folder rule can fix
  that — a note's projects live *inside* its file, so any rule that decides which
  files to open must work from the folder and the mtime alone, and is therefore
  distribution-dependent by construction. And it was **unnecessary**: `DateCoding`
  built a `DateFormatter` per date, 180 µs of the 291 µs a note then cost, so more
  than half of "loading is slow" was one throwaway allocation. Fixing that (see
  `DateCoding`, pinned by `DateCodingTests`) beat the entire lazy-loading feature.
  The lesson generalises — the apparatus was also paying its own per-record costs,
  normalising a path per file to track what was loaded, to avoid work that cost less
  than the accounting.
- **Compare paths, never `URL`s.** Use `Library.key(_:)`. A URL built by appending
  to a folder and one handed back by `FileManager` can name the very same file and
  still compare unequal. Not fussiness — it bit twice: it had a load re-decode notes
  it already held, leaving `deduped` to "resolve" the duplicate ids by trashing
  files; and in `persistNote`/`persistTask`, which write the new file *before*
  unlinking the old one, it made an ordinary in-place edit delete the file it had
  just written. Both are covered by `StorageLayoutTests`.
- **Colour** — `Tint` exposes colours by *role*, not by shade, and every value is
  solved against WCAG AA: `deep` is a fill that carries white type (≥4.5:1),
  `ink` is a foreground for glyphs on the app's own surfaces, and `accent` is
  decorative. `deep` and `ink` are separate because they invert relative to each
  other in Dark Mode — don't collapse them back into one "deep". Both adapt to
  Light/Dark and Increase Contrast through one dynamic `NSColor`, so call sites
  stay plain `Color`. **Selection is a filled pill, never an outline**: `deep` and
  `chip` share a hue, so a border drawn from one against the other can't reach
  the 3:1 an indicator needs in both appearances at any opacity.
- **Appearance** — Insert follows the system. There is deliberately **no** per-app
  Light/Dark override; HIG advises against one, and it previously lived in
  Settings → General. Please don't add it back.
- **Language** — the app is **English only**, and that includes dates. Every UI
  string is an English literal, so formatting dates in the *system* locale gave
  interfaces in two languages at once: a Spanish Mac showed a due badge reading
  "Last vie" and stamped an English note "25 jul 2026". Anything user-facing
  formats through `Formatting.locale` (`en_GB` — English names, but day-first
  dates and Monday-first weeks). Never format a user-facing date off
  `Locale.current`. The on-disk format is separate and pinned to `en_US_POSIX`
  in `DateCoding`, so none of this can rewrite a Markdown file.
- **Glass** — Liquid Glass is for the *control* layer. Cards, rows and pills in the
  content layer use `.island()` and the flat `Stone`/`Tint` washes instead (glass
  islands also pooled their shadows — see `Theme.swift`). The exception HIG allows,
  and the one Insert takes, is a transient floating control: the `#project`
  autocomplete dropdown. `.glassProminent` paints the accent colour behind a
  label, so it's rationed to **one per surface** — "New Note", "New Task", and the
  confirm button of each popover. Adding a second to any one surface is the thing
  to avoid.
- **Icon** — minimal stacked cards on a pastel lilac → warm apricot gradient
  with a purple/orange badge. Keep it soft and modern; palette and proportions
  live at the top of `tools/IconGenerator.swift`.
  One set of proportions drives two renders, and they differ on purpose. The
  layered `AppIcon.icon` is **full-bleed and unmasked with no baked-in effects** —
  macOS 26 draws the corner radius, the specular highlights and the dark/clear/
  tinted variants, and pre-masked layers wreck those. The flat `AppIcon.icns`
  keeps its own inset rounded tile, drop shadows and sheen, because nothing
  decorates a plain `.icns`. Don't align the two.
  **`groups` in `icon.json` runs front to back** — `groups[0]` is drawn last, on
  top. That's the reverse of how a layers panel usually reads and it's half of why
  this icon rendered wrong: the background was listed first, so it was painted
  *over* the cards as a translucent gradient sheet and left the whole design a
  ghost. The order is badge, front card, back card.
  **`translucency` is off for every group, the other half.** Icon Composer defaults
  it *on* at 0.5, and a white card on a pastel background you can half see through
  is most of the way to not being there. With it off, `glass: true` is welcome —
  that one is the Liquid Glass treatment the design wants, and the system still
  lights each layer, rims it and drops the `neutral` shadow that separates one card
  from the next. So: glass yes, translucency no. Turning translucency back on means
  darkening the background first; the cards have nothing else to contrast against.
  The **background is the document's `fill`**, a two-stop `linear-gradient`, not a
  layer. A background layer takes its group's glass treatment, and the dark /
  clear / tinted variants are derived from the fill, so hiding it in a layer
  leaves the system nothing to work from. `linear-gradient` carries no direction,
  which is why the layered background runs top-to-bottom where the flat `.icns`
  runs corner to corner — the one place the two renders differ on the *drawing*
  rather than the effects.
  `icon.json` isn't publicly documented, so two command-line tools stand in for
  reading the docs. `ictool` (inside Xcode's `Icon Composer.app`) is the authority
  on whether a document is *valid*: it validates by refusing to open one it
  dislikes, so a bad enum or a scale-only `position` reads as "the data couldn't be
  read" where a good document gets as far as rendering. And `actool` writes a flat
  `AppIcon.icns` of the composed result next to `Assets.car`, which is how to
  actually *see* the layered icon — up to 256px, and it needs no GPU, so unlike
  `ictool --export-image` it works in an agent sandbox:

  ```
  actool Resources/AppIcon.icon --compile /tmp/out --platform macosx \
      --minimum-deployment-target 26.0 --app-icon AppIcon \
      --output-partial-info-plist /tmp/out/p.plist
  iconutil -c iconset /tmp/out/AppIcon.icns -o /tmp/out/AppIcon.iconset
  ```

  (`--app-icon` must match the package's basename or it silently compiles nothing.)
  **The layered icon is what ships**, and `icon.json` is byte-for-byte what Icon
  Composer saves — five decimals of colour, expanded objects, no trailing newline —
  so opening the package, saving, and re-running `./build.sh icon` is a no-op rather
  than a diff. Keep it that way. The flat `.icns` stays as the fallback for a
  machine with only the Command Line Tools, where there's no `actool` to compile the
  layers; `INSERT_LAYERED_ICON=0 ./build.sh` forces that path for comparison.

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
