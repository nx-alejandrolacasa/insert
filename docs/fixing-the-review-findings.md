# Fixing the 48 review findings

## Context

A ten-angle code review of the whole codebase (prompted by "it's been buggy
lately") produced **48 findings, 37 CONFIRMED**, each verified against the
source. The review found three clusters that plausibly explain the reported
bugginess, and they are the reason for the phase order below:

- **Silent data loss.** The retention purge trashes tasks ticked off in
  Obsidian; `deduped` trashes a duplicate on an `updated` tie; a checkbox click
  on a line indented with a non-ASCII space rewrites the wrong character.
- **Typed text reverting.** Both card views re-seed their draft from the
  library mid-typing, and the task card does it whenever *any* field
  differs — so ticking a task from the menu bar while typing in it reverts the
  notes *and* saves the reverted text.
- **IME breakage.** `MarkdownEdits.apply` — the single write path every key and
  bar button funnels through — has no `hasMarkedText()` guard, so Return, Tab
  and ⌘B/I/K rewrite the storage while a composition owns it. This is the same
  state that produced the 0.17.1 `String index is out of bounds` trap, and it
  bites on every accented character on a Spanish layout.

Intended outcome: all 48 addressed, in four reviewable phases, each landing with
a clean `swift build` + `swift test` and its own CLAUDE.md updates.

## Status — 2026-09-03: complete

**All 48 findings are addressed.** `swift build`, `swift test` (375 tests, 1
skipped — the pasteboard write, which the agent sandbox refuses) and `./build.sh`
are green, and the app assembles and signs with the font-bundle check passing.

Delivery differed from the four-phase plan below, and the reason is worth
recording: every phase after the first touches files an earlier one holds, so
the work was dispatched as agents partitioned by **file ownership** rather than
by phase. Ten ran in parallel to begin with; a session limit cut six of them off
mid-task, and the rest were run one at a time, each verifying its own build and
tests. So there is no per-phase commit boundary — the ledger is by fix.

### Landed and verified, by phase

- **Phase 1 (7)** — retention requires a real `completed` stamp and the load
  stamps an externally-ticked task; `deduped` keeps both files on an `updated`
  tie and trashes only an encode-equal true duplicate; `toggleCheckbox` uses one
  whitespace predicate; `Frontmatter.quote` escapes `\n`/`\r`; id-less files
  get a deterministic id from the filename; `UpdateChecker.install` uses
  `replaceItemAt`; both panels drive one `CardEditingSession` whose reseed skips
  while editing and merges field-wise.
- **Phase 2 (5)** — the `hasMarkedText()` guard is on `MarkdownEdits.apply`, the
  single write path; `cancelOperation`/`complete`/⌘Return are guarded; the
  `updateNSView` guard is hoisted above `view.font`, `applyTabStops` and
  `highlightConfig`; `MarkdownResponder.markdownBody(in:)` replaces the four
  first-responder spellings; `settleClick` no longer flips the last checkbox on
  a click below the body.
- **Phase 3 (8)** — `font(for:)` memoised; `find` compares UTF-16 in place with
  its literals hoisted; `FormattingBarPanel.hide` early-returns; search is
  case- **and diacritic**-insensitive with no per-keystroke lowercasing;
  `counts(forProject:)` answers from a one-pass cache invalidated by `didSet` on
  `notes`/`tasks`; `reloadAll` is `async` and drains off the main actor;
  `publishGeometry` compares the pending value; the `columnVisibility` setter
  guards on change.
- **Phase 4a (10)** — `MarkdownText.codeFont(scale:)`, with a `fenced` flag
  separating a block from inline code; `MarkdownText.headingGap(level)` shared by
  the editor, its sizing segments and both renderers; `Mono` honours the
  requested size and takes the card's scale on-card only;
  `CardTextMetrics.current(for:)` at all four sites; ⋯ → Copy passes
  `scale:`/`lineHeight:`; `MarkdownText`'s constants are `nonisolated static`
  and `MarkdownRichText` reads them; one `paragraphStyle(base:lineHeight:)`
  factory for both base styles; `applyTabStops` owns its staleness check;
  `italicised` routes through `MarkdownHighlight.font(for:)`.
- **Phase 4b (9)** — `lineMarker` accepts a checkbox that ends the line; the due
  popover separates `selectedDay` from the month it opens on (which needed one
  additive change to `MonthCalendar`, since no single `Date` can express "this
  month, nothing chosen"); the preset highlight reads `clock.today`; `gap(at:)`
  requires a current frame and `rowFrames` is pruned; link schemes are filtered
  on render and click with a `clickedOnLink` delegate; `sizeThatFits` answers a
  zero-width proposal with the ideal width's height; `flattenToolbarGlass`
  excludes Settings and the three window passes share one identity helper;
  `export` allowlists the portable attributes; the variable weight axis is a
  property of the family.
- **Phase 4c (5)** — `onToggleCheckbox` and its `Button` fork deleted;
  `height(forWidth:)` deleted; `ValueStepper` computes its own enablement; one
  line splitter (`MarkdownText.lines(of:)`) serves the parser, `toggleCheckbox`
  and the highlighter's two walks; `UpdateChecker.swift` added to CLAUDE.md's
  Layout section.

### Two things this pass measured

- `"\r\n"` is a **single grapheme cluster**, so a `Set<Character>` holding
  `"\r"` and `"\n"` matches neither half of a Windows line ending. The
  frontmatter escaper walks `unicodeScalars` and escapes in one pass, because
  sequential `replacingOccurrences` calls decode `\\n` as a newline.
- `NSTextView` does **not** implement `cancelOperation:` — it is an optional
  key-binding action, and `super.cancelOperation(sender)` raises
  `NSInvalidArgumentException`. It took a test process down. Esc while marked
  discards the composition instead; `complete(_:)` is a real method and does
  defer to `super`.

### Still yours to do — the app can't be launched from an agent shell

The tests cover what is reachable without a window. These are the checks that
need the real app, grouped as the original plan grouped them:

- *Storage*: tick a task in Obsidian and confirm it isn't trashed (and note the
  first load after this writes one file per externally-ticked task); type in a
  note while another card saves; open an id-less `.md` from Obsidian and edit
  it.
- *IME*: on the Spanish layout, type `navegación` inside a list item; press Esc
  mid-accent; click below a body ending in an empty checklist item.
- *Performance*: type into a long note and scroll a column while an editor is
  open.
- *Metrics*: flip a note with a fenced block, and one with `##` headings,
  between view and edit mode — **the card must not change height**. The tests
  pin the attribute-level agreement (same font, same `paragraphSpacingBefore`,
  same segment gap) measured through TextKit 1; the real preview is TextKit 2
  and the real editor height comes from the SwiftUI sizing proxy, so the
  on-screen invariant is the one thing not machine-checked. Also: Text size 22
  must scale the timestamp, and ⋯ → Copy into Pages must paste at the chosen
  size.
- *Sidebar*: drag a project in a long list, including one scrolled so the rows
  above the pointer were never laid out.

Not committed — the working tree holds the whole pass on `main`.

---

## Decisions taken

| Question | Decision |
|---|---|
| Identity for id-less files | **Derive a deterministic UUID from the filename.** No writes to the user's vault. |
| Highlighter cost | **Cheap wins only.** Memoise + de-allocate; do *not* rewrite the pass incremental yet. |
| `MarkdownText` block renderer | **Keep it, share the constants.** Do not delete it or re-point the teaser's measurement. |
| Delivery | **Four staged phases**, data loss first, reviewed between each. |

---

## Phase 1 — Data loss and storage (7 fixes)

| Fix | Where |
|---|---|
| Never purge a done task with no `completed` stamp; stamp it in `reconcileTaskFolders` when `done && completed == nil` so externally-ticked tasks age from when Insert first saw them | `Library.swift:802`, `:378` |
| `deduped`: on an `updated` tie, keep **both** files — re-id the loser rather than trashing it. Trash only a true duplicate (same id *and* same `updated` *and* same content) | `Library.swift:408` |
| `toggleCheckbox`: use one whitespace predicate for the trim and the index (trim with the same ASCII set, or compute the index off the trimmed offset) | `MarkdownText.swift:676` |
| `Frontmatter.quote`: add `\n`/`\r` to `needsQuote` and escape them as `\n`/`\r`; teach `unquote` the inverse | `Frontmatter.swift:70` |
| Deterministic id from `url.lastPathComponent` when `id:` is absent, in both decoders | `MarkdownFiles.swift:76`, `:121` |
| `UpdateChecker.install`: `FileManager.replaceItemAt(_:withItemAt:)` instead of remove-then-move, so the old bundle survives a failed swap | `UpdateChecker.swift:177` |
| Extract the two panels' duplicated editing session (`scheduleSave`/`flushSave`/`finishEditing`/`focusForEntry`/reseed) into one generic type, and **fix the reseed once**: skip while `isEditing`, and merge field-wise rather than replacing the whole draft when any field differs | `NotesPanel.swift:273`,<br>`TasksPanel.swift:370` |

Reuse: `Library.key(_:)` for path comparison, the existing `stampCompletion`
(`Library.swift:745`), `DeletionKey`/`pendingDeletions`, `flushDiskWrites()`
before any read-back.

**Tests** (`StorageLayoutTests`, `DateCodingTests`): retention leaves an
unstamped done task alone and the reconcile stamps it; a tie in `deduped` keeps
both files; a checkbox click on `"\u{00A0}- [x] x"` round-trips; a title
containing a newline and a line reading `---` survives encode→parse; an id-less
file keeps one id across two loads; the reseed does not clobber a draft while
editing.

## Phase 2 — IME, composition and focus (5 fixes)

| Fix | Where |
|---|---|
| One `guard !textView.hasMarkedText()` at the top of `MarkdownEdits.apply` — the single write path, so Return/Tab/⇧Tab/⌘B/I/U/K and the bar's buttons are all covered at once and a seventh entry point inherits it | `MarkdownEditing.swift:925` |
| Guard `cancelOperation`, `complete` and the ⌘Return `keyDown` — defer to `super` while marked, so Esc cancels the accent instead of closing the card | `MarkdownEditing.swift:754`, `:768`, `:773` |
| Hoist the `hasMarkedText()` guard in `updateNSView` **above** `view.font`, `applyTabStops` and `highlightConfig`, so a settings change mid-composition can't flatten the storage's fonts | `MarkdownEditing.swift:264`–`301` |
| One shared first-responder predicate (`markdownBody(in:) -> MarkdownTextView?`) replacing the four spellings — this is also the fix for the read-only preview satisfying `!isFieldEditor` and standing the `@project` monitor down | `ProjectTagging.swift:148`, `MarkdownEditing.swift:896`, `RootView.swift:354`, `SpellChecking.swift:47` |
| `settleClick`: don't accept `index - 1` when `index == storage.length` unless the point is actually within the last glyph's rect, so a click below the body opens the card instead of flipping the last checkbox | `MarkdownPreview.swift:218` |

**Tests** (`MarkdownEditorTests`, extending the existing dead-key coverage):
`apply` declines while marked; Esc while marked does not call `onEscape`;
`markdownBody(in:)` rejects a non-editable preview; a click past the end of a
body ending in an empty checklist item reports a tap, not a toggle.

## Phase 3 — Performance (8 fixes)

| Fix | Where |
|---|---|
| `MemoCache` in front of `font(for:)`, keyed on style + base font name + size + typeface + scale — the one unmemoised font path | `MarkdownHighlight.swift:166` |
| `find`: compare UTF-16 units in place; hoist literals to `static let`. Removes ~one Array allocation per source character per keystroke | `MarkdownHighlight.swift:642` |
| `FormattingBarPanel.hide`: early-return when already hidden — currently `orderOut` runs per keystroke and per scroll frame | `FormattingBar.swift:238` |
| Search: `range(of:options:[.caseInsensitive, .diacriticInsensitive])` instead of lowercasing every title and body per keystroke | `Library.swift:869`, `:906` |
| `counts(forProject:)`: one `[UUID: (notes: Int, tasks: Int)]` pass, invalidated in `reloadAll`/`persist*`, instead of two full scans per sidebar row | `Library.swift:848` |
| `flushDiskWrites()` off the main actor: make `reloadAll` await the drain (or drain on the queue and hop back) so a stalled iCloud rename can't block the window. `applicationWillTerminate` keeps the synchronous drain — it *must* block | `Library.swift:462`, `:294` |
| `publishGeometry`: compare against the pending value, not the current one, so a resize schedules one write rather than N | `RootView.swift:537`, `:549` |
| `guard newValue != appState.sidebarVisible` in the `columnVisibility` setter — the rule `DayClock.tick()` already applies | `RootView.swift:227` |

Deliberately **not** in scope: making the highlight pass incremental. Measure
after these land and decide separately.

## Phase 4 — Reading metrics, correctness, cleanup (28 fixes)

**4a. One definition of the card's reading metrics.** The `scale:` family is
four call sites disagreeing about one number:

- Code spans: size off `.callout × scale` in the editor to match both renderers
  (`MarkdownHighlight.swift:163`).
- `Mono` takes a scale for the two sites **on a card** — the timestamp
  (`CardDatesFooter.swift:56`) and the type label (`CardMeta.swift:88`) — and
  keeps the unscaled path for the band (`ColumnHeaderBand.swift:111`) and the
  Settings stepper (`CardTextMetrics.swift:142`,`:174`). This mirrors
  `Card.chrome(_:)` (`Theme.swift:446`), which is the existing opt-out.
- `Mono.font(size:)`: honour the requested size under Monospace instead of
  substituting `.caption1` (`BundledFonts.swift:246`).
- ⋯ → Copy passes `scale:` and `lineHeight:` like the preview does
  (`NotesPanel.swift:732` vs `MarkdownPreview.swift:74`).
- One `CardTextMetrics.current(for:)` returning font/typeface/scale/lineSpacing,
  consumed by all four derivation sites (`NotesPanel.swift:665`,
  `TasksPanel.swift:857`, `MarkdownEditing.swift:185`, `MarkdownPreview.swift:72`).
- Heading `paragraphSpacingBefore` of 2pt in the editor and its sizing segments,
  matching both renderers (`MarkdownHighlight.swift:236`, `:318`).
- `markerGap`, `bulletDiameter`, `listIndent` and the heading gap become
  `nonisolated static` internal in `MarkdownText` and are read by
  `MarkdownRichText` instead of its literals (`MarkdownText.swift:140`,`:209`,
  `:211` → `MarkdownPreview.swift:453`,`:457`).
- One `MarkdownText.paragraphStyle(base:lineHeight:)` factory for the editor's
  and the preview's base styles (`MarkdownEditing.swift:233`,
  `MarkdownPreview.swift:511`); `applyTabStops` owns its own staleness check
  rather than the call site naming its inputs (`MarkdownEditing.swift:264`).
- `MarkdownText.italicised` routes through `MarkdownHighlight.font(for:)`
  (`MarkdownText.swift:366`).

**4b. Correctness.**

| Fix | Where |
|---|---|
| `lineMarker` accepts a checkbox that ends the line, matching `checkboxMarker` — so Return on `- [ ]` continues the checklist and `toggleList` doesn't leave `[x]` behind | `MarkdownEditing.swift:1373` |
| Due popover: separate `selectedDay: Date?` for the grid's highlight from the month it opens on, so an undated task doesn't show today as set | `TasksPanel.swift:656` |
| Preset highlight reads `clock.today`, not `Date()` | `TasksPanel.swift:706` |
| `gap(at:)`: require a *current* frame; treat unmeasured rows as unknown rather than "not above", so a drag can't fall through to `.end`. Prune `rowFrames` when a row leaves the list | `ProjectsSidebar.swift:499` |
| Filter link schemes on render/click (reuse `MarkdownFormatting.isLinkDestination`) and add a `clickedOnLink` delegate, so `file://` can't launch an app from a synced note | `MarkdownPreview.swift:741` |
| `sizeThatFits`: answer a zero-width proposal with the ideal width's height, not the height at 1pt | `MarkdownPreview.swift:110` |
| `flattenToolbarGlass` excludes the Settings window like its two siblings; fold the four `applicationDidUpdate` passes onto one window-identity helper | `AppDelegate.swift:233` |
| `export`: allowlist the portable keys (font, link, underline, strikethrough, paragraph geometry) instead of denylisting the renderer's private ones | `MarkdownPreview.swift:776` |
| `BundledFonts`: make "has a variable weight axis" a property of the family, not `family == grotesk && weight == .semibold` | `BundledFonts.swift:165` |

**4c. Cleanup.**

| Fix | Where |
|---|---|
| Delete the unreachable `onToggleCheckbox` and its `Button` fork | `MarkdownText.swift:20`, `:233` |
| Delete `height(forWidth:)`; tests call `usedSize(forWidth:).height` | `MarkdownPreview.swift:153` |
| `ValueStepper` computes `canDecrease`/`canIncrease` from value + bounds | `SettingsView.swift:373`, `:387` |
| One line splitter shared by the parser, the highlighter's two walks and `toggleCheckbox` | `MarkdownHighlight.swift:316`,`:362`, `MarkdownText.swift:463`,`:668` |
| Add `UpdateChecker.swift` to CLAUDE.md's Layout section | `CLAUDE.md` |

## Not fixed, deliberately

- **`MarkdownText`'s block renderer stays** as the hidden height proxy (your
  call). 4a shares its constants so the two renderers can't drift, but the
  duplication itself remains — worth revisiting if a third spacing rule has to
  be mirrored.
- **The highlight pass stays whole-document.** Phase 3 removes the per-keystroke
  allocations and font matches; the structural rewrite is a separate decision.
- **`Note.symbol` as editable state.** Three mechanisms maintain a field nothing
  displays. Removing it is a design change, not a defect fix — **I'll ask before
  touching it** rather than fold it into Phase 4.
- **Task cards have no ⋯ → Copy.** Not a defect: CLAUDE.md scopes Copy to notes.

## Verification

Per phase:

1. `swift build --disable-sandbox` and `swift test --disable-sandbox` — the
   seven existing suites must stay green; new pins added per phase above.
2. `./build.sh` to confirm the app assembles and the font bundle check passes.
3. **You run the app** — I can't launch it from the agent shell. Per phase, the
   things tests can't reach:
   - *P1*: tick a task in Obsidian, confirm it isn't trashed; type in a note
     while another card saves; open an id-less `.md` from Obsidian and edit it.
   - *P2*: on the Spanish layout, type `navegación` inside a list item; press
     Esc mid-accent; click below a body ending in an empty checklist item.
   - *P3*: type into a long note and scroll a column while an editor is open.
   - *P4*: flip a note with a fenced block and with `##` headings between view
     and edit mode — the card must not change height; Text size 22 must scale
     the timestamp; ⋯ → Copy into Pages must paste at the chosen size.
4. Commit per phase, so a regression bisects to one cluster.

---

## Appendix — the findings themselves

Provenance: `/code-review high` over the whole codebase, 2026-09-03, ten review
angles. 48 findings, 37 CONFIRMED. Every line below was verified against the
source by reading it; CONFIRMED means the defect follows from the code,
PLAUSIBLE means it depends on runtime behaviour that could not be observed from
an agent shell (the app can't be launched there).

Kept here because the plan above says *what to change* and this says *why* —
without it the failure scenarios live only in a transcript.

### Phase 1 — data loss and storage

| V | Where | Defect |
|---|---|---|
| C | `Library.swift:802` | Retention falls back to `updated` when `completed` is nil, and nothing on the load path stamps `completed` — so a task ticked off in Obsidian is trashed on the basis of a year-old edit date. Fires on the first housekeeping run, every time. |
| C | `TasksPanel.swift:370` | `onChange(of: task)` includes `done` in the any-field-differs test but re-seeds the *whole* draft, so ticking a task from the menu bar while typing in it reverts the notes — then `scheduleSave()` re-arms on the reverted text and writes it. |
| C | `NotesPanel.swift:273` | Same class, no `isEditing` guard: with no save yet fired there is no `suppressReloadUntil`, so any folder event during a typing burst reaches `reloadAll` and `draft = newValue` discards the unsaved text. |
| C | `MarkdownText.swift:676` | `toggleCheckbox` validates with `trimmingCharacters(in: .whitespaces)` (includes U+00A0, U+2003) but indexes with an ASCII-only prefix predicate, so one click on an NBSP-indented item writes `- [x]` → `-  x]` and saves it. |
| C | `Library.swift:408` | `deduped` breaks an `updated` tie by directory order and trashes the loser with only a log line — a Finder duplicate whose frontmatter was untouched can lose the copy carrying the new writing. |
| C | `MarkdownFiles.swift:76`, `:121` | `UUID(uuidString: s["id"] ?? "") ?? UUID()` mints a fresh id per load for files with no `id:`, so a reload mid-debounce makes `updateNote`'s `firstIndex` miss and the edit is dropped silently (`Library.swift:660`). |
| C | `UpdateChecker.swift:177` | Deletes the running bundle, then moves; the `catch` deletes the staging copy. A throw between them leaves neither bundle and `phase = .failed` points at a bundle that no longer exists. |
| P | `Frontmatter.swift:70` | `needsQuote` omits `\n`/`\r` and the escaper never encodes them, so a value with a newline is written across two frontmatter lines; a pasted line reading `---` closes the fence early and the body is re-read as garbage. |
| P | `NotesPanel.swift:873` | ~90 lines of editing session duplicated verbatim in both panels; the IME fix already had to land in both files separately and TasksPanel's copy lost the comment. |

### Phase 2 — IME, composition and focus

| V | Where | Defect |
|---|---|---|
| C | `MarkdownEditing.swift:925` | `MarkdownEdits.apply` — the single write path — has no `hasMarkedText()` guard, and nor does any caller. Return on a dead key inside a list item rewrites the storage across the marked range and swallows the commit. `hasMarkedText` appears only at lines 301, 367, 504, 661 — none on an edit path. |
| C | `MarkdownEditing.swift:754`, `:768`, `:773` | `cancelOperation`, `complete` and the ⌘Return `keyDown` call `onEscape` unconditionally, so Esc pressed to abandon an accent closes the card and loses the character in flight. |
| C | `MarkdownPreview.swift:218` | `settleClick`'s `index - 1` fallback: for a body ending in an empty checklist item the last character is the marker's tab carrying `.markdownCheckbox`, so a click below the body flips the box instead of opening the card — and it saves. |
| P | `MarkdownEditing.swift:266` | `view.font`, `applyTabStops` and `highlightConfig` are written *above* the `hasMarkedText()` guard at line 301, and `rehighlight()` self-guards — so a settings change mid-composition flattens every styled run and records the config as applied. Found independently by two angles. |
| P | `ProjectTagging.swift:148` | Guards only `!isFieldEditor`, which the read-only `MarkdownPreviewView` satisfies — so the `@project` monitor stands down for a text view that is not a body. The other three predicates each spell this differently. |

### Phase 3 — performance

| V | Where | Defect |
|---|---|---|
| C | `MarkdownHighlight.swift:166` | `font(for:)` does an uncached `withSymbolicTraits` + `NSFont(descriptor:size:)` per span per pass — the one unmemoised font path. 40 emphasis spans is 40 descriptor matches per character typed. |
| C | `MarkdownHighlight.swift:642` | `find` allocates `Array(literal.utf16)` per call and `Array(u[i..<i+l.count])` at every position stepped — on the order of one array per source character per keystroke. |
| C | `Library.swift:869`, `:906` | Search lowercases every record's title *and body* per evaluation, on every keystroke, for all three columns. |
| C | `Library.swift:848` | `counts(forProject:)` scans all notes and all tasks, once per sidebar row, on every library mutation — including each 0.4s debounced save. |
| C | `Library.swift:462` | `flushDiskWrites()` is `diskQueue.sync {}` and is the first statement of `reloadAll` on the main actor, so a stalled iCloud rename blocks the window. This is the stall the queue was added to remove. |
| C | `FormattingBar.swift:238` | `hide(for:)`'s guard admits the already-hidden case, so `orderOut` runs per keystroke and per scroll frame for every open editor. |
| P | `RootView.swift:537`, `:549` | `publishGeometry` compares the current `AppState` value but defers the write, defeating its own coalescing: a live resize schedules N writes where it used to schedule none. |
| P | `RootView.swift:227` | The `columnVisibility` setter writes shared `@Observable` state with no change comparison, from inside `NavigationSplitView`'s own layout resolution. |
| C | `MarkdownHighlight.swift:194` | **Deferred by decision.** The pass re-scans and `setAttributes` over the whole storage per keystroke. Phase 3 removes the per-keystroke allocations and font matches; making the pass incremental is a separate call. |

### Phase 4a — reading metrics

| V | Where | Defect |
|---|---|---|
| C | `MarkdownHighlight.swift:163` | Code sized off the card's *base* style in the editor, off `.callout × scale` in both renderers — a note card with a fenced block changes height on every open and close, and the sizing proxy agrees with the editor so nothing catches it. |
| C | `CardDatesFooter.swift:56`, `CardMeta.swift:88` | `Mono` never receives `CardTextSize.scale`, so at Text size 22 the body is 22pt and the timestamp still ~10pt. `Card.chrome(_:)` (`Theme.swift:446`) is the documented opt-out and on-card metadata is not it. |
| C | `NotesPanel.swift:732` | ⋯ → Copy builds `Config` without `scale:`/`lineHeight:` (both default to 1) where `MarkdownPreview.swift:74` passes them — so the RTF flavour is a render of settings the reader doesn't have, while the plain flavour on the same pasteboard is right. |
| C | `BundledFonts.swift:246` | `Mono.font(size:)`'s Monospace branch returns `.caption1` and ignores the requested size, collapsing the count pill (11pt) and type label (10.5pt) onto one size. |
| C | `MarkdownPreview.swift:540` | Both renderers add 2pt above an h1/h2; the editor's styles and sizing segments add none, so a note with three `##` is 6pt taller in view mode. |
| C | `MarkdownPreview.swift:453` | `MarkdownRichText` re-declares `markerGap = 8` and `listIndent = 5 + markerGap` as literals, naming `MarkdownText`'s as the originals — which are `private` there. The heading gap is a third uncoordinated copy. Found by two angles. |
| C | `MarkdownEditing.swift:264` | The base-paragraph-style staleness check names its two inputs at the call site; a third input is silently omitted, leaving `defaultParagraphStyle` stale while colours and fonts update — and the list styles are `mutableCopy()`s of it. |
| P | `NotesPanel.swift:665` | Four sites derive font/typeface/scale/lineSpacing independently (`TasksPanel.swift:857`, `MarkdownEditing.swift:185`, `MarkdownPreview.swift:72`), and the proxies resolve `Card.nsFont` twice per render. |
| P | `MarkdownEditing.swift:233` | Two hand-rolled base paragraph styles for one leading rule — the editor's has tab stops and no `lineBreakMode`, the preview's the reverse. |
| P | `MarkdownText.swift:366` | `italicised` re-implements the bold descriptor union and `Card.italic` that `MarkdownHighlight.font(for:)` already resolves in the same order. |

### Phase 4b — correctness

| V | Where | Defect |
|---|---|---|
| C | `MarkdownEditing.swift:1373` | `lineMarker` requires a space after `]` where `checkboxMarker` accepts a box at end-of-line ("a space **or the end of the line**", `MarkdownText.swift:649`) — so Return on `- [ ]` inserts a plain bullet and `toggleList` leaves `[x]` as literal text. |
| C | `TasksPanel.swift:656` | The grid's binding substitutes today for a nil due date, so an undated task's popover paints today as already selected while "Clear due date" is correctly disabled — it claims the task is due today and that there is nothing to clear. |
| C | `AppDelegate.swift:233` | `flattenToolbarGlass` gates on `toolbar != nil` alone where `configureSplitViews` (`:446`) and `restyleWindowTitle` (`:145`) also exclude Settings by name — so it walks the Settings titlebar its two siblings deliberately skip. |
| C | `MarkdownPreview.swift:776` | `export` sanitises with a denylist of the renderer's private attributes, so any attribute the renderer gains leaks into pasted RTF — and the failure only ever appears in another application. |
| P | `ProjectsSidebar.swift:499` | `gap(at:)` treats an unmeasured row as "pointer is not above it", so with no laid-out row above the pointer the drag falls through to `.end` and writes the project to the bottom of `Projects.md`. `rowFrames` is never pruned. |
| P | `MarkdownPreview.swift:741` | Link runs carry any scheme with no filtering and no `clickedOnLink` delegate, so `[Report](file:///Applications/Calculator.app)` in a synced note launches an app on one click. `isLinkDestination` restricts schemes only for ⌘K insertion. |
| P | `MarkdownPreview.swift:110` | `sizeThatFits` maps a zero-width proposal to `max($0, 1)`, answering the minimum-width question with the height of the body wrapped at one point. |
| P | `TasksPanel.swift:706` | The preset-pill highlight reads `Date()` where the panel elsewhere passes `clock.today`, so it registers no `DayClock` dependency and an open popover goes stale past midnight. |
| P | `BundledFonts.swift:165` | "Has a variable weight axis" is encoded as `family == grotesk && weight == .semibold`; any other unpublished weight silently rounds to a neighbouring static. |

### Phase 4c — cleanup

| V | Where | Defect |
|---|---|---|
| C | `MarkdownText.swift:20`, `:233` | `onToggleCheckbox` is passed by nobody — the only `MarkdownText(...)` in Sources is the hidden proxy at `:921`, which omits it; the live path is `MarkdownPreview.settleClick`. Its doc comment still claims otherwise. |
| C | `MarkdownPreview.swift:153` | `height(forWidth:)` has no production caller — only `MarkdownRichTextTests.swift:215`, `:219`, `:220`. |
| C | `SettingsView.swift:373`, `:387` | Both `ValueStepper` sites re-derive `canDecrease`/`canIncrease`, so each setting's bounds live in four places. |
| C | `MarkdownHighlight.swift:316`, `:362` | Four line splitters for one format (`MarkdownText.swift:463`, `:668`); the two in MarkdownHighlight are the same LF walk twice in one call. |
| C | `MarkdownText.swift:42` | **Not fixed by decision.** The whole block renderer survives only as the hidden height proxy, duplicating `MarkdownRichText` for one measurement. 4a shares the constants instead. |
| P | `NotesPanel.swift:598` | **Ask first.** `Note.symbol` is state nothing displays, kept coherent by three mechanisms (`:276`, `:289`, `:598`). Removing it is a design change, not a defect fix. |

### Clean

The conventions sweep found **nothing**: no `Locale.current` in user-facing
formatting, no third-party code, no unpaired `accessibilityReduce…` reads, no
`.shadow(` in app code, no `Color.accentColor`, no `@Environment(\.colorScheme)`,
no stored global escaping isolation, no raw `URL` equality, and every directory
read-back preceded by `flushDiskWrites()`.
