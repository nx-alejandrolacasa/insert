# Handoff: Insert — visual refresh (surfaces, note type signal, controls)

## Overview

Insert is an existing native macOS app: a three-column projects / notes / tasks window plus a
Settings window. This handoff covers a **visual refresh only**. No features are added, no
information architecture changes, no new screens.

Four things change:

1. The six background **gradients** behind the main window become a set of **flat tints**.
2. Note type stops being a full-bleed card wash and becomes a **marker stroke on the title** plus a
   small-caps type label in the meta row.
3. Metadata colour is quieted, accent colour is unified, and **all controls become pill-shaped**.
4. Filters become a **segmented control**, to be implemented with native glass material (see
   "Filters: glass segmented control" — this is the one part not yet designed).

---

## ⚠️ Scope and guardrails — read before writing code

This is the most important section. The HTML references were produced in a review conversation, and
**only the decisions listed in "Decision log" were actually agreed**. Everything else in the HTML is
incidental scaffolding.

**Do:**

- Implement only the items in the Decision log below.
- Treat the app's existing implementation as the baseline. Where this document is silent, **keep what
  the app does today** — do not "improve" it.
- Use native platform components and materials. This is a Mac app; it should keep feeling like one.
- Ask the maintainer before resolving anything listed under "Open questions".

**Do not:**

- Do not copy the HTML's markup, class structure, CSS, or layout code. It is a mock in a different
  medium; a literal port will not feel native.
- Do not restyle anything not named here — in particular: the window chrome, the toolbar, the search
  field's behaviour, the task checkboxes, the task list layout, the note editor, the Settings window's
  structure or its section order, or any copy that is not quoted in this document.
- Do not add new features, tints, typefaces, accent colours, empty states, animations, icons, or
  onboarding beyond what is specified.
- Do not change the Settings sidebar's icons in this pass. The mock shows monochrome glyphs; that was
  a suggestion the maintainer has **not** signed off on. Leave the existing icons alone.
- Do not remove the project icons from the sidebar. They are wanted.
- Do not delete data-model concepts to match the mock. The mock shows a note with four projects only
  to demonstrate overflow.
- Do not treat the mock's pixel values as gospel where they conflict with platform metrics: honour
  system control heights, 44×44 pt minimum hit targets, Dynamic Type / accessibility text sizes, and
  the user's Reduce Transparency / Reduce Motion / Increase Contrast settings.

**If a proposed change looks wrong in the real app, stop and report it rather than inventing a third
option.** Several of the mock's values were already corrected once during review for contrast; expect
to need judgment calls, and surface them.

---

## About the design files

The files in this bundle are **design references created in HTML** — prototypes showing intended look
and behaviour, not production code. The task is to recreate the intent in the app's existing native
codebase (SwiftUI / AppKit) using its established patterns, not to port HTML.

Two files:

- `Insert - Neutral Direction.dc.html` — the full main window plus Settings window in the agreed
  end state. **This is the primary reference.**
- `Insert - Note Type Explorations.dc.html` — the exploration that led to the note-card decision.
  Reference only, for understanding *why*. Options 2a, 2b, 3b were **rejected**. Do not implement them.

Colours in the HTML are authored in `oklch()`. The oklch values are the source of truth; hex values in
this document are sRGB approximations for convenience.

## Fidelity

**Medium-to-high.** Colour, type hierarchy, radii and the structure of each element are intentional and
should be matched closely. Exact pixel offsets, shadow spreads and font sizes are **indicative** —
convert them to the app's existing type ramp and spacing scale and to native control metrics. The mock
is at a fixed 1700px width and is not a responsive spec.

---

## Decision log

Each row is an agreed change, with the reasoning, so you can make consistent judgment calls.

### 1. Background gradients → flat tints

- **Before:** six gradients (None, Cloud, Stone, Dawn, Dusk, Grove) behind the main window, each with a
  light and a dark version.
- **After:** `Plain` plus six **flat** tints: `Linen`, `Clay`, `Blush`, `Sage`, `Mist`, `Lilac`.
- **Why:** the gradients were legible only in the outer margins and the sidebar, and each one needed a
  light and dark variant. Flat tints mean text contrast is identical everywhere in the window, so
  contrast only has to be verified once per theme instead of per gradient region.
- The tint applies to the window's base surface and the sidebar. Cards stay pure white in light mode.
- All tints sit at the same lightness and chroma (L 97.5%, C 0.014–0.016) so switching tint never
  changes contrast. Keep that constraint if you add dark-mode values.
- Settings row label is **"Tint"** under the heading **"Background"**. Caption: *"A flat, low-chroma
  tint on the window surface — no gradient. Each one has a Light and Dark value, so it follows the
  theme above."*
- Dark-mode values are **not designed yet**. See Open questions.

### 2. Note type: marker stroke, not a card wash

- **Before:** Meeting notes had a full yellow card, Note a full blue card.
- **Rejected on the way:** a 3px coloured left rule (felt generic), a filing-tab treatment, a
  no-card "ledger" layout with a mono gutter (too space-hungry).
- **After:** card face is white. Type is expressed twice:
  - a **highlighter stroke behind the note title** — a background band covering the bottom ~34% of the
    title's line box, at 60% opacity, in the type's hue;
  - a **small-caps type label** ("MEETING", "NOTE", "STAFFING") as the first item in the meta row.
- **Why:** puts the colour where the eye already is, keeps body-text contrast constant, and stops the
  card tint fighting the chips inside it.
- The stroke sits *behind* the glyphs. Do not reduce title text contrast to accommodate it.

### 3. Meta row: type · chips · time, on one line

- Order, left to right: type label → 1px vertical hairline divider → project chips → flexible space →
  timestamp (right aligned).
- Chips are **colour dot + project name**, no icon.
- **Multi-project:** show up to **two** chips. Any beyond that collapse into one overflow chip
  containing the remaining projects' colour dots, overlapped by 9px with a 2px surface-coloured
  outline for separation, followed by `+N`.
- **Why this and not wrapping chips onto their own line:** the maintainer expects one project per note
  most of the time, two at most, so fixed card height is worth more than showing every project. A
  wrapping variant exists in the exploration file (3b) and was rejected for the default.
- Overflow chip needs a hover/press affordance revealing the hidden project names — **not designed;
  use the platform's standard popover/tooltip.**

### 4. Colour discipline

- **One accent** (blue) for interactive and selected state only: primary buttons, selected segment,
  focus rings, selected rows.
- **Project colour** is the only other hue, and it only ever appears as a dot (sidebar aside, where the
  project's icon shows instead).
- **Metadata is grey.** Timestamps and due dates are neutral. Red appears only when a task is genuinely
  overdue ("Overdue · 4 days"). Previously all dates were orange.
- Accent is now a real user preference in Settings: **Accent → "Highlight colour"**, four swatches
  (blue, green, orange, graphite). Blue is default. Only add these four.

### 5. Contrast floor

Metadata was darkened during review to meet WCAG AA. Enforce as a rule rather than as literal values:

- text under 14px: **≥ 4.5:1** against its actual painted background;
- interactive glyphs (the `···` menu, chevrons): **≥ 4:1**;
- verify against the tinted surface, not against white.

### 6. Every control is a pill

- `border-radius: 999px` on buttons, the search field, segmented tracks and their segments, chips,
  project rows, Settings rows, the theme switch.
- **Containers keep a soft radius** (10–12px): cards, panels, the window. Rule: *round means pressable.*
- **Icons are not controls** — they keep their own shapes. (The sidebar-toggle glyph was accidentally
  turned into a pill during review and looked like a toggle switch; don't repeat that.)
- Tint swatches use a 9px radius — they are previews of a surface, not buttons.
- **Unresolved:** the four Typeface tiles are currently wide pills and read as buttons rather than type
  previews. See Open questions.

### 7. Filters → segmented control

- **Before:** a row of separate outlined chips; the active one was a dark filled pill. Read as dull and
  inconsistent with the rest of the toolbar.
- **After:** a single recessed track containing the segments, with the active segment as a raised
  light pill. Each note-type segment carries that type's colour dot, tying the filter row to the
  marker stroke on the cards. Task filters use the same construction; the active segment's dot is the
  accent colour.
- `All time ⌄` stays a **separate** button outside the track — it is a different kind of control.

---

## Filters: glass segmented control (new work, not yet designed)

This is the only item where the mock does **not** show the target. The mock's segmented control is a
flat approximation. The intent is that the filters feel like current native navigation elements —
i.e. iOS 26 / macOS Tahoe "Liquid Glass" style rather than a flat CSS pill.

**Requirements**

- Use the platform's own glass material and shape APIs (e.g. SwiftUI `glassEffect` on a capsule, glass
  button styles, or the equivalent `NSVisualEffectView` material where the SDK requires it). Do not
  hand-roll blur, gradient rims or specular highlights.
- The **moving selection indicator** is the glass element: it should travel between segments with the
  platform's default spring, refracting the track and content beneath it, rather than cross-fading
  background colours.
- The track itself is a subtle recess; it must not compete with the glass indicator.
- Segment labels stay legible over glass at every tint — verify against `Lilac` and `Mist`, which are
  the lightest, and against dark mode.
- Type dots keep their colours over glass.
- Respect **Reduce Transparency** (fall back to an opaque raised pill) and **Reduce Motion** (no travel
  animation — cut directly).
- Do not apply glass anywhere else in this pass. Cards, sidebar and settings rows stay opaque.

**Acceptance:** the filter row is indistinguishable in feel from a system segmented control in the same
OS version, at every tint, in both themes, and with Reduce Transparency on.

**Deliberately unspecified:** exact material tier, corner radii, indicator inset, animation timing —
take these from the platform defaults, not from the HTML.

---

## Screens

### 1. Main window

Three columns; unchanged structurally.

- **Sidebar (~248pt).** Header: window controls, `+`, sidebar-toggle glyph. Title "Projects" (20px/700).
  Project rows are pills: **project icon** (18pt slot, the app's existing icon per project) + name
  (14px, 600 when selected / 500 otherwise) + count line ("2 notes · 4 tasks", 11.5px, grey).
  Selected row: neutral raised fill. Sidebar carries the tint.
- **Toolbar.** Current scope label with its icon on the left; pill search field (~520pt) right-aligned,
  placeholder "Search notes, projects & tasks". Behaviour unchanged.
- **Notes column.** Heading "Notes" (21px/700) + primary pill button "+ New Note". Below it the filter
  segmented control: `All` (active), `Note`, `Meeting`, `Feedback`, `Staffing`, each with its type dot.
  Then the note cards.
- **Tasks column.** Heading "Tasks" + "+ New Task". Filter segmented control `All` / `Pending` (active,
  accent dot) / `Done`, then `All time ⌄` as a separate right-aligned button. Task cards keep their
  current construction: circular checkbox, title 15px/600, optional body, meta row of chips + due
  date. Only the colour rules from Decision 4 and 5 apply here.

**Note card anatomy** (white face, ~10px radius, hairline border, 1px ambient shadow):

1. Title row — title with marker stroke; `···` menu button right-aligned.
2. Body — the note's rendered Markdown, unchanged (headings, ordered/unordered lists, blockquote).
3. Meta row — as Decision 3.

### 2. Settings → General

Existing window and section order. Sections top to bottom: **Appearance** (Theme: Auto / Light / Dark
segmented), **Background** (Tint: Plain + six tints + caption), **Accent** (Highlight colour: four
swatches), **Typeface** (Standard / Rounded / Serif / Monospace + existing caption).

"Accent" is the one new section. Everything else keeps its current copy unless quoted above.

---

## Design tokens

Authored in oklch; hex is an sRGB approximation. Light mode only — dark values are outstanding.

**Surfaces**

| Token | oklch | ≈ hex |
| --- | --- | --- |
| Desk / behind window | `93.5% 0.016 25` | `#f0e3e0` |
| Window base (tinted) | `99% 0.004 25` | `#fdfbfb` |
| Sidebar (tinted) | `97.4% 0.009 25` | `#f8f1f0` |
| Card face | `100% 0 0` | `#ffffff` |
| Recessed track | `94.5% 0.006 25` | `#f2eceb` |
| Inset field / chip ground | `96.5% 0.005 255` | `#f4f4f5` |
| Hairline border | `90–91% 0.005 255` | `#e0e1e3` |

**Tints** (all L 97.5%, C 0.014–0.016; hue is the only variable)

| Name | Hue | ≈ hex |
| --- | --- | --- |
| Linen | 85 | `#faf6ea` |
| Clay | 45 | `#fdf3ec` |
| Blush | 25 | `#fdf2f1` |
| Sage | 145 | `#eef9f1` |
| Mist | 245 | `#eff5fd` |
| Lilac | 300 | `#f9f0fb` |

**Text**

| Role | oklch | ≈ hex |
| --- | --- | --- |
| Primary / titles | `28% 0.006 255` | `#2f3033` |
| Body | `35% 0.006 255` | `#414346` |
| Secondary / chip label | `42% 0.008 255` | `#52545a` |
| Metadata (AA floor) | `52% 0.008 255` | `#6d7076` |
| Glyph controls (`···`) | `58% 0.008 255` | `#7d8085` |

**Accent and semantic**

| Role | oklch | ≈ hex |
| --- | --- | --- |
| Accent blue (default) | `52% 0.11 252` | `#2c6ad1` |
| Accent green | `52% 0.11 155` | `#1f7a56` |
| Accent orange | `52% 0.11 30` | `#a75b3f` |
| Accent graphite | `45% 0.012 255` | `#5e6166` |
| Overdue | `52% 0.16 32` | `#c1462f` |

**Type colours** — marker stroke is the light value at 60% alpha; label is the dark value.

| Type | Marker | Label |
| --- | --- | --- |
| Meeting | `84% 0.13 60` | `52% 0.05 60` |
| Note | `82% 0.10 252` | `50% 0.07 252` |
| Staffing | `85% 0.11 150` | `48% 0.06 150` |
| Feedback | not specified — derive at the same L/C, hue ≈ 300 | |

**Project dot colours** are per-project data, not tokens. Examples used in the mock: `62% 0.13 252`
(blue), `62% 0.13 300` (violet), `70% 0.10 60` (amber), `60% 0.10 200` (teal).

**Type scale (indicative)** — column heading 21/700; sidebar heading 20/700; note title 16–17/650;
task title 15/600; body 13.5/1.6; controls 12.5–13; meta and chips 11.5; type label 11/650 with
0.07em tracking, uppercase.

**Radii** — controls `999px`; cards `10px`; panels/windows `12–14px`; tint swatches `9px`.

**Shadows** — cards: 1px ambient, ~5% black. Raised segment: 1px, ~10% black plus a hairline.
Windows: large soft drop. Replace all of these with the platform's own elevation.

## Assets

No new assets. Project icons are the app's existing per-project icons (the HTML stands in for them
with emoji glyphs — **do not ship emoji**; use whatever the app already uses). Settings sidebar icons
are unchanged. No new SVG or bitmap artwork is required.

## Open questions for the maintainer

1. **Dark mode.** Every tint needs a dark value, and the marker strokes need dark equivalents that keep
   title contrast. Not designed.
2. **Typeface tiles.** As pills they read as buttons. Revert to ~10px radius?
3. **Feedback type colour.** Never shown in the refresh; needs a hue assignment.
4. **Overflow chip disclosure.** Hover popover, click popover, or tooltip?
5. **Compact density.** The rejected "ledger" layout (option 2a in the exploration file) was noted as a
   possible future compact mode. Out of scope now — flagged so it isn't lost.
6. **Tint naming** is provisional; confirm before it reaches strings/localisation.

## Files

- `Insert - Neutral Direction.dc.html` — primary reference (main window + Settings).
- `Insert - Note Type Explorations.dc.html` — rejected alternatives, for context only.
- `support.js` — runtime needed to open the two HTML files locally. Not part of the design.
