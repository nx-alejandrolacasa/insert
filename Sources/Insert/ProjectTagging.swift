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
/// The key handlers all fall through (`.ignored`) while the dropdown is closed,
/// so Return/Tab/Esc keep their normal meaning the rest of the time; the owner
/// supplies that meaning via `onSubmit` / `onEscape`.
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
            .onKeyPress(.return) {
                guard dropdownVisible else { return .ignored }
                acceptMatch(at: highlightedIndex)
                return .handled
            }
            .onKeyPress(.tab) {
                guard dropdownVisible else { return .ignored }
                acceptMatch(at: 0)
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard dropdownVisible else { return .ignored }
                highlightedIndex = min(highlightedIndex + 1, matches.count - 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard dropdownVisible else { return .ignored }
                highlightedIndex = max(highlightedIndex - 1, 0)
                return .handled
            }
            // Esc closes the dropdown if it's open, otherwise it's the owner's.
            .onKeyPress(.escape) {
                if dropdownVisible {
                    dismissed = true
                } else {
                    onEscape()
                }
                return .handled
            }
            .onSubmit(onSubmit)
            // The dropdown floats over whatever follows the field.
            .overlay(alignment: .topLeading) {
                if dropdownVisible {
                    dropdown.offset(y: fieldHeight + 4)
                }
            }
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
        // material to stay legible and a shadow to read as lifted.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
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
/// recognisable without reading it. Double-click removes it — a deliberate,
/// hard-to-trigger-by-accident gesture, and single taps do nothing so chips are
/// safe to brush against.
struct ProjectChip: View {
    let project: Project
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: project.symbol)
                .foregroundStyle(project.tint.ink)
            Text(project.name)
        }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(project.tint.chip))
            .overlay(Capsule().strokeBorder(project.tint.accent.opacity(0.35), lineWidth: 0.5))
            .contentShape(Capsule())
            .onTapGesture(count: 2, perform: onRemove)
            .help("Double-click to remove \(project.name)")
            // Double-click was the *only* way to remove an assignment: no
            // keyboard path, nothing for VoiceOver, Switch Control or Voice
            // Control, and nothing discoverable without the tooltip. The gesture
            // stays (it's deliberately hard to trigger by accident); these add
            // the alternatives — a context menu for the pointer, a named action
            // for assistive technology.
            .contextMenu {
                Button("Remove \(project.name)", systemImage: "xmark", action: onRemove)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(project.name), assigned")
            .accessibilityAction(named: "Remove", onRemove)
    }
}

/// The ＋ that adds a project, listing everything not already assigned. The
/// complementary "add" affordance to a chip's double-click removal.
struct AddProjectMenu: View {
    let assigned: [UUID]
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
            Image(systemName: "plus")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(4)
                .background(Circle().fill(Stone.surface))
                // The glyph plus 4pt of padding is a small target for a control
                // that sits among chips; widen the hit area, not the circle.
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add to a project")
        .accessibilityLabel("Add to a project")
    }
}
