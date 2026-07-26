<div align="center">
  <img src="assets/AppIcon-1024.png" width="180" alt="Insert app icon">
  <h1>Insert</h1>
  <p>A calm, native macOS app for your projects, notes and tasks — stored as plain Markdown.</p>
</div>

---

**Insert** is a three-column macOS app (macOS 26, SwiftUI, Liquid Glass):

- **Projects** on the left — your projects and topics, each with an emoji and a live `X notes · Y tasks` count. Sort by latest-used or A–Z, add/rename/delete.
- **Notes** in the middle — shown as scrollable "islands", each with a title, emoji and a Markdown body. Pick a type (Note, Meeting, Feedback, Staffing… or your own) with colored pills. Sort by created/updated and filter by type.
- **Tasks** on the right — tick them off, give them due dates, and tag one or more projects by typing `#`. Filter by all / pending / done.

The search field in the toolbar filters all three columns at once, and hiding the
sidebar gives notes and tasks half the window each.

A **menu-bar item** shows your pending tasks at a glance — a short "past · today · upcoming" summary, grouped into Overdue / Today / Up Next / Unscheduled — and lets you tick tasks off without opening the app.

Everything is saved as **plain Markdown** in a folder you choose, so your data stays yours and stays editable anywhere.

## Build & run

Requires macOS 26 with the Xcode Command Line Tools.

```sh
./build.sh run        # build and launch build/Insert.app
./build.sh install    # install into /Applications
```

See [CLAUDE.md](CLAUDE.md) for the full layout, data format, and conventions.

## Storage layout

```
~/Documents/Insert/         (changeable in Settings → Storage)
  Notes/       one Markdown file per note
  Tasks/       one Markdown file per task
  Projects.md  the list of projects
```

Notes and tasks carry their metadata in a small YAML frontmatter block and their
content as Markdown — open the folder in any editor and everything just works.

## Shortcuts

- **⌘ + (key left of 1)** — show / hide the projects sidebar
- **⌘N** — new note · **⌘T** — new task · **⇧⌘N** — new project
- Type **`#`** in a task to tag a project (Tab picks the first match)

---

© 2026 Alejandro G. Lacasa.
