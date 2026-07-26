import Foundation

/// Converts models to and from their on-disk Markdown representation and owns
/// the filename conventions. Pure functions — no IO here (see `Library`).
enum MarkdownFiles {

    // MARK: - Filenames

    /// A filesystem- and Obsidian-friendly slug of `text`.
    static func slug(_ text: String) -> String {
        let lower = text.lowercased()
        var out = ""
        var lastDash = false
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let capped = String(trimmed.prefix(60))
        return capped.isEmpty ? "untitled" : capped
    }

    static func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).lowercased()
    }

    static func noteFilename(_ note: Note) -> String {
        "\(slug(note.title))-\(shortID(note.id)).md"
    }

    static func taskFilename(_ task: TaskItem) -> String {
        "\(slug(task.title))-\(shortID(task.id)).md"
    }

    // MARK: - Note <-> Markdown

    static func encode(_ note: Note) -> String {
        var lines: [String] = []
        lines.append("id: \(note.id.uuidString)")
        lines.append("title: \(Frontmatter.quote(note.title))")
        lines.append("symbol: \(Frontmatter.quote(note.symbol))")
        lines.append("type: \(Frontmatter.quote(note.typeID))")
        lines.append("projects: \(Frontmatter.encodeArray(note.projectIDs.map(\.uuidString)))")
        lines.append("created: \(DateCoding.string(note.created))")
        lines.append("updated: \(DateCoding.string(note.updated))")
        return Frontmatter.compose(lines: lines, body: note.body)
    }

    static func decodeNote(from content: String, url: URL) -> Note? {
        let parsed = Frontmatter.parse(content)
        let s = parsed.scalars
        let id = UUID(uuidString: s["id"] ?? "") ?? UUID()
        // `projects: [a, b]` is the current shape. Files written before notes
        // could belong to several projects carry a single `project: <id>`, so
        // fall back to that — rewritten into the list shape on the next save.
        var projectIDs = Frontmatter.decodeArray(s["projects"] ?? "[]").compactMap(UUID.init(uuidString:))
        if projectIDs.isEmpty, let legacy = s["project"].flatMap({ UUID(uuidString: $0) }) {
            projectIDs = [legacy]
        }
        return Note(
            id: id,
            title: s["title"] ?? "",
            // `emoji` is what files written before icons became SF Symbols carry;
            // `resolve` maps the ones Insert used to seed and defaults the rest.
            symbol: SymbolCatalog.resolve(s["symbol"] ?? s["emoji"] ?? "", fallback: SymbolCatalog.defaultNote),
            typeID: s["type"] ?? NoteType.noteID,
            projectIDs: projectIDs,
            body: parsed.body.trimmingCharacters(in: .newlines),
            created: DateCoding.date(s["created"] ?? "") ?? Date(),
            updated: DateCoding.date(s["updated"] ?? "") ?? Date(),
            fileURL: url
        )
    }

    // MARK: - Task <-> Markdown

    static func encode(_ task: TaskItem) -> String {
        var lines: [String] = []
        lines.append("id: \(task.id.uuidString)")
        lines.append("title: \(Frontmatter.quote(task.title))")
        lines.append("done: \(task.done)")
        lines.append("completed: \(task.completed.map(DateCoding.string) ?? "")")
        lines.append("projects: \(Frontmatter.encodeArray(task.projectIDs.map(\.uuidString)))")
        if let due = task.due {
            lines.append("due: \(DateCoding.dayString(due))")
        } else {
            lines.append("due: ")
        }
        lines.append("created: \(DateCoding.string(task.created))")
        lines.append("updated: \(DateCoding.string(task.updated))")
        return Frontmatter.compose(lines: lines, body: task.body)
    }

    static func decodeTask(from content: String, url: URL) -> TaskItem? {
        let parsed = Frontmatter.parse(content)
        let s = parsed.scalars
        let id = UUID(uuidString: s["id"] ?? "") ?? UUID()
        let projectIDs = Frontmatter.decodeArray(s["projects"] ?? "[]").compactMap(UUID.init(uuidString:))
        let done = (s["done"] ?? "false").lowercased() == "true"
        return TaskItem(
            id: id,
            title: s["title"] ?? "",
            body: parsed.body.trimmingCharacters(in: .newlines),
            done: done,
            // Files written before this field existed — or ticked off by hand in
            // Obsidian — have no stamp; `Library` falls back to `updated`.
            completed: done ? DateCoding.date(s["completed"] ?? "") : nil,
            projectIDs: projectIDs,
            due: DateCoding.day(s["due"] ?? ""),
            created: DateCoding.date(s["created"] ?? "") ?? Date(),
            updated: DateCoding.date(s["updated"] ?? "") ?? Date(),
            fileURL: url
        )
    }

    // MARK: - Projects.md <-> Markdown

    static func encodeProjects(_ projects: [Project]) -> String {
        var lines: [String] = ["projects:"]
        for p in projects {
            let map = Frontmatter.encodeMap([
                ("id", p.id.uuidString),
                ("name", p.name),
                ("symbol", p.symbol),
                ("tint", p.tint.rawValue),
                ("created", DateCoding.string(p.created)),
                ("lastUsed", DateCoding.string(p.lastUsed)),
            ])
            lines.append("  - \(map)")
        }
        // A human-readable body so the file is pleasant to open in Obsidian.
        var body = "# Projects\n\n"
        if projects.isEmpty {
            body += "_No projects yet._\n"
        } else {
            for p in projects {
                body += "- \(p.displayName)\n"
            }
        }
        return Frontmatter.compose(lines: lines, body: body)
    }

    static func decodeProjects(from content: String) -> [Project] {
        let parsed = Frontmatter.parse(content)
        var projects: [Project] = []
        for rawLine in parsed.raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ") else { continue }
            let mapText = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let map = Frontmatter.decodeMap(mapText)
            guard let idStr = map["id"], let id = UUID(uuidString: idStr) else { continue }
            projects.append(Project(
                id: id,
                name: map["name"] ?? "Untitled",
                symbol: SymbolCatalog.resolve(map["symbol"] ?? map["emoji"] ?? "",
                                              fallback: SymbolCatalog.defaultProject),
                // Projects written before they had colours default to blue.
                tint: map["tint"].flatMap(Tint.init(rawValue:)) ?? .blue,
                created: DateCoding.date(map["created"] ?? "") ?? Date(),
                lastUsed: DateCoding.date(map["lastUsed"] ?? "") ?? Date()
            ))
        }
        return projects
    }
}
