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
    // `ISO8601DateFormatter` and `DateFormatter` are classes and not Sendable, so
    // this used to build a fresh one per call rather than share mutable global
    // state — with a note that "this app's file counts make the cost negligible".
    //
    // They don't. Constructing those formatters was **62% of the cost of loading a
    // note** and about three quarters of a task's: 180 µs per note against 19 µs
    // to read its file off disk. Every date on every record paid for a formatter
    // that was then thrown away.
    //
    // So: `Calendar` and `Date.ISO8601FormatStyle` are Sendable *value* types, and
    // can simply be held. On top of that the canonical shapes — the ones Insert
    // itself writes — are parsed by hand, because integer arithmetic on twenty
    // ASCII characters beats any formatter. Anything else (a hand-edited offset,
    // fractional seconds) falls through to the format style, so the reader stays
    // exactly as tolerant as it was. `DateCodingTests` pins both halves against
    // the formatters this replaced.

    /// Gregorian, POSIX, auto-updating zone — matching the `DateFormatter` this
    /// replaced, including its use of the *local* zone for day-granularity dates.
    private static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.timeZone = TimeZone.autoupdatingCurrent
        return c
    }()

    /// `2026-07-24T10:00:00Z` — the same text `.withInternetDateTime` produced.
    private static let iso = Date.ISO8601FormatStyle(timeZone: .gmt)

    // MARK: Timestamps (RFC-3339)

    static func string(_ date: Date) -> String { iso.format(date) }

    static func date(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if let fast = fastTimestamp(s) { return fast }
        if let parsed = try? Date(s, strategy: iso.parseStrategy) { return parsed }
        // A `created:` written as a bare day still reads, as it always did.
        return day(s)
    }

    // MARK: Days (`yyyy-MM-dd`, local midnight)

    static func dayString(_ date: Date) -> String {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return pad(c.year ?? 0, 4) + "-" + pad(c.month ?? 0, 2) + "-" + pad(c.day ?? 0, 2)
    }

    static func day(_ string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)
        guard let (y, m, d) = ymd(s) else { return nil }
        // Through `Calendar`, not by hand: local midnight depends on the zone's
        // offset *on that day*, which is a DST question and not arithmetic.
        return gregorian.date(from: DateComponents(year: y, month: m, day: d))
    }

    // MARK: - Fast paths

    /// `yyyy-MM-ddTHH:mm:ssZ` exactly — the shape `string(_:)` writes — parsed as
    /// integers straight to an epoch offset. `nil` for anything else, which sends
    /// the caller to the format style.
    private static func fastTimestamp(_ s: String) -> Date? {
        let a = s.utf8
        guard a.count == 20, a.last == UInt8(ascii: "Z") else { return nil }
        let c = Array(a)
        guard c[4] == UInt8(ascii: "-"), c[7] == UInt8(ascii: "-"),
              c[10] == UInt8(ascii: "T"), c[13] == UInt8(ascii: ":"), c[16] == UInt8(ascii: ":")
        else { return nil }
        guard let year = int(c, 0, 4), let month = int(c, 5, 2), let day = int(c, 8, 2),
              let hour = int(c, 11, 2), let minute = int(c, 14, 2), let second = int(c, 17, 2),
              (1...12).contains(month), (1...31).contains(day),
              hour < 24, minute < 60, second <= 60
        else { return nil }
        let seconds = daysFromEpoch(year: year, month: month, day: day) * 86_400
            + hour * 3600 + minute * 60 + second
        return Date(timeIntervalSince1970: Double(seconds))
    }

    /// Leading `yyyy-MM-dd` of a string, as integers.
    private static func ymd(_ s: String) -> (Int, Int, Int)? {
        let c = Array(s.utf8)
        guard c.count >= 10, c[4] == UInt8(ascii: "-"), c[7] == UInt8(ascii: "-"),
              let y = int(c, 0, 4), let m = int(c, 5, 2), let d = int(c, 8, 2),
              (1...12).contains(m), (1...31).contains(d)
        else { return nil }
        return (y, m, d)
    }

    private static func int(_ bytes: [UInt8], _ start: Int, _ length: Int) -> Int? {
        var value = 0
        for i in start..<(start + length) {
            let digit = Int(bytes[i]) - 48
            guard (0...9).contains(digit) else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    /// Days from 1970-01-01 to a proleptic-Gregorian date, by Howard Hinnant's
    /// `days_from_civil`: shift the year to start in March so leap day lands at the
    /// end, then count era/year-of-era/day-of-year. No loops, no lookup tables.
    private static func daysFromEpoch(year: Int, month: Int, day: Int) -> Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400                                     // 0…399
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy             // 0…146096
        return era * 146_097 + doe - 719_468
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let s = String(value)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }
}
