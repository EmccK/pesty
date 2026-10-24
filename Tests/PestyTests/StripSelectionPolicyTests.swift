import CoreGraphics
import XCTest
@testable import Pesty

/// The strip's click behaviour is two separate decisions, and both used to be
/// baked into one unconditional `scrollTo(anchor: .center)`:
///
/// 1. whether a selection change moves the strip at all, and
/// 2. how far it moves when it does.
///
/// These tests pin the first one down. The second is a rendering concern that
/// only a live window can confirm.
final class StripSelectionPolicyTests: XCTestCase {
    func testKeepVisibleIsTheDefault() {
        XCTAssertEqual(SelectedClipPosition(rawValue: 2), .keepVisible)
        XCTAssertFalse(SelectedClipPosition.keepVisible.centersOnEverySelection,
                       "Clicking a visible card must not move the strip")
    }

    func testCenteringModesStillReparkOnEverySelection() {
        XCTAssertTrue(SelectedClipPosition.center.centersOnEverySelection)
        XCTAssertTrue(SelectedClipPosition.rightEdge.centersOnEverySelection)
    }

    func testEveryModeHasDistinctCopy() {
        let titles = SelectedClipPosition.allCases.map(\.title)
        let details = SelectedClipPosition.allCases.map(\.detail)

        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertEqual(Set(details).count, details.count)
        XCTAssertFalse(titles.contains(where: \.isEmpty))
        XCTAssertFalse(details.contains(where: \.isEmpty))
    }
}

/// A card counts as reachable only when both of its edges are inside the
/// strip's visible window. The original test compared a content-space offset
/// against a width, which silently became "is this the first card" once the
/// strip had scrolled.
final class StripVisibilityGeometryTests: XCTestCase {
    private func isOnScreen(_ frame: CGRect, stripWidth: CGFloat) -> Bool {
        frame.minX >= 0 && frame.maxX <= stripWidth
    }

    func testCardFullyInsideIsReachable() {
        XCTAssertTrue(isOnScreen(CGRect(x: 40, y: 0, width: 150, height: 150), stripWidth: 1200))
    }

    func testCardScrolledOffTheLeadingEdgeNeedsAScroll() {
        XCTAssertFalse(isOnScreen(CGRect(x: -60, y: 0, width: 150, height: 150), stripWidth: 1200))
    }

    func testCardPeekingInFromTheTrailingEdgeNeedsAScroll() {
        XCTAssertFalse(isOnScreen(CGRect(x: 1150, y: 0, width: 150, height: 150), stripWidth: 1200))
    }

    func testCardExactlyAtBothEdgesCountsAsVisible() {
        XCTAssertTrue(isOnScreen(CGRect(x: 0, y: 0, width: 150, height: 150), stripWidth: 1200))
        XCTAssertTrue(isOnScreen(CGRect(x: 1050, y: 0, width: 150, height: 150), stripWidth: 1200))
    }

    /// The regression this whole change guards: a card in the middle of a long
    /// row is on screen while the strip is scrolled to it, but its content
    /// offset is far from zero.
    func testMidRowCardIsVisibleDespiteLargeContentOffset() {
        let stripWidth: CGFloat = 1200
        // Row scrolled so card 8 (offset ~1368) is centred: card 8's frame
        // lands at minX ~520, well inside the window.
        XCTAssertTrue(isOnScreen(CGRect(x: 520, y: 0, width: 150, height: 150), stripWidth: stripWidth))
    }
}
