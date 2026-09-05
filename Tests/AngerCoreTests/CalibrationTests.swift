import Foundation
import XCTest
@testable import AngerCore

final class CalibrationTests: XCTestCase {
    func testClaudeUsesSafeOneShotFlagsRedactsInputAndValidatesStructuredOutput() async throws {
        let fixture = try CalibrationFixture(executableName: "claude")
        defer { fixture.remove() }
        let recorder = CommandRecorder { _, arguments, input, directory, _, _ in
            if arguments == ["--help"] {
                return .success(Self.claudeHelp)
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
            return .success(#"{"structured_output":{"summary":"개인 기준","rules":[{"phrase":"몇 번을 말","weight":8,"reason":"반복 압박"},{"phrase":"씨발","weight":30,"reason":"강한 욕설"}]}}"#)
        }
        let service = makeService(fixture: fixture, recorder: recorder)
        let profile = try await service.analyze(messages: [
            message("빨리 끝내 api_key=super-secret-value", offset: 0),
            message("오늘은 차분하게 진행했다", offset: 1),
            message("씨발 몇 번을 말하냐", offset: 2)
        ], provider: "claude")

        XCTAssertEqual(profile.summary, "개인 기준")
        XCTAssertEqual(profile.rules.map(\.phrase), ["몇 번을 말", "씨발"])
        let invocation = try XCTUnwrap(recorder.invocations.last)
        XCTAssertTrue(invocation.arguments.contains("--safe-mode"))
        XCTAssertTrue(invocation.arguments.contains("--no-session-persistence"))
        XCTAssertTrue(invocation.arguments.contains("--permission-mode"))
        XCTAssertEqual(invocation.arguments.last, "--disable-slash-commands")
        let prompt = String(decoding: invocation.input, as: UTF8.self)
        XCTAssertTrue(prompt.contains("[REDACTED]"))
        XCTAssertFalse(prompt.contains("super-secret-value"))
        XCTAssertTrue(prompt.contains("untrusted quoted data"))
    }

    func testCodexUsesEphemeralReadOnlyInvocationAndParsesAgentMessage() async throws {
        let fixture = try CalibrationFixture(executableName: "codex")
        defer { fixture.remove() }
        let recorder = CommandRecorder { _, arguments, _, directory, _, _ in
            if arguments == ["--help"] { return .success(Self.codexHelp) }
            if arguments == ["exec", "--help"] { return .success(Self.codexExecHelp) }
            if arguments == ["features", "list"] { return .success(Self.codexFeatures) }
            let payload = #"{"summary":"맞춤 기준","rules":[{"phrase":"개쓰레기","weight":30,"reason":"강한 비하"}]}"#
            let escaped = try JSONSerialization.data(withJSONObject: [
                "type": "item.completed",
                "item": ["type": "agent_message", "text": payload]
            ])
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("result-schema.json").path))
            return CalibrationCommandResult(status: 0, stdout: escaped + Data([0x0A]), stderr: Data())
        }
        let service = makeService(fixture: fixture, recorder: recorder)
        let profile = try await service.analyze(messages: [message("성과가 개쓰레긴데", offset: 0)], provider: "codex")

        XCTAssertEqual(profile.rules.first?.weight, 30)
        let arguments = try XCTUnwrap(recorder.invocations.last?.arguments)
        XCTAssertTrue(arguments.starts(with: ["-a", "on-request", "--disable", "shell_tool"]))
        XCTAssertTrue(arguments.contains("browser_use"))
        XCTAssertTrue(arguments.contains("computer_use"))
        XCTAssertTrue(arguments.contains("--ephemeral"))
        XCTAssertTrue(arguments.contains("--ignore-user-config"))
        XCTAssertTrue(arguments.contains("--ignore-rules"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--sandbox")! + 1], "read-only")
        XCTAssertFalse(arguments.contains("--dangerously-bypass-approvals-and-sandbox"))

        let temporaryPath = try XCTUnwrap(recorder.invocations.last?.directory.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryPath))
    }

    func testRejectsUnsafeCodexToolEvent() async throws {
        let fixture = try CalibrationFixture(executableName: "codex")
        defer { fixture.remove() }
        let recorder = CommandRecorder { _, arguments, _, _, _, _ in
            if arguments == ["--help"] { return .success(Self.codexHelp) }
            if arguments == ["exec", "--help"] { return .success(Self.codexExecHelp) }
            if arguments == ["features", "list"] { return .success(Self.codexFeatures) }
            return .success(#"{"type":"item.completed","item":{"type":"command_execution","command":"printenv"}}"#)
        }
        let service = makeService(fixture: fixture, recorder: recorder)

        do {
            _ = try await service.analyze(messages: [message("씨발", offset: 0)], provider: "codex")
            XCTFail("Expected unsafe tool event to be rejected")
        } catch let error as CalibrationError {
            guard case .invalidResponse(let reason) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(reason.contains("도구 이벤트"))
        }
    }

    func testRejectsDuplicateGenericAndOutOfRangeRules() async throws {
        let invalidPayloads = [
            #"{"structured_output":{"summary":"기준","rules":[{"phrase":"씨발","weight":20,"reason":"욕설"},{"phrase":"  씨발  ","weight":30,"reason":"중복"}]}}"#,
            #"{"structured_output":{"summary":"기준","rules":[{"phrase":"빨리","weight":8,"reason":"일반어"}]}}"#,
            #"{"structured_output":{"summary":"기준","rules":[{"phrase":"씨발","weight":51,"reason":"초과"}]}}"#
        ]

        for payload in invalidPayloads {
            let fixture = try CalibrationFixture(executableName: "claude")
            defer { fixture.remove() }
            let recorder = CommandRecorder { _, arguments, _, _, _, _ in
                arguments == ["--help"] ? .success(Self.claudeHelp) : .success(payload)
            }
            let service = makeService(fixture: fixture, recorder: recorder)
            do {
                _ = try await service.analyze(messages: [message("씨발 빨리", offset: 0)], provider: "claude")
                XCTFail("Expected invalid profile")
            } catch let error as CalibrationError {
                guard case .invalidResponse = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testFailsDescriptivelyWhenRequiredCLIFlagsAreMissing() async throws {
        let fixture = try CalibrationFixture(executableName: "claude")
        defer { fixture.remove() }
        let recorder = CommandRecorder { _, _, _, _, _, _ in .success("Usage: claude --print") }
        let service = makeService(fixture: fixture, recorder: recorder)

        do {
            _ = try await service.analyze(messages: [message("씨발", offset: 0)], provider: "claude")
            XCTFail("Expected unsupported CLI")
        } catch let error as CalibrationError {
            XCTAssertEqual(error, .unsupportedCLI("Claude"))
            XCTAssertTrue(error.localizedDescription.contains("업데이트"))
        }
    }

    func testProductionRunnerCompletesWithoutBeingMistakenForTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory
        let result = try await CalibrationService.runCommand(
            executable: URL(fileURLWithPath: "/bin/cat"),
            arguments: [],
            input: Data("normal completion".utf8),
            currentDirectory: directory,
            timeout: 2,
            didLaunch: { _ in }
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "normal completion")
        XCTAssertFalse(result.outputExceededLimit)
    }

    func testProductionRunnerTerminatesAtTimeout() async throws {
        do {
            _ = try await CalibrationService.runCommand(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"],
                input: Data(),
                currentDirectory: FileManager.default.temporaryDirectory,
                timeout: 0.1,
                didLaunch: { _ in }
            )
            XCTFail("Expected timeout")
        } catch let error as CalibrationError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testCancelTerminatesProductionCLIProcess() async throws {
        let fixture = try CalibrationFixture(executableName: "claude", script: """
        #!/bin/sh
        if [ "$1" = "--help" ]; then
          printf '%s' '\(Self.claudeHelp)'
          exit 0
        fi
        /bin/sleep 30
        """)
        defer { fixture.remove() }
        let service = CalibrationService(environment: ["PATH": fixture.directory.path], runner: { executable, arguments, input, directory, timeout, didLaunch in
            try await CalibrationService.runCommand(
                executable: executable,
                arguments: arguments,
                input: input,
                currentDirectory: directory,
                timeout: timeout,
                didLaunch: didLaunch
            )
        })
        let task = Task {
            try await service.analyze(messages: [message("씨발", offset: 0)], provider: "claude")
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        service.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as CalibrationError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testLiveCLIWhenExplicitlyEnabled() async throws {
        guard let provider = ProcessInfo.processInfo.environment["ANGER_RATE_LIVE_CLI"],
              provider == "codex" || provider == "claude"
        else { throw XCTSkip("Set ANGER_RATE_LIVE_CLI=codex or claude to run the authenticated CLI integration test.") }

        let profile = try await CalibrationService().analyze(messages: [
            message("오늘 작업은 차분하게 진행됐어", offset: 0),
            message("빨리 끝내라고 몇 번을 말하냐", offset: 1),
            message("이 결과는 진짜 개쓰레기 같아", offset: 2)
        ], provider: provider)
        XCTAssertFalse(profile.summary.isEmpty)
        XCTAssertFalse(profile.rules.isEmpty)
        XCTAssertTrue(profile.rules.allSatisfy { (5...50).contains($0.weight) })
    }

    private static let claudeHelp = "--safe-mode --no-session-persistence --no-chrome --tools --disallowedTools --output-format --json-schema --permission-mode --disable-slash-commands"
    private static let codexHelp = "--disable --ask-for-approval"
    private static let codexExecHelp = "--ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check --sandbox --json --output-schema --cd"
    private static let codexFeatures = "shell_tool browser_use browser_use_external computer_use apps image_generation"

    private func message(_ text: String, offset: TimeInterval) -> SessionMessage {
        SessionMessage(id: UUID().uuidString, timestamp: Date(timeIntervalSince1970: 1_700_000_000 + offset), source: "codex", text: text)
    }

    private func makeService(fixture: CalibrationFixture, recorder: CommandRecorder) -> CalibrationService {
        CalibrationService(environment: ["PATH": fixture.directory.path], runner: { executable, arguments, input, directory, timeout, didLaunch in
            try await recorder.run(
                executable: executable,
                arguments: arguments,
                input: input,
                currentDirectory: directory,
                timeout: timeout,
                didLaunch: didLaunch
            )
        })
    }
}

private final class CommandRecorder: @unchecked Sendable {
    struct Invocation {
        let arguments: [String]
        let input: Data
        let directory: URL
    }

    private let lock = NSLock()
    private var storedInvocations: [Invocation] = []
    private let handler: CalibrationCommandRunner

    init(handler: @escaping CalibrationCommandRunner) {
        self.handler = handler
    }

    var invocations: [Invocation] {
        lock.lock(); defer { lock.unlock() }
        return storedInvocations
    }

    func run(
        executable: URL,
        arguments: [String],
        input: Data,
        currentDirectory: URL,
        timeout: TimeInterval,
        didLaunch: @escaping @Sendable (Process) -> Void
    ) async throws -> CalibrationCommandResult {
        record(Invocation(arguments: arguments, input: input, directory: currentDirectory))
        return try await handler(executable, arguments, input, currentDirectory, timeout, didLaunch)
    }

    private func record(_ invocation: Invocation) {
        lock.lock(); defer { lock.unlock() }
        storedInvocations.append(invocation)
    }
}

private struct CalibrationFixture {
    let directory: URL

    init(executableName: String, script: String = "#!/bin/sh\nexit 0\n") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent(executableName)
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private extension CalibrationCommandResult {
    static func success(_ text: String) -> CalibrationCommandResult {
        CalibrationCommandResult(status: 0, stdout: Data(text.utf8), stderr: Data())
    }
}
