import SwiftUI

/// Shared `#project` tagging surfaces, used by both the task composer and the
/// note card so tagging works and *reads* identically on either side of the
/// window.

// MARK: - Hash field

/// A text field with inline `#project` autocomplete.
///
/// Typing `#` opens a dropdown of projects (filtered as you keep typing): Tab
/// takes the first match, Return the highlighted one, ↑/↓ move the highlight and
/// Esc closes the list. Accepting a match appends the project to `assigned` and
/// strips the `#token` from the text — the tag is only ever a command, never
/// part of the title.
///
/// The keys are intercepted with a **local `NSEvent` monitor**, not `onKeyPress`:
/// on macOS the field editor consumes Tab/Return/arrows/Esc before SwiftUI's
/// key-press handlers see them, so `onKeyPress` versions of these never fired —
/// Tab moved focus and Return submitted the raw `#token` as part of the title.
/// The monitor sees the event before the window dispatches it, handles it only
/// while *this* field is focused, and passes everything else through, so
/// Return/Tab keep their normal meaning the rest of the time; the owner supplies
/// that meaning via `onSubmit` / `onEscape`.
struct ProjectHashField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var assigned: [UUID]
    var font: Font = .body
    /// Return with the dropdown closed.
    var onSubmit: () -> Void = {}
    /// Esc with the dropdown closed.
    var onEscape: () -> Void = {}
    /// Owned by the caller, which also decides when the field takes focus.
    @FocusState.Binding var focused: Bool

    @Environment(Library.self) private var library

    /// Highlighted row in the dropdown (driven by ↑/↓).
    @State private var highlightedIndex = 0
    /// Set by Esc so the dropdown can be dismissed without altering the text;
    /// cleared on the next keystroke.
    @State private var dismissed = false
    /// Height of the field, so the overlay drops just below it.
    @State private var fieldHeight: CGFloat = 0
    /// The local key-down monitor, installed for the field's lifetime (its
    /// handler no-ops unless the field is focused).
    @State private var keyMonitor: Any?

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .focused($focused)
            .background(
                // Measure the field so the dropdown sits right beneath it
                // regardless of dynamic type.
                GeometryReader { proxy in
                    Color.clear.preference(key: FieldHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(FieldHeightKey.self) { fieldHeight = $0 }
            .onChange(of: text) {
                // Any edit re-opens a dismissed dropdown and resets the
                // highlight to the top match.
                dismissed = false
                highlightedIndex = 0
            }
            .onAppear { installKeyMonitor() }
            .onDisappear { removeKeyMonitor() }
            // Backstop for a Return the monitor didn't see: accept rather than
            // let a `#token` leak into the submitted title.
            .onSubmit {
                if dropdownVisible {
                    acceptMatch(at: highlightedIndex)
                } else {
                    onSubmit()
                }
            }
            // The dropdown floats over whatever follows the field.
            .overlay(alignment: .topLeading) {
                if dropdownVisible {
                    dropdown.offset(y: fieldHeight + 4)
                }
            }
    }

    // MARK: Key handling

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Monitors fire on the main thread, but the closure isn't annotated;
            // `assumeIsolated` can't *return* the non-Sendable event, so it
            // answers "swallow?" instead.
            let swallow = MainActor.assumeIsolated { handleKeyDown(event) }
            return swallow ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns `true` to swallow the event, `false` to let it through. Several
    /// fields can be on screen at once (the composer plus an editing card);
    /// `focused` keeps all but the active one out of the way.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard focused else { return false }
        // ⌘/⌃/⌥-modified presses keep their normal meaning.
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }

        if dropdownVisible {
            switch event.keyCode {
            case 48: // Tab → first match
                acceptMatch(at: 0)
                return true
            case 36, 76: // Return / keypad Enter → highlighted match
                acceptMatch(at: highlightedIndex)
                return true
            case 125: // ↓
                highlightedIndex = min(highlightedIndex + 1, matches.count - 1)
                return true
            case 126: // ↑
                highlightedIndex = max(highlightedIndex - 1, 0)
                return true
            case 53: // Esc closes the dropdown without touching the text.
                dismissed = true
                return true
            default:
                return false
            }
        }

        if event.keyCode == 53 { // Esc with the dropdown closed is the owner's.
            onEscape()
            return true
        }
        return false
    }

    // MARK: Matching

    /// The `#`-token currently being typed, without the leading `#`, or `nil`
    /// when the trailing token isn't a project command.
    private var hashQuery: String? {
        let token = text[tokenStartIndex...]
        guard token.hasPrefix("#") else { return nil }
        return String(token.dropFirst())
    }

    /// Start of the trailing whitespace-delimited token (used to read and strip
    /// the `#command`).
    private var tokenStartIndex: String.Index {
        if let lastBreak = text.lastIndex(where: { $0 == " " || $0 == "\n" }) {
            return text.index(after: lastBreak)
        }
        return text.startIndex
    }

    /// Projects matching the current `#query` (all projects for a bare `#`),
    /// excluding those already assigned so the list only offers new tags.
    private var matches: [Project] {
        guard let q = hashQuery else { return [] }
        return library.projects
            .filter { !assigned.contains($0.id) }
            .filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var dropdownVisible: Bool {
        focused && !dismissed && hashQuery != nil && !matches.isEmpty
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element.id) { index, project in
                Button {
                    acceptMatch(at: index)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: project.symbol)
                            .foregroundStyle(project.tint.ink)
                        Text(project.name)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(index == highlightedIndex ? Color.accentColor.opacity(0.22) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 240, alignment: .leading)
        // Glass here, unlike the cards: this floats over the list, so it needs a
        // material to stay legible.
        //
        // No drop shadow, though it's the one thing in the window that would have
        // the best claim to one. The app is deliberately shadowless — the look it
        // wears when the window is inactive and every glass surface flattens, which
        // is the look it's tuned for — and one lifted element would be the only
        // thing casting light in an otherwise flat window. Glass and the hairline
        // do the separating instead: the material already refracts the rows behind
        // it, and the border closes the edge the shadow used to.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Stone.line, lineWidth: 0.5)
        }
    }

    /// Accept the match at `index`: assign the project and strip the `#token`.
    private func acceptMatch(at index: Int) {
        guard matches.indices.contains(index) else { return }
        let project = matches[index]
        if !assigned.contains(project.id) {
            assigned.append(project.id)
        }
        // Remove the command token; the leading text (and any trailing space)
        // stays as the actual title.
        text.removeSubrange(tokenStartIndex..<text.endIndex)
        highlightedIndex = 0
        focused = true
    }
}

/// Measures the text field so its dropdown can be offset to just below it.
private struct FieldHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Chips

/// A removable project chip, wearing its project's colour so an assignment is
/// recognisable without reading it. Hovering fades the trailing end of the
/// name and shows an ✕ over it — the chip keeps its width, the button lands on
/// quiet ground, and one click removes the assignment.
struct ProjectChip: View {
    let project: Project
    let onRemove: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: project.symbol)
                .foregroundStyle(project.tint.ink)
            Text(project.name)
        }
            .font(.caption)
            .lineLimit(1)
            // A mask, not a shorter label: the chip must not change size under
            // the pointer. Same stop count both ways so the fade animates.
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.55),
                        .init(color: hovered ? .clear : .black, location: 0.95),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .chipHeight()
            .background(Capsule().fill(project.tint.chip))
            .overlay(Capsule().strokeBorder(project.tint.accent.opacity(0.35), lineWidth: 0.5))
            .overlay(alignment: .trailing) {
                if hovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(project.tint.ink)
                            // The glyph alone is a tiny target; grow the hit
                            // area, not the glyph.
                            .padding(4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 3)
                    .help("Remove \(project.name)")
                    .transition(.opacity)
                }
            }
            .contentShape(Capsule())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) { hovered = hovering }
            }
            // Hover is pointer-only and invisible until tried, so keep the
            // alternatives: a context menu for discovery, a named action for
            // VoiceOver, Switch Control and Voice Control.
            .contextMenu {
                Button("Remove \(project.name)", systemImage: "xmark", action: onRemove)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(project.name), assigned")
            .accessibilityAction(named: "Remove", onRemove)
    }
}

/// The quiet "＋ Add project" pill at the end of a chips row, listing everything
/// not already assigned. Dressed exactly like a task's "Add due" badge — grey
/// caption on a grey wash — so the two affordances read as one family.
///
/// `compact` drops the text and leaves a bare bold ＋ in a circle: that's the
/// form used next to existing chips, where "add another of these" needs no
/// spelling out. The full wording is for the unassigned case, where the pill
/// stands alone, and it stays a capsule.
struct AddProjectMenu: View {
    let assigned: [UUID]
    var compact = false
    let onAdd: (UUID) -> Void

    @Environment(Library.self) private var library

    var body: some View {
        let available = library.projects.filter { !assigned.contains($0.id) }
        return Menu {
            if available.isEmpty {
                Text("No other projects")
            } else {
                ForEach(available) { project in
                    Button {
                        onAdd(project.id)
                    } label: {
                        Label(project.name, systemImage: project.symbol)
                    }
                }
            }
        } label: {
            if compact {
                // A **circle**, not a short capsule: with the text gone there's
                // one glyph in there, so a capsule was a circle with slack at the
                // sides. Square at `chipHeight`, which is what makes it round and
                // keeps it the height of the chips it sits beside. The ＋ is bold
                // because at caption size a regular one is two hairlines — the
                // one glyph carrying the whole affordance has to be legible.
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: Metrics.chipHeight, height: Metrics.chipHeight)
                    .background(Circle().fill(Color.secondary.opacity(0.14)))
                    .contentShape(Circle())
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add project")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .chipHeight()
                .background(Capsule().fill(Color.secondary.opacity(0.14)))
                .contentShape(Capsule())
            }
        }
        // `.button` + plain, not `.borderlessButton`: the borderless style
        // redraws the label in its own type and drops the capsule, and this
        // pill has to twin the "Add due" badge beside it.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add to a project")
        .accessibilityLabel("Add to a project")
    }
}
