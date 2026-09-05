import Foundation

public struct DeviceSnapshot: Codable, Equatable, Sendable {
    public var deviceID: String
    public var name: String
    public var updatedAt: Date
    public var events: [ScoredEvent]
    public var profile: PersonalProfile

    public init(
        deviceID: String,
        name: String,
        updatedAt: Date,
        events: [ScoredEvent],
        profile: PersonalProfile
    ) {
        self.deviceID = deviceID
        self.name = name
        self.updatedAt = updatedAt
        self.events = events
        self.profile = profile
    }
}

public enum EventStoreError: Error, Equatable, LocalizedError, Sendable {
    case unsafeDeviceID(String)
    case invalidSnapshot(String)
    case fileTooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .unsafeDeviceID(let value):
            return "Unsafe device identifier: \(value)"
        case .invalidSnapshot(let reason):
            return "Invalid device snapshot: \(reason)"
        case .fileTooLarge(let bytes):
            return "Device snapshot is too large (\(bytes) bytes)"
        }
    }
}

public final class EventStore: @unchecked Sendable {
    private static let fileName = "snapshot.json"
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
        self.fileManager = FileManager()
    }

    public func load() throws -> DeviceSnapshot? {
        let fileURL = directory.appendingPathComponent(Self.fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard data.count <= SnapshotCodec.maximumFileSize else {
            throw EventStoreError.fileTooLarge(data.count)
        }
        let decoded = try SnapshotCodec.decode(data)
        return try SnapshotCodec.validated(decoded, now: Date(), pruningExpiredEvents: true, filteringFutureEvents: true)
    }

    public func save(_ snapshot: DeviceSnapshot) throws {
        let retained = try SnapshotCodec.validated(snapshot, now: Date(), pruningExpiredEvents: true, filteringFutureEvents: false)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try SnapshotCodec.encode(retained)
        guard data.count <= SnapshotCodec.maximumFileSize else {
            throw EventStoreError.fileTooLarge(data.count)
        }
        try data.write(
            to: directory.appendingPathComponent(Self.fileName, isDirectory: false),
            options: [.atomic]
        )
    }
}

public final class FolderSync: @unchecked Sendable {
    public private(set) var warnings: [String] = []

    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
        self.fileManager = FileManager()
    }

    public func exchange(local: DeviceSnapshot) throws -> [DeviceSnapshot] {
        warnings = []
        let now = Date()
        let retainedLocal = try SnapshotCodec.validated(local, now: now, pruningExpiredEvents: true, filteringFutureEvents: false)
        let visibleLocal = try SnapshotCodec.validated(retainedLocal, now: now, pruningExpiredEvents: true, filteringFutureEvents: true)
        let localFile = try fileURL(for: retainedLocal.deviceID)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let localData = try SnapshotCodec.encode(retainedLocal)
        guard localData.count <= SnapshotCodec.maximumFileSize else {
            throw EventStoreError.fileTooLarge(localData.count)
        }
        try localData.write(to: localFile, options: [.atomic])

        let candidates = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        var snapshots = [visibleLocal]
        for candidate in candidates where candidate.pathExtension.lowercased() == "json" {
            if candidate.standardizedFileURL == localFile.standardizedFileURL { continue }
            guard candidate.deletingPathExtension().lastPathComponent.isSafeDeviceID else {
                warnings.append("Skipped unsafe sync filename: \(candidate.lastPathComponent)")
                continue
            }

            do {
                let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    warnings.append("Skipped non-file sync entry: \(candidate.lastPathComponent)")
                    continue
                }
                let size = values.fileSize ?? 0
                guard size <= SnapshotCodec.maximumFileSize else {
                    warnings.append("Skipped oversized sync file: \(candidate.lastPathComponent)")
                    continue
                }
                let data = try Data(contentsOf: candidate, options: [.mappedIfSafe])
                let decoded = try SnapshotCodec.decode(data)
                guard decoded.deviceID == candidate.deletingPathExtension().lastPathComponent else {
                    throw EventStoreError.invalidSnapshot("device ID does not match filename")
                }
                guard decoded.deviceID != retainedLocal.deviceID else { continue }
                snapshots.append(try SnapshotCodec.validated(decoded, now: now, pruningExpiredEvents: true, filteringFutureEvents: true))
            } catch {
                warnings.append("Skipped invalid sync file \(candidate.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return snapshots.sorted { lhs, rhs in
            if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
            return lhs.updatedAt < rhs.updatedAt
        }
    }

    public func mergedEvents(snapshots: [DeviceSnapshot]) -> [ScoredEvent] {
        var byID: [String: ScoredEvent] = [:]
        for event in snapshots.flatMap(\.events) {
            if let existing = byID[event.id] {
                if SnapshotCodec.eventOrder(event, existing) {
                    byID[event.id] = event
                }
            } else {
                byID[event.id] = event
            }
        }
        return byID.values.sorted(by: SnapshotCodec.eventOrder)
    }

    public func latestProfile(snapshots: [DeviceSnapshot]) -> PersonalProfile? {
        snapshots.map(\.profile).max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            return lhs.id < rhs.id
        }
    }

    private func fileURL(for deviceID: String) throws -> URL {
        guard deviceID.isSafeDeviceID else { throw EventStoreError.unsafeDeviceID(deviceID) }
        let result = directory.appendingPathComponent(deviceID, isDirectory: false).appendingPathExtension("json")
        guard result.deletingLastPathComponent().standardizedFileURL.path == directory.path else {
            throw EventStoreError.unsafeDeviceID(deviceID)
        }
        return result
    }
}

private enum SnapshotCodec {
    static let maximumFileSize = 4 * 1_024 * 1_024
    static let retention: TimeInterval = 24 * 60 * 60

    static func encode(_ snapshot: DeviceSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate.bitPattern)
        }
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> DeviceSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSinceReferenceDate: Double(bitPattern: try container.decode(UInt64.self)))
        }
        return try decoder.decode(DeviceSnapshot.self, from: data)
    }

    static func validated(
        _ snapshot: DeviceSnapshot,
        now: Date,
        pruningExpiredEvents: Bool,
        filteringFutureEvents: Bool
    ) throws -> DeviceSnapshot {
        guard snapshot.deviceID.isSafeDeviceID else {
            throw EventStoreError.unsafeDeviceID(snapshot.deviceID)
        }
        let maximumClockSkew: TimeInterval = 30
        let latestAccepted = now.addingTimeInterval(maximumClockSkew)
        guard snapshot.updatedAt <= latestAccepted else {
            throw EventStoreError.invalidSnapshot("snapshot timestamp is in the future")
        }
        guard snapshot.profile.updatedAt <= latestAccepted else {
            throw EventStoreError.invalidSnapshot("profile timestamp is in the future")
        }
        guard snapshot.name.count <= 256 else {
            throw EventStoreError.invalidSnapshot("device name is too long")
        }
        let normalizedPhrases = snapshot.profile.rules.map {
            $0.phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let ruleIDs = snapshot.profile.rules.map(\.id)
        guard !snapshot.profile.id.isEmpty, snapshot.profile.id.count <= 256,
              snapshot.profile.summary.count <= 2_000,
              snapshot.profile.halfLifeSeconds.isFinite,
              (120...900).contains(snapshot.profile.halfLifeSeconds),
              snapshot.profile.rules.count <= 80,
              Set(ruleIDs).count == ruleIDs.count,
              Set(normalizedPhrases).count == normalizedPhrases.count,
              !ruleIDs.contains(where: { $0.isEmpty || $0.count > 256 }),
              !normalizedPhrases.contains(where: { $0.isEmpty || $0.count > 80 }),
              snapshot.profile.rules.allSatisfy({
                  $0.reason.count <= 1_024 && $0.weight.isFinite && (5...50).contains($0.weight)
              }) else {
            throw EventStoreError.invalidSnapshot("profile metadata exceeds limits")
        }

        let oldest = now.addingTimeInterval(-retention)
        var events: [ScoredEvent] = []
        for event in snapshot.events {
            guard event.timestamp <= latestAccepted else {
                throw EventStoreError.invalidSnapshot("event timestamp is in the future")
            }
            guard event.points.isFinite, (0...100).contains(event.points) else {
                throw EventStoreError.invalidSnapshot("event points must be finite and between 0 and 100")
            }
            guard event.deviceID == snapshot.deviceID else {
                throw EventStoreError.invalidSnapshot("event device ID does not match snapshot")
            }
            guard event.id.count <= 256, event.source.count <= 256,
                  event.profileID.count <= 256, event.reasons.count <= 64,
                  event.reasons.allSatisfy({ $0.count <= 512 }) else {
                throw EventStoreError.invalidSnapshot("event metadata exceeds limits")
            }
            let isRetained = !pruningExpiredEvents || event.timestamp >= oldest
            let isVisible = !filteringFutureEvents || event.timestamp <= now
            if isRetained && isVisible { events.append(event) }
        }

        var result = snapshot
        result.events = events.sorted(by: eventOrder)
        return result
    }

    static func eventOrder(_ lhs: ScoredEvent, _ rhs: ScoredEvent) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
        if lhs.source != rhs.source { return lhs.source < rhs.source }
        if lhs.points != rhs.points { return lhs.points < rhs.points }
        if lhs.profileID != rhs.profileID { return lhs.profileID < rhs.profileID }
        return lhs.reasons.lexicographicallyPrecedes(rhs.reasons)
    }
}

private extension String {
    var isSafeDeviceID: Bool {
        guard !isEmpty, utf8.count <= 128 else { return false }
        return unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
    }
}
