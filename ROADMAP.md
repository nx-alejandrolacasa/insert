# Roadmap

Five features, in the order they'll be built. Each entry records the
interaction decisions already settled, so planning starts from these rather
than reopening them. What was considered and cut is at the bottom — those are
decisions too.

## 1. Keyboard-first navigation

Moved to the top because it already chafes in daily use. The triggering case:
writing in a note's body, there is no key that moves focus back to the title
above it — reaching for the mouse mid-sentence is exactly what this feature
exists to remove. (The key reached for was ⌘Tab, which belongs to the system
app switcher and can never reach Insert — so part of the job is picking
bindings that are actually available. Tab/⇧Tab between an open card's fields
is the natural pair.)

Scope, roughly inside-out:

- **Inside an open card**: Tab/⇧Tab move between its fields (title ↔ body).
  This is the first deliverable, since it's the reported pain.
- **Between cards**: arrows move focus through the list, Return opens the
  focused card for editing, Esc closes it (already does), a shortcut ticks
  the focused task.
- **Between columns**: projects ↔ notes ↔ tasks need a key too.

To resolve in planning: most of it — this one is a spec problem before it is a
code problem. The constraint that shapes it: focus is currently click-driven
and deferred by a turn (see "Focus on entry" in CLAUDE.md), so keyboard focus
must go through the same paths, not around them.

## 2. Quick capture

A global hotkey opens a small floating panel from anywhere — type the thought,
Return files it, the panel vanishes. It captures **tasks and notes both**: the
panel opens in task mode and **Tab flips it to note mode and back**, so what
the entry becomes is decided on the way, not before the panel opens. Esc
closes without saving. `#project` assigns projects exactly as the tasks panel
does; nothing else about the entry is asked for — refinement happens in the
main window later, capture is for getting things down.

Settled:

- Tab switches mode. While the `#` autocomplete is open, Tab already means
  "accept the first match" (`ProjectHashField`), and that wins — mode-switch
  Tab is the fallback, never the override. If Tab proves unreachable in some
  state, we find another key, not another design.
- The panel is the transient floating control HIG allows Liquid Glass for —
  the `#project` dropdown's exception, one size up.

To resolve in planning: the hotkey mechanism (no third-party dependencies, so
Carbon `RegisterEventHotKey` is the likely system route), whether the hotkey
is a fixed picker of combos in Settings (the `ReminderSchedule.slots` shape)
rather than a free-form recorder, and how note mode splits title from body.

## 3. Wiki links + backlinks

Typing `@` in any Markdown body opens a note autocomplete; picking a note
inserts a link, written to disk as an Obsidian `[[Title]]` wiki link so the
files stay honest Obsidian. **Esc dismisses the autocomplete and the `@`
stays a plain character** — the trigger must never steal the symbol. The same
dismissal contract applies to the `#` project autocomplete. Cards grow a
"Linked from…" backlinks footer.

To resolve in planning: how links resolve (by title, and what a rename does),
what clicking a rendered link does (select that note, presumably), and whether
the autocomplete is `ProjectHashField` generalised or a sibling.

## 4. Templates

A new note opens pre-filled from its type's template — a Meeting note with the
agenda skeleton, Feedback with its shape. Templates are Markdown files under
the root (`Templates/`), editable in Obsidian like everything else; a type
with no template file behaves exactly as today.

To resolve in planning: the naming convention (per note-type), whether
Settings → Note Types edits templates in-app or just reveals the folder, and
what a template can parameterise (probably nothing — a template is a body, not
a language).

## 5. Zen mode

One note, nothing else. From an open note, a shortcut (and a ⋯ menu entry, so
it's discoverable) takes that note full-window: sidebar, tasks column, filter
rows and headers fall away, leaving title and editor in a centred column at a
readable measure, over whatever backdrop and card face are already set — the
writing atmosphere is theirs to provide, Zen mode just clears the room. Esc
returns to the three columns with the note still open and the caret kept.

Settled:

- A mode of the main window, not a second window — nothing new to manage, and
  the autosaved layout underneath must survive it untouched (the
  `_ConditionalContent` / split-view-identity traps CLAUDE.md documents apply
  in full: the mode overlays or restyles, it must not tear down the
  `NavigationSplitView`).
- Any knobs it grows (column measure, hiding the toolbar) live in Settings →
  Notes; the mode itself is entered per note, not switched on globally.

To resolve in planning: the shortcut, what of the card survives beyond title +
body (chips? footer? probably neither), and whether the toolbar/titlebar hides
with the columns.

## Considered and cut

- **Spotlight / CoreSpotlight indexing** — the author lives in Raycast and the
  app is mostly for the author; system-search integration solves a problem
  this install doesn't have.
- **On-device Foundation Models features** — fits *private* perfectly, but
  Apple Intelligence is MDM-blocked on the development machine, so nothing
  could be run or tested. Parked, not rejected.
