import Foundation
import XCTest
@testable import AngerCore

final class PeerCacheTests: XCTestCase {
    func testOutageAndRestartRetainLastGoodPeerWithoutCurrentDevice() throws {
        let parent = temporaryDirectory()
        let peer = snapshot(deviceID: "mac-b", updatedAt: Date().addingTimeInterval(-30))
        let firstRun = PeerCache(directory: parent)

        XCTAssertEqual(try firstRun.merge([snapshot(deviceID: "mac-a"), peer], excludingDeviceID: "mac-a"), [peer])
        XCTAssertEqual(try firstRun.merge([], excludingDeviceID: "mac-a"), [peer])

        let afterRestart = PeerCache(directory: parent)
        XCTAssertEqual(afterRestart.load(), [peer])
        XCTAssertEqual(try afterRestart.merge([], excludingDeviceID: "mac-a"), [peer])
    }

    func testOlderSnapshotCannotRegressCachedPeer() throws {
        let cache = PeerCache(directory: temporaryDirectory())
        let newest = snapshot(deviceID: "mac-b", updatedAt: Date().addingTimeInterval(-10), eventID: "new")
        let older = snapshot(deviceID: "mac-b", updatedAt: Date().addingTimeInterval(-20), eventID: "old")

        _ = try cache.merge([newest], excludingDeviceID: "mac-a")
        let result = try cache.merge([older], excludingDeviceID: "mac-a")

        XCTAssertEqual(result, [newest])
    }

    func testCorruptPeerIsSkippedWithWarning() throws {
        let parent = temporaryDirectory()
        let cache = PeerCache(directory: parent)
        let valid = snapshot(deviceID: "mac-b")
        _ = try cache.merge([valid], excludingDeviceID: "mac-a")
        let corruptDirectory = parent.appendingPathComponent("peer-cache-v1/mac-c", isDirectory: true)
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: corruptDirectory.appendingPathComponent("snapshot.json"))

        XCTAssertEqual(cache.load(), [valid])
        XCTAssertTrue(cache.warnings.contains { $0.contains("mac-c") })
    }

    func testSnapshotsOlderThanRetentionArePruned() throws {
        let parent = temporaryDirectory()
        let old = snapshot(deviceID: "mac-old", updatedAt: Date().addingTimeInterval(-(25 * 60 * 60)))
        let oldDirectory = parent.appendingPathComponent("peer-cache-v1/mac-old", isDirectory: true)
        try EventStore(directory: oldDirectory).save(old)

        let cache = PeerCache(directory: parent)

        XCTAssertTrue(cache.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDirectory.path))
        XCTAssertTrue(try cache.merge([old], excludingDeviceID: "mac-a").isEmpty)
    }

    func testClearRemovesOnlyOwnedCacheChild() throws {
        let parent = temporaryDirectory()
        let sibling = parent.appendingPathComponent("keep-me.txt")
        try Data("user data".utf8).write(to: sibling)
        let cache = PeerCache(directory: parent)
        _ = try cache.merge([snapshot(deviceID: "mac-b")], excludingDeviceID: "mac-a")

        try cache.clear()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
        XCTAssertTrue(cache.load().isEmpty)
    }

    func testUnsafeDeviceIDCannotCreateExternalPath() throws {
        let parent = temporaryDirectory()
        let cache = PeerCache(directory: parent)

        XCTAssertThrowsError(try cache.merge([snapshot(deviceID: "../escape")], excludingDeviceID: "mac-a"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent("escape").path))
    }

    private func snapshot(
        deviceID: String,
        updatedAt: Date = Date().addingTimeInterval(-10),
        eventID: String = "event"
    ) -> DeviceSnapshot {
        let profile = PersonalProfile(
            id: "profile",
            updatedAt: min(updatedAt, Date().addingTimeInterval(-1)),
            summary: "profile",
            rules: []
        )
        let eventDate = min(updatedAt, Date().addingTimeInterval(-1))
        return DeviceSnapshot(
            deviceID: deviceID,
            name: deviceID,
            updatedAt: updatedAt,
            events: [ScoredEvent(id: eventID, timestamp: eventDate, deviceID: deviceID, source: "codex", points: 10, reasons: ["rule"], profileID: profile.id)],
            profile: profile
        )
    }

    private func temporaryDirectory() -> URL {
        let result = FileManager.default.temporaryDirectory
            .appendingPathComponent("AngerRatePeerCacheTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: result) }
        return result
    }
}
