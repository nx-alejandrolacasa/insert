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
  BuildVariant.swift          dev vs release build, and what differs
  MarkdownText.swift          compact Markdown renderer for bodies
  Theme.swift                 Tint palette (roles + contrast), tokens, .island()
  Appearance.swift            Auto / Light / Dark preference
  Backdrop.swift              the five window gradients + their Settings picker
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

Two more suites cover the pure functions the UI is built on, for the reason given
under "Return continues a list": the interesting logic there is arithmetic over
offsets or dates, and arithmetic can be tested without a view.
`MarkdownFormattingTests` pins the ⌘B/⌘I wrapping and the list-continuation rules;
`ReminderScheduleTests` pins when the daily reminder is owed — the minute either
side of the time itself, the grace window, and the once-a-day rule — since the
alternative is waiting until tomorrow morning to find out.

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
  A note's **type** is a pill-shaped dropdown in that type's colour, sitting at
  the trailing end of the chips row while editing. It replaced a row of one
  `FilterPill` per type, whose selected state is where the `deep`-and-white comes
  from: the control shows exactly one type and it is always the current one. The
  row cost a line of every open card and grew with every type added in Settings,
  which is space the note being written should have. A `Menu` styled by hand
  rather than a `Picker`, because a `Picker` redraws the label in system chrome
  and the colour is the point.
- **Tasks** — a new task inherits the selected project, or stays unassigned. A
  task can be assigned to several projects. Typing `#` opens a project
  autocomplete; Tab picks the first match; the `#word` is *not* kept in the
  task text, it only adds the assignment. Assignments appear as chips below and
  are removed by double-clicking them (or via the chip's context menu — the
  double-click is deliberately hard to trigger, so it can't be the only route).
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
- **The daily reminder counts, and says nothing else.** Settings → Tasks can post
  one notification a day — "You have 3 tasks for today" — off by default, at a time
  the user picks (09:00 to begin with, and the picker allows any hour rather than
  policing "morning"). It counts the same bucket the menu bar labels **Today**:
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
  **Not verified: that a self-signed build can post at all.** `build.sh` signs with
  a self-signed certificate and falls back to ad-hoc, and notification authorization
  is one of the things macOS can decline on that basis. Nothing assumes it works — a
  refused authorization or a rejected `add` is logged and the app is otherwise
  unaffected — but if the reminder never appears, the signature is the first thing to
  rule out, ahead of the schedule.
- **Return continues a list** — in any Markdown body (note card, task card),
  Return on `- `, `* `, `+ `, `1. `/`1) ` or `- [ ] ` opens the next item with the
  same marker and indent, incrementing ordered numbers and continuing a ticked
  `- [x]` as an unchecked `- [ ]`. Return on an item with **no content** ends the
  list instead of adding an empty one to it. The rest of the list is never
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
- **Cards read in SF Pro Rounded with the one-storey `a`** (`Card` in
  `Theme.swift`). Two separate things, and it takes both — this is the bit that
  was got wrong first. The **rounded design**
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
- **Focus on entry is deferred by a turn, and has to be.** The click that opens a
  card is also the update that creates the editor, so `focusForEntry()` writing
  `@FocusState` straight from `onChange(of: isEditing)` named a field SwiftUI had
  not registered yet and was dropped in silence. The card opened with no caret and
  Esc did nothing either — the editor answers Esc through `onKeyPress`, which needs
  focus to fire — so it took a *second* click, which focused the text view the
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
  `ink` is a foreground for glyphs on the app's own surfaces, and `accent` is
  decorative. `deep` and `ink` are separate because they invert relative to each
  other in Dark Mode — don't collapse them back into one "deep". Both adapt to
  Light/Dark and Increase Contrast through one dynamic `NSColor`, so call sites
  stay plain `Color`. **Selection is a filled pill, never an outline**: `deep` and
  `chip` share a hue, so a border drawn from one against the other can't reach
  the 3:1 an indicator needs in both appearances at any opacity.
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
- **Backdrop** — Settings → General also offers five gradient washes for the main
  window — Cloud, Stone, Dawn, Dusk, Grove, quietest first —
  plus "None", which stays the default.
  Dawn and Dusk come from the icon's warm family and Grove is their
  cool counterpart — the only cool one left — kept low in saturation so its green
  and blue read as scenery rather than as the status colours those hues carry
  everywhere else in the app, and running sky *into* sage.
  Dawn and Dusk were toned well down from the icon's values — they were the two
  most saturated members and sat oddly beside the near-white borrowed ones. Every
  stop kept its hue and its lead channel and lost only chroma, with the pale ends
  holding more colour than the middle, because that's where each name lives
  (Dawn's lilac, Dusk's coral). Those two also **share a stop** — Dawn's last and
  Dusk's first are near-identical pale apricots — and get away with it only
  because they *chain* rather than mirror, so each reads as the colour at its own
  far end. Toning them down narrowed that margin; narrowing it again is how
  they'd collapse into one gradient.
  Cloud and Stone are borrowed from a CSS gradient gallery
  with their hex values intact; only their Dark halves are inferred. Stone is
  the one **radial** — hence `Ramp` carrying a shape alongside its stops — and its
  source is two stacked radials blended with `screen`, resolved here to two plain
  stops rather than reproduced: screening with black is the identity, so the outer
  stop is just the base colour, and screening with white at half alpha lands
  halfway to white. Its **outer stop is deepened past the source** on purpose: the
  CSS's own two stops are 1% apart and even with the bloom screened over them the
  result was a ~12% swing in luminance, which reads as a flat colour in the window
  and as nothing at all in a 52pt swatch. It's now ~19%. If a borrowed gradient's
  stops are that close together, copying them exactly is the wrong kind of
  faithful. That edge was first taken to ~30%, which overshot the other way — a
  near-white centre falling to a visibly sandy rim reads as a vignette, not as a
  lit off-white — so the two numbers bracket it: 12% is invisible, 30% is a frame,
  and a near-white radial wants the ~20% in between. Note Stone also *inherited* its name from a cut linear
  near-white-into-sand, so a saved `"stone"` from before now selects the radial.
  **Seven** others were tried and cut, and between them they are the brief for a
  sixth: a Honey and a Dune too close to Dawn's pale warm end, an Orchid that
  ended on the very lilac Dawn begins with, a linear near-white-into-sand that
  gave its name to Stone, a Neon (magenta → violet → cyan) simply too loud to look
  at all day, a Rare Wind (pink → aqua), and a Soft grass too bright at its deep
  end. Two rules come out of that: a gradient earns its place by **not being
  reachable from an existing one** — sharing a hue family is fine, sharing a *stop*
  makes two entries read as one mirrored — and by being **quiet enough to sit
  behind text all day**, because the one that wins the swatch row is usually the
  one you switch off within the hour. Five of the seven cuts were for one of those.
  What's left has one pair near the first line, ordered as neighbours so it reads
  as deliberate rather than duplicated: Cloud/Stone, both near-white, one cool and
  flat and one warm and lit, surviving on temperature alone.
  The picker is a **single row**: six entries at 52pt plus 10pt gaps is 362pt
  against the Settings pane's ~420. **Seven is where that stops fitting** (424pt),
  and the answer then is a `LazyVGrid` of four columns — not smaller swatches,
  since below about 46pt a gradient preview stops previewing anything, which
  defeats the point of not using a `Picker`.
  A backdrop is **one** gradient, not two:
  the hues are fixed per name and only their *value* changes between Light and
  Dark, resolved through the same dynamic `NSColor` trick `Tint` uses, so the
  choice follows the Theme picker with nothing to re-apply. Both halves of every
  pair clear 13:1 against the text drawn on them, which is why — unlike `Tint` —
  there are no Increase Contrast variants. Two things here are easy to get wrong:
  the window style is applied **unconditionally** (`None` resolves to
  `.windowBackground`), because branching on it in the view builder gives the two
  cases different identities and tears down `NavigationSplitView` — and with it
  the autosaved column widths — on every change of the picker. And the sidebar
  takes **Liquid Glass** over the backdrop, not AppKit's sidebar material, which
  blends *behind the window*: it frosts the desktop and is blind to anything
  Insert draws, so the gradient simply wouldn't be there. Glass rather than a
  `Material` — a `.thinMaterial` was the first attempt and it reads as a flat grey
  panel laid over the design, because a material only blurs and dims. Glass also
  refracts and picks up the backdrop's light, and it matches the toolbar's search
  field, the window's other large glass surface. With "None" the whole layer drops
  out, leaving the AppKit material and its desktop translucency exactly as they
  were. Two things about how that layer is attached, both of which bit. The `if`
  sits *inside* a `.background { }` builder, not around the
  column: branching around the `List` would give it a new identity on every change
  of the setting and tear down the autosaved split widths, the same trap
  `windowStyle` documents. And the glass layer needs its **own**
  `.ignoresSafeArea()` — the sidebar's content ignores the top safe area so the
  header can sit level with the traffic lights, but a background layer doesn't
  inherit that, so it started below the toolbar inset and left the titlebar band
  one glass layer short. That showed up as a hard seam under the traffic lights,
  reading as two stacked panels instead of one column.

  `.island()` changed with it, and only for tinted cards: those gained an
  **opaque base fill** under the wash, because `tint.soft` is translucent by
  design and over a gradient a note card stopped being a card — the wash ran
  through it and took the text with it. The base is `windowBackgroundColor`,
  exactly what sits behind an island with no backdrop, so that case stays
  pixel-identical. An **untinted** card is plain paper — `textBackgroundColor`,
  white in Light and near-black in Dark. That's the task row, and it is
  deliberately neither of the two things it has been before: not the warm `Stone`
  neutral (a column of faintly grey slabs) and not transparent (the gradient ran
  under the text). Opaque and neutral; colour is the backdrop's job. So
  `Stone.surface` is no longer an island fill — it survives only on the note
  composer's symbol well and the column divider's handle. Task rows are the
  untinted case (`dueTint` is nil for
  undated and done rows, and for every row with "Color tasks by due date" off).
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
  dropdown — the exception HIG allows — and, once a **Backdrop** is chosen, the
  projects sidebar, which is a navigation container and the one surface that has to
  refract the gradient rather than dim it. Those plus the toolbar's search field
  are the window's large glass surfaces, and they're meant to read as the same
  material; don't give one of them a `Material` and call it close enough.
  `.glassProminent` paints the **system accent** behind a
  label, so it's rationed to one per surface, and now survives only on the confirm
  button of each popover. "New Note" and "New Task" gave it up: system blue is the
  one colour in the window drawn from neither `Tint` nor a `Backdrop`, so against a
  pale wash it was the loudest thing on screen and it fought whatever gradient sat
  behind it. Their **semibold label** is what marks them as the primary action now —
  a colour isn't needed for that, and adding a second prominent button to any one
  surface is still the thing to avoid. They then gave up plain `.glass` as well, over
  its drop shadow — see "No shadows" below — so the two are the one *control*-layer
  place that draws a flat fill, and `.glassProminent` on a popover's confirm button
  is the only prominent left.
- **No shadows, anywhere.** Not a gap: the window is deliberately flat, the look it
  wears when it goes inactive and every glass surface settles down, which is the
  look it's tuned for. Separation is a **hairline** (`Stone.line`) plus, on glass,
  the material's own refraction — that's what `.island()` swapped its shadow for and
  what the `#project` dropdown and the column-divider handle now use too. There is
  no elevation scale to add a level to, and adding one lifted element would make it
  the only thing in the window casting light.
  Which is also why the window's **buttons are no longer glass**: Liquid Glass draws
  its own drop shadow and there's no API to turn it off. "New Note", "New Task" and
  the toolbar's show-sidebar glyph wear `FlatButtonStyle` instead — the same
  `Stone.chip` fill and `Stone.line` hairline as the filter pills, with hover as a
  `.primary` wash and a press as a deeper one. That wash *is* the hover state plain
  `.glass` never gave them, which had the primary action of each column reading as
  decoration. One style, two shapes, and the `Sizing` is why: `.actionCapsule` pads
  its label off `.controlSize`, `.toolbarGlyph` pins a square 28pt, because a padded
  lone glyph comes out an oval rather than the circle the toolbar rounds one to.
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
