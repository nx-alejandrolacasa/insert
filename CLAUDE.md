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
Settings → General → Storage):

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
  ProjectsSidebar.swift       left column: projects list, add/edit/delete/reorder,
                              SidebarVibrancy (see-through to the window)
  NotesPanel.swift            center: note islands, type pills, sort/filter, edit
  TasksPanel.swift            right: tasks, checkboxes, # project autocomplete
  MenuBar.swift               menu-bar extra: pending tasks at a glance
  SettingsView.swift          General / Appearance / Notes / Tasks / Accessibility
  Library.swift               @Observable store: lazy load/index/CRUD/search + watcher
  AppState.swift              transient window UI state (selection, filters…)
  SettingsStore.swift         persisted settings (note types, sort, retention…)
  Models.swift                Project / Note / TaskItem / NoteType + sort enums
  Frontmatter.swift           YAML-subset frontmatter reader/writer + date coding
  MarkdownFiles.swift         model <-> Markdown + filename conventions
  DirectoryWatcher.swift      debounced FS watcher (external edits)
  DateSections.swift          overdue/today/upNext buckets for the menu bar
  TaskReminder.swift          the once-a-day "N tasks for today" notification
  DayClock.swift              today, as observable state, so date labels age
  Formatting.swift            the locale the UI presents in (English)
  SpellChecking.swift         spell checking in the cards' titles and bodies
  BuildVariant.swift          dev vs release build, and what differs
  MarkdownText.swift          compact Markdown renderer for bodies + the shared
                              collapsible preview (CollapsibleMarkdown)
  Theme.swift                 Tint palette (roles + contrast), tokens, .island()
  AppTheme.swift              the six sourced themes: band / track / primary and
                              count-chip tones, the page and card grounds, the
                              metadata and link colours, the migration, the
                              picker
  ColumnHeaderBand.swift      the themed slab at the top of each column
  Appearance.swift            Auto / Light / Dark preference
  SegmentedFilter.swift       the filter rows' glass segmented control
  CardMeta.swift              marked title, type label, dot chips + overflow
  Typeface.swift              the five card faces + their Settings picker
  BundledFonts.swift          registers the two OFL faces; the Mono numeral face
  Fonts/                      Space Grotesk + IBM Plex Mono, and their licences
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

`TypefaceTests` also covers the **bundled** faces, and they need it more than the
system ones: a system font asked for wrongly is *substituted*, where a bundled one
can be missing outright — it lives in a SwiftPM resource bundle, so a build that
forgets to copy it resolves to the system font and looks like nothing happened,
which with Grotesk as the default face is the whole app quietly wearing something
else. Pinned: that both families register, that Grotesk resolves every weight
including the SemiBold only the variable axis has, that a symbolic bold trait
still reaches a heavier face (see the Typeface bullet — the trap that broke
`**bold**`), that `Mono` really is Plex Mono and defers to the card face under
Monospace, and that both OFL texts are in the bundle, which is a licensing
requirement rather than a cosmetic one.

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

`ThemePaletteTests` is the odd one out — it measures **colour**, and it is here for
the same "fails silently" reason. `AppTheme`'s table is 400-odd generated sRGB
literals across six themes and two appearances, so a band tone off by a step, a
type label that stops clearing its floor on a card, or an accent that drifts into
the hue one of its own note types wears would show up in no build, no test and no
screenshot of whichever theme you happen to use. It resolves each `Color` through
its dynamic `NSColor` inside an explicit `NSAppearance` — so what it measures is
what gets painted, not the literal — and asserts the plan's acceptance list: every
band and card pairing against its floor, links and rings and the overdue red on
every card face, the count chip measured **composited** over its band, the one
shared note-type label against all twelve card faces (and that neither it nor the
`accent` its mark uses moves when the theme changes, and that `accent` stays the
brighter of the two), that only the two sourced papers are off-white in Light, that
title and body colour are the
**system's** in five of the six and Dracula's own in the sixth — the check that
keeps "text is not themed" honest — and that Increase Contrast really reaches
7:1.

## Design intent

Behaviour that isn't obvious from the code, and shouldn't drift:

- **The August 2026 theme system** is the current word on the app's colour, and
  it *reverses* three parts of the July refresh below. Read this bullet before
  that one. Two things had gone wrong with the refresh: the highlighter stroke
  behind note titles hurt readability, and with the gradients gone and colour
  reduced to dots the app had gone flat. Both have the same fix — move colour out
  of the content and into **one band at the top of each column**, and make that
  band a named **theme**. Content stays neutral and readable; personality lives
  where it is never behind text. What changed:
  - **Theme replaces both Background → Tint and Accent → Highlight colour.**
    Six themes, each with a Light and a Dark value, in `AppTheme` — **System,
    Tokyo Night, Kanagawa, Dark Owl, Rosé Pine, Dracula** since the third cut
    below; **System is the default and the first case**. A theme is *three
    grounds and one accent*: band / page / card, plus the primary (buttons, rings,
    selected states), with the glass track derived from the band rather than a token
    set of its own. Note-type colour is shared by all six (`Tint.accent` and
    `Tint.ink`) — see the Theme bullet for the palette-per-theme that was tried and reversed.
    Whatever colour setting an older install holds is read **once** — a theme name
    from an earlier set, else the retired tint, else the retired accent
    (`AppTheme.migrated(theme:tint:accent:)`) — and the two retired keys are then
    **deleted**; **nothing migrates to Dracula**, which is an identity rather than
    a shade and has to be picked. Pinned by `ThemeMigrationTests`, including a
    sweep asserting no input reaches Dracula, and by `ThemePaletteTests`, which
    measures every value in the table.
  - **The column header band** (`ColumnHeaderBand`) replaces the heading row and
    the loose filter row in both columns: heading, a count in a mono pill, the
    primary button, then the filter track. Full column width, flush under the
    toolbar, **no radius of its own** — the window's corner clips it, which is
    what makes two adjacent bands read as one strip. **No hairline under it** in
    any theme: a light band took one until it was seen on screen, where it read as
    a rule *drawn under* the header rather than as the edge of a surface — the one
    thing that looks like a border in a window with no shadows anywhere. The band's
    own colour against the page is the boundary.
  - **The highlighter stroke is gone** — a 3×16pt capsule mark *beside* the
    title instead (`TypeMarkTitle`), in the type's themed colour. See the Notes
    bullet.
  - **The set is on its third cut, and each revision found the same kind of
    fault one level up.** The **first** six (Slate, Graphite, Pine, Amber, Indigo,
    Dracula) themed the band and nothing under it, so five read as a *preference*
    and only Dracula read as a theme — it was the only one bringing its own
    grounds and type hues. The **second** (Bone, Moss, Ember, Rosewood, Indigo,
    Dracula) fixed that by holding every theme to what Dracula was already doing:
    grounds for all six, a note-type palette per theme (since reversed), and an
    accent that may not repeat one of its own type hues (reversed with it). It still came out as a preference, for a
    reason a rule can't reach: **every hue in it was one somebody picked**, so
    there was no answer to "why this green" beyond taste, and the only theme that
    read as an identity was still the borrowed one. So the **third** cut is five
    *sourced* palettes plus the platform — read from the upstream project rather
    than designed here — with what we changed stated per theme in `AppTheme`
    (verbatim grounds, hairlines, links and accents; deepened where a label
    couldn't clear 4.5:1; derived where a comment grey failed on a card;
    re-levelled, always, for the four marks). The band-is-where-colour-goes
    finding from the first cut stands unchanged through all three; what was wrong
    the second time was authoring the hues at all.
  - **Two bundled typefaces**: Space Grotesk as a fifth face ("Grotesk", the
    default for new installs) and IBM Plex Mono as the app's numeral and label
    face. See the Typeface bullet.
  - **The sidebar is translucent white in every theme** — a pane you can see
    through, not a slab, and the one surface the theme never reaches. Two layers
    make it: the system's material, transparent to the *desktop*, plus a **white
    wash** over it (`ProjectsSidebar.sidebarWash`, 40% in Light / 16% in Dark, one
    dynamic `NSColor`, no `colorScheme` read). The wash is what turns "the desktop,
    blurred" into "frosted glass" and is what makes all six themes' sidebars the
    same pane; the two values differ because 40% over a near-black material in Dark
    is a grey haze rather than a lift. **A wash of the *band's* colour is still
    rejected** — see the three rejected approaches below; what changed is that
    white is theme-independent, which was the objection, and subtracting from the
    material is the *point* here rather than a side effect. The transparency itself
    is `SidebarVibrancy`, a
    zero-size probe in the sidebar's `.background` that walks **up** to the
    enclosing `NSVisualEffectView` and keeps `blendingMode` at the stock
    **`.behindWindow`** with `alphaValue` at 1. What that costs, honestly:
    a `.behindWindow` view samples the desktop and only the desktop, so nothing
    Insert draws can ever appear in the sidebar and the column does **not** follow
    the theme's page ground — it is the system's frost over whatever is behind the
    window.
    **The mode alone isn't enough, and the other half lives in `RootView`.** An
    opaque window has nothing behind it to sample, so the page ground is painted on
    the **detail side only** (`.background(settings.theme.windowFill…)` on the two
    columns) rather than as a window-wide `containerBackground`, and `WindowProbe`
    sets `isOpaque = false` *and* `backgroundColor = .clear` — both, since
    `isOpaque` alone still fills with `backgroundColor`. Undo any one of those three
    and the sidebar goes back to a slab.
    `material` is left at the stock `.sidebar`, and `state` at
    `followsWindowActiveState`, because the window is *meant* to settle down when
    inactive — see "No shadows". Walking *up* means it can only find this sidebar's
    effect view, never the titlebar's and never the Settings window's; no match is
    a no-op. **Reduce Transparency needs nothing by hand**, unlike the app's other
    glass: the effect view opaques its own material, and with no `alphaValue` of
    ours layered on top there is nothing left for the system switch to miss — and
    the white wash doesn't change that, since over an opaque material it is only a
    lighter opaque material.
    **Three rejected approaches, so they aren't re-proposed.** A translucent wash of
    the **band's colour** over the sidebar: wrong because it makes the column a
    *themed, painted* surface when what it wants is to be transparent, and because a
    colour layer over a vibrancy material subtracts from it one for one, so the
    tint and the transparency fight for the same pixels (at the 40% it shipped
    at, the sidebar read as flat tinted paint). The white wash above is not a
    reversal of this: it is fixed rather than themed, and it spends that same
    subtraction on frost instead of on hue. `blendingMode = .withinWindow` plus
    an `alphaValue` of 0.6, which was that same wash moved one layer down: a
    `NavigationSplitView` lays the sidebar out as a **column**, so the notes and
    tasks columns are beside it and never under it, and the only thing behind the
    sidebar was the window's own flat page ground — a pane you see one uniform
    colour through is indistinguishable from a slab painted that colour. And
    setting `material` to `.underWindowBackground`: that was solving a problem
    nobody had, on the theory that the material was what stood between us and
    what's behind — it's the blending mode, in one direction and then the other.
  - **Not followed, deliberately:** the plan specifies the card timestamp as
    `DD.MM HH:mm`. Only the *face* changed (to Plex Mono). The format would have
    undone the footer's own compaction — today is the time alone, this year drops
    the year, another year spells it out — and lost the year on an old note
    entirely; that part of the spec was solving a problem this app had already
    solved. See `CardDatesFooter`.
  Everything else in the refresh below still stands: meta row order, `+N`
  overflow, the contrast floor, "round means pressable", grey metadata with red
  only when overdue, project dots, no emoji.
- **The July 2026 visual refresh** restyled the surfaces without touching
  behaviour, and several bullets below changed with it. The handoff document and
  its two HTML mocks are **gone** — the refresh shipped, so the code is the
  record now, and the oklch tables the handoff carried are baked into
  `AppTheme`/`Theme` with their derivations in the comments there. What outlived
  them is this bullet, ending in the numbered decision log the source comments
  cite as "decision N". The shape of it: the five window *gradients* became
  flat **tints** (Plain + Linen / Clay / Blush / Sage / Mist / Lilac, with
  Seafoam added after the refresh — one L/C per role with hue the only
  variable) — **since replaced by the themes above**, and the tints' own
  gradient migration went with them; a note's type moved
  off the card wash onto a **marker stroke** behind the title plus a small-caps
  label in the meta row, so every card face is plain paper — **the stroke has
  since been retired** for the capsule mark, the label stayed; metadata went
  **grey with red reserved for genuinely overdue** (`Semantic.overdue`,
  `Stone.metaText` — both solved for the refresh's ≥4.5:1 floor on sub-14px
  text); the filter rows became **glass segmented tracks** (`SegmentedFilter`);
  the **accent became a preference** (`AccentColor`, Settings → General →
  Accent, threaded through `.tint()` and read directly by the primary buttons
  and selection rings) — **since folded into the theme**, which sets the accent
  rather than offering it beside the window's colour; and controls are pills
  while containers keep a 10–12pt
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
  The **decision log**, kept in full because it is what the source comments
  cite and because most of it is a rule rather than a value:
  1. **Gradients → flat tints.** A gradient was legible only in the outer
     margins and the sidebar, and each one needed its Light and Dark ends
     solved per region; a flat tint means text contrast is identical
     everywhere, so it's verified once per theme. The tint paints the window
     base and the sidebar, never the cards. *(Superseded: the tints are gone
     too. The reasoning survived them — one lightness and chroma, hue the only
     variable, verify once — and is what makes a new `AppTheme` a hue rather
     than a design. What didn't survive is the premise that a window
     **surface** is where colour belongs: at the low chroma a surface behind
     text has to sit at, it reads as almost nothing, which is why the colour
     moved into the band.)*
  2. **Note type is a marker stroke, not a card wash** — colour where the eye
     already is, body-text contrast constant, and no wash left to fight the
     chips inside the card. The band sits *behind* the glyphs, and title
     contrast is never reduced to accommodate it. Three treatments were
     rejected on the way and shouldn't be re-proposed: a coloured left rule
     (generic), a filing-tab treatment, and a no-card "ledger" layout with a
     monospaced gutter (too space-hungry). *(Superseded: the stroke is retired
     for a capsule mark beside the title. The wash was still the wrong answer —
     that half stands — but so was the stroke: pigment behind glyphs fights
     them at any opacity, which is why the strength had already come down from
     60% to 45%, and it forced every title onto a tinted ground. The one thing
     the two share is that the type's second voice is still the meta row's
     small-caps label. Note the rejected left rule is **not** what replaced it:
     a 3pt mark 16pt tall beside the first line is a mark on the card, not a
     rule down its side.)*
  3. **The meta row is one line** — type label · hairline · chips · timestamp,
     each chip a colour dot plus a name and no icon, held to two plus `+N`.
     Chosen over letting the chips wrap onto their own line, which was mocked
     and rejected: one project per note is the common case, two at most, so a
     fixed card height is worth more than showing every assignment.
  4. **Colour discipline** — one accent, for interactive and selected state
     only; project colour appears only as a dot (the sidebar's own icons
     aside); metadata is grey; red means genuinely overdue and nothing else.
     The accent is a preference of exactly four — blue, green, orange,
     graphite — and adding a fifth is a decision, not a tweak. *(Superseded in
     one clause: the accent is no longer chosen at all, it comes from the
     `AppTheme`. "One accent, for interactive and selected state only" stands
     unchanged and is exactly what `AppTheme.primary` is; adding a sixth theme
     is the decision this used to be about.)*
  5. **The contrast floor is three rules, not one.** Text under 14px ≥4.5:1;
     interactive glyphs (the ⋯ menu, the chevrons) ≥4:1; and both verified
     against the surface actually painted behind them — a tint or a card face,
     **not** a nominal white. That third rule is the one that gets forgotten,
     and it's why `Semantic.overdue` and `Stone.metaText` are each solved
     against *both* card faces, Light paper and Dark near-black; it is also
     what ruled out `.secondary`/`.tertiary` for metadata, since an alpha wash
     has no fixed contrast to verify.
  6. **Every control is a pill; containers keep a 10–12pt radius** — round
     means pressable. But **icons are not controls**: anything drawing a lone
     glyph rather than a label keeps its own shape, because a glyph rounded
     into a pill reads as a toggle switch. That happened to the
     sidebar-toggle glyph during review and was caught there;
     `Sizing.toolbarGlyph`'s square 28pt is what keeps it a circle. The tint
     swatches are the same case from the other side — a preview of a surface,
     so a soft radius, not a capsule.
  7. **The filter rows are a segmented track**, each note-type segment
     carrying its type's dot so the row ties back to the markers on the cards,
     with the date axis a separate button *outside* the track because it is a
     different kind of control.
  One thing was parked rather than rejected, flagged here so it isn't lost: the
  **"ledger" layout as a future compact density**. It lost as the default for
  the reason in decision 2, but a deliberately dense mode is the one context
  where being space-hungry stops being the objection.
- **The Settings window has five panes — General, Appearance, Notes, Tasks,
  Accessibility — and Storage is not one of them.** That is one change rather than
  two, made because of a footer. General had become the window's junk drawer
  (appearance, theme, typeface, spelling, the menu-bar item), and the typeface
  section ends in three paragraphs plus two licence links, because the OFL requires
  the notice to travel with the fonts — so the two toggles *under* that footer were
  effectively hidden behind the legal text. Moving the three chrome controls out
  into an **Appearance** pane also settled a smaller thing: the word "Appearance"
  was printed twice in one form, as a section header and as the row label under it.
  The pane's name in the title bar says it now, so the section header is gone and
  the row keeps its label — a bare segmented picker needs one.
  That left General with two toggles, so **Storage folded into it** as a section and
  its pane went: a folder path, two buttons and a footer was never a pane's worth on
  its own, and "where the files live" is as general as a setting gets. Nothing
  persists the selected pane, so the case that disappeared needed no migration.
  Typeface stays **last** in its pane for the reason the split happened: nothing
  should sit under that footer.
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
  filter indicator and the `@project` dropdown; the Plain sidebar's material is
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
  `idealSidebarWidth` changes; after that only widths outside the range are
  corrected, so a divider the user drags stays put. **Changing the constant is
  therefore enough** — but expect the *first* launch after it to be the one that
  moves an existing window, not the build itself.
  **The `max:` doesn't police the divider either**, which is the same gap from the
  other side and was reported as a screenshot: with `min: 200, max: 460` on the
  sidebar, the divider dragged out to most of the window and left notes and tasks a
  few characters wide. So the range is held in AppKit too —
  `constrainSidebarWidth()` sets `NSSplitViewItem.minimumThickness` /
  `maximumThickness` on the sidebar item, which become layout constraints, so a drag
  *stops* at the bound rather than snapping back from past it. It rides
  `applicationDidUpdate` for `flattenToolbarGlass()`'s reason — a second window or a
  SwiftUI update that resets the item is covered without knowing when either
  happens — and is idempotent by comparison, since assigning a thickness re-runs the
  split view's layout. Two things are **not** established and shouldn't be written
  down as if they were: why SwiftUI's values don't reach the divider, and whether
  setting the thicknesses once would hold. `sanitizeSidebarWidth()` gained the upper
  bound with it, because a build from before this could have autosaved 1,100pt and
  restoring that would give an otherwise-correct window one wrong first frame; it
  clamps a too-wide width to the maximum rather than resetting it to the default,
  since a wide sidebar is a width someone chose and only the excess needs taking off.
  The modifier stays — it is still what sets the *ideal* — but none of its three
  values is what enforces the range.
  **AppKit's hover-peek of the collapsed sidebar is switched off, because
  cancelling one segfaults.** 0.13.0 crashed on open → close → open of the
  projects column, with no frame of Insert's on the stack:
  `-[_NSSplitViewCollapsedInteractionsView mouseExited:]` →
  `-[NSSplitView _cancelProactivePeek]`, `EXC_BAD_ACCESS` at 0x59. The report's
  own instruction bytes name the fault exactly — `ldrb w8, [x0, #0x59]` with x0
  nil, a BOOL read off a pointer the call before it handed back nil for, three
  instructions after AppKit *had* nil-checked the peek state it loaded (`cbz x0`)
  — so the peek existed and one of its parts was already gone, and `x15` held
  `NSSplitViewPeekingViewParams`, which is the part. What makes it an ordinary
  gesture rather than an exotic one: the peek's sensitive zone is the window's
  leading edge, which is where the show button is, so hovering it starts a peek
  that clicking it then supersedes. That ordering is a reading of the trace and
  the repro and was **not** instrumented; the crash and the nil deref are the
  facts. There is no public API for any of the peek
  (`_beginProactivePeekAtLocation:`, `_proactivePeekParams`,
  `_canDoSidebarProactivePeek` are all private) and nothing on our side can make
  AppKit's nil deref safe, so `disableSidebarPeek(in:)` removes the path instead:
  `mouseExited:` arrives through an `NSTrackingArea`, and a view with none gets no
  enter or exit at all. The **cost is deliberate** — the leading edge no longer
  peeks the collapsed column, and the button, the menu item and ⌘§ are what open
  it. It asks the split view for its own `_leadingCollapsedInteractionsView`
  rather than matching a private class name down the hierarchy, so a future AppKit
  without one degrades to a no-op, and it repeats on `applicationDidUpdate`
  because AppKit re-adds the tracking areas from `updateTrackingAreas` every time
  a column collapses — the fourth place in the app that reaches past the public
  API, on `flattenToolbarGlass()`'s terms. `constrainSidebarWidth(in:)` was
  narrowed in the same pass to **skip a collapsed sidebar**: there is no divider
  to police while the column is away, the next update tick re-asserts the range as
  it reopens, and it keeps our writes — each of which re-runs the split view's
  layout — out of the interval the peek lives in. Whether those writes contributed
  at all is untested; the guard costs nothing either way. Both now run from one
  `configureSplitViews()`, so the hot path walks for the split view once.
- **The toolbar's leading side is the show button and AppKit's own title, and
  nothing else.** A project icon sat between them from an earlier design and was
  **removed**, along with every attempt to space it: the whole episode is kept
  because each attempt failed in a way that is worth not repeating.
  Spacing it as its own `ToolbarItem` needs a negative inset, and a negative inset
  **shrinks the view's frame**. On the button that left a 28pt circle drawing
  inside an 8pt frame, and only that sliver took clicks ("hard to click, as if
  there is something on top of it"). Moved onto the icon — decorative,
  `accessibilityHidden`, hit-tests nothing — it stopped costing clicks and stopped
  working: **the toolbar reserves an item's slot at its natural width whatever the
  padding says**, so the space came off one side and reappeared on the other
  (button→icon 29→12.5pt, icon→title 8.5→35pt, measured at 2×). And the same inset
  landed differently depending on the sidebar — 3pt to the title with the button in
  the stack, 18pt with the icon alone — so no single value was right in both.
  Putting all three in one `HStack` *did* fix the spacing, at a price that wasn't
  worth it: it needs `.toolbar(removing: .title)` and a `Text` of our own, and with
  the title item gone **the search field lost its trailing pin** and sat beside the
  title, because that item is what holds the space between the toolbar's two ends.
  `DefaultToolbarItem(kind: .search, placement: .primaryAction)` does not survive
  it. So the title is AppKit's again, styled only by
  `AppDelegate.restyleWindowTitle()`, and the icon is gone rather than reinstated —
  the simplification was the maintainer's call once the spacing had cost this much.
  **The button's exit is 40% of the slide, and that timing is about the title.**
  The toolbar holds the item's slot at its natural width whatever width is
  animated underneath — the same reservation that made a negative inset useless
  above — so the shrinking glyph moves nothing and the title travels its last
  ~36pt in **one step**, when the item is removed. The step can't be animated
  away, only placed: at the full slide length it landed the instant the column
  stopped, with the whole window still, which is the frame that makes it read as
  a jump. `exitFraction` ends the fade mid-slide instead, so the step is absorbed
  by a movement the eye is already following. With Reduce Motion there is no fade
  to wait for and the item leaves at once, since a slot held open for an invisible
  button is only a later jump.
  **The button's fade scale is floored at 0.01 and must never reach 0.** A zero
  scale is a **singular** transform, and `NSView.convertRect:fromView:` aborts
  rather than declining when it cannot invert one — `__assert_rtn` inside
  `NSViewGetTransformToDescendant`, reached from the window's own
  `_regionForOpaqueDescendants` pass under the titlebar, with **no frame of
  Insert's on the stack**, so the crash report names only AppKit and SwiftUI. It
  crashed while the button was a *descendant* inside a hosting view AppKit walks
  into (the one-item arrangement above) rather than that view's root, which is the
  only reason the same degenerate value had been survivable before. At 0.01 the
  button is equally invisible — `opacity` is the same 0 — and the matrix inverts.
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
  **In view mode a note's type shows twice and only twice**: a 3×16pt capsule
  mark before the title (`TypeMarkTitle`) and a small-caps `TypeCapsLabel`
  leading the meta row — the mark in the type's `Tint.accent` and the label in its
  `Tint.ink`, shared by every theme rather than themed per band; see the Theme
  bullet. The card face is the theme's own
  paper and never a type wash,
  and the view-mode type glyph is gone: mark + label already say it twice, and a
  third voice was the wash's mistake in miniature. The meta row is one line —
  type · hairline · project chips · timestamp — with the chips held to **two
  plus a `+N` overflow** whose hidden names are a click popover
  (`ProjectChipsRow`), so a card's height doesn't grow with its assignments.
  The mark replaced `MarkerTitle`'s **highlighter band** — the refresh's
  decision 2, and the one part of it undone rather than tuned; see the theme
  bullet for why. Four things about the mark are decided, not incidental. It is
  **fixed at 16pt and top-aligned** to the title's first line rather than
  stretched to the text's height, so a two-line title doesn't grow a 40pt bar —
  it marks the card, it isn't a rule down the side. It declares its own baseline
  through `centredOnTextCap()`, because the title row is
  `.firstTextBaseline`-aligned and a shape has none of its own. The colour is
  **`Tint.accent`**, the app's one dot colour — brighter than the `ink` the label
  beside it uses, and held to no contrast floor, because a mark is decoration next
  to a name while the word naming the type is text (see the Colour bullet). The two
  greyscale-ladder notes that used to sit here — first that the marks *weren't*
  distinguishable in greyscale, then that the sourced palettes fixed it — are both
  moot: there is one shared palette again and no ladder rule. And it costs
  the title 11pt of leading inset the **editor
  doesn't have** — the one place the two modes no longer start at the same x.
  That's accepted: indenting the editor to match would spend a line of writing
  width on a decoration.
  The type colours are **shared by every theme** — the app's own `Tint.accent` for
  the mark and dot, `Tint.ink` for the label, so the four types look the same
  whatever theme is on and a **custom** type on any of the nine tints is no special
  case. They were
  briefly a per-theme palette; the Theme bullet has why that was reversed and the
  two rules it took with it.
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
  **The ⋯ menu copies the writing, not the file.** "Copy" puts
  `MarkdownFiles.copyText(_:)` on the pasteboard — the title as an `#` heading, a
  blank line, then the body — deliberately *not* `encode(_:)`, whose frontmatter
  is Insert's own bookkeeping (ids, timestamps, project UUIDs) and means nothing
  wherever it is being pasted. An empty title contributes no heading and no blank
  line, since `displayTitle`'s "Untitled" is a label for a card with no name
  rather than a name anyone wants pasted; a note with neither title nor body
  copies as the empty string and the item is disabled. It carries **no ⌘C**, and
  that is the interesting constraint: a menu item's `keyboardShortcut` is live for
  as long as its view is, so every card on screen would claim ⌘C at once — both
  ambiguous between cards and taken off the text selection in whichever card is
  open. Pinned by `StorageLayoutTests`.
  **A body can read collapsed — "Preview lines", notes and tasks each their own**
  (Settings → Notes / Tasks): show everything, or a preview of 1 / 3 / 5 / 10
  rendered lines with a chevron beside the body's *first* line to reveal the
  rest. Notes default to everything, so an untouched install keeps showing whole
  notes (an install that had the earlier "Collapse long notes" toggle on is
  seeded to 10 — that toggle was ten lines or nothing); tasks default to 1 line,
  the teaser those rows have always shown. View mode only — the editor always
  shows everything.
  **A note stays expanded after being edited.** The editor showed the whole note,
  so folding it back to a preview the moment editing ends takes away the text
  someone was just reading, on the same frame the card is already resizing — it
  reads as the note shrinking away from them. Expanding is a state the reader can
  undo with the chevron; collapsing is one they have to. It rides the existing
  `onChange(of: isEditing)`, so every route out of edit mode is covered, and the
  two value-scoped animations mean the card resizes once rather than twice. One
  consequence in `CollapsibleMarkdown`: a card that has only ever been expanded
  has never laid its one-line teaser out, so `collapsible` falls back to one line
  of the card face rather than comparing against an unmeasured zero, which would
  call every body collapsible and hang a chevron on a note with nothing to fold.
  Tasks are deliberately unchanged — their preview is one line by default, and
  leaving every edited row expanded would rewrite the column's rhythm.
  All of it is **one shared view**, `CollapsibleMarkdown`
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
  task can be assigned to several projects. Typing `@` opens a project
  autocomplete; Tab picks the first match; the `@word` is *not* kept in the
  task text, it only adds the assignment. **The trigger was `#` until August
  2026**, and the swap is one character plus two placeholders, but it was the
  wrong character twice over: `#` is Markdown's heading marker and these fields
  sit directly above a Markdown editor, so one keystroke meant "tag a project" in
  the title and "make this a heading" one field down; and `@` is what mentioning
  something by name means everywhere else. `ProjectMentionField` is named for it
  (it was `ProjectHashField`). Nothing on disk carried either character — the
  token never survives the accept — so there was no migration.
  Assignments appear as chips below and
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
- **Today is observable state (`DayClock`), because nothing else tells a view the
  day turned over.** Several labels are a comparison against *now* made while a
  view renders — the due badge's words and the red it turns when a task is
  genuinely overdue, the card footer's compaction of a stamp to the time alone,
  the tasks column's Overdue / Today / Tomorrow window, and the menu bar's
  buckets. The passage of time reaches SwiftUI through nothing, so every one of
  them was only as fresh as the last unrelated edit: a task due yesterday still
  read "Today" the morning after until typing in some other card rebuilt the
  column, which is how it was reported. The functions behind those labels already
  took an injectable `now` — it is how they're tested — so the fix is to stop
  letting it default at the call sites and pass `clock.today` instead, which
  registers the read.
  Two things about the shape. It publishes a **day, not an instant**, and that is
  what makes it cheap: every label it feeds reduces `now` to `startOfDay` anyway,
  so publishing the minute would re-render every card on screen sixty times an
  hour to say the same words. And it **ticks every minute and asks** whether the
  day changed rather than being aimed at midnight — `TaskReminder`'s argument, for
  the same three reasons (a timer aimed at a moment has to be re-aimed on wake
  from sleep, on a timezone change and on a clock change). The assignment is
  guarded because `@Observable` publishes on *write*, not on change, so the 1,439
  ticks a day that aren't midnight cost one comparison and re-render nothing.
  It also asks **on app activation and on wake from sleep**, so the minute a tick
  is worth is never the minute someone is reading the window. It takes both, and
  the window is not the granularity: an app switched to from another one is what
  activation covers, and a lid opened on an already-frontmost Insert — the case
  this was reported from — activates nothing, so the workspace's wake is what
  covers that. Extra ticks are free by the same guard.
  `StorageLayoutTests` pins the plumbing half — that `Library.tasks(…, now:)`
  really hands the day on to the date filter — because that parameter has a
  default, so dropping it compiles, and nothing on a machine that never crosses
  midnight with the app open would say the bug was back.
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
  `ProjectMentionField` documents for Tab and Return, hit again here.
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
  single-line field where Return submits — the note title and the `@project`
  field keep their own behaviour. The event is swallowed *only* when `listReturn`
  returns an edit, so Return is ordinary everywhere else.
- **Cards read in one of five faces** — Settings → Appearance offers Standard /
  Rounded / **Grotesk** / Serif / Monospace (`Typeface.swift`, resolved by
  `Card` and nowhere else). **Grotesk is the default for a new install**;
  an existing install keeps Rounded and keeps it *explicitly* — a default that
  changes under someone is the one migration that can't announce itself, since
  there is no setting they chose for you to point at. "New" is read off
  `noteTintMigrated`, the one key written on **every** launch rather than only
  when its setting changes, so its absence during `SettingsStore.init` is the
  only reliable "this is the first process this install has ever run".
  **Grotesk and the numeral face are the app's only bundled files, and the only
  ones that aren't Apple's** — Space Grotesk and IBM Plex Mono, both SIL Open
  Font License 1.1, in `Sources/Insert/Fonts/` and registered `.process`-scoped
  by `BundledFonts` so they exist for this app and are never installed on the
  user's Mac. This bends "no third-party dependencies — system frameworks only":
  the rule is about *code*, and these are font files with no build step, no
  package manager and nothing executable. The licences are bundled beside them
  and shown from Settings → Appearance (`FontLicenceSheet` reads the shipped file
  rather than a Swift literal, so the text shown and the text shipped can't
  drift), because the OFL requires the notice to travel with the fonts.
  They are a **SwiftPM resource** (`resources: [.copy("Fonts")]`) rather than a
  folder in `Resources/` beside `Info.plist`, so they exist in both the assembled
  app and `swift test` — which is what lets `TypefaceTests` pin the registration.
  `build.sh` copies the generated `Insert_Insert.bundle` into
  `Contents/Resources` and now **fails** if SwiftPM didn't emit it, since Grotesk
  is the default face and a build without it looks wrong everywhere and says
  nothing.
  **`Bundle.module` must not be used to find it, and this is the bug that shipped
  a crash.** 0.12.0's DMG trapped in `applicationWillFinishLaunching` — a
  `Swift.fatalError` inside `Bundle.module`'s initialiser, before any window — on
  every Mac except the one that built it. The generated accessor tries exactly two
  paths: `Bundle.main.bundleURL` + `Insert_Insert.bundle`, which is a **sibling of
  `Contents/`** rather than anything inside `Contents/Resources`, and then an
  **absolute hard-coded path into the `.build` directory of the compiling
  machine**. So a locally built app worked by falling through to
  `/Users/<author>/…/.build/…`, while the CI-built one carried
  `/Users/runner/work/…` and died. `BundledFonts.resources` does the lookup
  itself, in the order a candidate can be right — `Bundle.main.resourceURL` (the
  assembled app, and the only correct place in a signed bundle), then
  `Bundle.main.bundleURL` (a bare `swift run`), then the marker class's bundle and
  its parent (under `swift test` the resource bundle sits beside
  `InsertPackageTests.xctest`) — and answers **`nil` rather than trapping**, since
  a missing font bundle is a font problem that `font(family:…)` and its callers
  already degrade to a system face. `build.sh` also checks the *assembled* app for
  the fonts and the licence before it says "Built", because every step of the
  0.12.0 build reported success.
  Four things about the bundled faces are load-bearing.
  Space Grotesk ships as the **variable** file, not the four statics: the
  published statics are Light / Regular / Medium / Bold with **no SemiBold**,
  which is the weight the card titles want, and the `wght` axis gives a real 600
  instance (verified — a distinct face, not Bold). It is **Latin-only**
  (measured: no Cyrillic, Greek or CJK) and nothing handles that, because
  CoreText's own cascade substitutes per *glyph*, so a Cyrillic title falls
  through a character at a time rather than switching the whole string.
  **Pinning the variable axis freezes the weight against every later symbolic
  trait**, which is the trap here and a silent one: a descriptor carrying
  `wght: 400` answers `withSymbolicTraits(.bold)` with the regular face again,
  no error — and `MarkdownText` resolves `**bold**` through exactly that lookup,
  so every bold run in a Grotesk body rendered as body text. Hence
  `BundledFonts.font` has three routes to a weight: regular gets the family
  **alone**, semibold-on-Grotesk gets the axis (the only case that needs it),
  everything else gets the ordinary weight trait. Pinned by
  `testSymbolicBoldStillReachesAHeavierGroteskFace`.
  And the PostScript names are **not** usable: the variable file's members come
  back as `SpaceGrotesk-Light_Regular` and Plex Mono's as `IBMPlexMono-Medm` /
  `-SmBld`, so `NSFont(name: "SpaceGrotesk-SemiBold")` and
  `NSFont(name: "IBMPlexMono-Medium")` are both nil. Everything goes through the
  family plus a weight.
  **IBM Plex Mono is not a body option** — it is the app's *numeral and label*
  face (`Mono`): the bands' counts, the cards' timestamps, and the uppercase type
  labels. Those three because they are read as **values** rather than as prose,
  and a proportional face makes them jitter sideways as they change ("11:59" is
  narrower than "12:00" in SF); the uppercase type label joins them because it is
  a tag, not a word. **Except under Monospace**, where the card's own face is
  already SF Mono and a second mono voice would be two faces saying different
  things, so the body face covers it — the one place `Mono` reads the typeface
  setting, and it reads it the way `Card` does, inside a view update.
  The four remaining options are *system designs*;
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
  headings included — plus everything else that is **a name somebody typed**:
  the three column headings (the band is the app's identity surface, and Grotesk
  being the default is most of what a new install's character is; the sidebar's
  "Projects" comes along because all three titles share one baseline and a
  different face at the same size has a different ascender), the **project names
  in the sidebar rows**, and the **window title**, which is the selected
  project's name. The line the scope follows is authored text versus derived
  text: a project's name is the user's, so it takes their face, while the
  `X notes · Y tasks` under it is a count Insert worked out and stays on the
  system font. The rest of the chrome does too — chips, pills, the due badge, the
  metadata footer. Fenced code stays monospaced, and the numerals and type labels
  are `Mono`, not the card face.
  **The window title is re-fonted in AppKit**, by `AppDelegate.restyleWindowTitle()`
  on the `applicationDidUpdate` tick that already flattens the toolbar's glass.
  It has to be: `RootView` supplies the title as a `String` through
  `.navigationTitle` and AppKit draws it, there is no modifier for its font, and
  both obvious workarounds are worse — hiding it and adding a `Text` toolbar item
  costs the window its real title (menus, the Window menu, Mission Control, plus
  the `titleVisibility` trap `WindowProbe` documents), and adding one alongside
  gives two titles. So the field AppKit already made is re-fonted instead, which
  keeps a title a title. Three exclusions keep it off what it shouldn't touch:
  **search fields** (`NSSearchField` is an `NSTextField` subclass, and the search
  field stays the system's — the same exclusion `SpellChecking` makes), the
  **Settings window** (its pane name is chrome, not content), and the **size and
  weight**, which are read off the font AppKit chose and handed straight back, so
  only the face changes. It is idempotent by comparing the resolved font to the
  one already set rather than by remembering — the fields get rebuilt, so there is
  nothing durable to mark, and assigning every tick would re-invalidate the
  titlebar continuously. One consequence of that comparison: under **Standard**
  the resolved font *is* the plain system font, so the title is left alone and
  Standard's one-storey `a` doesn't reach it. Nothing here is contractual, the
  same trade `flattenToolbarGlass()` makes; if a release draws the title another
  way, it stays on the system font.
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
  **Lists nest, and a level is relative rather than a unit of spaces.** A run of
  list lines is **one** `.list` block whatever its markers do inside it — `-`,
  `*`, `+`, `1.` and `1)` all parse the same and a bullet sub-list may sit under a
  numbered parent — because two blocks would put a paragraph's worth of space in
  the middle of one list. Depth comes from a **stack of the indents already
  open** (`nestingLevel(for:in:)`): a wider indent than the top opens a level, a
  narrower one closes every level it has left. That is what lets two-space and
  four-space indentation both mean one level down, which is the requirement —
  dividing a column count by a fixed unit can't, since four spaces is level 1
  under one convention and level 2 under the other, and the source alone never
  says which. It also means indentation the author didn't line up still reads by
  relative depth. A tab counts as four columns. On screen a level is the **marker
  column** (dot plus its gap), so a child's bullet lands under the first character
  of its parent's text; it is deliberately not a count of the source's spaces,
  which would make the same list step differently depending on how it was typed.
  Numbers are per level — a sub-list restarts at 1, its parent resumes — and a
  bullet takes no number and *resets* the level it sits at, so a numbered run
  interrupted by a bullet sibling starts over instead of silently skipping.
  Source numbers are still ignored (`1. 1. 1.` renders 1, 2, 3, as Markdown does).
  Return already carried the indent (`LineMarker`), so typing a sub-list worked
  before it rendered as one. Pinned by `MarkdownParserTests`.
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
- **Tab walks an open card's fields — except out of the body, where Tab is a
  tab.** From the title, Tab (or ⇧Tab) moves to the body. From the **body**, ⇧Tab
  moves back to the title and **Tab inserts a literal tab character**, which is
  the text view's own behaviour left alone. The asymmetry is the point and was
  asked for: a body is prose, where an indent is something you type, while a
  title is a field in a form you page through. It also means ⇧Tab is the *only*
  key that leaves the body, which is why that one has to be answered.
  The title side is an `onTab` on `ProjectMentionField`'s existing monitor,
  firing only with the dropdown closed — dropdown open, Tab still means "first
  match", which stays the override. The body side was a focus-gated monitor of
  the same shape inside `MarkdownEditor` and is now an `insertBacktab(_:)`
  override on the editor's own text view (`onBacktab`, optional so an owner
  without a second field leaves the key alone), with `insertTab(_:)` left to
  `super` — answered where the key lands rather than intercepted before it. The
  hook was called `onTab` and fired for both directions; the rename is what keeps
  the two from being confused again.
  **On a list item, Tab sets the item's level instead** — `* ` on a fresh line
  plus Tab is `  * `, two spaces inserted at the **start of the line** rather than
  a tab at the caret, so an item already one level in goes to two rather than
  growing a gap after its marker. Two spaces because that is the smaller of the
  conventions `MarkdownParser` reads, and it counts levels relative to the indents
  already open, so it needs no agreement about the unit. **Anywhere on the line
  counts**, which is Obsidian's rule and so this app's (the same reason
  `continueList` follows it): where the caret sits within an item says nothing
  about whether its author meant to nest it, and the cost — a tab cannot be typed
  inside an item's text — is accepted. Quotes are excluded, since `>` nests by
  repeating the marker and spaces in front of one change nothing the renderer
  reads. **⇧Tab is its opposite** (`listOutdent`): it takes off exactly what Tab
  put on — `indentUnit`'s spaces, or a single tab where the line was indented with
  one — and only when there is no level left to remove does ⇧Tab go back to
  meaning "leave the body" and hand focus to the title. A line indented by an odd
  number of spaces loses what there is rather than refusing, since a stray space
  left behind would keep the item nested on a level of its own. Both rules are
  pure functions over offsets beside `listReturn`, pinned the same way (including
  that Tab then ⇧Tab is a round trip at every caret position), and both edits are
  applied through the shared `MarkdownEdits.apply` — the text view, not the
  binding, which is what earns them native undo.
  **The `@project` field's key monitor has to stand down while the body has the
  keyboard**, and not doing so is what made *the first Tab in a body do nothing*.
  That monitor is gated on the field's `@FocusState`, the body is an `NSTextView`
  that takes and reports focus through AppKit, and the two can disagree — so the
  monitor claimed the Tab, called `onTab` (already in the body, nothing visible
  happened) and swallowed it, and only the second reached the editor. It now bails
  when the first responder is a text view that is **not** a field editor, which is
  the same conclusion `MarkdownReturn` reached: the first responder is the truth.
  A field editor doesn't disqualify, since that is this field or another one.
  **The editor also has to say what a tab is worth**, or the key looks broken in a
  second way: an `NSTextView` arrives with twelve tab stops 28pt apart and a
  `defaultTabInterval` of **0**, so past the twelfth stop there is no next one and
  the layout manager hands the tab the rest of the line — the caret lands on the
  line below, and a tab at the end of a long line reads as having inserted a
  newline too. `applyTabStops` clears the stops and sets the interval to **four
  spaces measured in the editor's font**: four because that is what a tab means in
  the file (`MarkdownParser` counts one as four columns when working out a
  sub-list's depth), and measured rather than written down so a serif or
  monospaced card steps by its own four spaces. It is re-applied whenever the font
  changes.
  **The two directions are not symmetrical, and that is the finding.** Body →
  title is a plain `@FocusState` pair (`bodyFocused = false; titleFocused = true`),
  written directly rather than through `focusForEntry()`'s deferred turn, and it
  has always worked — the body is an `NSTextView` of ours, so
  `MarkdownTextViewBridge` reports its own resignation back out. Title → body
  through the same mechanism **never landed**: the caret went nowhere and the
  title kept focus. Three things were tried and are recorded so they aren't tried
  again: setting `bodyFocused = true` alone; clearing `titleFocused` first so the
  pair reads as one exclusive choice; and deferring the arriving write by a
  main-actor turn. All three left the title focused.
  So the handoff is made in **AppKit** — `CardFocus.moveToEditorBesideCurrentField()`
  makes the card's editor first responder, and the editor reports the change back
  into `bodyFocused`, so SwiftUI's state still ends up right. It is the conclusion
  Return, Esc and Tab-in-the-body had already reached in that file, and the one
  `SpellChecking` and the window title reached: when SwiftUI won't say it, say it
  to AppKit. The `@FocusState` pair stays as the fallback for a hierarchy the walk
  can't read.
  Two details in that walk. It starts from the **field editor's delegate**,
  because a focused `TextField` makes the window's shared field editor first
  responder rather than the field itself, and the field is what's in the view
  tree. And it climbs to the first ancestor holding **exactly one**
  `MarkdownTextView` — that ancestor is the card; more than one means it has
  climbed past the card into the column (a note card and a task card can both be
  open at once), so it stops rather than guessing.
  What is **known** here is only the behaviour: the key reaches the handler (Esc
  from the same field, through the same monitor, leaves edit mode), the body → title
  direction works, and title → body did not through any `@FocusState` spelling.
  *Why* the write is dropped was never instrumented — don't repeat a mechanism for
  it as fact.
- **Spelling is marked, never corrected — and the body editor is an
  `NSTextView` because of it.** Settings → General → "Check spelling while
  typing" (on by default) underlines misspellings in a card's **title and
  body**, notes and tasks alike; corrections come from the text view's own
  Control-click menu, where they're accepted deliberately. Grammar checking,
  automatic spelling correction, smart quotes, smart dashes, completion
  and link detection are all refused **by name**, because a bare `NSTextView`
  arrives with them *on* (measured) and these are Markdown files Obsidian also
  opens: a substitution made on the user's behalf is a write to someone's note,
  and `--` has no business becoming an en dash in a file.
  **macOS text replacement is the exception, and it is on** — it was refused with
  the rest until August 2026, when it was reported as "keyboard shortcuts not
  working", which is exactly what it looks like from outside. The line is *who
  decided*: the refused ones are macOS deciding that what someone typed isn't what
  they meant, where the replacement table is one the user wrote themselves in
  System Settings and fires only on the exact strings they put in it — typing
  `->` and getting `→` works in every other app on the Mac. It is set in **both**
  places a card is typed into: `MarkdownTextViewBridge.makeNSView` for the body,
  and `SpellChecking.apply` for the titles, where it has to be written rather than
  left to the default because the window's field editor is shared and arrives
  carrying whatever the last field it served was given.
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
  (`ProjectMentionField`) with no text view of its own: it borrows the window's one
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
  otherwise swallow it.
  **⌘Return is Esc's twin — it finishes the edit** — and it is a `keyDown(with:)`
  override rather than another `doCommandBySelector` action, because AppKit binds
  it to nothing: Return alone is `insertNewline(_:)`, and with ⌘ held there is no
  action to override. Only the first responder receives `keyDown`, so two open
  cards can't both answer. The title side is a case in `ProjectMentionField`'s
  monitor, placed **before** the dropdown's own handling, since Return alone there
  means "take the highlighted match" and ⌘Return has to mean one thing wherever it
  is pressed. Both routes call the same `onEscape` the four call sites already
  point at `exitEdit()`, so ⌘Return and Esc settle a card identically. **Return is not here**: `MarkdownReturn`'s app-wide
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
  is `ProjectMentionField` sitting a point above centre where a `Text` is centred
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
- **Colour** — `Tint` exposes colours by *role*, not by shade: `deep` is a fill
  that carries white type (≥4.5:1), `ink` is a foreground for text and glyphs on
  the app's own surfaces (≥4.5:1, re-solved against every theme's card faces), and
  `accent` is **decorative and held to no floor** — the app's one dot colour, worn
  by project chips, the tasks track's Pending and Done dots, the Settings type
  swatches and a note type's mark and filter dot. (A `marker` role — the note
  title's highlighter band, blended from `accent` — was added by the refresh and
  left with the stroke it drew.) A note type uses **two** of the three: `accent`
  for its graphics, `ink` for its label, both shared by every theme (see the Theme
  bullet). Keeping `accent` unsolved is deliberate: a dot always sits beside the
  name of what it marks, so the text carries the contrast and the colour is the
  second voice. `deep` and `ink` are separate because they invert
  relative to each other in Dark Mode — don't collapse them back into one
  "deep". Both adapt to Light/Dark and Increase Contrast through one dynamic
  `NSColor`, so call sites stay plain `Color`. **Within the tint family,
  selection is a filled pill, never an outline**: `deep` and `chip` share a
  hue, so a border drawn from one against the other can't reach the 3:1 an
  indicator needs in both appearances at any opacity. The refresh's pickers do
  use outline rings, and that isn't the same case — the `AccentColor` ring sits
  on *neutral* ground (a Form row, `Stone.chip`), where it can carry it.
  The refresh added two more solved colours with one job each:
  `Semantic.overdue` (the only red, ≥4.5:1 on every theme's card faces, both
  modes — re-measured whenever the card faces change, which the sourced set's two
  off-white papers made a live concern rather than a formality) and
  `Stone.metaText`, a
  solid grey at ~7:1 rather than `.secondary`/`.tertiary`, which are alpha
  washes landing under the refresh's 4.5:1 floor for sub-14px text. On a **card**
  that job now belongs to `AppTheme.metaText`, which is the same argument at the
  page's own hue; `Stone.metaText` stayed for the neutral surfaces, which today
  means the `@project` dropdown. The interactive colour is
  `AppTheme.primary`, threaded app-wide with `.tint()` from `InsertApp` and read
  directly (inside view bodies, so the `@Observable` access registers) by
  `AccentButtonStyle`, the pickers' rings, the task checkbox, the tasks column's
  active date pill, the `@project` dropdown's highlight and the editor's caret —
  the six places that need the value rather than the environment, because
  `Color.accentColor` reads the *app/system* accent and ignores `.tint()`.
  Project and type colour never
  appears on a card except as a **dot** or the type's mark; metadata is grey; red
  means overdue and nothing else.
- **Appearance** — Settings → Appearance leads with an Auto / Light / Dark picker,
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
- **Theme** — Settings → Appearance offers six, in this order: **System** (the
  platform's own greys, and `systemBlue` deepened), **Tokyo Night**
  (indigo-slate grounds, mint action), **Kanagawa** (warm cream on cold ink —
  Wave in Dark, Lotus in Light — orange action, and the set's one warm theme),
  **Dark Owl** (teal-navy, violet action, spring-green links), **Rosé Pine**
  (plum and rose; Dawn is pink-cream paper) and **Dracula**.
  **Five of the six are sourced palettes**, read from the upstream project rather
  than designed here, and that is this cut's whole argument rather than a
  shortcut: a set of authored hues has nothing to be faithful to, which is why
  the previous six still read as a preference (see the theme-system bullet's
  third-cut paragraph). What we changed is stated per theme in `AppTheme`:
  **verbatim** grounds, card edges, links and accents; **deepened** where an
  accent's label couldn't clear 4.5:1 (Kanagawa's Lotus orange, Rosé Pine's Dawn
  `love`); **derived** where a palette's comment grey failed on a card or where it
  publishes no light half at all (Tokyo Night's light foregrounds, Dark Owl's
  entire light mode); **desaturated** in exactly one place — Kanagawa's Lotus
  grounds, whose published band is 0.060 C, more than twice any other band in the
  set, and which read as a khaki slab rather than as warm paper, so its three light
  grounds keep Lotus's hue and lightness at **half its chroma**. (The fifth kind of
  change, re-levelling each palette's four note-type hues, went with the per-theme
  type palettes — see below.)
  **Declaration order is the picker's order, and the default is the first case
  again** — System leads and System is the default, where the previous set had
  those as two deliberately different things. Pinned by
  `testSystemLeadsThePickerAndIsTheDefault`, since reordering the enum for any
  other reason would silently move both.
  **System is written down rather than read from semantic tokens, and that was
  measured.** The plan asks for the tokens themselves, on the sound ground that
  they resolve per appearance and contrast setting; the obstacle is that its names
  are UIKit's (`systemGroupedBackground`, `systemGray5`) and the AppKit pair that
  would stand in for page and card — `windowBackgroundColor` and
  `controlBackgroundColor` — resolve to **the same value** on macOS 26 (`#ffffff`
  Light, `#1e1e1e` Dark), so a card would vanish into the page it is meant to sit
  forward of. macOS has no token for the numbered greys either, and the band's
  derived tones have to be composited against a concrete band. So System's grounds
  are written down (page **white** / true black, card white / `#1C1C1E`, band
  `#F2F2F7` / `#2C2C2E`) and its blues are `systemBlue` deepened,
  since as shipped it is ~4.0:1 under a white label. The writing is still the
  platform's, through `labelColor`, which is what five of the six hand back anyway.
  Its Light half is a **white page under a grey band** — the grouped ladder with its
  two lightest steps swapped, since `windowBackgroundColor` really does resolve to
  `#ffffff` in Light on macOS 26, so the sheet under the cards is white and the band
  is the grey the page used to be. One consequence is deliberate and is System's
  alone: **its light card *is* its page**, both pure white, so the card's hairline is
  the whole separation — which is how a stack of white cards on white paper reads in
  the platform's own apps. `testEveryCardSitsForwardOfItsPage` names that exception
  and asserts it as an equality, so a value drifting off white in *either* of the two
  still fails.
  Each theme has a Light and a Dark value and follows the Mode picker with nothing
  to re-apply, through the same dynamic `NSColor` trick `Tint` uses. The row label is
  **"Theme"** and the Auto/Light/Dark control above it is labelled **"Mode"** — a
  collision resolved twice over: first "Theme" against "Appearance", since the two
  would otherwise both answer to "theme", and then "Appearance" against the pane and
  sidebar row of that name (see the Settings-panes bullet). **Neither row carries a
  section header**: each row's own label names its control, and a header would print
  the same word directly above itself.
  **A theme is three grounds, one accent and a palette, and each of the three is
  load-bearing.** The *band* is `ColumnHeaderBand`; the *page* is `windowFill`
  (and so the sidebar, which is see-through to it); the *card* is `cardFace` —
  **no longer pure white in Light for all six**, which reverses the previous set's
  rule: Kanagawa's cards are Lotus cream (`#fffdf0`) and Rosé Pine's are Dawn's
  `surface` (`#fffaf3`), because a sourced palette's paper is part of what it is.
  The cost is real and is accepted: body-text contrast can no longer be verified
  once against white, so every value that lands on a card is measured against the
  face **actually painted** (the refresh's third contrast rule), and
  `testOnlyTheTwoSourcedPapersAreOffWhiteInLight` keeps the exception at two
  themes rather than letting it spread. The accent is `primary`, for interactive
  and selected state only. Note-type colour is **not** among a theme's values —
  see below.
  A band is **thirteen tones per appearance** and nine are the palette's; the four
  that make the filter track are *derived from the band's hue*, which is what
  keeps adding a theme a matter of bringing a palette rather than designing one:
  the dark track is white at 10% over the band (composited offline to an opaque
  value, so nothing layers alpha at draw time), the light track is the hue at
  92% L, the segment labels at 87% L dark / 42% L light, and the raised pill at
  93% L or pure white. The selected segment's label is the band's **text** in
  Light, where the pill is white, and the band's own **fill** in Dark, where the
  pill is near-white and the label reads as the band inverted — either way it is a
  value that was already solved.
  **The count chip carries a second hue from the palette, not the accent**, and it
  has been three things. White at 12% was a value with no opinion and left the one
  number in the band reading as chrome. The **accent** at low alpha over the band,
  composited offline under a legible tint of itself, fixed that on paper and not on
  screen: composited into a *pale* band it lands above `L` 0.90 in every light
  theme, so the chip was a wash of the button beside it and still read as chrome —
  while Dracula's, which was never a wash, read as the theme. So all five sourced
  themes now do what Dracula does: a **vivid** hue read from the palette — Tokyo
  Night's `blue` `#7aa2f7`, Kanagawa's `springGreen` `#98bb6c`, Dark Owl's coral
  `#f78c6c`, Rosé Pine's `gold` `#f6c177`, Dracula's pink `#ff79c6` — and never the
  accent, since the button owns that and repeating it is what made the wash look
  like chrome. **The hue swaps roles per appearance**, because it can't carry both:
  the chip's *fill* in Light, and the numeral itself in Dark, on that hue at 20% over
  the band — lightened in-hue only where the floor needs it, which is Tokyo Night's
  blue and Kanagawa's green. Dracula's dark fill is the one that is *recessed below*
  its band rather than tinted above it, which is its own value and kept.
  **The light numeral is white, and the fill is deepened to carry it**, by request:
  the bright hue under a near-black numeral was the first cut and read muddy. White
  needs the fill at `L` ≈ 0.55 or below to clear 4.5:1, so each is the palette's own
  deep member of that hue where it publishes one (Tokyo Night's `blue0` `#3d59a1`,
  verbatim) and the hue deepened in oklch at constant chroma and hue where it doesn't
  (Kanagawa's `lotusGreen` → `#637c42`, Dark Owl's coral → `#bb5638`, Rosé Pine's
  `gold` → `#9b6b1a`, Dracula's pink → `#b02a72`). It is the "deepen and invert to
  white-on-deep" move Kanagawa's and Rosé Pine's *buttons* already make, spent on
  the chip; the cost is that a light chip reads heavier than the bright pill it
  replaced, and that was the trade asked for. **System keeps a neutral chip** — a
  theme whose whole claim is that it adds no colour of its own cannot spend one here.
  All of it is measured on the **composited** value rather than on the raw fill,
  which is the check that caught the most defects in design, and
  `testEverySourcedChipIsAPaletteHueThatSwapsRolesBetweenAppearances` pins both
  halves — the hue angle on each side of the swap, the white numeral, and a
  **lightness ceiling** on the light fill, since a fill drifting lighter takes the
  white numeral under the floor one theme at a time.
  The rule for a seventh theme is therefore "bring a palette, don't author one":
  take the band, its text, the hairline, the grounds, the accent and the chip's hue
  from the source — the chip's being a *second* palette colour, never the accent;
  derive the track and the raised segment from the band's hue by the rules above; hold the accent to 4.5:1 under its label in both appearances — if
  it can't, deepen it and invert to white-on-deep, which is what Kanagawa's Lotus
  orange and Rosé Pine's Dawn `love` do; and regenerate the whole table rather
  than nudging one entry. Every theme's worst *text* pairing, either appearance,
  clears the **4.5:1** floor — Dracula's own named metadata value at 4.52:1 is the
  tightest in the file — measured across eight pairings each: band text on the
  band, count text on the count chip, primary label on the primary fill, an
  unselected segment label on the track, a selected one on the raised pill, the
  metadata colour on the card, a link on the card, and each type label on the
  card. Graphics — the marks, the dots and the selection ring — are held to 3:1
  and clear it (worst 3.03:1, and the three values stepped to get there are named
  where they are declared). `Semantic.overdue` is re-measured on all six card
  faces, which matters more now that two of them aren't white. All of it runs, in
  `ThemePaletteTests`, resolved through the dynamic `NSColor` under an explicit
  `NSAppearance`, because the table is data that can only be wrong quietly.
  **A note type's colour is not a theme value, and two rules went with that.** For
  one release each theme authored four type hues — kept 25° clear of its own accent,
  re-levelled into a greyscale ladder, mark and label a few points apart — and it
  was reversed by the maintainer on sight: *"the notes colours are off in all
  themes; the ones for tasks stay vibrant and crisp."* A type wears the app's own
  tint again, one palette for all six — **`accent` for its two graphics** (the
  capsule mark, the filter dot) and **`ink` for the label**, which is the split
  `Tint` is built around and what it was before the theme system existed. The first
  pass at the reversal used `ink` for all three and was itself reversed on sight
  (*"the tones in the settings are nice, but the ones shown in the UI not"*): every
  other dot in the window — project chips, the tasks track's Pending and Done, the
  type swatches in Settings — is `accent`, so a type's dot in the deeper value read
  as muted beside them. The trade, in full, because two acceptance criteria are gone
  with it:
  - What the per-theme palettes bought was hues tuned to each band, at 6 × 4 × 2
    authored values. What they cost was more: the four types are the *same four*
    whatever theme is on, so a user learning "blue is a Note" shouldn't have them
    shift under a colour preference — and tuned to sit quietly beside a band, they
    read **muted** against the rest of the app's colour, which is how it was
    reported.
  - **The 25° rule can't hold** with one palette against six accents, and two
    themes break it: Dark Owl's violet and Dracula's lavender are both within a
    couple of degrees of the purple a Feedback note wears. What the rule was for —
    "action" reading as action — is carried instead by the accent being the only
    thing that *fills* a pill, and by nothing on a card wearing it.
  - **The greyscale ladder goes too.** The app's four tints don't form one, and
    levelling them apart would mean re-authoring the palette the whole app shares
    to fix one card's meta row. The mono label spells the type out beside its mark,
    which is what the ladder was insurance for.
  What stays is the half that fails silently, and it got **stricter**: the label's
  value is measured against **every theme's** card face, in both appearances and
  across all nine tints, since types are user-extensible. That re-solve moved four of
  `Tint.ink`'s base values and eight of its Increase Contrast ones, a few points of
  lightness each at the same hue — a themed dark card is *lighter* than the flat
  near-black island `ink` was first solved on, which is what had taken dark purple
  under the floor. Worst pairing now 4.65:1 on a card.
  The **graphics are deliberately not measured**, which is the other half and the
  one to state plainly: `accent` is bright, and yellow lands at 1.28:1 as a dot on
  Dracula's light track — under the 3:1 a *required* graphic answers to. Nothing here
  is required: a dot and a mark always sit beside the name of the type they mark, so
  the colour is a second voice and the text carries the floor. What the tests pin
  instead is that the graphics really are `accent` and that `accent` stays brighter
  than `ink`, since the moment it isn't, the two roles have no reason to exist.
  **A theme sets exactly two text colours, and Dracula is the exception**:
  `metaText` — each palette's own comment grey where it clears 4.5:1 on the card,
  derived from the page's hue where it doesn't, for timestamps, chip names, the
  resting due badge and the `···` menu, with an Increase Contrast pair stepping to
  ≥7:1 — and `link`, below. `titleText` and `bodyText` exist, and in five of the
  six themes they are **`labelColor`** — unthemed, full contrast, the system's
  business. That is the rule, not an omission, and it is the one place this set
  deliberately **declines** a sourced value: all five palettes publish a title and
  a body, and the title and the body are the writing, read at length, so their
  contrast should not become a function of a colour preference. Metadata is
  different in kind, already quiet, and a tinted grey is what makes it read as
  part of the theme. **Dracula keeps all three**, because it is a text palette by
  origin — `#f8f8f2` / `#cfd2e0` / `#9098b8` dark, `#2c2145` / `#463d63` /
  `#6b6288` light, its body deliberately a step softer than its title, and no
  Increase Contrast variants needed since the softest of them is already 8.6:1.
  Its metadata is also the **tightest text pairing in the file** — 4.52:1 in Dark
  — so it clears the floor with nothing to spare, and a card face nudged lighter
  would take it under.
  `testTitleAndBodyAreUnthemedExceptInDracula` is what keeps "text is not themed"
  true, since the tempting next step from a themed metadata colour is a themed
  body and nothing on screen would announce it.
  **A link in a card's body is themed too**, and it had to be: SwiftUI draws a
  link in the environment's **tint**, so without a value of its own a link
  inherited the app-wide tint — which is `primary`, i.e. a lavender at 2.4:1 or a
  mint at 1.7:1 on a white card. `MarkdownText` applies `theme.link` as a
  `.tint()` on the render and on the collapsed teaser. Verbatim from the palette
  in Dark; deepened or derived in Light, where two of them publish a value that
  can't sit on paper (Dark Owl's `#00ff9f` is **1.4:1** on white) and Kanagawa
  publishes none for Lotus at all.
  The **`ring`** follows the accent, and the previous set's rule that a ring must
  differ from the button beside it is **gone** — only contrast moves it now. Two
  of the departures are the palettes' own (Tokyo Night's deepened jade in Light,
  Dark Owl's lifted violet in Dark); the one solved here is Dracula's light ring,
  because the table repeats the lavender and on white that is 2.41:1, under the
  3:1 an indicator needs.
  A type's colours come from its **`Tint`**, which is what makes it work with a
  user-extensible list: every one of the nine tints has both roles, so a custom type is
  no more of a special case than a default one. (The per-theme table was keyed by
  tint too, for the same reason, and it still had to name `Tint.ink` as the
  fallback for the five tints no theme authored.)
  The edit-mode type dropdown uses a third role, `Tint.deep`, and that is a floor
  rather than an inconsistency: it is a *fill* under white type, which neither
  `accent` nor `ink` is solved for.
  **Dracula is unchanged in structure, and is the theme the other five were built
  to match** — it was the only one of the first cut that read as an identity, which
  is the observation the whole sourced-palette set came from. It brings its own
  grounds (`#282a36` / `#2f313f` dark, `#faf7ff` / white light), because a Dracula
  that keeps the app's white card is not
  Dracula; it ships in **both** appearances by request, though it is dark-first by
  origin. Its three changes here are the **pink/purple swap** — the accent is the
  lavender and Feedback takes the pink `#ff79c6`, because with Rosé Pine
  in the set a rose-pink button on a plum ground made two themes read as the same
  idea; the **count chip** described above, whose construction the other five
  have since adopted with hues of their own; and the accent **deepened to
  `#8359ba` in both appearances so its button label can be white**, by request —
  `#bd93f9` is 2.41:1 under white and wore a dark plum label until then. It is the
  one accent in the set deepened for the *label's* sake rather than because a ground
  demanded it, and the cost is that the button is no longer the palette's bright
  purple; the `ring` still is in Dark, which is where that lavender survives. Its light type values are the
  palette darkened in oklch until each clears its floor on white, since the
  published light ones land at 4.1–4.3:1: fine for a capsule, short for the label
  beside it.
  Two themes reorder which colour a **new** project is auto-assigned
  (`AppTheme.projectTintOrder`): Dracula leads with red/yellow/cyan/purple/orange,
  and Kanagawa pushes orange **last**, which is its "the only orange on screen is
  the button" rule reaching the dots as the plan asks. Both orders stay total, so
  a tenth project still gets a colour — a demotion, not a removal. Only the
  auto-assignment: a colour the user picked is data, in `Projects.md`, and
  switching theme must never rewrite it.
  **The Settings swatch shows one half — the appearance in effect** — drawn with
  the same dynamic `band.fill` and `band.primary` the window uses, so the swatch
  and the band can't disagree. Stacking the light and dark halves in one swatch
  was tried and reversed on sight: the argument for it (a theme carries both
  values, so previewing one hides half the choice) is real, but at 74pt wide two
  22pt slabs read as two slabs rather than as one preview. The footer caption
  carries that information instead — "Light and dark values are built in —
  Mode decides which you see" — which is a sentence doing a job no small
  rectangle could. Three columns, not six across: below about 46pt a swatch stops
  previewing anything, which is the line the seven-swatch tint picker had already
  hit.
  Two things are easy to get wrong. The window style is applied
  **unconditionally**, because branching on it in the view builder gives the two
  cases different identities and tears down `NavigationSplitView` — and with it
  the autosaved column widths — on every change of the picker. And if the sidebar
  is ever given a wash of the band's hue on top of the page ground, its layer
  needs its **own** `.ignoresSafeArea()`: the sidebar's content ignores the top
  safe area so the header can sit level with the traffic lights, but a background
  layer doesn't inherit that, so it starts below the toolbar inset and leaves the
  titlebar band one layer short — a hard seam under the traffic lights, reading as
  two stacked panels. Any `if` around such a layer sits *inside* the
  `.background { }` builder, for the identity reason above.

  `.island()` is the **theme's card ground** — white in Light for four of the six
  and the palette's own paper in Kanagawa and Rosé Pine, the theme's own dark card
  in Dark, opaque, with the theme's own hairline
  (`Stone`'s warm wash over a tinted card reads as a smudge rather than an edge).
  Its `tint:` parameter (a translucent wash over an opaque base, the layering the
  gradients forced) left with the last thing using it, the "Color tasks by due
  date" wash — see the refresh bullet. Colour still never arrives on a card as a
  *type* wash; what changed is that the paper itself belongs to the theme.
  `Stone.surface` survives only on the column divider's handle, and
  `Stone.metaText` only in the `@project` dropdown, which is a floating control
  rather than a card.
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
  controls take it: a transient floating control, the `@project` autocomplete
  dropdown — the exception HIG allows — and the **`SegmentedFilter` indicator**,
  the refresh's one new glass surface: the moving selection pill refracts the
  track and the band under it and travels on the platform spring, with Reduce
  Transparency swapping in the band's own opaque raised pill and Reduce Motion
  cutting the travel. The band is what finally makes that glass worth having —
  an indicator refracts what is *under* it, and under a neutral panel there was
  nothing to refract, which is why the track and both label states now come from
  `BandColors` rather than `Stone`, each solved against the band actually painted
  behind them. (The projects sidebar *was* the third glass surface — glass over
  the gradient — and gave it up with the gradients; a flat colour has nothing to
  refract. AppKit's own sidebar material is still there, and is the system's, not
  ours.) Those plus
  the toolbar's search field are the window's glass surfaces, and they're meant
  to read as the same material; don't give one of them a `Material` and call it
  close enough.
  **Primary buttons are colour pills again** (`AccentButtonStyle`), and that is
  a deliberate reversal with its history attached: "New Note" / "New Task" once
  wore `.glassProminent`, gave it up because the *system* accent belonged to
  nothing in the design and fought the gradients, then wore the flat neutral
  capsule with a semibold label. The colour came back by becoming
  the design's own — now `AppTheme.primary`, one filled pill per column, solved
  against the band it sits on —
  while keeping both standing objections honoured: it's flat (glass casts a
  drop shadow; see "No shadows"), and one prominent control per surface is
  still the ration. `.glassProminent` survives only on each popover's confirm
  button, which `.tint()` now paints in the theme's primary rather than system
  blue.
- **No shadows, anywhere.** Not a gap: the window is deliberately flat, the look it
  wears when it goes inactive and every glass surface settles down, which is the
  look it's tuned for. Separation is a **hairline** (`Stone.line`) plus, on glass,
  the material's own refraction — that's what `.island()` swapped its shadow for and
  what the `@project` dropdown and the column-divider handle now use too. There is
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
  `AppDelegate.flattenToolbarGlass()`, the first of the four places in the app that
  reach past the
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

- Pure native, **no third-party *code*** — system frameworks only, no package
  manager, no build step beyond `build.sh`. The two bundled OFL font files are
  the sole exception and a knowing one (see the Typeface bullet); they are data,
  not dependencies.
- Shared state is `@MainActor @Observable` (`Library`, `AppState`, `SettingsStore`),
  created once in `InsertApp` and injected via `.environment(…)`; views read them
  with `@Environment(Type.self)`.
- Settings persist to `UserDefaults`; notes/tasks/projects persist to Markdown.
- Swift 6 strict concurrency: no shared non-Sendable globals (date formatters are
  built per-call; the FS watcher confines its state to a serial queue).
