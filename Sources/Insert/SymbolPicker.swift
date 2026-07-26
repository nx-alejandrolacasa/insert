import AppKit
import SwiftUI

// MARK: - Catalogue

/// One pickable SF Symbol: its name plus extra words to search it by, since a
/// symbol's own name is often not what you'd type looking for it ("ant" for a
/// bug, "target" for a goal).
struct SymbolOption: Identifiable, Hashable {
    let name: String
    let keywords: String

    var id: String { name }
}

/// The symbols Insert offers for projects, notes and note types.
///
/// macOS ships no symbol picker and no way to *enumerate* symbols — you can only
/// ask whether one particular name resolves (`NSImage(systemSymbolName:)`) — so
/// this list is hand-picked and every name in it was checked against the SDK.
/// `SymbolPicker` searches it by name and keywords.
enum SymbolCatalog {
    static let all: [SymbolOption] = [
        // Writing
        SymbolOption(name: "note.text", keywords: "note write text"),
        SymbolOption(name: "doc.text", keywords: "document file page"),
        SymbolOption(name: "doc.richtext", keywords: "document formatted"),
        SymbolOption(name: "text.alignleft", keywords: "text paragraph"),
        SymbolOption(name: "text.justify", keywords: "text paragraph"),
        SymbolOption(name: "pencil", keywords: "edit write draw"),
        SymbolOption(name: "pencil.and.outline", keywords: "edit sketch draft"),
        SymbolOption(name: "highlighter", keywords: "mark emphasis"),
        SymbolOption(name: "quote.bubble", keywords: "quote citation feedback"),
        SymbolOption(name: "newspaper", keywords: "news press article"),
        SymbolOption(name: "magazine", keywords: "publication read"),
        SymbolOption(name: "book", keywords: "read manual guide"),
        SymbolOption(name: "book.closed", keywords: "read library"),
        SymbolOption(name: "books.vertical", keywords: "library shelf reading"),
        SymbolOption(name: "graduationcap", keywords: "learning training study"),

        // Lists & tasks
        SymbolOption(name: "list.bullet", keywords: "list items"),
        SymbolOption(name: "list.bullet.clipboard", keywords: "backlog agenda"),
        SymbolOption(name: "checklist", keywords: "tasks todo"),
        SymbolOption(name: "checkmark.circle", keywords: "done complete ok"),
        SymbolOption(name: "checkmark.seal", keywords: "approved verified"),
        SymbolOption(name: "target", keywords: "goal objective okr aim"),
        SymbolOption(name: "flag", keywords: "milestone marker"),
        SymbolOption(name: "flag.pattern.checkered", keywords: "finish launch race"),
        SymbolOption(name: "rosette", keywords: "award quality badge"),
        SymbolOption(name: "trophy", keywords: "win award success"),
        SymbolOption(name: "medal", keywords: "award recognition"),
        SymbolOption(name: "crown", keywords: "priority leadership best"),

        // Organising
        SymbolOption(name: "folder", keywords: "project directory"),
        SymbolOption(name: "folder.badge.plus", keywords: "new project add"),
        SymbolOption(name: "folder.badge.gearshape", keywords: "project settings"),
        SymbolOption(name: "tray.full", keywords: "inbox everything all"),
        SymbolOption(name: "tray.2", keywords: "inbox stack queue"),
        SymbolOption(name: "archivebox", keywords: "archive storage old"),
        SymbolOption(name: "shippingbox", keywords: "package delivery release"),
        SymbolOption(name: "square.stack", keywords: "stack layers group"),
        SymbolOption(name: "rectangle.stack", keywords: "cards collection"),
        SymbolOption(name: "square.grid.2x2", keywords: "grid overview board"),
        SymbolOption(name: "circle.grid.2x2", keywords: "grid dots"),
        SymbolOption(name: "tag", keywords: "label category type"),
        SymbolOption(name: "bookmark", keywords: "saved later"),
        SymbolOption(name: "pin", keywords: "pinned important"),
        SymbolOption(name: "paperclip", keywords: "attachment file"),
        SymbolOption(name: "trash", keywords: "delete remove bin"),

        // Time
        SymbolOption(name: "calendar", keywords: "date schedule"),
        SymbolOption(name: "calendar.badge.clock", keywords: "deadline due schedule"),
        SymbolOption(name: "clock", keywords: "time hour"),
        SymbolOption(name: "alarm", keywords: "reminder wake"),
        SymbolOption(name: "timer", keywords: "countdown stopwatch"),
        SymbolOption(name: "hourglass", keywords: "waiting pending"),
        SymbolOption(name: "bell", keywords: "notification reminder"),

        // People & talking
        SymbolOption(name: "person", keywords: "someone user one-to-one"),
        SymbolOption(name: "person.2", keywords: "meeting pair staffing"),
        SymbolOption(name: "person.3", keywords: "team group staffing"),
        SymbolOption(name: "person.crop.circle", keywords: "profile account"),
        SymbolOption(name: "person.2.wave.2", keywords: "meeting greeting intro"),
        SymbolOption(name: "hand.wave", keywords: "hello welcome greeting"),
        SymbolOption(name: "hand.raised", keywords: "stop question blocked"),
        SymbolOption(name: "hand.thumbsup", keywords: "approve like feedback"),
        SymbolOption(name: "bubble.left", keywords: "comment message note"),
        SymbolOption(name: "bubble.left.and.bubble.right", keywords: "discussion chat feedback"),
        SymbolOption(name: "bubble.left.and.text.bubble.right", keywords: "conversation feedback review"),
        SymbolOption(name: "text.bubble", keywords: "comment feedback"),
        SymbolOption(name: "captions.bubble", keywords: "notes transcript"),
        SymbolOption(name: "envelope", keywords: "mail message"),
        SymbolOption(name: "paperplane", keywords: "send ship launch"),
        SymbolOption(name: "phone", keywords: "call"),
        SymbolOption(name: "video", keywords: "call meeting recording"),
        SymbolOption(name: "mic", keywords: "record interview"),
        SymbolOption(name: "headphones", keywords: "listen audio"),
        SymbolOption(name: "speaker.wave.2", keywords: "sound announcement"),

        // Thinking
        SymbolOption(name: "brain", keywords: "idea think research"),
        SymbolOption(name: "brain.head.profile", keywords: "thinking learning"),
        SymbolOption(name: "lightbulb", keywords: "idea insight"),
        SymbolOption(name: "lightbulb.max", keywords: "bright idea"),
        SymbolOption(name: "sparkles", keywords: "new magic ai"),
        SymbolOption(name: "wand.and.stars", keywords: "magic generate ai"),
        SymbolOption(name: "puzzlepiece", keywords: "problem piece fit"),
        SymbolOption(name: "questionmark.circle", keywords: "question unknown open"),
        SymbolOption(name: "info.circle", keywords: "info detail"),
        SymbolOption(name: "exclamationmark.triangle", keywords: "warning risk blocked"),

        // Work & tools
        SymbolOption(name: "hammer", keywords: "build make"),
        SymbolOption(name: "wrench.and.screwdriver", keywords: "maintenance fix tools"),
        SymbolOption(name: "screwdriver", keywords: "fix tweak"),
        SymbolOption(name: "gearshape", keywords: "settings config"),
        SymbolOption(name: "gearshape.2", keywords: "settings system"),
        SymbolOption(name: "slider.horizontal.3", keywords: "settings tuning"),
        SymbolOption(name: "dial.medium", keywords: "control tuning"),
        SymbolOption(name: "ruler", keywords: "measure spec design"),
        SymbolOption(name: "scissors", keywords: "cut trim"),
        SymbolOption(name: "paintbrush", keywords: "design style"),
        SymbolOption(name: "paintpalette", keywords: "design colour brand"),
        SymbolOption(name: "photo", keywords: "image picture"),
        SymbolOption(name: "camera", keywords: "photo capture"),
        SymbolOption(name: "magnifyingglass", keywords: "search research find"),
        SymbolOption(name: "eye", keywords: "review watch monitor"),
        SymbolOption(name: "function", keywords: "formula math logic"),
        SymbolOption(name: "sum", keywords: "total math"),
        SymbolOption(name: "percent", keywords: "rate metric"),
        SymbolOption(name: "number", keywords: "hash tag count"),
        SymbolOption(name: "asterisk", keywords: "note footnote"),
        SymbolOption(name: "at", keywords: "mention handle"),
        SymbolOption(name: "link", keywords: "url reference"),
        SymbolOption(name: "command", keywords: "shortcut key"),
        SymbolOption(name: "option", keywords: "shortcut key"),
        SymbolOption(name: "sidebar.left", keywords: "layout panel"),

        // Data
        SymbolOption(name: "chart.bar", keywords: "metrics report data"),
        SymbolOption(name: "chart.pie", keywords: "share split data"),
        SymbolOption(name: "chart.line.uptrend.xyaxis", keywords: "growth trend metrics"),
        SymbolOption(name: "chart.xyaxis.line", keywords: "graph analysis"),
        SymbolOption(name: "waveform", keywords: "signal audio activity"),
        SymbolOption(name: "gauge.with.dots.needle.bottom.50percent", keywords: "gauge status health"),
        SymbolOption(name: "speedometer", keywords: "performance speed"),
        SymbolOption(name: "arrow.triangle.branch", keywords: "branch git fork"),
        SymbolOption(name: "arrow.triangle.2.circlepath", keywords: "sync loop repeat"),
        SymbolOption(name: "arrow.up.right", keywords: "outgoing increase"),
        SymbolOption(name: "arrow.down.left", keywords: "incoming decrease"),

        // Tech
        SymbolOption(name: "cpu", keywords: "processor hardware"),
        SymbolOption(name: "memorychip", keywords: "memory hardware"),
        SymbolOption(name: "desktopcomputer", keywords: "mac computer"),
        SymbolOption(name: "laptopcomputer", keywords: "mac laptop"),
        SymbolOption(name: "macbook", keywords: "mac laptop"),
        SymbolOption(name: "iphone", keywords: "mobile phone ios"),
        SymbolOption(name: "ipad", keywords: "tablet ios"),
        SymbolOption(name: "display", keywords: "monitor screen"),
        SymbolOption(name: "keyboard", keywords: "typing input"),
        SymbolOption(name: "printer", keywords: "print"),
        SymbolOption(name: "externaldrive", keywords: "disk storage backup"),
        SymbolOption(name: "internaldrive", keywords: "disk storage"),
        SymbolOption(name: "server.rack", keywords: "infrastructure backend"),
        SymbolOption(name: "cloud", keywords: "cloud hosting"),
        SymbolOption(name: "icloud", keywords: "sync cloud apple"),
        SymbolOption(name: "network", keywords: "connections infrastructure"),
        SymbolOption(name: "wifi", keywords: "wireless connection"),
        SymbolOption(name: "antenna.radiowaves.left.and.right", keywords: "signal broadcast"),
        SymbolOption(name: "lock", keywords: "security private"),
        SymbolOption(name: "lock.shield", keywords: "security privacy"),
        SymbolOption(name: "key", keywords: "access credentials"),
        SymbolOption(name: "shield", keywords: "protection security"),
        SymbolOption(name: "ant", keywords: "bug defect issue"),
        SymbolOption(name: "ladybug", keywords: "bug defect"),
        SymbolOption(name: "atom", keywords: "science core physics"),
        SymbolOption(name: "testtube.2", keywords: "experiment test lab"),
        SymbolOption(name: "flask", keywords: "experiment research"),
        SymbolOption(name: "stethoscope", keywords: "diagnosis health check"),

        // Business
        SymbolOption(name: "creditcard", keywords: "payment billing"),
        SymbolOption(name: "banknote", keywords: "money budget cost"),
        SymbolOption(name: "cart", keywords: "shop commerce"),
        SymbolOption(name: "bag", keywords: "shop order"),
        SymbolOption(name: "gift", keywords: "present perk"),
        SymbolOption(name: "ticket", keywords: "issue ticket event"),
        SymbolOption(name: "building.2", keywords: "company office client"),
        SymbolOption(name: "building.columns", keywords: "bank institution"),
        SymbolOption(name: "house", keywords: "home personal"),
        SymbolOption(name: "door.left.hand.open", keywords: "onboarding entry exit"),
        SymbolOption(name: "globe", keywords: "world international web"),
        SymbolOption(name: "map", keywords: "plan roadmap"),
        SymbolOption(name: "location", keywords: "place where"),

        // Life
        SymbolOption(name: "star", keywords: "favourite important"),
        SymbolOption(name: "heart", keywords: "love health favourite"),
        SymbolOption(name: "bolt", keywords: "energy fast urgent"),
        SymbolOption(name: "flame", keywords: "hot urgent streak"),
        SymbolOption(name: "drop", keywords: "water hydration"),
        SymbolOption(name: "leaf", keywords: "nature growth eco"),
        SymbolOption(name: "tree", keywords: "nature growth"),
        SymbolOption(name: "carrot", keywords: "food health"),
        SymbolOption(name: "cup.and.saucer", keywords: "coffee break chat"),
        SymbolOption(name: "fork.knife", keywords: "food lunch"),
        SymbolOption(name: "birthday.cake", keywords: "birthday celebration"),
        SymbolOption(name: "moon", keywords: "night later someday"),
        SymbolOption(name: "sun.max", keywords: "day morning"),
        SymbolOption(name: "cloud.rain", keywords: "weather rain"),
        SymbolOption(name: "snowflake", keywords: "frozen paused winter"),
        SymbolOption(name: "thermometer.medium", keywords: "temperature health"),
        SymbolOption(name: "umbrella", keywords: "protection backup"),
        SymbolOption(name: "beach.umbrella", keywords: "holiday vacation break"),
        SymbolOption(name: "airplane", keywords: "travel trip"),
        SymbolOption(name: "car", keywords: "travel commute"),
        SymbolOption(name: "bicycle", keywords: "cycling commute"),
        SymbolOption(name: "tram", keywords: "transport commute"),
        SymbolOption(name: "fuelpump", keywords: "fuel energy"),
        SymbolOption(name: "figure.walk", keywords: "walk progress step"),
        SymbolOption(name: "figure.run", keywords: "run sport fast"),
        SymbolOption(name: "dumbbell", keywords: "gym training"),
        SymbolOption(name: "sportscourt", keywords: "sport game"),
        SymbolOption(name: "gamecontroller", keywords: "game play"),
        SymbolOption(name: "dice", keywords: "chance random game"),
        SymbolOption(name: "cross.case", keywords: "health medical kit"),
        SymbolOption(name: "pills", keywords: "medicine health"),
        SymbolOption(name: "bandage", keywords: "fix patch hotfix"),
        SymbolOption(name: "pawprint", keywords: "pet animal"),
        SymbolOption(name: "hare", keywords: "fast quick"),
        SymbolOption(name: "tortoise", keywords: "slow steady"),
        SymbolOption(name: "fish", keywords: "animal sea"),
        SymbolOption(name: "bird", keywords: "animal social"),
    ]

    /// Fallbacks used when nothing has been chosen yet.
    static let defaultProject = "folder"
    static let defaultNote = "note.text"
    static let everything = "tray.full"

    /// Case-insensitive search over names and keywords; every whitespace-separated
    /// term has to match somewhere, so "person team" narrows rather than widens.
    static func matching(_ query: String) -> [SymbolOption] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return all }
        return all.filter { option in
            let haystack = "\(option.name) \(option.keywords)".lowercased()
            return terms.allSatisfy(haystack.contains)
        }
    }

    /// Anything Insert reads that isn't a symbol it knows — an emoji from a file
    /// written before this change, say — falls back to `fallback`. Emoji can't be
    /// translated to symbols, but the handful the app used to seed are mapped so
    /// existing projects and notes keep a sensible icon.
    static func resolve(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return fallback }
        if NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil { return trimmed }
        return legacyEmoji[trimmed] ?? fallback
    }

    private static let legacyEmoji: [String: String] = [
        "👋": "hand.wave",
        "🚀": "paperplane",
        "🎯": "target",
        "📝": "note.text",
        "🗒️": "note.text",
        "🤝": "person.2.wave.2",
        "🤝🏻": "person.2.wave.2",
        "💬": "bubble.left.and.text.bubble.right",
        "👥": "person.3",
        "✅": "checkmark.circle",
        "⭐️": "star",
        "🔥": "flame",
        "💡": "lightbulb",
        "📌": "pin",
        "🐛": "ant",
        "📅": "calendar",
        "❓": "questionmark.circle",
        "📥": "tray.full",
    ]
}

// MARK: - Picker

/// A searchable SF Symbols grid, used everywhere Insert asks for an icon
/// (projects, notes, note types). Typing filters by name *and* keyword, so
/// "goal" finds `target` and "bug" finds `ant`.
struct SymbolPicker: View {
    /// The symbol currently chosen, highlighted in the grid.
    let selection: String
    /// Tint for the selected cell, so the picker matches whatever it's editing.
    var tint: Tint = .blue
    let onPick: (String) -> Void

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 4), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search symbols", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Stone.chip))

            let matches = SymbolCatalog.matching(query)
            if matches.isEmpty {
                Text("No symbols match “\(query)”")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(matches) { option in
                            cell(option)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 180)
            }
        }
        .padding(12)
        // No fixed width: standalone popovers give it one, while the project
        // editor lets it fill the form (a hard 320 overflowed that layout).
        .onAppear { searchFocused = true }
    }

    private func cell(_ option: SymbolOption) -> some View {
        let chosen = option.name == selection
        return Button {
            onPick(option.name)
        } label: {
            Image(systemName: option.name)
                .font(.title3)
                .foregroundStyle(chosen ? AnyShapeStyle(tint.ink) : AnyShapeStyle(.primary))
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(chosen ? tint.chip : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(option.name)
        .accessibilityLabel(option.name)
        // The tinted fill is the only cue for the current symbol.
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}
