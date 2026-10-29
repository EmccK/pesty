import CoreGraphics
import XCTest
@testable import Pesty

final class CardHitTestingTests: XCTestCase {
    func testClickOnTheTrailingEdgeHitsTheCard() {
        let id = UUID()
        let frame = CGRect(x: 10, y: 10, width: 100, height: 100)
        let hit = CardHitTesting.bestID(
            at: CGPoint(x: 110, y: 50),
            slots: [CardHit(id: id, frame: frame)],
            visibleIDs: [id]
        )
        XCTAssertEqual(hit, id)
    }

    func testInvisibleSlotDoesNotStealTheClick() {
        let stale = UUID()
        let clicked = UUID()
        let slots = [
            CardHit(id: stale, frame: CGRect(x: 0, y: 0, width: 400, height: 200)),
            CardHit(id: clicked, frame: CGRect(x: 180, y: 20, width: 150, height: 150)),
        ]
        let hit = CardHitTesting.bestID(
            at: CGPoint(x: 250, y: 90),
            slots: slots,
            visibleIDs: [clicked]
        )
        XCTAssertEqual(hit, clicked)
    }

    func testOverlapPrefersTheCardWhoseCenterIsNearest() {
        let older = UUID()
        let clicked = UUID()
        let slots = [
            CardHit(id: older, frame: CGRect(x: 0, y: 0, width: 200, height: 200)),
            CardHit(id: clicked, frame: CGRect(x: 160, y: 40, width: 150, height: 150)),
        ]
        let hit = CardHitTesting.bestID(
            at: CGPoint(x: 190, y: 100),
            slots: slots,
            visibleIDs: [older, clicked]
        )
        XCTAssertEqual(hit, clicked)
    }

    func testPointOutsideEveryCardMisses() {
        let id = UUID()
        let hit = CardHitTesting.bestID(
            at: CGPoint(x: 0, y: 0),
            slots: [CardHit(id: id, frame: CGRect(x: 20, y: 20, width: 100, height: 100))],
            visibleIDs: [id]
        )
        XCTAssertNil(hit)
    }
}
