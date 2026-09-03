import CryptoKit
import Foundation

/// Converts models to and from their on-disk Markdown representation and owns
/// the filename conventions. Pure functions — no IO here (see `Library`).
enum MarkdownFiles {

    // MARK: - Identity

    /// The id a record loads under: its `id:` when the file carries a readable
    /// one, otherwise a UUID **derived from the filename**.
    ///
    /// Minting a fresh `UUID()` per load was silent data loss. `Library` matches
    /// records by id, so a file with no `id:` — one written by hand in Obsidian —
    /// arrived under a different identity on every load, and a reload landing
    /// inside a card's ~0.4s save debounce made `updateNote`'s `firstIndex` miss:
    /// the edit was dropped with nothing said.
    ///
    /// Deriving rather than writing an `id:` back is a decision — the user's vault
    /// stays as they left it — and it is what makes the derivation's requirement
    /// strict: the id has to be identical across processes and machines, so
    /// `Hasher` (seeded per process) is unusable. Renaming the file does change
    /// the id, which is the accepted cost of holding the identity nowhere.
    static func identity(_ raw: String?, filename: String) -> UUID {
        if let raw, let id = UUID(uuidString: raw) { return id }
        return derivedID(filename: filename)
    }

    /// SHA-256 over the filename's UTF-8, first 16 bytes, stamped with
    /// RFC-4122's version-4 and variant bits — so a derived id is
    /// indistinguishable from the `UUID()` it replaces everywhere downstream,
    /// `shortID(_:)` and the filename conventions included.
    static func derivedID(filename: String) -> UUID {
        var b = Array(SHA256.hash(data: Data(filename.utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x40
        b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

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

    /// A note as it goes onto the **pasteboard** — the title as an `#` heading,
    /// a blank line, then the body.
    ///
    /// Deliberately not `encode(_:)`: what is on disk carries frontmatter, which
    /// is Insert's bookkeeping (ids, timestamps, project UUIDs) and means nothing
    /// in the mail or the message someone is pasting into. This is the writing.
    ///
    /// An empty title contributes **nothing** — no heading, no blank line — since
    /// `displayTitle`'s "Untitled" is a label for a card with no name and not a
    /// name anyone wants pasted. A note with neither title nor body copies as the
    /// empty string, and the menu item is disabled in that case.
    static func copyText(_ note: Note) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return body }
        if body.isEmpty { return "# \(title)" }
        return "# \(title)\n\n\(body)"
    }

    static func decodeNote(from content: String, url: URL) -> Note? {
        let parsed = Frontmatter.parse(content)
        let s = parsed.scalars
        let id = identity(s["id"], filename: url.lastPathComponent)
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
        let id = identity(s["id"], filename: url.lastPathComponent)
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
