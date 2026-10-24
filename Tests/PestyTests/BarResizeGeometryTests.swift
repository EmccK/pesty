import XCTest
@testable import Pesty

final class BarResizeGeometryTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 875)

    func testPanelFloatsOffEveryEdge() {
        let frame = BarResizeGeometry.panelFrame(for: 349, in: visibleFrame)

        XCTAssertEqual(frame.minX, visibleFrame.minX + BarResizeGeometry.sideInset)
        XCTAssertEqual(frame.minY, visibleFrame.minY + BarResizeGeometry.bottomInset)
        XCTAssertEqual(frame.width,
                       visibleFrame.width - BarResizeGeometry.sideInset * 2)
        XCTAssertEqual(frame.height, 349)
    }

    /// A display narrower than the minimum panel width gives up the side
    /// margin rather than letting the bar collapse to a sliver.
    func testNarrowDisplayTradesMarginForWidth() {
        let narrow = CGRect(x: 0, y: 0, width: 460, height: 875)
        let frame = BarResizeGeometry.panelFrame(for: 349, in: narrow)

        XCTAssertEqual(frame.minX, narrow.minX)
        XCTAssertEqual(frame.width, narrow.width)
    }

    /// The panel is placed one inset above the visible frame, so that inset has
    /// to come out of the height budget too: without it a bar dragged to the
    /// display's full height poked 8 pt into the menu bar.
    func testTallRequestNeverEscapesTheVisibleFrame() {
        let short = CGRect(x: 0, y: 0, width: 1440, height: 700)
        let frame = BarResizeGeometry.panelFrame(for: 720, in: short)

        XCTAssertEqual(frame.height, 700 - BarResizeGeometry.bottomInset)
        XCTAssertLessThanOrEqual(frame.maxY, short.maxY)
    }

    func testCancellingAResizeRestoresTheInsetFrame() {
        let session = BarResizeSession(initialPanelHeight: 400,
                                       initialScreenY: 200,
                                       visibleFrame: visibleFrame)

        XCTAssertEqual(session.cancelledFrame,
                       BarResizeGeometry.insetFrame(height: 400, in: visibleFrame))
        XCTAssertEqual(session.frame(atScreenY: 260).height, 460)
    }
}
