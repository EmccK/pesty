import XCTest
@testable import Pesty

/// The strip reads a clip's title, search haystack, band timestamp and band
/// color many times per second. These tests pin the cached values to the same
/// answers the old computed properties produced, and pin the refresh points so
/// a later edit cannot silently leave a card showing stale metadata.
final class ClipItemDerivedStateTests: XCTestCase {
    func testDerivedStateMatchesComputedValues() {
        let item = ClipItem(
            type: .text,
            text: "Hello\nSecond line",
            sourceBundleID: "com.apple.Safari",
            sourceAppName: "Safari",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(item.cachedDisplayTitle, "Hello")
        XCTAssertEqual(item.displayTitle, item.cachedDisplayTitle)
        // The haystack covers the searchable fields: title, text, app name,
        // file paths and color. Browse ID is deliberately absent — the search
        // box matches what a person can see on the card.
        XCTAssertEqual(item.searchTextLowercased, "hello\nsecond line safari")
    }

    func testCustomTitleWinsAndRefreshesAfterMutation() {
        var item = ClipItem(type: .text, text: "body")
        XCTAssertEqual(item.displayTitle, "body")

        item.customTitle = "Renamed"
        item.refreshDerivedState()

        XCTAssertEqual(item.displayTitle, "Renamed")
        XCTAssertTrue(item.searchTextLowercased.contains("renamed"))
    }

    func testPromotedClipRefreshesItsAgeAndSearchIndex() {
        var item = ClipItem(type: .text, text: "old", createdAt: Date(timeIntervalSince1970: 0))
        let stale = item.cachedRelativeDate

        item.text = "brand new content"
        item.createdAt = Date()
        item.refreshDerivedState()

        XCTAssertNotEqual(item.cachedRelativeDate, stale)
        XCTAssertEqual(item.searchTextLowercased, "brand new content")
    }

    func testCachedStateSurvivesPersistence() throws {
        // Derived fields are rebuilt on decode, not stored. A decoded clip is
        // usable immediately, and the file does not carry a second copy of the text.
        let original = ClipItem(type: .text, text: "persisted")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipItem.self, from: encoded)
        let json = String(decoding: encoded, as: UTF8.self)

        XCTAssertFalse(json.contains("searchTextLowercased"))
        XCTAssertFalse(json.contains("cachedPreviewText"))
        XCTAssertEqual(decoded.displayTitle, "persisted")
        XCTAssertEqual(decoded.searchTextLowercased, original.searchTextLowercased)
        XCTAssertEqual(decoded, original)
    }

    func testSearchHaystackAndPreviewAreCapped() {
        let text = String(repeating: "A", count: 5_000)
        let item = ClipItem(type: .text, text: text, sourceAppName: "Safari")

        XCTAssertLessThanOrEqual(item.searchTextLowercased.count, 2_048)
        XCTAssertTrue(item.searchTextLowercased.hasPrefix(String(repeating: "a", count: 64)))
        XCTAssertFalse(item.searchTextLowercased.contains("safari"))
        XCTAssertEqual(item.cachedPreviewText.count, 800)
        XCTAssertEqual(item.contentHash, ClipItem(type: .text, text: text).contentHash)
    }

    func testDecodingRestoresDerivedState() throws {
        let original = ClipItem(
            type: .link,
            text: "https://example.com/deep/path",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipItem.self, from: encoded)

        XCTAssertEqual(decoded.displayTitle, "example.com")
        XCTAssertFalse(decoded.searchTextLowercased.isEmpty)
    }
}
