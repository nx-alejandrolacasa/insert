import AppKit
import SwiftUI
import XCTest
@testable import Insert

/// Pins the one layout promise `CollapsibleMarkdown` makes to the card around
/// it: the collapsed teaser never widens its row. The teaser is deliberately
/// laid out at its natural single-line width (`fixedSize`) so a cut line fades
/// instead of truncating to an ellipsis — and a `frame(maxWidth:)` with no
/// minimum is "no smaller than its child", so that natural width silently
/// became the whole card's minimum. A task whose first line outmeasured the
/// column blew its island past the window edge and pushed the checkbox
/// off-screen; nothing else in the app would have said so.
final class CollapsibleLayoutTests: XCTestCase {

    @MainActor
    func testALongTeaserDoesNotWidenItsRow() {
        let view = CollapsibleMarkdown(
            markdown: "Create search solution comparisons (basic vs. advanced) and then some",
            textStyle: .callout,
            previewLines: 1,
            expanded: .constant(false),
            chevronBox: CGSize(width: 20, height: 14),
            expandLabel: "Expand",
            collapseLabel: "Collapse"
        )
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 200, height: nil)
        guard let image = renderer.nsImage else { return XCTFail("nothing rendered") }
        XCTAssertEqual(
            image.size.width, 200, accuracy: 0.5,
            "the teaser's natural width must overflow into the clip, not become the row's minimum"
        )
    }
}
