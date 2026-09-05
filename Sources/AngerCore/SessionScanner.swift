import CryptoKit
import Foundation

public enum SessionParser {
    public static func parse(line: Data, source: String, sessionID: String) -> SessionMessage? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let timestamp = parseDate(object["timestamp"] ?? object["created_at"] ?? object["createdAt"])
        else { return nil }

        let sourceKind = source.lowercased()
        let text: String?
        if sourceKind.contains("codex") {
            text = codexText(object)
        } else if sourceKind.contains("claude") {
            text = claudeText(object)
        } else {
            return nil
        }

        guard let rawText = text else { return nil }
        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isInjectedWrapper(cleaned) else { return nil }

        let timestampKey = String(
            format: "%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            timestamp.timeIntervalSince1970
        )
        let identity = [source, sessionID, timestampKey, cleaned].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return SessionMessage(id: digest, timestamp: timestamp, source: source, text: cleaned)
    }

    private static func codexText(_ object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any] else { return nil }
        if object["type"] as? String == "event_msg", payload["type"] as? String == "user_message" {
            return payload["message"] as? String ?? payload["text"] as? String
        }
        guard object["type"] as? String == "response_item",
              payload["type"] as? String == "message",
              payload["role"] as? String == "user",
              let blocks = payload["content"] as? [[String: Any]]
        else { return nil }
        let texts = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "input_text" else { return nil }
            return block["text"] as? String
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    private static func claudeText(_ object: [String: Any]) -> String? {
        guard object["type"] as? String == "user",
              object["isMeta"] as? Bool != true,
              object["isSidechain"] as? Bool != true,
              object["agentId"] == nil,
              object["agent_id"] == nil,
              let message = object["message"] as? [String: Any],
              (message["role"] as? String ?? "user") == "user"
        else { return nil }

        if let content = message["content"] as? String { return content }
        guard let blocks = message["content"] as? [[String: Any]] else { return nil }
        let textBlocks = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            let value = block["text"] as? String
            guard let value, !isInjectedWrapper(value) else { return nil }
            return value
        }
        return textBlocks.isEmpty ? nil : textBlocks.joined(separator: "\n")
    }

    private static func isInjectedWrapper(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefixes = [
            "<system-reminder", "<environment_context", "<recommended_plugins",
            "<agents", "<developer", "# agents.md instructions", "#agents.md instructions",
            "you are an ai assistant"
        ]
        return prefixes.contains(where: value.hasPrefix)
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }
}

public final class SessionScanner: @unchecked Sendable {
    private struct Cursor {
        var offset: UInt64
    }

    private struct FileCache {
        var createdAt: Date
        var rootModificationDates: [Date]
        var files: [URL]
    }

    private enum RecordKind: String {
        case codexEvent
        case codexResponse
        case other
    }

    private struct ParsedCandidate {
        var message: SessionMessage
        var sessionID: String
        var kind: RecordKind
    }

    private struct SeenCopy {
        var kind: RecordKind
        var timestamp: Date
        var observedAt: Date
    }

    private let roots: [URL]
    private let historyRoots: [URL]
    private let claudeRoots: Set<String>
    private let fileManager: FileManager
    private var cursors: [String: Cursor] = [:]
    private var fileCaches: [String: FileCache] = [:]
    private var recentCopies: [String: [SeenCopy]] = [:]
    private var initialized = false
    private let maxTrackedFiles = 4_096
    private let maxIncrementalRead = 2 * 1_024 * 1_024

    public private(set) var scannedFileCount = 0
    public private(set) var historicalArchiveMessageCount = 0
    public private(set) var lastError: String?

    public init(roots: [URL] = SessionScanner.defaultRoots()) {
        self.roots = Self.uniqueURLs(roots)
        self.historyRoots = Self.uniqueURLs(roots + roots.compactMap { root in
            guard root.lastPathComponent == "sessions" else { return nil }
            return root.deletingLastPathComponent().appendingPathComponent("archived_sessions")
        })
        self.claudeRoots = Set(Self.configuredClaudeRoots().map { $0.resolvingSymlinksInPath().standardizedFileURL.path })
        self.fileManager = .default
    }

    public static func defaultRoots() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates: [URL] = []

        if let codexHome = environment["CODEX_HOME"], !codexHome.isEmpty {
            candidates.append(URL(fileURLWithPath: codexHome).appendingPathComponent("sessions"))
        }
        if let claudeHome = environment["CLAUDE_CONFIG_DIR"], !claudeHome.isEmpty {
            candidates.append(URL(fileURLWithPath: claudeHome).appendingPathComponent("projects"))
        }

        if let names = try? FileManager.default.contentsOfDirectory(atPath: home.path) {
            for name in names where name == ".codex" || name.hasPrefix(".codex-") {
                candidates.append(home.appendingPathComponent(name).appendingPathComponent("sessions"))
            }
        }
        candidates.append(home.appendingPathComponent(".claude/projects"))
        return uniqueURLs(candidates)
    }

    public func scanNew() -> [SessionMessage] {
        lastError = nil
        let files = sessionFiles()
        scannedFileCount = files.count
        let paths = Set(files.map(\.path))
        cursors = cursors.filter { paths.contains($0.key) }

        if !initialized {
            for file in files {
                cursors[file.path] = Cursor(offset: lastCompleteLineOffset(file))
            }
            initialized = true
            trimCursorsIfNeeded(files: files)
            return []
        }

        var candidates: [ParsedCandidate] = []
        for file in files {
            let size = fileSize(file)
            var offset = cursors[file.path]?.offset ?? 0
            if size < offset { offset = 0 }
            guard size > offset else {
                cursors[file.path] = Cursor(offset: offset)
                continue
            }

            do {
                let result = try readCompleteLines(from: file, startingAt: offset, fileSize: size)
                let sessionID = file.deletingPathExtension().lastPathComponent
                for line in result.lines {
                    if let candidate = parseCandidate(line: line, file: file, sessionID: sessionID) {
                        candidates.append(candidate)
                    }
                }
                cursors[file.path] = Cursor(offset: result.nextOffset)
            } catch {
                lastError = "\(file.lastPathComponent): \(error.localizedDescription)"
            }
        }
        trimCursorsIfNeeded(files: files)
        return collapseCopies(candidates, trackRecent: true).sorted {
            if $0.timestamp == $1.timestamp { return $0.id < $1.id }
            return $0.timestamp < $1.timestamp
        }
    }

    public func historicalMessages(limit: Int = 400) -> [SessionMessage] {
        guard limit > 0 else { return [] }
        lastError = nil
        // Stratify by log root so old archives cannot be crowded out by live files.
        let groups = historyRoots.map { sessionFiles(in: [$0]) }
        scannedFileCount = Set(groups.flatMap { $0 }.map(\.path)).count
        var selected: [URL] = []
        var selectedPaths = Set<String>()
        var depth = 0
        while selected.count < 160 {
            var added = false
            for group in groups where depth < group.count {
                let file = group[depth]
                if selectedPaths.insert(file.path).inserted { selected.append(file); added = true }
                if selected.count == 160 { break }
            }
            if !added { break }
            depth += 1
        }
        historicalArchiveMessageCount = 0
        var archiveIDs = Set<String>()
        var perFile: [[SessionMessage]] = []

        for file in selected {
            do {
                let data = try tailData(of: file, maximumBytes: 512 * 1_024)
                let sessionID = file.deletingPathExtension().lastPathComponent
                let candidates = data.split(separator: 0x0A).compactMap {
                    parseCandidate(line: Data($0), file: file, sessionID: sessionID)
                }
                let parsed = collapseCopies(candidates, trackRecent: false).sorted { $0.timestamp > $1.timestamp }
                if !parsed.isEmpty { perFile.append(parsed) }
                if file.pathComponents.contains("archived_sessions") { archiveIDs.formUnion(parsed.map(\.id)) }
            } catch {
                lastError = "\(file.lastPathComponent): \(error.localizedDescription)"
            }
        }

        var result: [SessionMessage] = []
        var index = 0
        while result.count < limit {
            var added = false
            for messages in perFile where index < messages.count {
                result.append(messages[index])
                added = true
                if result.count == limit { break }
            }
            if !added { break }
            index += 1
        }
        let output = Array(deduplicated(result).prefix(limit))
        historicalArchiveMessageCount = output.filter { archiveIDs.contains($0.id) }.count
        return output
    }

    private func sessionFiles() -> [URL] {
        sessionFiles(in: roots)
    }

    private func sessionFiles(in searchRoots: [URL]) -> [URL] {
        let cacheKey = searchRoots.map(\.path).sorted().joined(separator: "\u{1f}")
        let now = Date()
        let rootDates = discoveryModificationDates(for: searchRoots)
        if let cache = fileCaches[cacheKey],
           now.timeIntervalSince(cache.createdAt) < 30,
           cache.rootModificationDates == rootDates {
            return cache.files
        }

        var discovered: [String: (url: URL, modifiedAt: Date)] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        for root in searchRoots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let file as URL in enumerator where file.pathExtension.lowercased() == "jsonl" {
                if file.pathComponents.contains("subagents") { continue }
                if (try? file.resourceValues(forKeys: Set(keys)).isRegularFile) == true {
                    let resolved = file.resolvingSymlinksInPath().standardizedFileURL
                    let modifiedAt = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    if let existing = discovered[resolved.path] {
                        if modifiedAt > existing.modifiedAt { discovered[resolved.path] = (resolved, modifiedAt) }
                    } else {
                        discovered[resolved.path] = (resolved, modifiedAt)
                    }
                }
            }
        }
        let result = Array(discovered.values.sorted {
            if $0.modifiedAt == $1.modifiedAt { return $0.url.path < $1.url.path }
            return $0.modifiedAt > $1.modifiedAt
        }.prefix(maxTrackedFiles).map(\.url))
        fileCaches[cacheKey] = FileCache(createdAt: now, rootModificationDates: rootDates, files: result)
        return result
    }

    private func readCompleteLines(
        from file: URL,
        startingAt offset: UInt64,
        fileSize: UInt64
    ) throws -> (lines: [Data], nextOffset: UInt64) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let requested = min(UInt64(maxIncrementalRead), fileSize - offset)
        let data = try handle.read(upToCount: Int(requested)) ?? Data()
        guard let lastNewline = data.lastIndex(of: 0x0A) else {
            // Do not retain an unbounded partial line. Malformed multi-megabyte
            // records are skipped in chunks while normal partial JSON is retried.
            let next = data.count >= maxIncrementalRead ? offset + UInt64(data.count) : offset
            return ([], next)
        }
        let complete = Data(data[...lastNewline])
        let lines = complete.split(separator: 0x0A).map { Data($0) }
        return (lines, offset + UInt64(complete.count))
    }

    private func tailData(of file: URL, maximumBytes: Int) throws -> Data {
        let size = fileSize(file)
        let start = size > UInt64(maximumBytes) ? size - UInt64(maximumBytes) : 0
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: start)
        var data = try handle.read(upToCount: maximumBytes) ?? Data()
        if start > 0, let newline = data.firstIndex(of: 0x0A) {
            data = Data(data[data.index(after: newline)...])
        }
        return data
    }

    private func sourceName(for file: URL) -> String {
        let resolvedPath = file.resolvingSymlinksInPath().standardizedFileURL.path
        if claudeRoots.contains(where: { resolvedPath == $0 || resolvedPath.hasPrefix($0 + "/") }) {
            return "claude"
        }
        return resolvedPath.lowercased().contains(".claude") ? "claude" : "codex"
    }

    private func parseCandidate(line: Data, file: URL, sessionID: String) -> ParsedCandidate? {
        let preferred = sourceName(for: file)
        if let message = SessionParser.parse(line: line, source: preferred, sessionID: sessionID) {
            return ParsedCandidate(message: message, sessionID: sessionID, kind: recordKind(line, source: preferred))
        }
        let fallback = preferred == "claude" ? "codex" : "claude"
        guard let message = SessionParser.parse(line: line, source: fallback, sessionID: sessionID) else { return nil }
        return ParsedCandidate(message: message, sessionID: sessionID, kind: recordKind(line, source: fallback))
    }

    private func recordKind(_ line: Data, source: String) -> RecordKind {
        guard source == "codex",
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String else { return .other }
        return type == "response_item" ? .codexResponse : (type == "event_msg" ? .codexEvent : .other)
    }

    private func collapseCopies(_ input: [ParsedCandidate], trackRecent: Bool) -> [SessionMessage] {
        let ordered = input.sorted {
            if $0.message.timestamp == $1.message.timestamp {
                if $0.kind != $1.kind { return $0.kind == .codexResponse }
                return $0.message.id < $1.message.id
            }
            return $0.message.timestamp < $1.message.timestamp
        }
        var accepted: [ParsedCandidate] = []
        var indicesByKey: [String: [Int]] = [:]
        for candidate in ordered {
            let key = copyKey(candidate)
            let oppositeIndex = indicesByKey[key]?.reversed().first { index in
                let existing = accepted[index]
                return existing.kind != .other && candidate.kind != .other
                    && existing.kind != candidate.kind
                    && abs(existing.message.timestamp.timeIntervalSince(candidate.message.timestamp)) <= 1
            }
            if let oppositeIndex {
                if candidate.kind == .codexResponse { accepted[oppositeIndex] = candidate }
                continue
            }
            indicesByKey[key, default: []].append(accepted.count)
            accepted.append(candidate)
        }

        guard trackRecent else { return deduplicated(accepted.map(\.message)) }
        let observedAt = Date()
        recentCopies = recentCopies.compactMapValues { values in
            let fresh = values.filter { observedAt.timeIntervalSince($0.observedAt) <= 120 }
            return fresh.isEmpty ? nil : fresh
        }
        var messages: [SessionMessage] = []
        for candidate in accepted {
            let key = copyKey(candidate)
            let isCrossScanCopy = recentCopies[key]?.contains { seen in
                seen.kind != .other && candidate.kind != .other && seen.kind != candidate.kind
                    && abs(seen.timestamp.timeIntervalSince(candidate.message.timestamp)) <= 1
            } == true
            if !isCrossScanCopy { messages.append(candidate.message) }
            if candidate.kind != .other {
                recentCopies[key, default: []].append(SeenCopy(
                    kind: candidate.kind, timestamp: candidate.message.timestamp, observedAt: observedAt
                ))
                if recentCopies[key]!.count > 8 { recentCopies[key]!.removeFirst(recentCopies[key]!.count - 8) }
            }
        }
        if recentCopies.count > 4_096 {
            let keep = recentCopies.sorted { lhs, rhs in
                (lhs.value.last?.observedAt ?? .distantPast) > (rhs.value.last?.observedAt ?? .distantPast)
            }.prefix(4_096)
            recentCopies = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        return deduplicated(messages)
    }

    private func copyKey(_ candidate: ParsedCandidate) -> String {
        let source = candidate.message.source == "codex" ? "codex" : candidate.message.source
        let identity = [source, candidate.sessionID, candidate.message.text].joined(separator: "\u{1f}")
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func fileSize(_ file: URL) -> UInt64 {
        let attributes = try? fileManager.attributesOfItem(atPath: file.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func lastCompleteLineOffset(_ file: URL) -> UInt64 {
        let size = fileSize(file)
        guard size > 0 else { return 0 }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return size }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: size - 1)
            if try handle.read(upToCount: 1)?.first == 0x0A { return size }
            let maximum: UInt64 = 64 * 1_024
            let start = size > maximum ? size - maximum : 0
            try handle.seek(toOffset: start)
            let data = try handle.read(upToCount: Int(size - start)) ?? Data()
            guard let newline = data.lastIndex(of: 0x0A) else { return start == 0 ? 0 : size }
            return start + UInt64(data.distance(from: data.startIndex, to: data.index(after: newline)))
        } catch {
            return size
        }
    }

    private func modificationDate(_ file: URL) -> Date {
        let attributes = try? fileManager.attributesOfItem(atPath: file.path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }

    private func discoveryModificationDates(for searchRoots: [URL]) -> [Date] {
        var directories = searchRoots
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        for root in searchRoots {
            if root.lastPathComponent == "sessions",
               let year = components.year, let month = components.month, let day = components.day {
                directories.append(root
                    .appendingPathComponent(String(format: "%04d", year))
                    .appendingPathComponent(String(format: "%02d", month))
                    .appendingPathComponent(String(format: "%02d", day)))
            } else if root.lastPathComponent == "projects",
                      let children = try? fileManager.contentsOfDirectory(
                        at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
                      ) {
                directories.append(contentsOf: children.filter {
                    (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                })
            }
        }
        return Self.uniqueURLs(directories).sorted { $0.path < $1.path }.map(modificationDate)
    }

    private func trimCursorsIfNeeded(files: [URL]) {
        guard cursors.count > maxTrackedFiles else { return }
        let keep = Set(files.prefix(maxTrackedFiles).map(\.path))
        cursors = cursors.filter { keep.contains($0.key) }
    }

    private func deduplicated(_ messages: [SessionMessage]) -> [SessionMessage] {
        var seen = Set<String>()
        return messages.filter { seen.insert($0.id).inserted }
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .filter { seen.insert($0.path).inserted }
    }

    private static func configuredClaudeRoots() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        var roots = [home.appendingPathComponent(".claude/projects")]
        if let configured = environment["CLAUDE_CONFIG_DIR"], !configured.isEmpty {
            roots.append(URL(fileURLWithPath: configured).appendingPathComponent("projects"))
        }
        return uniqueURLs(roots)
    }
}
