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
        SymbolOption(name: "note.text", keywords: "write memo jot record idea"),
        SymbolOption(name: "doc.text", keywords: "document file page paper report"),
        SymbolOption(name: "doc.richtext", keywords: "document file formatted report layout"),
        SymbolOption(name: "text.alignleft", keywords: "paragraph writing body copy prose"),
        SymbolOption(name: "text.justify", keywords: "paragraph writing body block prose"),
        SymbolOption(name: "pencil", keywords: "edit write draw draft compose"),
        SymbolOption(name: "pencil.and.outline", keywords: "edit sketch draft annotate draw"),
        SymbolOption(name: "highlighter", keywords: "mark emphasis important review marker"),
        SymbolOption(name: "quote.bubble", keywords: "citation feedback testimonial saying comment"),
        SymbolOption(name: "newspaper", keywords: "news press article headline journalism"),
        SymbolOption(name: "magazine", keywords: "publication article journal press read"),
        SymbolOption(name: "book", keywords: "read manual guide documentation study"),
        SymbolOption(name: "book.closed", keywords: "read library reference study cover"),
        SymbolOption(name: "books.vertical", keywords: "library shelf reading collection study"),
        SymbolOption(name: "graduationcap", keywords: "learning training study education course"),

        // Lists & tasks
        SymbolOption(name: "list.bullet", keywords: "items agenda points outline todo"),
        SymbolOption(name: "list.bullet.clipboard", keywords: "backlog agenda plan tasks report"),
        SymbolOption(name: "checklist", keywords: "tasks todo done plan items"),
        SymbolOption(name: "checkmark.circle", keywords: "done complete ok finished approved"),
        SymbolOption(name: "checkmark.seal", keywords: "approved verified certified official quality"),
        SymbolOption(name: "target", keywords: "goal objective okr aim focus"),
        SymbolOption(name: "flag", keywords: "milestone marker priority banner report"),
        SymbolOption(name: "flag.pattern.checkered", keywords: "finish launch race goal done"),
        SymbolOption(name: "rosette", keywords: "award quality badge ribbon prize"),
        SymbolOption(name: "trophy", keywords: "win award success achievement prize"),
        SymbolOption(name: "medal", keywords: "award recognition achievement prize honour"),
        SymbolOption(name: "crown", keywords: "priority leadership best vip king"),

        // Organising
        SymbolOption(name: "folder", keywords: "project directory files organise group"),
        SymbolOption(name: "folder.badge.plus", keywords: "new project add create directory"),
        SymbolOption(name: "folder.badge.gearshape", keywords: "project settings configure directory options"),
        SymbolOption(name: "tray.full", keywords: "inbox everything all incoming mail"),
        SymbolOption(name: "tray.2", keywords: "inbox stack queue incoming sorted"),
        SymbolOption(name: "archivebox", keywords: "storage old history keep past"),
        SymbolOption(name: "shippingbox", keywords: "package delivery release parcel ship"),
        SymbolOption(name: "square.stack", keywords: "layers group pile collection cards"),
        SymbolOption(name: "rectangle.stack", keywords: "cards collection pile layers gallery"),
        SymbolOption(name: "square.grid.2x2", keywords: "overview board dashboard tiles apps"),
        SymbolOption(name: "circle.grid.2x2", keywords: "dots board tiles pattern menu"),
        SymbolOption(name: "tag", keywords: "label category type classify price"),
        SymbolOption(name: "bookmark", keywords: "saved later keep favourite reading"),
        SymbolOption(name: "pin", keywords: "pinned important sticky keep location"),
        SymbolOption(name: "paperclip", keywords: "attachment file attach document clip"),
        SymbolOption(name: "trash", keywords: "delete remove bin discard garbage"),

        // Time
        SymbolOption(name: "calendar", keywords: "date schedule month agenda plan"),
        SymbolOption(name: "calendar.badge.clock", keywords: "deadline due schedule appointment date"),
        SymbolOption(name: "clock", keywords: "time hour schedule watch when"),
        SymbolOption(name: "alarm", keywords: "reminder wake morning ring urgent"),
        SymbolOption(name: "timer", keywords: "countdown stopwatch pomodoro minutes deadline"),
        SymbolOption(name: "hourglass", keywords: "waiting pending patience time slow"),
        SymbolOption(name: "bell", keywords: "notification reminder alert ring announcement"),

        // People & talking
        SymbolOption(name: "person", keywords: "someone user individual contact profile"),
        SymbolOption(name: "person.2", keywords: "meeting pair staffing duo couple"),
        SymbolOption(name: "person.3", keywords: "team group staffing crowd department"),
        SymbolOption(name: "person.crop.circle", keywords: "profile account avatar user contact"),
        SymbolOption(name: "person.2.wave.2", keywords: "meeting greeting intro welcome handshake"),
        SymbolOption(name: "hand.wave", keywords: "hello welcome greeting goodbye hi"),
        SymbolOption(name: "hand.raised", keywords: "stop question blocked wait volunteer"),
        SymbolOption(name: "hand.thumbsup", keywords: "approve like feedback good yes"),
        SymbolOption(name: "bubble.left", keywords: "comment message chat reply talk"),
        SymbolOption(name: "bubble.left.and.bubble.right", keywords: "discussion chat conversation dialogue feedback"),
        SymbolOption(name: "bubble.left.and.text.bubble.right", keywords: "conversation feedback review dialogue chat"),
        SymbolOption(name: "text.bubble", keywords: "comment feedback chat message reply"),
        SymbolOption(name: "captions.bubble", keywords: "transcript subtitles minutes notes record"),
        SymbolOption(name: "envelope", keywords: "mail email message letter inbox"),
        SymbolOption(name: "paperplane", keywords: "send ship launch deliver message"),
        SymbolOption(name: "phone", keywords: "call telephone contact dial ring"),
        SymbolOption(name: "video", keywords: "call meeting recording camera film"),
        SymbolOption(name: "mic", keywords: "record interview podcast voice audio"),
        SymbolOption(name: "headphones", keywords: "listen audio music podcast focus"),
        SymbolOption(name: "speaker.wave.2", keywords: "sound announcement volume audio broadcast"),

        // Thinking
        SymbolOption(name: "brain", keywords: "idea think research mind intelligence"),
        SymbolOption(name: "brain.head.profile", keywords: "thinking learning mind memory psychology"),
        SymbolOption(name: "lightbulb", keywords: "idea insight inspiration eureka bright"),
        SymbolOption(name: "lightbulb.max", keywords: "idea inspiration brainstorm bright eureka"),
        SymbolOption(name: "sparkles", keywords: "new magic ai shiny special"),
        SymbolOption(name: "wand.and.stars", keywords: "magic generate ai automation wizard"),
        SymbolOption(name: "puzzlepiece", keywords: "problem fit solve jigsaw piece"),
        SymbolOption(name: "questionmark.circle", keywords: "unknown open help doubt faq"),
        SymbolOption(name: "info.circle", keywords: "information detail about help notice"),
        SymbolOption(name: "exclamationmark.triangle", keywords: "warning risk blocked alert caution"),

        // Work & tools
        SymbolOption(name: "hammer", keywords: "build make construction fix tool"),
        SymbolOption(name: "wrench.and.screwdriver", keywords: "maintenance fix repair tools setup"),
        SymbolOption(name: "screwdriver", keywords: "fix tweak repair tool adjust"),
        SymbolOption(name: "gearshape", keywords: "settings config preferences options setup"),
        SymbolOption(name: "gearshape.2", keywords: "settings system preferences machinery advanced"),
        SymbolOption(name: "slider.horizontal.3", keywords: "settings tuning filters adjust controls"),
        SymbolOption(name: "dial.medium", keywords: "control tuning knob adjust volume"),
        SymbolOption(name: "ruler", keywords: "measure spec design size length"),
        SymbolOption(name: "scissors", keywords: "cut trim crop snip edit"),
        SymbolOption(name: "paintbrush", keywords: "design style art paint colour"),
        SymbolOption(name: "paintpalette", keywords: "design colour color brand art"),
        SymbolOption(name: "photo", keywords: "image picture gallery media snapshot"),
        SymbolOption(name: "camera", keywords: "photo capture picture snapshot shoot"),
        SymbolOption(name: "magnifyingglass", keywords: "search research find inspect zoom"),
        SymbolOption(name: "eye", keywords: "review watch monitor observe visibility"),
        SymbolOption(name: "function", keywords: "formula math logic equation code"),
        SymbolOption(name: "sum", keywords: "total math add calculation sigma"),
        SymbolOption(name: "percent", keywords: "rate metric discount ratio share"),
        SymbolOption(name: "number", keywords: "hashtag count pound sign symbol"),
        SymbolOption(name: "asterisk", keywords: "footnote star wildcard required annotation"),
        SymbolOption(name: "at", keywords: "mention handle email username sign"),
        SymbolOption(name: "link", keywords: "url reference chain connect website"),
        SymbolOption(name: "command", keywords: "shortcut key keyboard cmd mac"),
        SymbolOption(name: "option", keywords: "shortcut key keyboard alt mac"),
        SymbolOption(name: "sidebar.left", keywords: "layout panel navigation column interface"),

        // Data
        SymbolOption(name: "chart.bar", keywords: "metrics report data statistics analytics"),
        SymbolOption(name: "chart.pie", keywords: "share split data percentage statistics"),
        SymbolOption(name: "chart.line.uptrend.xyaxis", keywords: "growth metrics increase progress revenue"),
        SymbolOption(name: "chart.xyaxis.line", keywords: "graph analysis plot data trends"),
        SymbolOption(name: "waveform", keywords: "signal audio activity pulse sound"),
        SymbolOption(name: "gauge.with.dots.needle.bottom.50percent", keywords: "status health meter dashboard level"),
        SymbolOption(name: "speedometer", keywords: "performance fast dashboard velocity gauge"),
        SymbolOption(name: "arrow.triangle.branch", keywords: "git fork split version merge"),
        SymbolOption(name: "arrow.triangle.2.circlepath", keywords: "sync loop repeat refresh recycle"),
        SymbolOption(name: "arrow.up.right", keywords: "outgoing increase growth export external"),
        SymbolOption(name: "arrow.down.left", keywords: "incoming decrease receive import inbound"),

        // Tech
        SymbolOption(name: "cpu", keywords: "processor hardware chip computer performance"),
        SymbolOption(name: "memorychip", keywords: "ram hardware silicon computer storage"),
        SymbolOption(name: "desktopcomputer", keywords: "mac imac workstation screen office"),
        SymbolOption(name: "laptopcomputer", keywords: "mac notebook portable work screen"),
        SymbolOption(name: "macbook", keywords: "laptop notebook apple portable"),
        SymbolOption(name: "iphone", keywords: "mobile ios apple cell smartphone"),
        SymbolOption(name: "ipad", keywords: "tablet ios apple touch"),
        SymbolOption(name: "display", keywords: "monitor screen external presentation projector"),
        SymbolOption(name: "keyboard", keywords: "typing input keys shortcuts hardware"),
        SymbolOption(name: "printer", keywords: "print paper document output copy"),
        SymbolOption(name: "externaldrive", keywords: "disk storage backup ssd usb"),
        SymbolOption(name: "internaldrive", keywords: "disk storage ssd hard local"),
        SymbolOption(name: "server.rack", keywords: "infrastructure backend hosting datacenter cloud"),
        SymbolOption(name: "cloud", keywords: "hosting online storage sky saas"),
        SymbolOption(name: "icloud", keywords: "sync apple backup storage online"),
        SymbolOption(name: "network", keywords: "connections infrastructure internet nodes graph"),
        SymbolOption(name: "wifi", keywords: "wireless connection internet signal router"),
        SymbolOption(name: "antenna.radiowaves.left.and.right", keywords: "signal broadcast radio transmit cellular"),
        SymbolOption(name: "lock", keywords: "security private password protected secret"),
        SymbolOption(name: "lock.shield", keywords: "security privacy protection safe defence"),
        SymbolOption(name: "key", keywords: "access credentials password unlock secret"),
        SymbolOption(name: "shield", keywords: "protection security defence safe guard"),
        SymbolOption(name: "ant", keywords: "bug defect issue insect debug"),
        SymbolOption(name: "ladybug", keywords: "defect issue insect debug fix"),
        SymbolOption(name: "atom", keywords: "science physics core nucleus research"),
        SymbolOption(name: "testtube.2", keywords: "experiment lab science trial chemistry"),
        SymbolOption(name: "flask", keywords: "experiment research lab chemistry science"),
        SymbolOption(name: "stethoscope", keywords: "diagnosis health check doctor medical"),

        // Development
        SymbolOption(name: "chevron.left.forwardslash.chevron.right", keywords: "code brackets tags html development"),
        SymbolOption(name: "curlybraces", keywords: "code brackets json syntax development"),
        SymbolOption(name: "curlybraces.square", keywords: "code brackets block scope syntax"),
        SymbolOption(name: "ellipsis.curlybraces", keywords: "code snippet placeholder template log"),
        SymbolOption(name: "terminal", keywords: "shell console command cli prompt"),
        SymbolOption(name: "apple.terminal", keywords: "shell console command cli bash"),
        SymbolOption(name: "macwindow", keywords: "app window ui frontend interface"),
        SymbolOption(name: "swift", keywords: "language code apple programming ios"),
        SymbolOption(name: "puzzlepiece.extension", keywords: "plugin addon integration module install"),
        SymbolOption(name: "cube", keywords: "package module dependency box 3d"),
        SymbolOption(name: "square.stack.3d.up", keywords: "layers architecture deploy platform tiers"),

        // Business
        SymbolOption(name: "creditcard", keywords: "payment billing money purchase finance"),
        SymbolOption(name: "banknote", keywords: "money budget cost cash finance"),
        SymbolOption(name: "cart", keywords: "shop commerce purchase buy checkout"),
        SymbolOption(name: "bag", keywords: "shop order purchase retail store"),
        SymbolOption(name: "gift", keywords: "present perk reward bonus celebration"),
        SymbolOption(name: "ticket", keywords: "issue event support admission pass"),
        SymbolOption(name: "building.2", keywords: "company office client business corporate"),
        SymbolOption(name: "building.columns", keywords: "bank institution government finance legal"),
        SymbolOption(name: "house", keywords: "home personal family property base"),
        SymbolOption(name: "door.left.hand.open", keywords: "onboarding entry exit welcome leave"),
        SymbolOption(name: "globe", keywords: "world international web earth global"),
        SymbolOption(name: "map", keywords: "plan roadmap directions travel navigation"),
        SymbolOption(name: "location", keywords: "place gps position navigate where"),

        // Life
        SymbolOption(name: "star", keywords: "favourite favorite important rating highlight"),
        SymbolOption(name: "heart", keywords: "love health favourite favorite like"),
        SymbolOption(name: "bolt", keywords: "energy fast urgent power lightning"),
        SymbolOption(name: "flame", keywords: "hot urgent streak fire trending"),
        SymbolOption(name: "drop", keywords: "water hydration liquid blood wet"),
        SymbolOption(name: "leaf", keywords: "nature growth eco plant green"),
        SymbolOption(name: "tree", keywords: "nature growth forest plant environment"),
        SymbolOption(name: "carrot", keywords: "food vegetable health diet nutrition"),
        SymbolOption(name: "cup.and.saucer", keywords: "coffee tea break chat cafe"),
        SymbolOption(name: "fork.knife", keywords: "food lunch dinner meal restaurant"),
        SymbolOption(name: "birthday.cake", keywords: "celebration party anniversary dessert treat"),
        SymbolOption(name: "moon", keywords: "night later someday sleep dark"),
        SymbolOption(name: "sun.max", keywords: "day morning bright summer light"),
        SymbolOption(name: "cloud.rain", keywords: "weather storm wet drizzle forecast"),
        SymbolOption(name: "snowflake", keywords: "frozen paused winter cold ice"),
        SymbolOption(name: "thermometer.medium", keywords: "temperature health fever weather degrees"),
        SymbolOption(name: "umbrella", keywords: "protection backup rain cover insurance"),
        SymbolOption(name: "beach.umbrella", keywords: "holiday vacation break summer relax"),
        SymbolOption(name: "airplane", keywords: "travel trip flight journey abroad"),
        SymbolOption(name: "car", keywords: "travel commute drive vehicle road"),
        SymbolOption(name: "bicycle", keywords: "cycling commute ride exercise bike"),
        SymbolOption(name: "tram", keywords: "transport commute train transit rail"),
        SymbolOption(name: "fuelpump", keywords: "energy gas petrol diesel station"),
        SymbolOption(name: "figure.walk", keywords: "progress step stroll exercise hike"),
        SymbolOption(name: "figure.run", keywords: "sport fast exercise sprint jog"),
        SymbolOption(name: "dumbbell", keywords: "gym training exercise weights fitness"),
        SymbolOption(name: "sportscourt", keywords: "game basketball tennis play field"),
        SymbolOption(name: "gamecontroller", keywords: "play video gaming console fun"),
        SymbolOption(name: "dice", keywords: "chance random luck game gamble"),
        SymbolOption(name: "cross.case", keywords: "health medical kit aid emergency"),
        SymbolOption(name: "pills", keywords: "medicine health medication pharmacy vitamins"),
        SymbolOption(name: "bandage", keywords: "fix patch hotfix injury plaster"),
        SymbolOption(name: "pawprint", keywords: "pet animal dog cat wildlife"),
        SymbolOption(name: "hare", keywords: "fast quick rabbit speed agile"),
        SymbolOption(name: "tortoise", keywords: "slow steady turtle patient"),
        SymbolOption(name: "fish", keywords: "animal sea ocean aquarium seafood"),
        SymbolOption(name: "bird", keywords: "animal social tweet fly nature"),
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
