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
  TaskReminder.swift          the once-a-day "N tasks for today" notification
  Formatting.swift            the locale the UI presents in (English)
  SpellChecking.swift         spell checking in the cards' titles and bodies
  BuildVariant.swift          dev vs release build, and what differs
  MarkdownText.swift          compact Markdown renderer for bodies + the shared
                              collapsible preview (CollapsibleMarkdown)
  Theme.swift                 Tint palette (roles + contrast), tokens, .island()
  Appearance.swift            Auto / Light / Dark preference
  Backdrop.swift              the seven flat window tints + their Settings picker
  SegmentedFilter.swift       the filter rows' glass segmented control
  CardMeta.swift              marker title, type label, dot chips + overflow
  Typeface.swift              the four card faces + their Settings picker
tools/IconGenerator.swift     draws the app icon (SVG layers + CoreGraphics)
Resources/AppIcon.icon/       generated layered icon (icon.json + SVG layers)
Resources/AppIcon.icns        generated flat icon, the fallback
Tests/InsertTests/            the one test target — see below
```

`swift test --disable-sandbox` runs two suites over the data on disk.
`StorageLayoutTests` drives the real
`Library` against a throwaway root — the legacy-flat-layout migration, filing tasks
under `Done/`, writes that must not lose a file, the retention purge, and that the
parallel load is complete and ordered. `DateCodingTests` pins the date reader and
writer against the two formatters it replaced, over 4,013 dates, because that is the
on-disk format for every record and "faster" is worthless if it isn't identical.

Both exist because this code moves the user's Markdown around, where a mistake is
data loss rather than a wrong pixel; between them they caught three real bugs that
reading the code had not. `swift build` skips the test target, so neither `build.sh`
nor CI is affected.

Four more suites cover the pure functions the UI is built on, for the reason given
under "Return continues a list": the interesting logic there is arithmetic over
offsets, dates or font descriptors, and none of that needs a view.
`MarkdownFormattingTests` pins the ⌘B/⌘I wrapping and the rules for continuing a
list or a quote on Return; `MarkdownParserTests` pins the two parser outputs that
decide what a card *shows* — a quote's line breaks, and the one line a collapsed
task row teases; `ReminderScheduleTests` pins when the daily reminder is owed — the
minute either side of the time itself, the grace window, and the once-a-day rule —
since the alternative is waiting until tomorrow morning to find out. And
`TypefaceTests` pins which face each typeface resolves to and that its italic
really slants, because both fail *silently*: a system font asked for by name is
substituted (New York becomes Times), and a missing italic face falls back to the
upright one, so "it renders" and "it renders right" are different claims.

## Design intent

Behaviour that isn't obvious from the code, and shouldn't drift:

- **The July 2026 visual refresh** (`docs/plans/README.md` is the handoff, with
  the decision log and its mocks) restyled the surfaces without touching
  behaviour, and several bullets below changed with it. The shape of it: the
  five window *gradients* became seven flat **tints** (Plain + Linen / Clay /
  Blush / Sage / Mist / Lilac — saved gradients migrate by family, dark values
  derived, one L/C per role with hue the only variable); a note's type moved
  off the card wash onto a **marker stroke** behind the title plus a small-caps
  label in the meta row, so every card face is plain paper; metadata went
  **grey with red reserved for genuinely overdue** (`Semantic.overdue`,
  `Stone.metaText` — both solved for the refresh's ≥4.5:1 floor on sub-14px
  text); the filter rows became **glass segmented tracks** (`SegmentedFilter`);
  the **accent became a preference** (`AccentColor`, Settings → General →
  Accent, threaded through `.tint()` and read directly by the primary buttons
  and selection rings); and controls are pills while containers keep a 10–12pt
  radius — round means pressable. Judgment calls made during the port, so they
  aren't re-litigated: the Settings window's sidebar kept the system's own
  selection shape (the mock's pill sidebar there was never signed off); the
  due badge kept its `DueFormat.relative` copy and gained only the colour rule;
  and the typeface tiles are capsules by the maintainer's explicit choice.
  Two things the refresh then swept away entirely, both maintainer calls made
  after living with it: the opt-in **"Color tasks by due date" wash** (it was
  named after the badge colours the refresh had just retired, so the setting
  described nothing — removed, `island()` lost its `tint:` with it) and the
  **note-type symbols**, everywhere at once — the view-mode glyph, the
  edit-mode symbol-picker button, the type menu's icons and Settings' symbol
  wells — leaving marker, label and dot as a type's only marks. The model and
  frontmatter keep the `symbol` field, so files stay compatible; removing the
  edit-mode button is also what stopped the title sliding sideways as a card
  opened, and the note card's title row gained the explicit
  `cardTitleRowHeight` floor its 26pt symbol well used to provide by accident.
- **Settings → Accessibility** offers in-app Reduce Motion / Reduce Transparency /
  Increase Contrast (briefly a top-level menu, moved to its own Settings pane),
  each **OR-ed with its system counterpart** — they only add
  quiet, never override a system setting that's on. The first two pair at every
  `@Environment(\.accessibilityReduce…)` read (those keys are read-only, so
  there is no way to inject an override into the environment once for all).
  Increase Contrast is the odd one: the HC palette variants are chosen inside
  dynamic `NSColor` providers, which are nonisolated and can't read the store,
  so `SettingsStore` mirrors the flag into `AccessibilityOverride` — and then
  has to `refreshDynamicColors()`, flipping `NSApp.appearance` away and back in
  one turn, because providers cache per appearance and nothing else makes
  AppKit ask them again when only the flag changes. What the switches cover:
  Reduce Transparency opaques the window's two glass surfaces of ours (the
  filter indicator and the `#project` dropdown; the Plain sidebar's material is
  the system's and only the system switch touches it). Increase Contrast flips
  the tinted fills to their ≥7:1 variants **and hardens the `Stone` neutrals**
  — hairlines 0.18→0.45, washes up a step, `metaText` most of the way to the
  label colour — because the solved fills alone barely moved and the switch
  looked like it did nothing.
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
  subtitle. **The order is the user's own**: rows are dragged into place, and
  `Projects.md`'s line order *is* that order, so there is no sort control and
  nothing to persist beyond the file the list already lives in. (`lastUsed` is
  still recorded per project, and nothing reads it — it outlived the "Latest used"
  sort it was added for.)
  **The drag is a `DragGesture`, and both of the platform's own ways of doing it
  were observed not to work here.** `ForEach.onMove` gives an AppKit reorder for
  free and no row could be picked up; `.draggable` per row plus `.dropDestination`
  per gap, the modern spelling of the same thing, didn't lift a row either. Those
  two failures are the finding. The *explanation* — that both begin a native drag
  session from the row's **mouse-down**, and the row is a `Button`, because the
  selection pill is Insert's own rather than the system's, so the button answers
  that mouse-down and no session ever starts — fits, but it was never tested; the
  reorder was rewritten instead of instrumented. Don't repeat it as fact. What
  would settle it is one throwaway row that isn't a `Button` with `.draggable` on
  it. What stands on its own: a gesture *does* reach these rows (this file's own
  note that an `onTapGesture` on a row *swallows* the list's click is the same
  fact from the other side), so `reorderable` does it by
  hand: `.simultaneousGesture(DragGesture(minimumDistance: 4))`, each row
  reporting its frame with `onGeometryChange`, and the pointer's y read against
  those frames' **midpoints** — the rule every reorderable list on the platform
  uses, and the reason nothing needs to know a row's height in points.
  `simultaneousGesture` and a non-zero `minimumDistance` are both load-bearing:
  below the threshold the gesture never recognises, so the click that selects a
  project still lands, and "simultaneous" is what keeps the button and the drag
  from competing for one event stream.
  Both measurements are `.global`, and a **named** coordinate space measurably
  isn't a substitute. With `.coordinateSpace(.named(…))` on the `List` and both the
  row frames and the gesture asking for that name, the only position a project
  could be dragged to was the **top of the list** — which is what you get if both
  sides are really measuring *row-local* coordinates, since every row's local frame
  is then the same rectangle and the pointer is always above the first midpoint.
  Switching both to `.global` fixed it. That the name fails to reach the rows
  because a list hosts each one separately is the likely reason and is not
  something this repo has verified. `.global` needs no registration and does
  resolve inside a row, which the sidebar header's own measurement already relies
  on — reason enough to use it here without settling the rest.
  Three details worth keeping. The insertion line is drawn **inside** a row's
  bounds (top edge for the gap above it, bottom edge of the last row for the gap
  no row owns), because an overlay that leaves its row is the table cell's to clip
  and half a line is worse than none. The row in flight **fades rather than
  moves**, for the same clipping reason. And `gap(at:)` returns `nil` — no line,
  no write — both for the two gaps a row is already in and when *no* frame has
  been measured yet, since the fallback there reads as "past the last row" and
  would have any drag at all send the project to the end.
  Reordering is off while **searching**: the move would be well defined (gaps are
  named by row, not by offset), but the list on screen is a subset, so "above this
  row" would jump the project over rows the search is hiding, and there'd be no
  visible end of the list to aim at. `Library.moveProject(_:before:)` owns the
  off-by-one (`move(fromOffsets:toOffset:)` counts the source itself, so "stay
  put" is `from + 1`) and refuses a move that changes nothing rather than
  rewriting the file; `StorageLayoutTests` covers both ends of that and the round
  trip through the Markdown. The reorder **is** animated, unlike the notes
  column's re-sort: here it's the same rows in a new order, where there the whole
  list is replaced on the frame it happens and there is nothing left to animate.
- **Notes** — with no project selected, all notes are shown and each island
  displays the project it belongs to. Default types are Note (📝, blue),
  Meeting (🤝🏻, yellow), Feedback (💬, purple) and Staffing (👥, green); users
  can add/edit/remove types in Settings, except **Note**, which is locked
  (`NoteType.isLocked`) because it is the fallback type.
  **A note never moves while you're looking at it.** Typing saves on a ~0.4s
  debounce and every save bumps `updated`, so under the default "Updated (newest)"
  sort the card you were writing in slid from third place to first mid-sentence,
  taking the text under the cursor with it. `NotesPanel` pins a note's `updated`
  as it opens for editing (`NotePins`, keyed off `selectedNoteID` so every route
  into edit mode is covered) and `Library.notes(…, pinned:)` sorts it by the
  pinned value. The pins are dropped **only when the list is being rebuilt
  anyway** — another project, type filter, search or sort order — not when editing
  ends: the re-sort then lands on a frame where the whole column is replaced, so
  it is invisible. That is also why the reorder isn't animated; there is nothing
  left to animate, and animating a filter change would be wrong.
  Two things to keep: pin the *value*, not the whole list's order (an order can't
  say where a note created or externally edited meanwhile belongs), and
  `pin(_:)` is a no-op on an already-pinned note — re-pinning on a second edit
  would hand back exactly the jump this prevents. Covered by
  `StorageLayoutTests`.
  **In view mode a note's type shows twice and only twice** (the refresh's
  card anatomy): a highlighter band behind the title — `MarkerTitle`, drawing
  the type's `Tint.marker` over the bottom ~34% of *each line box*, because a
  single bottom-aligned background under a wrapped title strokes only the last
  line — and a small-caps `TypeCapsLabel` leading the meta row, in the type's
  `ink`. The card face itself is plain paper for every type, and the view-mode
  type glyph is gone: marker + label already say it twice, and a third voice
  was the wash's mistake in miniature. The meta row is one line — type ·
  hairline · project chips · timestamp — with the chips held to **two plus a
  `+N` overflow** whose hidden names are a click popover (`ProjectChipsRow`),
  so a card's height doesn't grow with its assignments.
  A note's **type** is, while editing, a pill-shaped dropdown in that type's
  colour at the trailing end of the chips row. It replaced a row of one filter
  pill per type, whose selected state is where the `deep`-and-white comes
  from: the control shows exactly one type and it is always the current one. The
  row cost a line of every open card and grew with every type added in Settings,
  which is space the note being written should have. A `Menu` styled by hand
  rather than a `Picker`, because a `Picker` redraws the label in system chrome
  and the colour is the point.
  The note's **type glyph is gone from every surface** (see the refresh
  bullet); a type's marks are the marker, the label and the dot. Worth keeping
  from the glyph's history, since it generalises: **a frame doesn't clip a
  glyph** — an SF Symbol wider than its frame spills straight out of the fill
  behind it (`person.3` measured 33pt wide at 15pt against a 26pt well), so
  anything drawing a symbol in a well must size the glyph to the widest symbol
  it can be asked to hold, the reason `chipHeight` is pinned to its tallest
  case.
  **A body can read collapsed — "Preview lines", notes and tasks each their own**
  (Settings → Notes / Tasks): show everything, or a preview of 1 / 3 / 5 / 10
  rendered lines with a chevron beside the body's *first* line to reveal the
  rest. Notes default to everything, so an untouched install keeps showing whole
  notes (an install that had the earlier "Collapse long notes" toggle on is
  seeded to 10 — that toggle was ten lines or nothing); tasks default to 1 line,
  the teaser those rows have always shown. View mode only — the editor always
  shows everything. All of it is **one shared view**, `CollapsibleMarkdown`
  (`MarkdownText.swift`), and it has two collapsed shapes because one line is
  not just a smaller ten. **One line** is the teaser (`MarkdownParser.lead`,
  rendered inline), laid out at its natural width and faded out at the trailing
  edge when the line is cut — never an ellipsis — with the full render swapped
  in on expand in one frame (`.transition(.identity)` against the default
  cross-fade). **Several lines** clamp the full render to that many line heights
  *of the card face* — not a count of source lines; the body is a stack of
  blocks no `lineLimit` fits, and a serif or monospaced card should fold at its
  own rhythm — fading to nothing over the last of them. Whether the chevron
  appears is measured off the **render** (the parser joins hard-wrapped lines,
  so a long source can render short), with **half a line of tolerance** on the
  clamp: a body of exactly the preview height drifts a fraction of a point per
  line against `n ×` an unrounded line height, and must not earn a chevron that
  reveals nothing. Two of the cards' own lessons are load-bearing in there. The
  clamped body is **one view** collapsed and expanded — `fixedSize` vertically
  so the clamp can't squeeze its blocks into ellipses, with only the
  `frame(maxHeight:)` value switching — because a conditional branch is two
  identities and would kill the height animation, which each card value-scopes
  to `expanded` beside the one scoped to `isEditing`; the masks are applied in
  *both* states (expanded they are opaque everywhere, a no-op) for the same
  one-identity reason. And the chevron rides the body's **first** line wearing
  the ⋯ menu's measured box: a control under the fold travels with the card's
  height — collapsing an expanded note had it floating down through the
  contraction with its `.replace` turn still playing — where on the first line
  it holds still, flush on the ⋯'s own trailing axis.
- **Tasks** — a new task inherits the selected project, or stays unassigned. A
  task can be assigned to several projects. Typing `#` opens a project
  autocomplete; Tab picks the first match; the `#word` is *not* kept in the
  task text, it only adds the assignment. Assignments appear as chips below and
  are removed by double-clicking them (or via the chip's context menu — the
  double-click is deliberately hard to trigger, so it can't be the only route).
  **A task's notes are Markdown, exactly as a note's body is** — including the
  collapsed one-line teaser, which used to print the *source*. So `**Ship it**` read
  as asterisks, and since the expand chevron only appears when there is more than
  one line to reveal, a short body had no route to ever being seen rendered.
  `MarkdownParser.lead(_:)` takes the first line and drops its *block* marker (a
  heading reads as its words, a bullet as its item) while leaving the inline markers
  for `MarkdownText.inline(_:in:)` to draw — the same two steps the expanded view
  takes per block. The chevron is now measured off the **render** rather than the
  source, because that is what it promises: the parser joins hard-wrapped lines into
  one paragraph, so a two-line source can render as one line and used to earn a
  chevron that revealed nothing. Pinned by `MarkdownParserTests`.
  A teaser longer than the row **fades out at its trailing edge instead of
  truncating to an ellipsis** — the clamp's gradient turned sideways, so the two
  cuts read as one gesture. The line is laid out at its natural width
  (`fixedSize`), clipped, and masked; the fade appears only when that width
  measurably exceeds the box's, because a fade over a line that fits would
  promise more where there isn't any. How many lines a row previews is the
  "Preview lines" setting — the folding is `CollapsibleMarkdown`, shared with
  the note card; see the notes bullet for the whole design.
  **A task doesn't move while you're looking at it either**, the notes column's
  rule read off a different sort key. Tasks sort pending-first, then by due date,
  then newest — and *both* mutable halves of that are things a row changes about
  itself, so `TaskPins` freezes the pair the moment it changes and
  `Library.tasks(…, pinned:)` sorts by the frozen value. The pins drop only when
  the list is being rebuilt anyway (project, task filter, search — there is no task
  sort setting, so that's the whole list), same as `NotePins`, and `pin(_:)` is the
  same no-op on an already-pinned row.
  The due-date popover is what this was reported from, and the shape of the
  report is worth keeping: **the preset pills "set the wrong date" while the month
  grid was fine.** Neither was true — due date is the list's *main* key, so dating
  an undated task sent it from the tail of the list to wherever that date belongs,
  and a pill dismisses the popover on the click that sets it, so the row left at
  the same instant the popover did and a *different*, still-undated task slid under
  the cursor. Two tasks are often the same shape, so that read as the click having
  landed wrong. The grid looked fine only because it leaves the popover open, which
  kept the row it was anchored to in view. Filtering is deliberately **not** pinned:
  under "Pending" a task you tick still leaves the list, because it is no longer one
  of the things that view is showing — the same line `NotePins` draws against the
  notes column's type filter. Covered by `StorageLayoutTests`.
  The filter row carries **two axes that combine**: the state track (All /
  Pending / Done), a `SegmentedFilter` radio — exactly one always lit — and a
  date **dropdown** (All time / Overdue / Today / Tomorrow, "All time" the
  default). ANDed together, so Pending + Today is the day's remaining work and
  Done + Overdue is what got finished late. The date axis was briefly a second
  trio of pills that *toggled* — clicking the lit one cleared it — and was
  redone as a dropdown on the grounds that two chip rows behaving differently
  is worse than a second control; the refresh kept it **outside the track**
  for the same reason from the other side, a window with an off state has no
  place among radios. The dropdown is neutral at rest and accent-filled while
  a window is active — the orange/green/purple it used to wear went grey with
  the rows it selects, so the pair still tell the same story. "All time" is
  `nil` in the model, not a fourth case, so every `TaskDateFilter` case is a
  real window and `matches` has no always-true branch. The date axis reads
  the **due date alone** — done-ness belongs to the state axis, or the
  combinations would mean nothing — so its "Overdue" is "due before today",
  *not* the menu bar's pending-only rule, which `DateSections` keeps for its
  buckets. The logic is `TaskFilter.matches(_:)` and
  `TaskDateFilter.matches(_:now:)`, pure functions with `now` injectable,
  pinned by `TaskFilterTests` at the day boundaries (yesterday / today /
  tomorrow / later, undated, done). Layout is a `ViewThatFits`: state track
  anchored left and the dropdown anchored right while the column fits both plus
  a 16pt gap; when it doesn't, they join **one line that scrolls sideways
  together**, the notes column's arrangement — never two rows, never a crushed
  gap. And a new task is pending and undated, so `createTask` resets a Done
  state segment and any date window before creating, or the task would be born
  hidden.
  The **due badge is grey until the task is genuinely overdue, then
  `Semantic.overdue` red** — today and upcoming are things the date already
  says, and reserving red is what makes it mean something (the refresh's
  colour discipline). Nothing else colours by due date any more: the opt-in
  "Color tasks by due date" row wash briefly outlived the refresh and was then
  removed (see the refresh bullet).
- **The daily reminder counts, and says nothing else.** Settings → Tasks can post
  one notification a day — "You have 3 tasks for today" — off by default, at a time
  the user picks from a **fixed list of half hours, 06:00 to 12:00**, 09:00 to begin
  with (`ReminderSchedule.slots`). The control is called **"Daily morning
  reminder"**, and the word is load-bearing: with it, a list that stops at midday
  reads as the point of the feature; without it, as a missing half of the clock. The
  footer says why in full, so the constraint is explained where it's met rather than
  only here. It counts the same bucket the menu bar labels **Today**:
  due today, still pending, with **overdue work deliberately left out**, so the
  sentence means exactly what it says. A day with nothing due sends nothing, and no
  notification ever names a task or a project — a banner is read on a lock screen
  and over a shoulder, and a count is the most that is always safe to show there.
  **It only arrives while Insert is running, and that is the design.** The
  alternative is a `UNCalendarNotificationTrigger`, which the system delivers
  whether the app is running or not — but a trigger's text is fixed when the request
  is added, and there is no way to keep a count fresh in one: a task due tomorrow
  becomes a task due today at midnight, with nothing happening in the app to
  re-schedule on. So the count is computed at the moment it is delivered, which
  means someone has to be there to compute it. Insert is a menu-bar app that stays
  open; overstating the day's work is worse than a reminder that needs the app
  running.
  Which is why the timer **ticks every minute and asks** whether the reminder is
  owed (`ReminderSchedule.isDue`), rather than being aimed at the reminder's exact
  minute: a timer aimed at 09:00 has to be re-aimed on wake from sleep, on a
  timezone change and on a clock change, where a comparison against `Date()` is
  right through all three by construction. Three details carry the behaviour, and
  all three are pinned by `ReminderScheduleTests`. There is a **two-hour grace
  window**, so a Mac woken at 09:40 still says what the day holds and one woken at
  16:00 doesn't, since by then the day is the thing being reminded about. The
  "already told you" stamp is a **date, not a flag**, compared with
  `isDate(_:inSameDayAs:)`, which is what keeps a relaunch at 09:05 quiet. And it is
  stamped **even when the day is clear** — otherwise dating a task for today at
  10:30 would earn an unprompted notification seconds later, from a feature the user
  thinks of as a morning thing.
  `ReminderSchedule.time(_:on:)` builds the day's moment from explicit components
  rather than `Calendar.date(bySettingHour:minute:second:of:)`, which resolves the
  *next* matching time and answers "tomorrow at 09:00" when asked in the afternoon —
  exactly the case that has to come back "not due".
  **The time is a list of `Int` minutes, and a `DatePicker` here is a trap.** The
  setting began as `DatePicker(…, displayedComponents: .hourAndMinute)`, and it
  **froze Settings → Tasks for seconds** on a real library while merely stuttering on
  a small one. What pinned it: turning the reminder off — which unmounts the picker
  and changes nothing else on the pane — made it instant again. A `sample` of the
  hung app names two costs, both on the AppKit control. SwiftUI re-applies
  `setLocale:`/`setCalendar:`/`setTimeZone:`/`setDatePickerElements:` to the
  `NSDatePickerCell` on **every graph update**, and each one invalidates the cell's
  subfields and formatter, so every update rebuilds an ICU `SimpleDateFormat` and its
  `DateFormatSymbols` (`_concoctUnholyAbominationOfADatePicker` →
  `CFDateFormatterCreateDateFormatFromTemplate` → `_regenerateFormatter`). And
  `GroupedFormRowLayout.Cache.updateAlignment()` asks the control for
  `_baselineOffsetsAtSize:` from **five separate measurement sites in one layout
  pass**. It is `DateCoding`'s lesson met from the other side: a throwaway formatter
  inside something that runs far more often than it looks like it does, except here
  AppKit is the one allocating it. `.environment(\.locale, Formatting.locale)` was on
  that picker to keep the app's English-only date rule, which made the mismatch worse
  and is *why* the list is the better answer rather than merely the faster one:
  literal digits (`ReminderSchedule.label`) are the same on a machine in any locale,
  so there is no date being formatted to get wrong. Anything else that wants a time
  of day in this app should reach for the same shape before a `DatePicker`.
  `nearestSlot(to:)` exists because the free picker allowed any minute of any hour,
  so an install can hold 07:13; a `Picker` whose selection matches no tag draws
  **blank**, and `SettingsStore.init` snaps the saved value onto the list. It is
  idempotent on a value already offered — it runs every launch, so a snap that
  drifted would walk the user's choice somewhere else. Pinned by
  `ReminderScheduleTests`.
  **Not verified: that a self-signed build can post at all.** `build.sh` signs with
  a self-signed certificate and falls back to ad-hoc, and notification authorization
  is one of the things macOS can decline on that basis. Nothing assumes it works — a
  refused authorization or a rejected `add` is logged and the app is otherwise
  unaffected — but if the reminder never appears, the signature is the first thing to
  rule out, ahead of the schedule.
- **Return continues a list — and a quote** — in any Markdown body (note card,
  task card),
  Return on `- `, `* `, `+ `, `1. `/`1) ` or `- [ ] ` opens the next item with the
  same marker and indent, incrementing ordered numbers and continuing a ticked
  `- [x]` as an unchecked `- [ ]`. Return on an item with **no content** ends the
  list instead of adding an empty one to it.
  A **block quote** does all of the same, read off a different marker: `> ` carries
  onto the next line, the whole run of `>`s comes with it so a nested quote stays
  nested, and an empty `> ` ends the quote. The space is *normalised in* — `>quoted`
  is a quote to the renderer, which strips the marker and trims, so the line being
  opened wants the space however the one above it was typed. The marker at the head
  of the line is the one that continues, so `> - item` continues as `> `, not as a
  bullet. (`LineMarker` is named for that: it is no longer only lists. The API is
  still `listReturn`/`continueList`.) The rest of the list is never
  renumbered — Markdown renders it right either way, and rewriting lines the
  caret isn't on is how an editor loses text. ⇧Return is the plain newline that
  leaves a list without ending it.
  The rules are a pure function (`MarkdownFormatting.listReturn`) over character
  offsets, testable without a view like the ⌘B/⌘I toggles beside it and pinned by
  `MarkdownFormattingTests`.
  Return is caught by a **local `NSEvent` monitor** (`MarkdownReturn`), not
  `onKeyPress` and not an invisible `keyboardShortcut` button: an unmodified
  Return carries no key equivalent, and the text view consumes it as
  `insertNewline(_:)` before SwiftUI's key-press handlers see it — the wall
  `ProjectHashField` documents for Tab and Return, hit again here.
  The monitor is **one, app-wide**, installed from `AppDelegate`, not one per
  editor, and it reads the **first responder** rather than `@FocusState` and the
  `TextSelection` binding. It was written the other way first, and the rewrite
  happened while chasing a "nothing happens" report that turned out to be Return
  pressed on lines that weren't list items — so **the first version was never
  shown to be broken**, and "those bindings can't be read from an `NSEvent`
  monitor" is a hypothesis that went untested. Don't repeat it as fact. What
  stands on its own is the shape: the text view holds the text and the caret, so
  nothing has to ask SwiftUI for state outside a view update, and there's nothing
  to gate on focus, because the first responder *is* the focused editor.
  And the edit is applied **through the text view**
  (`shouldChangeText` → `replaceCharacters` → `didChangeText`), not by assigning
  the `text` binding, which is what gives it native undo and lets SwiftUI pull
  the new string back the same way it does for typing.
  **Field editors are skipped**, which is the line between a multiline body and a
  single-line field where Return submits — the note title and the `#project`
  field keep their own behaviour. The event is swallowed *only* when `listReturn`
  returns an edit, so Return is ordinary everywhere else.
- **Cards read in one of four faces, Rounded by default** — Settings → General
  offers Standard / Rounded / Serif / Monospace (`Typeface.swift`, resolved by
  `Card` and nowhere else). All four are *system designs*, so nothing is bundled;
  the serif is **New York**, which ships with macOS at
  `/System/Library/Fonts/NewYork.ttf` but is a hidden system font reachable
  **only** through `withDesign(.serif)`. Asking for it by name is a trap worth
  knowing: `NSFont(name: ".NewYork-Regular")` is nil and the PostScript name hands
  back *Times New Roman* as a silent substitution, which CoreText logs. The
  "New York" families that show up in Font Book on a developer's Mac are Apple's
  optional download in `/Library/Fonts` and are absent on a clean install.
  `TypefaceTests` pins the resolution, including that the serif isn't a fallback.
  Two things come free with the serif: CoreText tracks its optical-size axis to the
  point size (`opsz` 12/15/20/34 at those sizes), and it has a real italic.
  `Card` reads the setting itself, inside a view update, so an `@Observable` read
  registers as a dependency and every card re-renders on a change — there is no
  notification and nothing to thread through the dozen call sites. The
  `typeface:`-taking overloads exist for `TypefacePicker`, whose specimens each
  draw in their own face; its swatch is **"Aa"**, which is not filler — the
  lowercase `a` shows the alternate the two SF designs carry.
  The **one-storey `a` belongs to both SF designs, Standard included.** Standard
  first shipped without it, on the grounds that its job is to match the chrome
  beside it and a stylistic alternate would break that — reversed by request in
  July 2026, because Apple Notes sets its plain SF body with the one-storey `a`
  and that look is what the option is for. So the cards under Standard differ
  from the chrome in exactly that glyph, a decision rather than a drift. The
  serif and the monospaced face don't list the selector, and asking anyway is a
  true no-op there (verified: identical glyph ids when shaped).
  **Italic needs synthesising, and only under Rounded** (`Card.italic(_:)`).
  Standard, Serif and Monospace each ship a real italic; **SF Rounded ships none**,
  and asking a rounded descriptor for `.italic` returns the *upright* face without
  erroring — so `*emphasis*` drew as plain text under the app's default face, which
  a quote's italic attribution is where you notice. A face with no italic is
  sheared through the **font matrix** instead, at the angle SF's own italic slants
  at (`italicAngle`, 12.5°), read off that face rather than picked. Two traps, both
  hit: the trait must be **added** to the font's existing traits, never set on its
  own (`withSymbolicTraits(.italic)` replaces the set, dropping a bold base's
  weight — and then the "is this a real italic?" name check believes the different
  name, which is how `***bold italic***` came out neither), and `MarkdownText` must
  **give up the emphasis intent** on any run it has fonted by hand, or SwiftUI
  re-resolves the emphasis on top through the very trait lookup that has no rounded
  italic to find, throwing the oblique away. `strikethrough` stays: it was never
  ours to draw. All of it is pinned by `TypefaceTests`.
- **The one-storey `a` costs two separate things, and it takes both** — this is the
  bit that was got wrong first. The **rounded design**
  (`NSFontDescriptor.withDesign(.rounded)`) softens the terminals but **keeps the
  two-storey `a`**; the round single-storey `a` is a *stylistic alternate*,
  `Alternative Stylistic Sets` → `One storey a`, applied through
  `.featureSettings` as type 35 / selector 14. Those numbers were read off the
  font's own table with `CTFontCopyFeatures`, which is also how to check them
  again rather than trusting this paragraph. Both are the system font, so nothing
  is bundled and the no-dependencies rule is untouched.
  Because the alternate can only be asked for through a descriptor, **the AppKit
  font is the real one** and the SwiftUI `Font` is `Font(nsFont)` derived from it
  — and **weight has to be baked in** (`Card.font(.title3, weight: .bold)`), never
  added afterwards with `.weight()`/`.fontWeight()`, which resolves to a
  different font and silently drops the alternate. Inline `**bold**` inside a
  `Text(AttributedString)` still works; that was checked with `ImageRenderer`
  rather than assumed.
  Scope is the **content** of a card — title and body, rendered and source,
  headings included. Chrome stays on the default design: panel headers, chips,
  pills, the due badge, the metadata footer. Fenced code stays monospaced.
  `Card` hands out **both** a SwiftUI `Font` and the matching `NSFont`, and both
  are needed: the `NSFont` is what `MarkdownText` measures `blankLine` from and
  what the cards' hidden sizing proxies lay out in, so taking the `Font` alone
  would leave every card's height computed in a face it no longer draws.
- **The preview and the source keep the same rhythm.** A card shows
  `MarkdownText` in view mode and the raw Markdown in edit mode, and the flip
  between them is the one moment the two are compared — so they are sized and
  spaced to match, and drift here shows up as the card changing shape under the
  cursor. Two things do it. `MarkdownText` takes a **`textStyle`** rather than
  hardcoding `.body`, because the note card's editor is `.body` and the task
  card's is `.callout`, and the task card was previewing a size it never edited
  at. And its **block spacing is one blank line**, measured off that same font
  (`blankLine`) instead of written down: two paragraphs are separated in the
  source by a blank line at full line height, so a flat 8pt made every paragraph
  break tighten on entering view mode. List items get **0** for the same reason
  read the other way — they sit on consecutive source lines with nothing between
  them, so the 4pt they used to add had lists loosening while paragraphs
  tightened.
  **A quote keeps its line breaks**, and gets 0 between its lines for the list's
  reason. Every `>` line used to be joined into one paragraph, which ran the shape
  quotes are actually written in — the quotation, then its attribution on the next
  line — into a single sentence. So `.quote` carries `[String]`, one entry per line.
  A `>` on its own is a paragraph break *inside* the quote and survives as an empty
  line, drawn as a space so it keeps the font's full line height, which is what the
  editor shows for the same source; empty lines at either **end** are trimmed,
  because they'd draw the bar past the text it marks.
- **Cards opening and closing** — a card's **height** animates
  (`Metrics.cardModeDuration`), and its **content does not**. Both matter, and
  each took a wrong turn first.
  Nothing animated at all until the cards stopped being written as
  `if isEditing { card } else { card.onTapGesture… }`. That is a
  `_ConditionalContent`: two branches, two identities, so entering edit mode was a
  teardown and a rebuild rather than a resize, and no `.animation` anywhere could
  have fired. Both cards are now one view with the gesture switched off by
  `.gesture(_:isEnabled:)` and the "Edit" accessibility action moved into an
  `.accessibilityActions { }` builder — keep it that way; re-introducing a
  conditional around either card silently kills the animation.
  The body text then **swaps in one frame**, which is what `.transition(.identity)`
  on both branches is for: SwiftUI's default is a cross-fade, and the two halves
  are the same paragraph with and without its `**` and `#`, so a cross-fade showed
  both at once, half-transparent, while the card was still resizing. Two ways of
  softening that were tried and both are worse. A sequenced fade (preview out,
  editor in) *alongside* the resize flashes. The same fade *after* the resize,
  holding the preview until the card has finished growing, stops being a
  transition and becomes a wait. The swap is legible because the card around it is
  moving; it needs nothing else.
  Typing inside a task's editor eases too, and that one needed the sizing proxy
  moved **out of the layout** into a `.background` on the body container: in the
  stack the proxy *was* the height, so the row jumped the instant text wrapped.
  In the background it doesn't size its host, so the height is one animatable
  number — and it keeps measuring in view mode, without which the first open of a
  long task grew twice, once to the floor and again when the real height arrived.
  Note cards still snap while typing; only the mode change is animated there.
  **Expanding a task's notes eases the same way**, at the same
  `Metrics.cardModeDuration`: it is the same kind of change — the row grows, the rows
  below travel — so it should not be a different gesture. Two things carry it, and
  both are this bullet's own lessons applied a second time. The `.animation` is
  **value-scoped** to `expanded`, alongside the one scoped to `isEditing`, so the two
  can't drive each other and a card opened while expanded resizes once rather than
  twice. And both branches of the expanded/collapsed conditional take
  `.transition(.identity)`, because they are the same first line with and without the
  rest of the body under it — a cross-fade showed those words twice at half opacity
  while the row was still resizing. The chevron itself turns over with
  `.contentTransition(.symbolEffect(.replace))`: one symbol in two directions is what
  `.replace` is for, and with Reduce Motion the whole thing drops to no animation, so
  the glyph cuts rather than turning.
- **Focus on entry is deferred by a turn, and has to be.** The click that opens a
  card is also the update that creates the editor, so `focusForEntry()` writing
  `@FocusState` straight from `onChange(of: isEditing)` named a field SwiftUI had
  not registered yet and was dropped in silence. The card opened with no caret and
  Esc did nothing either — the editor answered Esc through `onKeyPress` then, which
  needs focus to fire (it is `cancelOperation(_:)` on the editor's own text view
  now, which needs first-responder status just the same) — so it took a *second*
  click, which focused the text view the
  AppKit way, to make either work. Both cards now wrap the write in
  `Task { @MainActor in }`, which lands it after the editor exists and after the
  click's own responder handling, the other thing that can take focus straight
  back. Entry also places the caret at the **end of the body**, through the
  `selection` binding `MarkdownEditor` hands its owner; set it *only* alongside a
  programmatic focus, since writing it on every focus change stamps on the position
  a click inside the editor just chose. Not the character you clicked, and that is
  as close as this gets: view mode shows `MarkdownText`'s render, which strips
  `**`/`#`, draws bullets as circles and joins hard-wrapped lines into one
  paragraph, so a point in the preview has no source character to map to.
  Landing in the right *block* would mean `MarkdownParser` carrying source ranges.
- **Tab walks an open card's fields.** Tab or ⇧Tab moves focus between a card's
  title and body, both directions the same because two fields make a loop of
  two. Without it there is no key out of a body: the editor's text view answers
  Tab itself, as a literal tab character — the `ProjectHashField` wall again
  (the field editor and the text view both consume Tab before `onKeyPress`
  sees it), solved its way both times. The title side is a new `onTab` on
  `ProjectHashField`'s existing monitor, firing only with the dropdown closed —
  dropdown open, Tab still means "first match", which stays the override. The
  body side was a focus-gated monitor of the same shape inside `MarkdownEditor`
  and is now an `insertTab(_:)`/`insertBacktab(_:)` override on the editor's own
  text view (`onTab`, optional so an owner without a second field leaves Tab
  alone) — the same behaviour, answered where the key lands rather than
  intercepted before it. The
  focus writes are direct, *not* `focusForEntry()`'s deferred turn: that delay
  exists because entry creates the fields in the same update, and here both
  fields already exist when the key fires, so there is no registration to wait
  for.
- **Spelling is marked, never corrected — and the body editor is an
  `NSTextView` because of it.** Settings → General → "Check spelling while
  typing" (on by default) underlines misspellings in a card's **title and
  body**, notes and tasks alike; corrections come from the text view's own
  Control-click menu, where they're accepted deliberately. Grammar checking,
  automatic spelling correction, smart quotes, smart dashes, text replacement
  and link detection are all refused **by name**, because a bare `NSTextView`
  arrives with them *on* (measured) and these are Markdown files Obsidian also
  opens: a substitution made on the user's behalf is a write to someone's note,
  and `--` has no business becoming an en dash in a file.
  **SwiftUI's `TextEditor` cannot do this on macOS, and that is what cost the
  editor its `TextEditor`.** There is no spell-checking modifier in SwiftUI at
  all (`autocorrectionDisabled` is iOS's, a different thing), the state lives per
  `NSTextView` — and SwiftUI writes `isContinuousSpellCheckingEnabled = false`
  on every graph update. Instrumented here, on macOS 26: **45 reversions across
  44 keystrokes**, one per edit, 8–20ms after it, always the same text view
  object, so it is reconfigured rather than rebuilt. That's FB13607434
  (feedback-assistant/reports#467), still open; Apple's forums (thread 744800)
  report the same from the outside — enabling it from the Control-click menu
  "works briefly but becomes disabled again after typing a few characters".
  **Two workarounds were tried from outside the text view, and both are
  instructive dead ends.** Setting the flag once when focus lands gave marks
  that arrived "late, only when I stop typing, and not even always" — the
  reversion, seen from the user's side. Re-asserting it every update tick then
  made the underlines *flicker on every keystroke*, because turning checking off
  clears the marks and turning it on schedules a fresh check, so the flag being
  fought is a visible flash. A forced `checkText(in:)` over the whole note twice
  per typing pause was in that version too, and was worse than useless: it
  re-checked every word in the document to find the one that changed, and was
  measurably slow on a long note. **Neither is what AppKit wants** — its own
  machinery checks incrementally, around the edit and the visible range, and
  keeps the marks it has, which is the behaviour Notes has and the one to aim
  for.
  So the body editor hosts its **own** `NSTextView` (`MarkdownEditor` →
  `MarkdownTextViewBridge`, `MarkdownTextView`): the flag is set once in
  `makeNSView` and nothing takes it away. What that cost, and what it bought
  back, is under "The editor is ours" below.
  **The titles are why `SpellChecking` still exists.** A title is a `TextField`
  (`ProjectHashField`) with no text view of its own: it borrows the window's one
  shared **field editor**, and so do the toolbar's search field and Settings'
  text fields. What that editor is given follows it to the next field, so it's
  told on every focus change what the field it is *currently* attached to wants —
  read from the **first responder** in `applicationDidUpdate`, since focus moves
  between a card's two fields and from card to card with no notification to hang
  it on. Hence two exclusions: the **search field** (a query, not prose, and it
  names itself by being an `NSSearchField`) and the **Settings window**
  (`SettingsWindowController.owns(_:)` — a note type's name is an ordinary
  `NSTextField` exactly as a card's title is, so the window is the only thing
  that separates them). A field that can't be identified counts as excluded, so
  nothing inherits underlines from whatever was edited before it. The same pass
  is also what lands a flipped Settings toggle on an already-open body.
- **The editor is ours** — `MarkdownEditor` wraps an `NSViewRepresentable`
  (`MarkdownTextViewBridge`) over an `NSTextView` subclass, for the reason in the
  bullet above. The API the cards call is unchanged apart from two things: the
  font is now the `NSFont` (`Card.nsFont(_:)`, the same face the proxies measure
  through `Card.font(_:)`), and Esc is an `onEscape:` hook rather than an
  `.onKeyPress(.escape)` at the call site, because a hosted text view answers keys
  before SwiftUI's handlers see them.
  What must not drift, since the cards' geometry rules depend on it: the text
  container's `lineFragmentPadding` stays at its default **5pt** and
  `textContainerInset` at **zero**, which is exactly the inset SwiftUI's editor
  had — the call sites' hidden sizing proxies carry `.padding(.horizontal, 5)`
  and their placeholders sit at `(5, 0)` "on the caret", and the preview/source
  flip is compared on one frame.
  The keys the text view now answers itself: **Tab / ⇧Tab** are
  `insertTab(_:)` / `insertBacktab(_:)` overrides (the local `NSEvent` monitor
  inside `MarkdownEditor` is gone — same behaviour, answered where the key
  actually lands), and **Esc** is `cancelOperation(_:)` *plus* `complete(_:)`,
  because a text view binds Esc to inline completion by default and that would
  otherwise swallow it. **Return is not here**: `MarkdownReturn`'s app-wide
  monitor reads the first responder, so it works unchanged — and `isFieldEditor`
  still separates a body from a title.
  Three details in the bridge that are easy to undo by accident. Text is written
  into the view **only when it really differs**, because typing round-trips
  through the binding and comes back equal — assigning then would throw away the
  caret and the undo stack on every keystroke. Focus is reported *out* of the view
  by overriding `becomeFirstResponder`/`resignFirstResponder`, so a click inside
  the editor still counts as focus for the owner's `@FocusState`; the callback is
  suppressed (`reportsFocus`) around a `makeFirstResponder` the bridge asks for
  itself, since that one happens inside a view update. And `allowsUndo` plus
  `isRichText = false` are what keep native undo and stop a paste arriving as
  styled text.
- **Chips are one height** — `Metrics.chipHeight` (24pt), applied as a *floor* by
  `chipHeight()` rather than by equalising paddings, because a chip's 8pt of
  horizontal padding is right where a pill's 11pt is right. There were three
  heights before: a caption line is 13pt, so 5pt of padding gave 23 and 3pt gave
  19, and a pill whose SF Symbol is a two-person glyph (Meeting, Staffing)
  measures 14pt rather than 13 and came out 24 beside a text-only "All" at 23. 24
  is that tallest case, pinned, so a chip's height no longer depends on which
  glyph it carries. The compact "add project" ＋ is the exception in shape only:
  square at `chipHeight`, so it's a **circle**, since with the text gone a capsule
  was a circle with slack at the sides.
- **Align on the baseline, not the box** (`centredOnTextCap()`). A glyph padded
  out to a comfortable click target centres the *box*: a 17pt circle in a 28pt
  target sits 14pt from the row's top while a 13pt title's capitals start 4.6pt
  from theirs, which had the task row's checkbox 7.5pt below the title it belongs
  to. Text isn't centred on its own frame either — the frame carries a descender
  the title may not use. So the row aligns `.firstTextBaseline` and each control
  declares where its own centre sits relative to that baseline, off the font's cap
  height. The guide reads the *measured* height, so a control that brings its own
  chrome (a borderless `Menu`) needs no allowance made for it.
  The task row's **expand chevron wears the ⋯ menu's box**, measured off it rather
  than written down (`actionsSize`), and both dimensions earn their place. The
  *width* is what puts the two on one vertical axis: they are flush to the same
  trailing edge, so equal widths is all it takes, and the chevron's 28pt against a
  borderless `Menu`'s own 20pt had it sitting 4pt to the menu's left. The *height*
  is the subtler half — a 28pt box centred on a 15pt line sticks out above it, and
  because the row is baseline-aligned that raised the row's top and pushed the
  preview text **below** the editor's first line, trading one misalignment for its
  mirror image. At the menu's 14pt the box sits inside the line box and pushes
  nothing.
  **A card's title row is floored at `Metrics.cardTitleRowHeight`** (26pt) in *both*
  modes, because **Done** exists in only one of them. The capsule is 26pt at
  `.actionCapsule`/`.controlSize(.small)` against a 16pt title line, and the row is
  baseline-aligned, so the extra 10pt landed 5pt above the title and 5pt below: a
  task card opening slid its title down 5pt and its body down 10pt, out from under
  the cursor that had just clicked it. Measured, both before and after — the
  title-to-body gap is now 29pt collapsed against 30pt open, and the 1pt left over
  is `ProjectHashField` sitting a point above centre where a `Text` is centred
  exactly. The note card dodged the fault for as long as its 26pt symbol well set
  that height as a side effect; when the type symbols were removed the note card
  gained the same explicit floor. The cost is 10pt on every collapsed task row,
  which is the deliberate trade — the alternative is taking Done out of the
  row's height and letting a 26pt capsule overhang a 16pt row.
  That floor is also why the body carries a **bottom padding of `titleRowSlack`**.
  A row floored taller than its text keeps the difference as slack at both ends, so
  the body's gap *upward* is that slack plus the stack's 8pt spacing while its gap
  *downward* was the spacing alone — 13pt above against 8pt below, which reads as
  the chips crowding the text. Repeating the slack underneath makes the two one
  margin; measured at 13.00 above and 13.34 below. It's derived from the two numbers
  that create it rather than written down, because one of them moves: the title's
  line height comes off the **card face**, so a serif or monospaced card measures
  differently from a rounded one.
  A `•` is the same kind of trap: the glyph is **2.6pt** across at body size, and
  the font is no lever on it (still under 4pt at 20pt, by which point the taller
  line has loosened the list). `MarkdownText` draws a 5pt `Circle` instead and
  declares the baseline guide itself, because a shape has none.
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
  `ink` is a foreground for glyphs on the app's own surfaces, `accent` is
  decorative, and `marker` (added by the refresh) is the note title's
  highlighter band, derived by blending `accent` into the card face — 45% over
  white in Light, a quieter 34% in Dark; the mock's 60% crowded the title under
  saturated tints and was softened by request — so a custom type's marker falls
  out of its tint automatically. `deep` and `ink` are separate because they invert
  relative to each other in Dark Mode — don't collapse them back into one
  "deep". Both adapt to Light/Dark and Increase Contrast through one dynamic
  `NSColor`, so call sites stay plain `Color`. **Within the tint family,
  selection is a filled pill, never an outline**: `deep` and `chip` share a
  hue, so a border drawn from one against the other can't reach the 3:1 an
  indicator needs in both appearances at any opacity. The refresh's pickers do
  use outline rings, and that isn't the same case — the `AccentColor` ring sits
  on *neutral* ground (a Form row, `Stone.chip`), where it can carry it.
  The refresh added two more solved colours with one job each:
  `Semantic.overdue` (the only red, ≥4.5:1 on the card faces both modes) and
  `Stone.metaText` (timestamps, chip names, the resting due badge — a solid
  grey at ~7:1, because `.secondary`/`.tertiary` are alpha washes that land
  under the refresh's 4.5:1 floor for sub-14px text). `AccentColor` is the
  user's highlight colour: four options, each ≥4.5:1 under white and past 7:1
  with Increase Contrast, threaded app-wide with `.tint()` from `InsertApp` and
  read directly (inside view bodies, so the `@Observable` access registers) by
  `AccentButtonStyle` and the pickers' rings. Project and type colour never
  appears on a card except as a **dot** or the marker; metadata is grey; red
  means overdue and nothing else.
- **Appearance** — Settings → General has a Theme picker: Auto / Light / Dark,
  the same control prtscn has (`Appearance.swift` is a copy of its enum). Auto
  means `NSApp.appearance = nil` — follow the system — and is the default, so an
  install that never touches it behaves as before. This override was removed once
  on HIG grounds (a per-app appearance makes people adjust two places to get one
  result) and put back deliberately in July 2026; if you're weighing removing it
  again, that's the argument, and it has already been overruled.
  `applyAppearance()` runs from `applicationWillFinishLaunching`, before the first
  window, so a non-Auto choice isn't a flash of the system appearance on launch.
  Every colour in `Tint`/`Stone` resolves through a dynamic `NSColor`, so setting
  `NSApp.appearance` is all it takes — nothing reads `Locale`-style globals or
  caches a resolved shade.
- **Backdrop** — Settings → General offers seven flat tints for the main window —
  Linen, Clay, Blush, Sage, Seafoam, Mist, Lilac — plus "Plain", which stays the
  default. (Seafoam came after the handoff's six, filling the wheel's one empty
  family — cyan, the widest gap in the set — by the "not reachable from an
  existing one" rule.)
  These replaced the five gradient washes in the July 2026 refresh; a saved
  gradient migrates to its nearest tint by family (`migratedFromGradient`:
  cloud→mist, stone→linen, dawn→blush, dusk→clay, grove→sage), persisted once
  from `SettingsStore.init`. The gradients' own selection lessons (a member
  earns its place by not being reachable from an existing one, and by being
  quiet enough to sit behind text all day) still govern any new tint, and the
  spec makes them mechanical: **one lightness and chroma per role, hue the only
  variable** (light oklch L 97.5 / C 0.014–0.016; dark derived at L 23.5–27),
  so switching tint never changes contrast and a new entry is a hue, not a
  design. Sage and Mist are kept at the set's low chroma so green and blue read
  as scenery, not as the status colours those hues mean elsewhere.
  A tint paints **two strengths**: the window base at ~30% of the identity
  chroma and the sidebar at ~60–70%, where it actually reads; the Settings
  swatch shows the full identity value, because a 52pt swatch of the base
  colour previews nothing. The picker is a `LazyVGrid` of four columns — seven
  entries at 52pt is exactly past where the old single row stopped fitting —
  and not smaller swatches, since below about 46pt a swatch stops previewing.
  A backdrop is **one** tint, not two: hue fixed per name, only the value
  changing between Light and Dark through the same dynamic `NSColor` trick
  `Tint` uses, so the choice follows the Theme picker with nothing to re-apply,
  and both halves clear AAA against the text on them — no Increase Contrast
  variants needed. Two things here are easy to get wrong: the window style is
  applied **unconditionally** (`Plain` resolves to `.windowBackground`),
  because branching on it in the view builder gives the two cases different
  identities and tears down `NavigationSplitView` — and with it the autosaved
  column widths — on every change of the picker. And the sidebar's tint layer
  needs its **own** `.ignoresSafeArea()` — the sidebar's content ignores the
  top safe area so the header can sit level with the traffic lights, but a
  background layer doesn't inherit that, so it started below the toolbar inset
  and left the titlebar band one layer short: a hard seam under the traffic
  lights, reading as two stacked panels. The `if` around that layer sits
  *inside* the `.background { }` builder for the identity reason above. The
  sidebar's fill is a **flat colour now, not Liquid Glass**: the glass earned
  its place by refracting a gradient's travel, and a flat tint has none — with
  "Plain" the layer drops out and AppKit's own sidebar material (and its
  desktop translucency) is untouched.

  `.island()` is **plain paper, full stop** — `textBackgroundColor`, white in
  Light and near-black in Dark, opaque and neutral on every card; colour is
  the backdrop's job. Its `tint:` parameter (a translucent wash over an opaque
  base, the layering the gradients forced) left with the last thing using it,
  the "Color tasks by due date" wash — see the refresh bullet. `Stone.surface`
  survives only on the column divider's handle and the `SegmentedFilter`
  track.
- **Language** — the app is **English only**, and that includes dates. Every UI
  string is an English literal, so formatting dates in the *system* locale gave
  interfaces in two languages at once: a Spanish Mac showed a due badge reading
  "Last vie" and stamped an English note "25 jul 2026". Anything user-facing
  formats through `Formatting.locale` (`en_GB` — English names, but day-first
  dates and Monday-first weeks). Never format a user-facing date off
  `Locale.current`. The on-disk format is separate and pinned to `en_US_POSIX`
  in `DateCoding`, so none of this can rewrite a Markdown file.
- **Glass** — Liquid Glass is for the *control* and *navigation* layers. Cards,
  rows and pills in the
  content layer use `.island()` and the flat `Stone`/`Tint` washes instead (glass
  islands also pooled their shadows — see `Theme.swift`). Two things outside plain
  controls take it: a transient floating control, the `#project` autocomplete
  dropdown — the exception HIG allows — and the **`SegmentedFilter` indicator**,
  the refresh's one new glass surface: the moving selection pill refracts the
  track and the tint under it and travels on the platform spring, with Reduce
  Transparency swapping in an opaque paper pill and Reduce Motion cutting the
  travel. (The projects sidebar *was* the third — glass over the gradient — and
  gave it up with the gradients; a flat tint has nothing to refract.) Those plus
  the toolbar's search field are the window's glass surfaces, and they're meant
  to read as the same material; don't give one of them a `Material` and call it
  close enough.
  **Primary buttons are accent pills again** (`AccentButtonStyle`), and that is
  a deliberate reversal with its history attached: "New Note" / "New Task" once
  wore `.glassProminent`, gave it up because the *system* accent belonged to
  nothing in the design and fought the gradients, then wore the flat neutral
  capsule with a semibold label. The refresh re-arms the colour by making it
  the design's own — an `AccentColor` preference, one filled pill per column —
  while keeping both standing objections honoured: it's flat (glass casts a
  drop shadow; see "No shadows"), and one prominent control per surface is
  still the ration. `.glassProminent` survives only on each popover's confirm
  button, which `.tint()` now paints in the chosen accent rather than system
  blue.
- **No shadows, anywhere.** Not a gap: the window is deliberately flat, the look it
  wears when it goes inactive and every glass surface settles down, which is the
  look it's tuned for. Separation is a **hairline** (`Stone.line`) plus, on glass,
  the material's own refraction — that's what `.island()` swapped its shadow for and
  what the `#project` dropdown and the column-divider handle now use too. There is
  no elevation scale to add a level to, and adding one lifted element would make it
  the only thing in the window casting light.
  Which is also why the window's **buttons are no longer glass**: Liquid Glass draws
  its own drop shadow and there's no API to turn it off. The cards' "Done" and
  the toolbar's show-sidebar glyph wear `FlatButtonStyle` — `Stone.chip` fill
  and `Stone.line` hairline, with hover as a `.primary` wash and a press as a
  deeper one; "New Note" / "New Task" wear the same construction with the
  accent under it (`AccentButtonStyle`, hover a black wash since the label is
  white). That wash *is* the hover state plain
  `.glass` never gave them, which had the primary action of each column reading as
  decoration. One flat style, two shapes, and the `Sizing` is why: `.actionCapsule`
  pads its label off `.controlSize`, `.toolbarGlyph` pins a square 28pt, because a
  padded lone glyph comes out an oval rather than the circle the toolbar rounds one
  to.
  The toolbar's **search field stays the system's** (`.searchable(placement:
  .toolbar)`) — a hand-built field costs ⌘F, Escape-to-clear and the search item's
  collapse behaviour — so its glass is dealt with in AppKit instead, by
  `AppDelegate.flattenToolbarGlass()`, the one place in the app that reaches past the
  public API. What's worth knowing:
  its shadow is **not a `CALayer` shadow**. Dumping the whole titlebar's view *and*
  layer tree found no `shadowOpacity` anywhere in it — the only shadowed layers in
  the app belong to the menu-bar extra — so it's painted inside the glass renderer,
  `NSGlassEffectView` (public in macOS 26) offers only `cornerRadius`, `tintColor`
  and `style`, and an earlier pass that zeroed every layer shadow in the titlebar did
  exactly nothing. What makes it tractable is that the glass is a **platter behind
  the field, not the field's background**: `NSToolbarPlatterView` holds the
  `NSGlassEffectView` while the field lives in its own `NSSearchToolbarItemView`. So
  the platter is hidden and a `FlatToolbarCapsule` — a plain `NSView` drawing the
  same chip-and-hairline capsule — goes in its place, as a **sibling**, because a
  hidden view doesn't draw its children either. It runs from `applicationDidUpdate`,
  since AppKit rebuilds the platter as the field expands and takes focus; it assumes
  no depth, so a reshuffled hierarchy degrades to "the glass is back" rather than
  breaking; and it **skips the content view**, which is load-bearing — the projects
  sidebar is glass and is meant to stay glass. Only the titlebar band is touched.
  Otherwise anything the *system* draws — popover and menu shadows, the glass
  controls' own lighting — is untouched; `.shadow(…)` appears nowhere in Insert's
  own code.
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
