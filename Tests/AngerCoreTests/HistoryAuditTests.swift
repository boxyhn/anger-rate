import Foundation
import XCTest
@testable import AngerCore

final class HistoryAuditTests: XCTestCase {
    func testAuditsEveryFileBeyondOldCapsAndReadsMarkerAtHeadOfLargeFile() throws {
        let fixture = try AuditFixture()
        defer { fixture.remove() }
        let sessions = fixture.root.appendingPathComponent(".codex-test/sessions")
        let archive = fixture.root.appendingPathComponent(".codex-test/archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)

        for index in 0..<164 {
            let directory = index == 163 ? archive : sessions
            try fixture.writeLines(
                [try codexEvent(text: "message \(index)", timestamp: "2026-01-01T00:00:00Z")],
                to: directory.appendingPathComponent("\(index).jsonl")
            )
        }
        let large = sessions.appendingPathComponent("large.jsonl")
        let marker = try codexEvent(text: "head marker", timestamp: "2026-01-02T00:00:00Z")
        let padding = try JSONSerialization.data(withJSONObject: [
            "timestamp": "2026-01-02T00:00:01Z", "type": "response_item",
            "payload": ["type": "message", "role": "assistant", "content": [
                ["type": "output_text", "text": String(repeating: "p", count: 600_000)]
            ]]
        ])
        try fixture.writeLines([marker, padding], to: large)

        let report = HistoryAuditor(roots: [sessions]).audit()

        XCTAssertTrue(report.completed)
        XCTAssertEqual(report.discoveredFiles, 165)
        XCTAssertEqual(report.readFiles, 165)
        XCTAssertEqual(report.failedFiles, 0)
        XCTAssertEqual(report.userMessages, 165)
        XCTAssertEqual(report.archiveMessages, 1)
        XCTAssertEqual(report.uniqueMessages, 165)
        XCTAssertTrue(report.selectedMessages.contains { $0.text == "head marker" })
    }

    func testCountsMalformedAndOversizedLinesWithoutLosingFollowingMessage() throws {
        let fixture = try AuditFixture()
        defer { fixture.remove() }
        let sessions = fixture.root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("broken.jsonl")
        var data = Data(repeating: 0x78, count: 4 * 1_024 * 1_024 + 1)
        data.append(0x0A)
        data.append(Data("{broken json}\n".utf8))
        data.append(try codexEvent(text: "survived", timestamp: "2026-01-01T00:00:00Z"))
        data.append(0x0A)
        try data.write(to: file)

        let report = HistoryAuditor(roots: [sessions]).audit()

        XCTAssertEqual(report.oversizedLines, 1)
        XCTAssertEqual(report.malformedLines, 1)
        XCTAssertEqual(report.userMessages, 1)
        XCTAssertEqual(report.selectedMessages.map(\.text), ["survived"])
    }

    func testCollapsesDualCodexShapesButPreservesRawAndArchiveCoverage() throws {
        let fixture = try AuditFixture()
        defer { fixture.remove() }
        let sessions = fixture.root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let event = try codexEvent(text: "same", timestamp: "2026-01-01T00:00:00.100Z")
        let response = try codexResponse(text: "same", timestamp: "2026-01-01T00:00:00.700Z")
        try fixture.writeLines([event, response], to: sessions.appendingPathComponent("session.jsonl"))

        let report = HistoryAuditor(roots: [sessions]).audit()

        XCTAssertEqual(report.userMessages, 2)
        XCTAssertEqual(report.uniqueMessages, 1)
        XCTAssertEqual(report.selectedMessages.count, 1)
    }

    func testSelectsNonSwearFrustrationWithNeighborAndCountsRepeatedPhrases() throws {
        let fixture = try AuditFixture()
        defer { fixture.remove() }
        let sessions = fixture.root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try fixture.writeLines([
            try codexResponse(text: "앞에서 설명한 요구사항", timestamp: "2026-01-01T00:00:00Z"),
            try codexResponse(text: "왜 또 다시 해야 해", timestamp: "2026-01-01T00:00:01Z"),
            try codexResponse(text: "  반복   문장! ", timestamp: "2026-01-01T00:00:02Z"),
            try codexResponse(text: "반복 문장.", timestamp: "2026-01-01T00:00:03Z")
        ], to: sessions.appendingPathComponent("session.jsonl"))

        let report = HistoryAuditor(roots: [sessions]).audit()

        XCTAssertEqual(report.phraseCounts["반복 문장"], 2)
        XCTAssertTrue(report.selectedMessages.contains { $0.text == "왜 또 다시 해야 해" })
        XCTAssertTrue(report.selectedMessages.contains { $0.text == "앞에서 설명한 요구사항" })
        XCTAssertLessThanOrEqual(report.selectedMessages.count, 600)
    }

    func testCancellationReturnsReadablePartialReportWithoutCompletionClaim() throws {
        let fixture = try AuditFixture()
        defer { fixture.remove() }
        let sessions = fixture.root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        for index in 0..<5 {
            try fixture.writeLines(
                [try codexEvent(text: "message \(index)", timestamp: "2026-01-01T00:00:00Z")],
                to: sessions.appendingPathComponent("\(index).jsonl")
            )
        }
        let probe = CancellationProbe(cancelAfterChecks: 4)
        let report = HistoryAuditor(roots: [sessions]).audit(isCancelled: { probe.shouldCancel() })

        XCTAssertFalse(report.completed)
        XCTAssertEqual(report.discoveredFiles, 5)
        XCTAssertLessThan(report.readFiles, 5)
        XCTAssertGreaterThanOrEqual(report.uniqueMessages, 1)
    }

    func testCountsFileThatDisappearsAfterDiscoveryAsFailed() throws {
        let fixture = try AuditFixture()
        defer { fixture.remove() }
        let sessions = fixture.root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let vanishing = sessions.appendingPathComponent("vanishing.jsonl")
        try fixture.writeLines(
            [try codexEvent(text: "gone", timestamp: "2026-01-01T00:00:00Z")],
            to: vanishing
        )

        let report = HistoryAuditor(roots: [sessions]).audit(progress: { completed, _ in
            if completed == 0 { try? FileManager.default.removeItem(at: vanishing) }
        })

        XCTAssertTrue(report.completed)
        XCTAssertEqual(report.discoveredFiles, 1)
        XCTAssertEqual(report.readFiles, 0)
        XCTAssertEqual(report.failedFiles, 1)
    }

    private func codexEvent(text: String, timestamp: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "timestamp": timestamp, "type": "event_msg",
            "payload": ["type": "user_message", "message": text]
        ], options: [.sortedKeys])
    }

    private func codexResponse(text: String, timestamp: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "timestamp": timestamp, "type": "response_item",
            "payload": ["type": "message", "role": "user", "content": [
                ["type": "input_text", "text": text]
            ]]
        ], options: [.sortedKeys])
    }
}

private final class AuditFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func writeLines(_ lines: [Data], to file: URL) throws {
        var data = Data()
        for line in lines {
            data.append(line)
            data.append(0x0A)
        }
        try data.write(to: file)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAfterChecks: Int
    private var checks = 0

    init(cancelAfterChecks: Int) {
        self.cancelAfterChecks = cancelAfterChecks
    }

    func shouldCancel() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        checks += 1
        return checks >= cancelAfterChecks
    }
}
