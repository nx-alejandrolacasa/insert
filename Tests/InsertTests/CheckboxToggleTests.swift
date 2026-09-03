import XCTest
@testable import Insert

/// Pins `MarkdownParser.toggleCheckbox(_:atLine:)` against the whitespace it
/// finds in front of an item, which is where it lost text: the line was
/// validated with a trim over `CharacterSet.whitespaces` — U+00A0 and U+2003
/// included — while the state character's index was counted with an ASCII-only
/// prefix, so one click on a non-breaking-space indent rewrote the `[` and saved
/// `-  x] x`. The two halves are one predicate now, and these are the cases that
/// tell them apart.
///
/// `String`-in, `String`-out, so none of it needs a view — the same reason
/// `MarkdownParserTests` can pin the parser beside it.
final class CheckboxToggleTests: XCTestCase {

    private let nbsp = "\u{00A0}"
    private let emSpace = "\u{2003}"

    /// The bug, and its round trip: a click unchecks the box and leaves every
    /// other character of the line alone, and a second click puts it back.
    func testNonBreakingSpaceIndentRoundTrips() {
        let checked = "\(nbsp)- [x] x"
        let unchecked = "\(nbsp)- [ ] x"
        XCTAssertEqual(MarkdownParser.toggleCheckbox(checked, atLine: 0), unchecked)
        XCTAssertEqual(MarkdownParser.toggleCheckbox(unchecked, atLine: 0), checked)
    }

    /// An em space is the other member of the set the trim accepted and the index
    /// did not, and a paste is how either one arrives.
    func testEmSpaceIndentRoundTrips() {
        let checked = "\(emSpace)- [x] pack"
        let unchecked = "\(emSpace)- [ ] pack"
        XCTAssertEqual(MarkdownParser.toggleCheckbox(checked, atLine: 0), unchecked)
        XCTAssertEqual(MarkdownParser.toggleCheckbox(unchecked, atLine: 0), checked)
    }

    /// A wider indent is still one indent, whatever it is made of, and the flip
    /// must not depend on how many characters it took.
    func testMixedIndentRoundTrips() {
        let checked = " \(nbsp)\t \(emSpace)- [x] deep"
        let unchecked = " \(nbsp)\t \(emSpace)- [ ] deep"
        XCTAssertEqual(MarkdownParser.toggleCheckbox(checked, atLine: 0), unchecked)
        XCTAssertEqual(MarkdownParser.toggleCheckbox(unchecked, atLine: 0), checked)
    }

    /// Only the addressed line is touched: the item above keeps its indent and
    /// its state, which is what "the wrong character" would have shown up as.
    func testOnlyTheAddressedLineChanges() {
        XCTAssertEqual(
            MarkdownParser.toggleCheckbox("\(nbsp)- [x] parent\n\(nbsp)\(nbsp)- [ ] child", atLine: 1),
            "\(nbsp)- [x] parent\n\(nbsp)\(nbsp)- [x] child"
        )
    }

    /// The ASCII indents are the behaviour that was already right, kept here so
    /// the fix is pinned from both sides.
    func testAsciiIndentsAreUnchanged() {
        XCTAssertEqual(MarkdownParser.toggleCheckbox("- [ ] flat", atLine: 0), "- [x] flat")
        XCTAssertEqual(MarkdownParser.toggleCheckbox("  - [ ] spaced", atLine: 0), "  - [x] spaced")
        XCTAssertEqual(MarkdownParser.toggleCheckbox("\t- [x] tabbed", atLine: 0), "\t- [ ] tabbed")
    }

    /// A custom state reads as checked, so a click unchecks it — under a
    /// non-ASCII indent as under any other.
    func testCustomStateUnchecksUnderANonAsciiIndent() {
        XCTAssertEqual(
            MarkdownParser.toggleCheckbox("\(nbsp)- [-] parked", atLine: 0),
            "\(nbsp)- [ ] parked"
        )
    }

    /// A line that is not a checklist item edits nothing, whatever it is indented
    /// with — the guard that keeps a stale index from flipping a bystander.
    func testNonCheckboxLinesAreANoOp() {
        XCTAssertNil(MarkdownParser.toggleCheckbox("\(nbsp)- plain bullet", atLine: 0))
        XCTAssertNil(MarkdownParser.toggleCheckbox("\(emSpace)prose", atLine: 0))
        XCTAssertNil(MarkdownParser.toggleCheckbox("\(nbsp)1. numbered", atLine: 0))
        XCTAssertNil(MarkdownParser.toggleCheckbox("\(nbsp)\(emSpace)", atLine: 0))
        XCTAssertNil(MarkdownParser.toggleCheckbox("", atLine: 0))
        XCTAssertNil(MarkdownParser.toggleCheckbox("\(nbsp)- [ ] only line", atLine: 2))
    }

    /// What the parser renders as a checkbox is what the toggle has to accept:
    /// the item is addressed by the line `parse` recorded, so the two must agree
    /// about which lines those are.
    func testEveryRenderedCheckboxCanBeToggled() {
        let source = "- [ ] flat\n  - [x] spaced\n\t- [ ] tabbed\n\(nbsp)- [x] nbsp\n\(emSpace)- [ ] em"
        var checkboxLines: [Int] = []
        for block in MarkdownParser.parse(source) {
            if case .list(let items) = block {
                checkboxLines += items.filter { $0.checked != nil }.map(\.line)
            }
        }
        XCTAssertEqual(checkboxLines, [0, 1, 2, 3, 4])
        for line in checkboxLines {
            XCTAssertNotNil(
                MarkdownParser.toggleCheckbox(source, atLine: line),
                "the parser drew a checkbox on line \(line) that the toggle refuses"
            )
        }
    }
}
