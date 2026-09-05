import Foundation

public final class PeerCache: @unchecked Sendable {
    public private(set) var warnings: [String] = []

    private static let cacheDirectoryName = "peer-cache-v1"
    private static let retention: TimeInterval = 24 * 60 * 60

    private let directory: URL
    private let fileManager: FileManager

    /// `directory` is an app-owned parent. PeerCache only creates and removes
    /// its `peer-cache-v1` child and never treats sibling files as cache data.
    public init(directory: URL) {
        self.directory = directory.standardizedFileURL
            .appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
        self.fileManager = FileManager()
    }

    public func load() -> [DeviceSnapshot] {
        warnings = []
        return load(now: Date())
    }

    public func merge(
        _ snapshots: [DeviceSnapshot],
        excludingDeviceID: String
    ) throws -> [DeviceSnapshot] {
        guard excludingDeviceID.isSafePeerCacheDeviceID else {
            throw PeerCacheError.unsafeDeviceID(excludingDeviceID)
        }

        let now = Date()
        var cached = Dictionary(uniqueKeysWithValues: load(now: now).map { ($0.deviceID, $0) })
        let oldest = now.addingTimeInterval(-Self.retention)

        for snapshot in snapshots where snapshot.deviceID != excludingDeviceID {
            guard snapshot.deviceID.isSafePeerCacheDeviceID else {
                throw PeerCacheError.unsafeDeviceID(snapshot.deviceID)
            }
            guard snapshot.updatedAt >= oldest else { continue }
            if let existing = cached[snapshot.deviceID], existing.updatedAt >= snapshot.updatedAt {
                continue
            }
            try store(for: snapshot.deviceID).save(snapshot)
            cached[snapshot.deviceID] = snapshot
        }

        cached.removeValue(forKey: excludingDeviceID)
        return cached.values
            .filter { $0.updatedAt >= oldest }
            .sorted(by: Self.snapshotOrder)
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func load(now: Date) -> [DeviceSnapshot] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            warnings.append("Could not read peer cache: \(error.localizedDescription)")
            return []
        }

        let oldest = now.addingTimeInterval(-Self.retention)
        var snapshots: [DeviceSnapshot] = []
        for entry in entries {
            let deviceID = entry.lastPathComponent
            guard deviceID.isSafePeerCacheDeviceID else {
                warnings.append("Skipped unsafe peer cache entry: \(deviceID)")
                continue
            }

            do {
                let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else {
                    warnings.append("Skipped invalid peer cache entry: \(deviceID)")
                    continue
                }
                guard let snapshot = try store(for: deviceID).load() else {
                    warnings.append("Skipped empty peer cache entry: \(deviceID)")
                    continue
                }
                guard snapshot.deviceID == deviceID else {
                    throw PeerCacheError.deviceIDMismatch(expected: deviceID, actual: snapshot.deviceID)
                }
                guard snapshot.updatedAt >= oldest else {
                    try fileManager.removeItem(at: entry)
                    continue
                }
                snapshots.append(snapshot)
            } catch {
                warnings.append("Skipped invalid peer cache entry \(deviceID): \(error.localizedDescription)")
            }
        }
        return snapshots.sorted(by: Self.snapshotOrder)
    }

    private func store(for deviceID: String) throws -> EventStore {
        guard deviceID.isSafePeerCacheDeviceID else {
            throw PeerCacheError.unsafeDeviceID(deviceID)
        }
        let deviceDirectory = directory.appendingPathComponent(deviceID, isDirectory: true)
        guard deviceDirectory.deletingLastPathComponent().standardizedFileURL.path == directory.path else {
            throw PeerCacheError.unsafeDeviceID(deviceID)
        }
        return EventStore(directory: deviceDirectory)
    }

    private static func snapshotOrder(_ lhs: DeviceSnapshot, _ rhs: DeviceSnapshot) -> Bool {
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
        return lhs.updatedAt < rhs.updatedAt
    }
}

public enum PeerCacheError: Error, Equatable, LocalizedError, Sendable {
    case unsafeDeviceID(String)
    case deviceIDMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .unsafeDeviceID(let value):
            return "Unsafe peer device identifier: \(value)"
        case .deviceIDMismatch(let expected, let actual):
            return "Peer cache device mismatch: expected \(expected), found \(actual)"
        }
    }
}

private extension String {
    var isSafePeerCacheDeviceID: Bool {
        guard !isEmpty, utf8.count <= 128 else { return false }
        return utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || $0 == 45 || $0 == 95
        }
    }
}
