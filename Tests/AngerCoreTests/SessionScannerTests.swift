import Foundation
import XCTest
@testable import AngerCore

final class SessionScannerTests: XCTestCase {
    func testOldArchiveIsNotCrowdedOutByManyRecentLiveFiles() throws {
        let fixture = try FixtureDirectory(name: ".codex-test/sessions")
        defer { fixture.remove() }
        for index in 0..<161 {
            try fixture.writeLine(codexLine(text: "active-\(index)", second: 1), to: fixture.url.appendingPathComponent("s-\(index).jsonl"))
        }
        let archive = fixture.url.deletingLastPathComponent().appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let archivedFile = archive.appendingPathComponent("old.jsonl")
        try fixture.writeLine(codexLine(text: "archive-signal", second: 2), to: archivedFile)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: archivedFile.path)
        let scanner = SessionScanner(roots: [fixture.url])
        let sample = scanner.historicalMessages(limit: 400)
        XCTAssertTrue(sample.contains { $0.text == "archive-signal" })
        XCTAssertEqual(scanner.historicalArchiveMessageCount, 1)
    }

    func testCodexParserAcceptsBothUserRecordShapesAndProducesStableID() throws {
        let valid = try jsonData([
            "timestamp": "2026-09-05T01:02:03.123Z",
            "type": "event_msg",
            "payload": ["type": "user_message", "message": "빨리 끝내"]
        ])
        let assistant = try jsonData([
            "timestamp": "2026-09-05T01:02:03Z",
            "type": "event_msg",
            "payload": ["type": "agent_message", "message": "빨리 끝내"]
        ])
        let response = try jsonData([
            "timestamp": "2026-09-05T01:02:03.456Z",
            "type": "response_item",
            "payload": [
                "type": "message", "role": "user",
                "content": [["type": "input_text", "text": "response-only input"]]
            ]
        ])
        let assistantResponse = try jsonData([
            "timestamp": "2026-09-05T01:02:03.456Z",
            "type": "response_item",
            "payload": [
                "type": "message", "role": "assistant",
                "content": [["type": "output_text", "text": "assistant"]]
            ]
        ])

        let first = SessionParser.parse(line: valid, source: "codex", sessionID: "session-a")
        let second = SessionParser.parse(line: valid, source: "codex", sessionID: "session-a")

        XCTAssertEqual(first?.text, "빨리 끝내")
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(first?.id.count, 64)
        XCTAssertNil(SessionParser.parse(line: assistant, source: "codex", sessionID: "session-a"))
        XCTAssertEqual(SessionParser.parse(line: response, source: "codex", sessionID: "session-a")?.text, "response-only input")
        XCTAssertNil(SessionParser.parse(line: assistantResponse, source: "codex", sessionID: "session-a"))
    }

    func testClaudeParserKeepsTextAndSkipsMetadataToolsAndSubagents() throws {
        let valid = try jsonData([
            "timestamp": "2026-09-05T01:02:03Z",
            "type": "user",
            "message": ["role": "user", "content": [
                ["type": "text", "text": "실제 사용자 말"],
                ["type": "tool_result", "content": "도구 결과"]
            ]]
        ])
        let meta = try jsonData([
            "timestamp": "2026-09-05T01:02:03Z", "type": "user", "isMeta": true,
            "message": ["role": "user", "content": "메타"]
        ])
        let subagent = try jsonData([
            "timestamp": "2026-09-05T01:02:03Z", "type": "user", "agentId": "child",
            "message": ["role": "user", "content": "서브에이전트"]
        ])

        XCTAssertEqual(SessionParser.parse(line: valid, source: "claude", sessionID: "s")?.text, "실제 사용자 말")
        XCTAssertNil(SessionParser.parse(line: meta, source: "claude", sessionID: "s"))
        XCTAssertNil(SessionParser.parse(line: subagent, source: "claude", sessionID: "s"))
    }

    func testScannerTailsExistingContentAndWaitsForCompleteLine() throws {
        let fixture = try FixtureDirectory(name: ".codex-test/sessions")
        defer { fixture.remove() }
        let log = fixture.url.appendingPathComponent("session.jsonl")
        try fixture.writeLine(codexLine(text: "old", second: 0), to: log)
        let scanner = SessionScanner(roots: [fixture.url])

        XCTAssertEqual(scanner.scanNew(), [])
        XCTAssertEqual(scanner.scannedFileCount, 1)

        let partial = try codexLine(text: "new", second: 1)
        try fixture.append(partial, to: log)
        XCTAssertEqual(scanner.scanNew(), [])
        try fixture.append(Data([0x0A]), to: log)
        XCTAssertEqual(scanner.scanNew().map(\.text), ["new"])
        XCTAssertNil(scanner.lastError)
    }

    func testScannerKeepsStartupPartialRecordUntilItIsCompleted() throws {
        let fixture = try FixtureDirectory(name: ".codex-test/sessions")
        defer { fixture.remove() }
        let log = fixture.url.appendingPathComponent("session.jsonl")
        let complete = try codexLine(text: "completed after launch", second: 1)
        let split = complete.count / 2
        try Data(complete[..<split]).write(to: log)
        let scanner = SessionScanner(roots: [fixture.url])

        XCTAssertTrue(scanner.scanNew().isEmpty)
        try fixture.append(Data(complete[split...]), to: log)
        try fixture.append(Data([0x0A]), to: log)

        XCTAssertEqual(scanner.scanNew().map(\.text), ["completed after launch"])
    }

    func testScannerHandlesTruncationAndNewFilesAfterStartup() throws {
        let fixture = try FixtureDirectory(name: ".codex-test/sessions")
        defer { fixture.remove() }
        let first = fixture.url.appendingPathComponent("first.jsonl")
        try fixture.writeLine(codexLine(text: "old-long-message", second: 0), to: first)
        let scanner = SessionScanner(roots: [fixture.url])
        XCTAssertTrue(scanner.scanNew().isEmpty)

        try fixture.writeLine(codexLine(text: "x", second: 1), to: first)
        XCTAssertEqual(scanner.scanNew().map(\.text), ["x"])

        let second = fixture.url.appendingPathComponent("second.jsonl")
        try fixture.writeLine(codexLine(text: "brand new session", second: 2), to: second)
        XCTAssertEqual(scanner.scanNew().map(\.text), ["brand new session"])
    }

    func testScannerDetectsAppendsThroughSymlinkedSessionRoot() throws {
        let fixture = try FixtureDirectory(name: ".codex-test/real-sessions")
        defer { fixture.remove() }
        let log = fixture.url.appendingPathComponent("session.jsonl")
        let linkedRoot = fixture.root.appendingPathComponent("linked-sessions")
        try fixture.writeLine(codexLine(text: "old", second: 0), to: log)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: fixture.url)
        let scanner = SessionScanner(roots: [linkedRoot])

        XCTAssertEqual(scanner.scanNew(), [])

        try fixture.appendLine(codexLine(text: "from symlink root", second: 1), to: log)
        XCTAssertEqual(scanner.scanNew().map(\.text), ["from symlink root"])
    }

    func testScannerPrefersResponseItemAndCollapsesNearbyEventCopy() throws {
        let fixture = try FixtureDirectory(name: ".codex-test/sessions")
        defer { fixture.remove() }
        let log = fixture.url.appendingPathComponent("session.jsonl")
        try Data().write(to: log)
        let scanner = SessionScanner(roots: [fixture.url])
        XCTAssertTrue(scanner.scanNew().isEmpty)

        let event = try jsonData([
            "timestamp": "2026-09-05T01:02:03.100Z", "type": "event_msg",
            "payload": ["type": "user_message", "message": "same input"]
        ])
        let response = try jsonData([
            "timestamp": "2026-09-05T01:02:03.500Z", "type": "response_item",
            "payload": [
                "type": "message", "role": "user",
                "content": [["type": "input_text", "text": "same input"]]
            ]
        ])
        try fixture.appendLine(event, to: log)
        try fixture.appendLine(response, to: log)

        let messages = scanner.scanNew()
        XCTAssertEqual(messages.map(\.text), ["same input"])
        XCTAssertEqual(messages.first?.timestamp, SessionParser.parse(
            line: response, source: "codex", sessionID: "session"
        )?.timestamp)
    }

    func testScannerPreservesSameShapeRepeatedText() throws {
        let fixture = try FixtureDirectory(name: ".codex-test/sessions")
        defer { fixture.remove() }
        let log = fixture.url.appendingPathComponent("session.jsonl")
        try Data().write(to: log)
        let scanner = SessionScanner(roots: [fixture.url])
        XCTAssertTrue(scanner.scanNew().isEmpty)

        try fixture.appendLine(codexLine(text: "repeat", second: 1), to: log)
        try fixture.appendLine(codexLine(text: "repeat", second: 1), to: log)
        XCTAssertEqual(scanner.scanNew().count, 1, "identical record IDs are deduplicated")

        try fixture.appendLine(codexLine(text: "repeat", second: 2), to: log)
        XCTAssertEqual(scanner.scanNew().map(\.text), ["repeat"], "a distinct same-shape repeat is preserved")
    }

    func testHistoricalMessagesAreDiverseAndDoNotMoveLiveCursor() throws {
        let fixture = try FixtureDirectory(name: ".codex-test/sessions")
        defer { fixture.remove() }
        let a = fixture.url.appendingPathComponent("a.jsonl")
        let b = fixture.url.appendingPathComponent("b.jsonl")
        try fixture.writeLines([
            codexLine(text: "a1", second: 1), codexLine(text: "a2", second: 3)
        ], to: a)
        try fixture.writeLines([
            codexLine(text: "b1", second: 2), codexLine(text: "b2", second: 4)
        ], to: b)
        let scanner = SessionScanner(roots: [fixture.url])

        let history = scanner.historicalMessages(limit: 2)
        XCTAssertEqual(Set(history.map(\.text)), Set(["a2", "b2"]))
        XCTAssertEqual(scanner.scanNew(), [])

        try fixture.appendLine(codexLine(text: "live", second: 5), to: a)
        XCTAssertEqual(scanner.scanNew().map(\.text), ["live"])
    }

    func testHistoricalMessagesIncludeCodexArchiveAndSkipClaudeSubagentDirectory() throws {
        let fixture = try FixtureDirectory(name: ".codex-test")
        defer { fixture.remove() }
        let sessions = fixture.url.appendingPathComponent("sessions")
        let archive = fixture.url.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try fixture.writeLine(codexLine(text: "archived", second: 1), to: archive.appendingPathComponent("old.jsonl"))

        let scanner = SessionScanner(roots: [sessions])
        XCTAssertEqual(scanner.historicalMessages(limit: 10).map(\.text), ["archived"])

        let claudeRoot = fixture.url.appendingPathComponent(".claude/projects/project")
        let subagents = claudeRoot.appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: subagents, withIntermediateDirectories: true)
        let line = try jsonData([
            "timestamp": "2026-09-05T01:02:03Z", "type": "user",
            "message": ["role": "user", "content": "should be skipped"]
        ])
        try fixture.writeLine(line, to: subagents.appendingPathComponent("agent.jsonl"))
        let claudeScanner = SessionScanner(roots: [claudeRoot])
        XCTAssertTrue(claudeScanner.historicalMessages(limit: 10).isEmpty)
    }

    private func codexLine(text: String, second: Int) throws -> Data {
        try jsonData([
            "timestamp": String(format: "2026-09-05T01:02:%02dZ", second),
            "type": "event_msg",
            "payload": ["type": "user_message", "message": text]
        ])
    }

    private func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

private final class FixtureDirectory {
    let root: URL
    let url: URL

    init(name: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func writeLine(_ data: Data, to file: URL) throws {
        var value = data
        value.append(0x0A)
        try value.write(to: file)
    }

    func writeLines(_ lines: [Data], to file: URL) throws {
        var value = Data()
        for line in lines {
            value.append(line)
            value.append(0x0A)
        }
        try value.write(to: file)
    }

    func append(_ data: Data, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func appendLine(_ data: Data, to file: URL) throws {
        var value = data
        value.append(0x0A)
        try append(value, to: file)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
