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
        // The cache lives in the file format, so a decoded clip is usable
        // immediately. `displayTitle` and friends have to match the stored
        // content and not the (defaulted) cache, which is why both are written.
        let original = ClipItem(type: .text, text: "persisted")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipItem.self, from: encoded)

        XCTAssertEqual(decoded.displayTitle, "persisted")
        XCTAssertEqual(decoded, original)
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
