import Foundation

/// A tiny, dependency-free reader/writer for the slice of YAML frontmatter this
/// app uses: `key: value` scalars, single-line flow arrays (`[a, b]`) and, for
/// `Projects.md`, a sequence of single-line flow maps (`- {k: v, ...}`).
///
/// This is deliberately NOT a general YAML parser — it round-trips the files
/// the app writes and tolerates the common shapes a human (or Obsidian) might
/// produce, but no more.
enum Frontmatter {
    /// The result of splitting a Markdown file into its frontmatter and body.
    struct Parsed {
        /// Top-level `key: value` scalars (indented / nested lines excluded).
        var scalars: [String: String]
        /// The raw text inside the `---` fence (for custom block parsing).
        var raw: String
        /// Everything after the closing fence.
        var body: String
    }

    /// Splits `content` into frontmatter + body. If there's no frontmatter
    /// fence, everything is treated as body.
    static func parse(_ content: String) -> Parsed {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            return Parsed(scalars: [:], raw: "", body: normalized)
        }
        let afterOpen = normalized.dropFirst(4) // "---\n"
        guard let closeRange = afterOpen.range(of: "\n---") else {
            return Parsed(scalars: [:], raw: "", body: normalized)
        }
        let rawBlock = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
        var rest = afterOpen[closeRange.upperBound...]
        // Skip the rest of the closing-fence line and one trailing newline.
        if let nl = rest.firstIndex(of: "\n") {
            rest = rest[rest.index(after: nl)...]
        } else {
            rest = rest[rest.endIndex...]
        }

        var scalars: [String: String] = [:]
        for line in rawBlock.split(separator: "\n", omittingEmptySubsequences: false) {
            // Only capture non-indented `key: value` lines.
            guard let first = line.first, first != " ", first != "-", first != "\t" else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { scalars[key] = unquote(value) }
        }
        return Parsed(scalars: scalars, raw: rawBlock, body: String(rest))
    }

    /// Assembles a Markdown file from ordered frontmatter lines + body.
    static func compose(lines: [String], body: String) -> String {
        var out = "---\n"
        out += lines.joined(separator: "\n")
        out += "\n---\n"
        out += body
        if !body.hasSuffix("\n") { out += "\n" }
        return out
    }

    // MARK: - Scalars

    static func quote(_ value: String) -> String {
        // Quote when the value could otherwise be misread (empty, has special
        // chars, or leading/trailing space).
        let needsQuote = value.isEmpty
            || value != value.trimmingCharacters(in: .whitespaces)
            || value.contains(where: { ":#[]{}\",".contains($0) })
        if !needsQuote { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        let inner = String(value.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - Flow arrays: [a, b, c]

    static func encodeArray(_ items: [String]) -> String {
        "[" + items.map(quote).joined(separator: ", ") + "]"
    }

    static func decodeArray(_ value: String) -> [String] {
        var v = value.trimmingCharacters(in: .whitespaces)
        guard v.hasPrefix("["), v.hasSuffix("]") else {
            return v.isEmpty ? [] : [unquote(v)]
        }
        v = String(v.dropFirst().dropLast())
        return splitTopLevel(v, separator: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Flow maps: {k: v, k2: "v2"}

    static func encodeMap(_ pairs: [(String, String)]) -> String {
        "{" + pairs.map { "\($0.0): \(quote($0.1))" }.joined(separator: ", ") + "}"
    }

    static func decodeMap(_ value: String) -> [String: String] {
        var v = value.trimmingCharacters(in: .whitespaces)
        guard v.hasPrefix("{"), v.hasSuffix("}") else { return [:] }
        v = String(v.dropFirst().dropLast())
        var map: [String: String] = [:]
        for pair in splitTopLevel(v, separator: ",") {
            guard let colon = pair.firstIndex(of: ":") else { continue }
            let key = String(pair[pair.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let val = String(pair[pair.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { map[key] = unquote(val) }
        }
        return map
    }

    /// Splits on `separator`, ignoring separators inside quotes or brackets.
    private static func splitTopLevel(_ s: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuote = false
        var depth = 0
        var escaped = false
        for ch in s {
            if escaped { current.append(ch); escaped = false; continue }
            switch ch {
            case "\\": current.append(ch); escaped = true
            case "\"": inQuote.toggle(); current.append(ch)
            case "[", "{": if !inQuote { depth += 1 }; current.append(ch)
            case "]", "}": if !inQuote { depth = max(0, depth - 1) }; current.append(ch)
            case separator where !inQuote && depth == 0:
                parts.append(current); current = ""
            default: current.append(ch)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty || !parts.isEmpty {
            parts.append(current)
        }
        return parts
    }
}

// MARK: - Date formatting

/// Timestamps use RFC-3339 (`2026-07-24T10:00:00Z`); due dates use plain days
/// (`2026-07-24`) to match Obsidian / todo.txt conventions.
enum DateCoding {
    // Formatters aren't Sendable, so build a fresh one per call rather than
    // sharing mutable global state (this app's file counts make the cost
    // negligible).
    private static func timestampFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    private static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    static func string(_ date: Date) -> String { timestampFormatter().string(from: date) }

    static func date(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        return timestampFormatter().date(from: s) ?? day(s)
    }

    static func dayString(_ date: Date) -> String { dayFormatter().string(from: date) }

    static func day(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        return dayFormatter().date(from: s)
    }
}
