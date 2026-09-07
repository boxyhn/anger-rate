import CryptoKit
import Foundation

public struct HistoryAuditReport: Codable, Sendable {
    public var discoveredFiles: Int
    public var readFiles: Int
    public var failedFiles: Int
    public var malformedLines: Int
    public var oversizedLines: Int
    public var userMessages: Int
    public var archiveMessages: Int
    public var uniqueMessages: Int
    public var selectedMessages: [SessionMessage]
    public var phraseCounts: [String: Int]
    public var completed: Bool

    public init(
        discoveredFiles: Int = 0,
        readFiles: Int = 0,
        failedFiles: Int = 0,
        malformedLines: Int = 0,
        oversizedLines: Int = 0,
        userMessages: Int = 0,
        archiveMessages: Int = 0,
        uniqueMessages: Int = 0,
        selectedMessages: [SessionMessage] = [],
        phraseCounts: [String: Int] = [:],
        completed: Bool = false
    ) {
        self.discoveredFiles = discoveredFiles
        self.readFiles = readFiles
        self.failedFiles = failedFiles
        self.malformedLines = malformedLines
        self.oversizedLines = oversizedLines
        self.userMessages = userMessages
        self.archiveMessages = archiveMessages
        self.uniqueMessages = uniqueMessages
        self.selectedMessages = selectedMessages
        self.phraseCounts = phraseCounts
        self.completed = completed
    }
}

public final class HistoryAuditor: @unchecked Sendable {
    private enum RecordKind {
        case codexEvent
        case codexResponse
        case other
    }

    private struct CopyRecord {
        var kind: RecordKind
        var timestamp: Date
    }

    private struct Sample {
        var message: SessionMessage
        var rank: String
        var stratum: String
        var stratumRank: String
    }

    private struct StableReservoir {
        let capacity: Int
        private var primary: [String: Sample] = [:]
        private var heap: [Sample] = []

        init(capacity: Int) {
            self.capacity = capacity
        }

        var samples: [Sample] { Array(primary.values) + heap }

        private var primaryCapacity: Int { capacity / 2 }
        private var overflowCapacity: Int { capacity - primaryCapacity }

        mutating func insert(_ sample: Sample) {
            guard capacity > 0 else { return }
            if let existing = primary[sample.stratum] {
                if isBetter(sample, than: existing) {
                    primary[sample.stratum] = sample
                    insertOverflow(existing)
                } else {
                    insertOverflow(sample)
                }
                return
            }
            if primary.count < primaryCapacity {
                primary[sample.stratum] = sample
                return
            }
            if let worst = primary.max(by: { $0.value.stratumRank < $1.value.stratumRank }),
               sample.stratumRank < worst.value.stratumRank {
                primary.removeValue(forKey: worst.key)
                primary[sample.stratum] = sample
                insertOverflow(worst.value)
            } else {
                insertOverflow(sample)
            }
        }

        private mutating func insertOverflow(_ sample: Sample) {
            guard overflowCapacity > 0 else { return }
            if heap.count < overflowCapacity {
                heap.append(sample)
                siftUp(from: heap.count - 1)
            } else if isBetter(sample, than: heap[0]) {
                heap[0] = sample
                siftDown(from: 0)
            }
        }

        private func isBetter(_ lhs: Sample, than rhs: Sample) -> Bool {
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.message.id < rhs.message.id
        }

        private mutating func siftUp(from start: Int) {
            var child = start
            while child > 0 {
                let parent = (child - 1) / 2
                guard isBetter(heap[parent], than: heap[child]) else { break }
                heap.swapAt(parent, child)
                child = parent
            }
        }

        private mutating func siftDown(from start: Int) {
            var parent = start
            while true {
                let left = parent * 2 + 1
                guard left < heap.count else { return }
                let right = left + 1
                var worseChild = left
                if right < heap.count, isBetter(heap[left], than: heap[right]) { worseChild = right }
                guard isBetter(heap[parent], than: heap[worseChild]) else { return }
                heap.swapAt(parent, worseChild)
                parent = worseChild
            }
        }
    }

    private struct AuditCancelled: Error {}

    private let roots: [URL]
    private let fileManager = FileManager.default
    private let chunkSize = 1 * 1_024 * 1_024
    private let maximumLineSize = 4 * 1_024 * 1_024
    private let frustrationAnchors = [
        "왜", "아니", "다시", "제발", "그만", "말했", "말했잖", "했다고", "짜증",
        "실망", "빨리", "도대체", "몇 번", "제대로", "못하", "안 되", "안돼",
        "stop", "again", "listen", "already", "please", "why", "hurry", "wrong",
        "frustrat", "disappoint", "ridiculous", "enough"
    ]

    public init(roots: [URL] = SessionScanner.defaultRoots()) {
        var expanded = roots
        for root in roots where root.lastPathComponent == "sessions" {
            expanded.append(root.deletingLastPathComponent().appendingPathComponent("archived_sessions"))
        }
        self.roots = Self.uniqueURLs(expanded)
    }

    public func audit(
        progress: @Sendable (Int, Int) -> Void = { _, _ in },
        isCancelled: @Sendable () -> Bool = { false }
    ) -> HistoryAuditReport {
        let files = discoverFiles()
        var report = HistoryAuditReport(discoveredFiles: files.count)
        progress(0, files.count)

        var seenIDs = Set<String>()
        var copyRecords: [String: [CopyRecord]] = [:]
        var phraseCounts: [String: Int] = [:]
        var frustrationSamples = StableReservoir(capacity: 800)
        var neutralSamples = StableReservoir(capacity: 400)

        for (fileIndex, file) in files.enumerated() {
            if isCancelled() {
                report.phraseCounts = repeatedPhrases(phraseCounts)
                report.selectedMessages = selectSamples(frustration: frustrationSamples.samples, neutral: neutralSamples.samples)
                return report
            }

            let sessionID = file.deletingPathExtension().lastPathComponent
            let source = sourceName(for: file)
            let archived = file.pathComponents.contains("archived_sessions")
            var previousUniqueMessage: SessionMessage?

            do {
                try streamLines(in: file, isCancelled: isCancelled) { lineResult in
                    autoreleasepool {
                        switch lineResult {
                        case .oversized:
                            report.oversizedLines += 1
                        case .line(let line):
                            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                                report.malformedLines += 1
                                return
                            }
                            guard isPotentialUserRecord(object) else { return }

                            let parsedSource: String
                            let message: SessionMessage?
                            if let parsed = SessionParser.parse(object: object, source: source, sessionID: sessionID) {
                                parsedSource = source
                                message = parsed
                            } else {
                                parsedSource = source == "claude" ? "codex" : "claude"
                                message = SessionParser.parse(object: object, source: parsedSource, sessionID: sessionID)
                            }
                            guard let message else { return }
                            report.userMessages += 1
                            if archived { report.archiveMessages += 1 }

                            let kind = recordKind(object, source: parsedSource)
                            let copyKey = crossShapeKey(message: message, sessionID: sessionID)
                            let isCopy = copyRecords[copyKey]?.contains {
                                $0.kind != .other && kind != .other && $0.kind != kind
                                    && abs($0.timestamp.timeIntervalSince(message.timestamp)) <= 1
                            } == true
                            if kind != .other {
                                copyRecords[copyKey, default: []].append(CopyRecord(kind: kind, timestamp: message.timestamp))
                                if copyRecords[copyKey]!.count > 8 {
                                    copyRecords[copyKey]!.removeFirst(copyRecords[copyKey]!.count - 8)
                                }
                            }
                            guard !isCopy, seenIDs.insert(message.id).inserted else { return }

                            report.uniqueMessages += 1
                            for phrase in normalizedPhrases(message.text) {
                                phraseCounts[phrase, default: 0] += 1
                            }

                            let sampleMessage = bounded(message)
                            let stratum = sampleStratum(message: message, file: file)
                            if looksFrustrated(message.text) {
                                addSample(sampleMessage, stratum: stratum, salt: "anger", to: &frustrationSamples)
                                if let previousUniqueMessage {
                                    addSample(bounded(previousUniqueMessage), stratum: stratum, salt: "context-\(message.id)", to: &frustrationSamples)
                                }
                            } else {
                                addSample(sampleMessage, stratum: stratum, salt: "neutral", to: &neutralSamples)
                            }
                            previousUniqueMessage = message
                        }
                    }
                }
                report.readFiles += 1
            } catch is AuditCancelled {
                report.phraseCounts = repeatedPhrases(phraseCounts)
                report.selectedMessages = selectSamples(frustration: frustrationSamples.samples, neutral: neutralSamples.samples)
                return report
            } catch {
                report.failedFiles += 1
            }
            progress(fileIndex + 1, files.count)
        }

        report.phraseCounts = repeatedPhrases(phraseCounts)
        report.selectedMessages = selectSamples(frustration: frustrationSamples.samples, neutral: neutralSamples.samples)
        report.completed = true
        return report
    }

    private enum LineResult {
        case line(Data)
        case oversized
    }

    private func streamLines(
        in file: URL,
        isCancelled: @Sendable () -> Bool,
        consume: (LineResult) -> Void
    ) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var buffer = Data()
        var discardingOversizedLine = false

        while true {
            let shouldContinue = try autoreleasepool {
                if isCancelled() { throw AuditCancelled() }
                let chunk = try handle.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty { return false }
                var cursor = chunk.startIndex

                while cursor < chunk.endIndex {
                    if discardingOversizedLine {
                        guard let newline = chunk[cursor...].firstIndex(of: 0x0A) else { break }
                        discardingOversizedLine = false
                        cursor = chunk.index(after: newline)
                        continue
                    }

                    if let newline = chunk[cursor...].firstIndex(of: 0x0A) {
                        let segment = chunk[cursor..<newline]
                        if buffer.count + segment.count > maximumLineSize {
                            consume(.oversized)
                        } else {
                            buffer.append(contentsOf: segment)
                            if !buffer.isEmpty { consume(.line(buffer)) }
                        }
                        buffer.removeAll(keepingCapacity: true)
                        cursor = chunk.index(after: newline)
                    } else {
                        let segment = chunk[cursor...]
                        if buffer.count + segment.count > maximumLineSize {
                            consume(.oversized)
                            buffer.removeAll(keepingCapacity: false)
                            discardingOversizedLine = true
                        } else {
                            buffer.append(contentsOf: segment)
                        }
                        break
                    }
                }
                return true
            }
            if !shouldContinue { break }
        }
        if !discardingOversizedLine, !buffer.isEmpty { consume(.line(buffer)) }
    }

    private func discoverFiles() -> [URL] {
        var paths: [String: URL] = [:]
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let file as URL in enumerator where file.pathExtension.lowercased() == "jsonl" {
                if file.pathComponents.contains("subagents") { continue }
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let resolved = file.resolvingSymlinksInPath().standardizedFileURL
                paths[resolved.path] = resolved
            }
        }
        return paths.values.sorted { $0.path < $1.path }
    }

    private func sourceName(for file: URL) -> String {
        file.path.lowercased().contains(".claude") ? "claude" : "codex"
    }

    private func isPotentialUserRecord(_ object: [String: Any]) -> Bool {
        guard let type = object["type"] as? String else { return false }
        if type == "user" { return true }
        guard let payload = object["payload"] as? [String: Any] else { return false }
        if type == "event_msg" { return payload["type"] as? String == "user_message" }
        return type == "response_item" && payload["type"] as? String == "message"
            && payload["role"] as? String == "user"
    }

    private func recordKind(_ object: [String: Any], source: String) -> RecordKind {
        guard source == "codex", let type = object["type"] as? String else { return .other }
        return type == "response_item" ? .codexResponse : (type == "event_msg" ? .codexEvent : .other)
    }

    private func crossShapeKey(message: SessionMessage, sessionID: String) -> String {
        stableHash(["codex", sessionID, message.text].joined(separator: "\u{1f}"))
    }

    private func looksFrustrated(_ text: String) -> Bool {
        let normalized = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        return frustrationAnchors.contains(where: normalized.contains)
    }

    private func normalizedPhrases(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        let pieces = folded.components(separatedBy: CharacterSet(charactersIn: "\n\r.!?。！？;；"))
        return Set(pieces.compactMap { piece in
            let normalized = piece
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            guard normalized.count >= 2, normalized.count < 80 else { return nil }
            return normalized
        })
    }

    private func bounded(_ message: SessionMessage) -> SessionMessage {
        guard message.text.count > 4_000 else { return message }
        var copy = message
        copy.text = String(message.text.prefix(4_000))
        return copy
    }

    private func sampleStratum(message: SessionMessage, file: URL) -> String {
        let month = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: message.timestamp)
        let monthKey = String(format: "%04d-%02d", month.year ?? 0, month.month ?? 0)
        let fileKey = String(stableHash(file.path).prefix(4))
        return [message.source, monthKey, fileKey].joined(separator: ":")
    }

    private func addSample(
        _ message: SessionMessage,
        stratum: String,
        salt: String,
        to samples: inout StableReservoir
    ) {
        let sample = Sample(
            message: message,
            rank: stableHash("\(salt):\(message.id)"),
            stratum: stratum,
            stratumRank: stableHash("stratum:\(stratum)")
        )
        samples.insert(sample)
    }

    private func selectSamples(
        frustration: [Sample],
        neutral: [Sample]
    ) -> [SessionMessage] {
        let anger = roundRobin(Dictionary(grouping: frustration, by: \.stratum), limit: 400)
        let neutral = roundRobin(Dictionary(grouping: neutral, by: \.stratum), limit: 200)
        var seen = Set<String>()
        return (anger + neutral).filter { seen.insert($0.id).inserted }
    }

    private func roundRobin(_ samples: [String: [Sample]], limit: Int) -> [SessionMessage] {
        let strata = samples.keys.sorted()
        let ranked = samples.mapValues { $0.sorted { $0.rank < $1.rank } }
        var result: [SessionMessage] = []
        var index = 0
        while result.count < limit {
            var added = false
            for stratum in strata {
                guard let group = ranked[stratum], index < group.count else { continue }
                result.append(group[index].message)
                added = true
                if result.count == limit { break }
            }
            if !added { break }
            index += 1
        }
        return result
    }

    private func repeatedPhrases(_ counts: [String: Int]) -> [String: Int] {
        counts.filter { $0.value >= 2 }
    }

    private func stableHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .filter { seen.insert($0.path).inserted }
    }
}
