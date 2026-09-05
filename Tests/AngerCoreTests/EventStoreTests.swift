import Foundation
import XCTest
@testable import AngerCore

final class EventStoreTests: XCTestCase {
    func testLocalStoreRoundTripsWithoutRawMessages() throws {
        let directory = temporaryDirectory()
        let snapshot = makeSnapshot(deviceID: "mac-a", eventIDs: ["one"])
        let store = EventStore(directory: directory)

        try store.save(snapshot)

        XCTAssertEqual(try store.load(), snapshot)
        let json = try String(contentsOf: directory.appendingPathComponent("snapshot.json"), encoding: .utf8)
        XCTAssertFalse(json.contains("text"))
        XCTAssertFalse(json.contains("message"))
    }

    func testTwoVirtualMacsConvergeWithoutDoubleCounting() throws {
        let directory = temporaryDirectory()
        let syncA = FolderSync(directory: directory)
        let syncB = FolderSync(directory: directory)
        let sharedEvent = makeEvent(id: "shared", deviceID: "mac-a", secondsAgo: 20)
        let a = makeSnapshot(deviceID: "mac-a", events: [sharedEvent, makeEvent(id: "a", deviceID: "mac-a")])
        let b = makeSnapshot(deviceID: "mac-b", events: [
            makeEvent(id: "shared", deviceID: "mac-b"),
            makeEvent(id: "b", deviceID: "mac-b"),
        ])

        _ = try syncA.exchange(local: a)
        let seenByB = try syncB.exchange(local: b)
        let seenByA = try syncA.exchange(local: a)

        XCTAssertEqual(syncA.mergedEvents(snapshots: seenByA).map(\.id), ["shared", "a", "b"])
        XCTAssertEqual(syncB.mergedEvents(snapshots: seenByB).map(\.id), ["shared", "a", "b"])
    }

    func testInvalidAndTruncatedPeerAreSkippedWithWarnings() throws {
        let directory = temporaryDirectory()
        let validPeer = makeSnapshot(deviceID: "mac-b", eventIDs: ["b"])
        try EventStore(directory: directory.appendingPathComponent("encoder")).save(validPeer)
        let encoded = try Data(contentsOf: directory.appendingPathComponent("encoder/snapshot.json"))
        try encoded.write(to: directory.appendingPathComponent("mac-b.json"))
        try Data("{\"deviceID\":".utf8).write(to: directory.appendingPathComponent("mac-c.json"))
        let invalidStoreDirectory = directory.appendingPathComponent("invalid-encoder")
        try EventStore(directory: invalidStoreDirectory).save(makeSnapshot(deviceID: "mac-d", eventIDs: ["bad"]))
        let validData = try Data(contentsOf: invalidStoreDirectory.appendingPathComponent("snapshot.json"))
        var invalidObject = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        var invalidEvents = try XCTUnwrap(invalidObject["events"] as? [[String: Any]])
        invalidEvents[0]["points"] = 101
        invalidObject["events"] = invalidEvents
        try JSONSerialization.data(withJSONObject: invalidObject).write(to: directory.appendingPathComponent("mac-d.json"))

        let sync = FolderSync(directory: directory)
        let result = try sync.exchange(local: makeSnapshot(deviceID: "mac-a", eventIDs: ["a"]))

        XCTAssertEqual(Set(result.map(\.deviceID)), ["mac-a", "mac-b"])
        XCTAssertEqual(sync.warnings.count, 2)
        XCTAssertTrue(sync.warnings.contains { $0.contains("mac-c.json") })
        XCTAssertTrue(sync.warnings.contains { $0.contains("mac-d.json") })
    }

    func testHostileDeviceIDsAndFilenamesCannotEscapeDirectory() throws {
        let directory = temporaryDirectory()
        let sync = FolderSync(directory: directory)

        XCTAssertThrowsError(try sync.exchange(local: makeSnapshot(deviceID: "../escape", eventIDs: [])))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("bad name.json"))
        let result = try sync.exchange(local: makeSnapshot(deviceID: "safe-device", eventIDs: []))

        XCTAssertEqual(result.map(\.deviceID), ["safe-device"])
        XCTAssertEqual(sync.warnings.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent("escape.json").path))
    }

    func testProfileConflictUsesTimestampThenStableID() {
        let sync = FolderSync(directory: temporaryDirectory())
        let timestamp = Date().addingTimeInterval(-10)
        let profileA = PersonalProfile(id: "profile-a", updatedAt: timestamp, summary: "A", rules: [])
        let profileB = PersonalProfile(id: "profile-b", updatedAt: timestamp, summary: "B", rules: [])
        let old = PersonalProfile(id: "profile-z", updatedAt: timestamp.addingTimeInterval(-1), summary: "old", rules: [])
        let snapshots = [
            makeSnapshot(deviceID: "a", profile: profileA),
            makeSnapshot(deviceID: "b", profile: old),
            makeSnapshot(deviceID: "c", profile: profileB),
        ]

        XCTAssertEqual(sync.latestProfile(snapshots: snapshots), profileB)
    }

    func testSharedProfileCarriesHalfLifeAcrossDevices() throws {
        let directory = temporaryDirectory()
        let syncA = FolderSync(directory: directory)
        let syncB = FolderSync(directory: directory)
        let profile = PersonalProfile(
            id: "shared-profile",
            updatedAt: Date().addingTimeInterval(-5),
            summary: "shared",
            rules: [],
            halfLifeSeconds: 420
        )

        _ = try syncA.exchange(local: makeSnapshot(deviceID: "mac-a", profile: profile))
        let snapshots = try syncB.exchange(local: makeSnapshot(deviceID: "mac-b"))

        XCTAssertEqual(syncB.latestProfile(snapshots: snapshots)?.halfLifeSeconds, 420)
    }

    func testSmallClockSkewKeepsPeerButFiltersFutureEvent() throws {
        let directory = temporaryDirectory()
        let futureDate = Date().addingTimeInterval(10)
        let profile = PersonalProfile(id: "future-profile", updatedAt: futureDate, summary: "", rules: [])
        let peer = DeviceSnapshot(
            deviceID: "mac-b",
            name: "B",
            updatedAt: futureDate,
            events: [ScoredEvent(id: "future", timestamp: futureDate, deviceID: "mac-b", source: "codex", points: 10, reasons: [], profileID: profile.id)],
            profile: profile
        )
        try EventStore(directory: directory.appendingPathComponent("encoder")).save(peer)
        let peerData = try Data(contentsOf: directory.appendingPathComponent("encoder/snapshot.json"))
        try peerData.write(to: directory.appendingPathComponent("mac-b.json"))

        let sync = FolderSync(directory: directory)
        let snapshots = try sync.exchange(local: makeSnapshot(deviceID: "mac-a"))

        XCTAssertEqual(Set(snapshots.map(\.deviceID)), ["mac-a", "mac-b"])
        XCTAssertTrue(snapshots.first(where: { $0.deviceID == "mac-b" })?.events.isEmpty == true)
        XCTAssertTrue(sync.warnings.isEmpty)
    }

    func testExpiredEventsArePrunedAndFutureEventsRejectPeer() throws {
        let directory = temporaryDirectory()
        let sync = FolderSync(directory: directory)
        let old = makeEvent(id: "old", deviceID: "mac-a", secondsAgo: 25 * 60 * 60)
        let current = makeEvent(id: "current", deviceID: "mac-a")

        let localResult = try sync.exchange(local: makeSnapshot(deviceID: "mac-a", events: [old, current]))
        XCTAssertEqual(localResult[0].events.map(\.id), ["current"])

        let future = makeSnapshot(
            deviceID: "mac-b",
            events: [makeEvent(id: "future", deviceID: "mac-b", secondsAgo: -60)]
        )
        let peerStore = EventStore(directory: directory.appendingPathComponent("peer"))
        XCTAssertThrowsError(try peerStore.save(future))
    }

    private func makeSnapshot(
        deviceID: String,
        eventIDs: [String] = [],
        events: [ScoredEvent]? = nil,
        profile: PersonalProfile? = nil
    ) -> DeviceSnapshot {
        let profile = profile ?? PersonalProfile(
            id: "profile-\(deviceID)",
            updatedAt: Date().addingTimeInterval(-60),
            summary: "profile",
            rules: []
        )
        return DeviceSnapshot(
            deviceID: deviceID,
            name: deviceID,
            updatedAt: Date().addingTimeInterval(-1),
            events: events ?? eventIDs.enumerated().map {
                makeEvent(id: $0.element, deviceID: deviceID, secondsAgo: 10 - Double($0.offset))
            },
            profile: profile
        )
    }

    private func makeEvent(id: String, deviceID: String, secondsAgo: TimeInterval = 0) -> ScoredEvent {
        ScoredEvent(
            id: id,
            timestamp: Date().addingTimeInterval(-secondsAgo),
            deviceID: deviceID,
            source: "codex",
            points: 10,
            reasons: ["rule"],
            profileID: "profile-\(deviceID)"
        )
    }

    private func temporaryDirectory() -> URL {
        let result = FileManager.default.temporaryDirectory
            .appendingPathComponent("AngerRateTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: result) }
        return result
    }
}
