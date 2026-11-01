import XCTest
@testable import Pesty

/// The iCloud Drive merge and the on-disk housekeeping are the two places a
/// wrong answer loses a user's clips, so their pure parts are pinned here.
final class ClipboardStoreFilesTests: XCTestCase {
    private func clip(_ text: String, at seconds: TimeInterval, id: UUID = UUID()) -> ClipItem {
        ClipItem(id: id, type: .text, text: text, createdAt: Date(timeIntervalSince1970: seconds))
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testMergeKeepsOneCopyPerContentNewestFirst() {
        let shared = UUID()
        let local = [clip("a", at: 10), clip("b", at: 5, id: shared)]
        let remote = [clip("b", at: 5), clip("c", at: 7), clip("b", at: 9, id: shared)]

        let merged = ClipboardStore.mergeClips(local: local, remote: remote, tombstones: [:])

        XCTAssertEqual(merged.map(\.text), ["a", "b", "c"])
        XCTAssertEqual(merged[1].id, shared)
        XCTAssertEqual(merged[1].createdAt, Date(timeIntervalSince1970: 9))
    }

    func testTombstoneDropsAClipTheSharedFileNoLongerLists() {
        let id = UUID()
        let deleted = clip("gone", at: 5, id: id)
        let kept = clip("still here", at: 20)

        let merged = ClipboardStore.mergeClips(local: [deleted, kept], remote: [kept],
                                               tombstones: [id.uuidString: Date(timeIntervalSince1970: 8)])

        XCTAssertEqual(merged.map(\.id), [kept.id])
    }

    func testTombstoneKeepsAClipTheSharedFileStillLists() {
        let id = UUID()
        let revived = clip("back", at: 5, id: id)

        let merged = ClipboardStore.mergeClips(local: [revived], remote: [revived],
                                               tombstones: [id.uuidString: Date(timeIntervalSince1970: 8)])

        XCTAssertEqual(merged.map(\.id), [revived.id], "an undo, or a re-copy, revives the clip everywhere")
    }

    func testPruneRemovesOnlyOldUnreferencedFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let live = dir.appendingPathComponent("live.txt")
        let orphan = dir.appendingPathComponent("orphan.txt")
        let fresh = dir.appendingPathComponent("fresh.txt")
        for url in [live, orphan, fresh] { try Data("x".utf8).write(to: url) }
        let old = Date(timeIntervalSinceNow: -7200)
        for url in [live, orphan] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        }

        ClipboardStore.pruneOrphans(in: [dir], live: ["live.txt"],
                                    modifiedBefore: Date(timeIntervalSinceNow: -3600))

        XCTAssertTrue(FileManager.default.fileExists(atPath: live.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path), "a file too new to judge stays")
    }

    func testQuarantineMovesTheUnreadableStoreAside() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("store.json")
        try Data("garbage".utf8).write(to: store)

        let name = try XCTUnwrap(ClipboardStore.quarantine(storeAt: store))

        XCTAssertTrue(name.hasPrefix("store.corrupt-"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.path))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8), "garbage")
    }
}
