import XCTest
@testable import Pesty

final class ClipItemTests: XCTestCase {
    func testCodableRoundTripPreservesClipMetadata() throws {
        let original = ClipItem(
            id: UUID(uuidString: "61F39299-3C8E-45AE-90BA-C53889BF9304")!,
            type: .link,
            text: "https://example.com/path",
            sourceBundleID: "com.apple.Safari",
            sourceAppName: "Safari",
            customTitle: "Example",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipItem.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.displayTitle, "Example")
    }

    func testRichTextIsAFilenameNotInlineBytes() throws {
        let item = ClipItem(type: .richText, text: "hi", rtfFileName: "a.rtf", htmlFileName: "a.html")
        let json = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        XCTAssertTrue(json.contains("a.rtf"))
        XCTAssertTrue(json.contains("a.html"))
        XCTAssertFalse(json.contains("rtfData"))
        XCTAssertFalse(json.contains("htmlData"))

        struct Legacy: Encodable {
            var id = UUID()
            var type = "richText"
            var text = "hi"
            var rtfData = Data("{\\rtf1 hi}".utf8)
            var fileURLs = [String]()
            var createdAt = Date(timeIntervalSince1970: 0)
        }
        let decoded = try JSONDecoder().decode(ClipItem.self, from: JSONEncoder().encode(Legacy()))
        XCTAssertEqual(decoded.pendingRTF, Data("{\\rtf1 hi}".utf8))
        XCTAssertNil(decoded.rtfFileName)
        XCTAssertEqual(decoded.text, "hi")
    }

    func testLongTextStaysOutOfTheStoreFile() throws {
        var item = ClipItem(type: .text, text: String(repeating: "A", count: 3_000) + "TAIL")
        XCTAssertEqual(item.textCount, 3_004)
        XCTAssertEqual(item.textPrefix?.count, 2_048)
        XCTAssertFalse(item.textPrefix?.contains("TAIL") ?? true)
        item.textFileName = "body.txt"
        item.text = nil
        let json = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        XCTAssertTrue(json.contains("body.txt"))
        XCTAssertFalse(json.contains("TAIL"))
        XCTAssertFalse(json.contains("\"text\":"))
    }
}
