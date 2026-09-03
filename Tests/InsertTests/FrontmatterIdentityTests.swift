import Foundation
import XCTest
@testable import Insert

/// Pins the two ways a record's *identity and framing* on disk could be lost
/// without anything on screen saying so.
///
/// Both are data-loss faults rather than wrong pixels, and both are quiet.
/// `Frontmatter.quote` used to write a newline raw, so a pasted line inside a
/// title continued the frontmatter — and a pasted line reading `---` closed the
/// fence, leaving the rest of the record to be re-read as body. And a file with
/// no `id:` was minted a fresh `UUID()` on every load, so a reload landing inside
/// a card's save debounce made `Library`'s match by id miss and dropped the edit.
///
/// The escaping is asserted through `encode` → `parse`/`decode` rather than on
/// `quote` alone, because what has to hold is the *round trip*: it is the file the
/// app wrote being read back that the user's writing depends on.
final class FrontmatterIdentityTests: XCTestCase {

    // MARK: - Line breaks in a scalar

    func testATitleContainingANewlineSurvivesEncodeAndParse() throws {
        let note = Note(title: "Sprint review\nand retro", body: "Body stays put.")
        let decoded = try XCTUnwrap(MarkdownFiles.decodeNote(from: MarkdownFiles.encode(note),
                                                            url: Self.url("sprint-review-abc12345.md")))
        XCTAssertEqual(decoded.title, "Sprint review\nand retro")
        XCTAssertEqual(decoded.body, "Body stays put.")
        XCTAssertEqual(decoded.id, note.id)
    }

    /// The newline must not reach the file at all — a value split across two
    /// frontmatter lines round-trips only by accident of what the second half
    /// happens to say, and `id:`/`created:` follow it.
    func testAScalarIsWrittenOnOneLine() {
        let encoded = MarkdownFiles.encode(Note(title: "one\ntwo\rthree", body: "b"))
        let lines = Frontmatter.parse(encoded).raw
            .split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.count, 7, "seven scalars, so seven lines: \(lines)")
        XCTAssertTrue(lines.contains { $0.hasPrefix("title: ") })
        XCTAssertFalse(encoded.contains("one\ntwo"), "the newline never reaches the file")
        XCTAssertFalse(encoded.contains("two\rthree"))
    }

    /// The reported failure: a value carrying a line that reads `---` closed the
    /// fence early, so `parse` handed back a truncated body and lost every scalar
    /// written after the paste.
    func testAValueContainingAFenceLineDoesNotTruncateTheRecord() throws {
        let title = "Pasted\n---\nfrom a doc"
        let body = "First paragraph.\n\nSecond paragraph."
        let note = Note(title: title, typeID: "meeting", body: body)

        let parsed = Frontmatter.parse(MarkdownFiles.encode(note))
        XCTAssertEqual(parsed.scalars["title"], title)
        XCTAssertEqual(parsed.scalars["type"], "meeting")
        XCTAssertEqual(parsed.scalars["id"], note.id.uuidString, "scalars after the paste survive")
        XCTAssertEqual(parsed.body.trimmingCharacters(in: .newlines), body)

        let decoded = try XCTUnwrap(MarkdownFiles.decodeNote(from: MarkdownFiles.encode(note),
                                                            url: Self.url("pasted-abc12345.md")))
        XCTAssertEqual(decoded.title, title)
        XCTAssertEqual(decoded.body, body)
    }

    func testACarriageReturnRoundTrips() throws {
        let task = TaskItem(title: "Old Mac\rline", body: "Notes.")
        let decoded = try XCTUnwrap(MarkdownFiles.decodeTask(from: MarkdownFiles.encode(task),
                                                            url: Self.url("old-mac-abc12345.md")))
        XCTAssertEqual(decoded.title, "Old Mac\rline")
        XCTAssertEqual(decoded.body, "Notes.")

        XCTAssertEqual(Frontmatter.unquote(Frontmatter.quote("a\r\nb")), "a\r\nb")
        XCTAssertEqual(Frontmatter.quote("a\r\nb"), "\"a\\r\\nb\"")
    }

    /// The escaping has to be a *bijection*: a value that already contains the
    /// two characters `\` and `n` must not read back as a newline, which is what a
    /// chain of `replacingOccurrences` passes would do.
    ///
    /// `"\r\n"` is in the list because it is one *grapheme cluster*, so a
    /// `Character`-level scan for `"\r"` and `"\n"` matches neither half and lets
    /// a Windows line ending straight through. It did, until this test.
    func testEscapesAreExactInverses() {
        for value in ["a\\nb", "a\nb", "\\", "\\\\n", "quote\"inside", "back\\slash",
                      "mixed \"\\n\" and \n real", "\r", "\n\n", "trailing\\",
                      "a\r\nb", "x\r\n---\r\ny", "\r\n", "emoji 🤝🏻 stays",
                      "e\u{0301}\naccent", "\u{2028}separator", "", " lead", "trail "] {
            XCTAssertEqual(Frontmatter.unquote(Frontmatter.quote(value)), value,
                           "round trip failed for \(value.debugDescription)")
            XCTAssertFalse(Frontmatter.quote(value).unicodeScalars.contains { $0 == "\n" || $0 == "\r" },
                           "a line break reached the file for \(value.debugDescription)")
        }
    }

    /// A newline in a *project name* is the same fault one container down: the
    /// projects list is a flow map per line, and `decodeProjects` reads it by line.
    func testAProjectNameContainingANewlineRoundTrips() throws {
        let project = Project(name: "Client\nWork", tint: .green)
        let decoded = MarkdownFiles.decodeProjects(from: MarkdownFiles.encodeProjects([project]))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.name, "Client\nWork")
        XCTAssertEqual(decoded.first?.id, project.id)
        XCTAssertEqual(decoded.first?.tint, Tint.green)
    }

    // MARK: - Identity of an id-less file

    private static let idless = """
    ---
    title: Written in Obsidian
    ---
    Some writing.
    """

    func testAnIdlessFileDecodesToTheSameIdTwice() throws {
        let url = Self.url("written-in-obsidian.md")
        let first = try XCTUnwrap(MarkdownFiles.decodeNote(from: Self.idless, url: url))
        let second = try XCTUnwrap(MarkdownFiles.decodeNote(from: Self.idless, url: url))
        XCTAssertEqual(first.id, second.id)

        let task = try XCTUnwrap(MarkdownFiles.decodeTask(from: Self.idless, url: url))
        XCTAssertEqual(task.id, first.id, "both decoders derive identity the same way")
    }

    /// The folder a file is reached through must not change its id — `Library`
    /// moves a task between `Tasks/` and `Tasks/Done/`, and the derivation is
    /// over the filename alone.
    func testTheDerivationReadsTheFilenameNotThePath() {
        let pending = MarkdownFiles.decodeNote(from: Self.idless, url: Self.url("Tasks/ship-it.md"))
        let done = MarkdownFiles.decodeNote(from: Self.idless, url: Self.url("Tasks/Done/ship-it.md"))
        XCTAssertEqual(pending?.id, done?.id)
    }

    func testDifferentFilenamesDeriveDifferentIds() throws {
        let a = try XCTUnwrap(MarkdownFiles.decodeNote(from: Self.idless, url: Self.url("one.md")))
        let b = try XCTUnwrap(MarkdownFiles.decodeNote(from: Self.idless, url: Self.url("two.md")))
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(MarkdownFiles.derivedID(filename: "one.md"),
                          MarkdownFiles.derivedID(filename: "onf.md"))
    }

    /// Derived, not random: the same filename has to give the same id in a *later
    /// process*, so the expected value is **written down** rather than compared
    /// with itself — an in-process comparison passes just as happily against a
    /// per-process seed, which is the failure this exists to catch. Changing the
    /// hash construction on purpose means regenerating these two lines, and
    /// re-identifying every id-less file in every vault with them.
    func testTheDerivedIdIsStableAcrossProcesses() {
        XCTAssertEqual(MarkdownFiles.derivedID(filename: "written-in-obsidian.md").uuidString,
                       "74E36DBC-8241-4761-85EF-3C67B0A9C333")
        XCTAssertEqual(MarkdownFiles.derivedID(filename: "one.md").uuidString,
                       "C8E62EDC-B389-4144-8D0A-C6B2DB9769B4")

        let id = Array(MarkdownFiles.derivedID(filename: "one.md").uuidString)
        XCTAssertEqual(id[14], "4", "v4-shaped, so it is indistinguishable downstream")
        XCTAssertTrue("89abAB".contains(id[19]), "RFC-4122 variant bits: \(String(id))")
    }

    /// A readable `id:` still wins — the derivation is the fallback, not a
    /// replacement, or every existing file would change identity at once.
    func testAPresentIdIsPreferredOverTheDerivation() throws {
        let id = UUID()
        let content = """
        ---
        id: \(id.uuidString)
        title: Has an id
        ---
        Body.
        """
        let note = try XCTUnwrap(MarkdownFiles.decodeNote(from: content, url: Self.url("has-an-id.md")))
        XCTAssertEqual(note.id, id)
        XCTAssertNotEqual(note.id, MarkdownFiles.derivedID(filename: "has-an-id.md"))
    }

    func testAnUnparseableIdFallsBackToTheDerivation() throws {
        let content = """
        ---
        id: not-a-uuid
        title: Broken id
        ---
        Body.
        """
        let note = try XCTUnwrap(MarkdownFiles.decodeNote(from: content, url: Self.url("broken-id.md")))
        XCTAssertEqual(note.id, MarkdownFiles.derivedID(filename: "broken-id.md"))
    }

    // MARK: -

    /// Nothing is read or written — both decoders take the content as a string and
    /// use the URL for its last path component alone.
    private static func url(_ path: String) -> URL {
        URL(fileURLWithPath: "/insert-tests/" + path)
    }
}
