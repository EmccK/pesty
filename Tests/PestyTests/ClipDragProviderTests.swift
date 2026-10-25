import XCTest
import UniformTypeIdentifiers
@testable import Pesty

@MainActor
final class ClipDragProviderTests: XCTestCase {
    /// A card dragged inside the bar has to carry its own identity, not just its
    /// content. The content representations (text, PNG, file URL) are what a drop
    /// into another app consumes; a drop target inside Pesty needs the id, or it
    /// cannot tell one of our cards from something dragged in from elsewhere and
    /// would import a second copy instead of pinning the clip being dragged.
    func testDragCarriesClipIdentityAlongsideItsContent() throws {
        let item = ClipItem(
            id: UUID(uuidString: "5B1C0C61-2E4E-4E2F-9A2C-0F1C8A9E4D31")!,
            type: .text,
            text: "dragged clip",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let provider = ClipDragProvider.make(for: item)

        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(ClipDragProvider.clipType.identifier))
        // The content registration is still there, so dragging a card out of
        // Pesty into another app keeps working.
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier))

        let loaded = expectation(description: "clip id loaded")
        provider.loadDataRepresentation(forTypeIdentifier: ClipDragProvider.clipType.identifier) { data, error in
            defer { loaded.fulfill() }
            XCTAssertNil(error)
            guard let data, let raw = String(data: data, encoding: .utf8) else {
                return XCTFail("clip identity payload missing")
            }
            XCTAssertEqual(UUID(uuidString: raw), item.id)
        }
        wait(for: [loaded], timeout: 2)
    }

    /// The drop target matches on this exact identifier, and the drag source
    /// registers under it, so the two have to agree.
    func testClipTypeIdentifierIsStable() {
        XCTAssertEqual(ClipDragProvider.clipType.identifier, "com.greycorelabs.pesty.clip")
    }

    /// The identifier is also declared in `packaging/Info.plist` under
    /// `UTExportedTypeDeclarations`. The drop target matches it as a plain
    /// pasteboard string, so the declaration is not what makes dropping work -
    /// but it is what makes the type visible outside Pesty, and losing it would
    /// be a silent regression no other test would notice.
    func testClipTypeIsDeclaredInTheAppManifest() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PestyTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("packaging/Info.plist")

        let data = try Data(contentsOf: plist)
        let root = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let declarations = try XCTUnwrap(root["UTExportedTypeDeclarations"] as? [[String: Any]])
        let identifiers = declarations.compactMap { $0["UTTypeIdentifier"] as? String }

        XCTAssertTrue(identifiers.contains(ClipDragProvider.clipType.identifier),
                      "packaging/Info.plist does not export \(ClipDragProvider.clipType.identifier)")
    }

    /// The drop target's overlay is invisible and has to stay out of the way.
    /// Without a drag in flight it must not answer a hit test at all, or the
    /// tab underneath would stop taking clicks.
    func testDropTargetIgnoresClicksWhenNoCardIsBeingDragged() {
        ClipDragProvider.clearDraggedItem()

        let view = PinboardDropTargetView(frame: NSRect(x: 0, y: 0, width: 120, height: 28))
        XCTAssertNil(view.hitTest(NSPoint(x: 10, y: 10)))
    }

    /// The drag start stamps the clip, so a drop target inside Pesty can act on
    /// the mouse-up frame instead of waiting for the provider round trip, which
    /// measured 332 ms here and showed up as a freeze after the release.
    func testDragStartStampsTheClipBeingDragged() {
        let item = ClipItem(type: .text, text: "stamped", createdAt: Date(timeIntervalSince1970: 1_700_000_000))

        ClipDragProvider.clearDraggedItem()
        XCTAssertNil(ClipDragProvider.draggedItemID)

        _ = ClipDragProvider.make(for: item)
        XCTAssertEqual(ClipDragProvider.draggedItemID, item.id)

        ClipDragProvider.clearDraggedItem()
        XCTAssertNil(ClipDragProvider.draggedItemID)
    }

    /// A drag that never lands — cancelled, or the bar closed mid-drag — must
    /// not leave its id behind for the next drop to pin.
    func testClearingForgetsTheStampWithoutTouchingThePayload() throws {
        let item = ClipItem(type: .text, text: "cancelled", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let provider = ClipDragProvider.make(for: item)

        ClipDragProvider.clearDraggedItem()

        XCTAssertNil(ClipDragProvider.draggedItemID)
        // The provider still carries the identity, so a target that only speaks
        // content types can still complete the drop.
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(ClipDragProvider.clipType.identifier))
    }
}
