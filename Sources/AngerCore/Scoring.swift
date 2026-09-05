import Foundation

public enum ScoreEngine {
    public static let defaultHalfLife: TimeInterval = 300

    /// Reduces immutable score events into a current 0...100 value. Repetition is
    /// derived only from the sorted event set so connected devices converge on
    /// the same result regardless of arrival order.
    public static func score(
        events: [ScoredEvent],
        at date: Date,
        halfLife: TimeInterval = defaultHalfLife
    ) -> Double {
        guard halfLife > 0, halfLife.isFinite, date.timeIntervalSinceReferenceDate.isFinite,
              !events.isEmpty else { return 0 }

        let ordered = orderedEvents(events, at: date)
        return reduce(ordered: ordered, at: date, halfLife: halfLife).score
    }

    fileprivate static func orderedEvents(_ events: [ScoredEvent], at date: Date) -> [ScoredEvent] {
        var unique: [String: ScoredEvent] = [:]
        for event in events where event.points > 0 && event.points.isFinite
            && event.timestamp.timeIntervalSinceReferenceDate.isFinite && event.timestamp <= date {
            if let existing = unique[event.id] {
                unique[event.id] = canonical(existing, event)
            } else {
                unique[event.id] = event
            }
        }
        return unique.values.sorted {
            if $0.timestamp == $1.timestamp { return $0.id < $1.id }
            return $0.timestamp < $1.timestamp
        }
    }

    fileprivate static func reduce(
        ordered: [ScoredEvent],
        at date: Date,
        halfLife: TimeInterval,
        visit: (ScoredEvent, Double, Double) -> Void = { _, _, _ in }
    ) -> (score: Double, lastTimestamp: Date?) {
        var recentTimestamps: [Date] = []
        var runningScore = 0.0
        var previousTimestamp: Date?
        for event in ordered {
            if let previousTimestamp {
                let elapsed = max(0, event.timestamp.timeIntervalSince(previousTimestamp))
                runningScore *= pow(0.5, elapsed / halfLife)
            }
            let cutoff = event.timestamp.addingTimeInterval(-120)
            recentTimestamps.removeAll { $0 < cutoff }
            let repeatMultiplier = 1 + min(Double(recentTimestamps.count) * 0.15, 0.45)
            recentTimestamps.append(event.timestamp)
            let scoreBeforeEvent = runningScore
            runningScore = min(100, runningScore + event.points * repeatMultiplier)
            visit(event, scoreBeforeEvent, runningScore)
            previousTimestamp = event.timestamp
        }
        guard let previousTimestamp else { return (0, nil) }
        let finalDecay = pow(0.5, max(0, date.timeIntervalSince(previousTimestamp)) / halfLife)
        return (min(100, max(0, runningScore * finalDecay)), previousTimestamp)
    }

    public static func evaluate(
        message: SessionMessage,
        profile: PersonalProfile,
        deviceID: String
    ) -> ScoredEvent? {
        let text = scorableText(from: message.text)
        guard !text.isEmpty, !looksLikeMetaDiscussion(text) else { return nil }

        let folded = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        var candidates: [MatchCandidate] = []
        for (ruleIndex, rule) in profile.rules.enumerated()
            where rule.enabled && rule.weight > 0 && rule.weight.isFinite {
            let phrase = rule.phrase
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
            guard !phrase.isEmpty else { continue }
            for range in occurrenceRanges(of: phrase, in: folded, limit: 3) {
                candidates.append(MatchCandidate(ruleIndex: ruleIndex, range: range, phraseLength: range.length))
            }
        }

        candidates.sort {
            if $0.phraseLength != $1.phraseLength { return $0.phraseLength > $1.phraseLength }
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            return $0.ruleIndex < $1.ruleIndex
        }
        var claimed: [NSRange] = []
        var matchCounts: [Int: Int] = [:]
        for candidate in candidates where !claimed.contains(where: { NSIntersectionRange($0, candidate.range).length > 0 }) {
            claimed.append(candidate.range)
            matchCounts[candidate.ruleIndex, default: 0] += 1
        }

        var points = 0.0
        var reasons: [String] = []
        for (index, rule) in profile.rules.enumerated() {
            guard let count = matchCounts[index] else { continue }
            points += rule.weight * Double(count)
            reasons.append(count == 1 ? rule.reason : "\(rule.reason) ×\(count)")
        }

        guard points > 0 else { return nil }
        return ScoredEvent(
            id: message.id,
            timestamp: message.timestamp,
            deviceID: deviceID,
            source: message.source,
            points: min(100, points),
            reasons: reasons,
            profileID: profile.id
        )
    }

    private struct MatchCandidate {
        var ruleIndex: Int
        var range: NSRange
        var phraseLength: Int
    }

    private static func occurrenceRanges(of phrase: String, in text: String, limit: Int) -> [NSRange] {
        let haystack = text as NSString
        let needleLength = (phrase as NSString).length
        guard needleLength > 0 else { return [] }
        var ranges: [NSRange] = []
        var searchRange = NSRange(location: 0, length: haystack.length)
        while ranges.count < limit, searchRange.length > 0 {
            let found = haystack.range(of: phrase, options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: haystack.length - next)
        }
        return ranges
    }

    private static func canonical(_ lhs: ScoredEvent, _ rhs: ScoredEvent) -> ScoredEvent {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp ? lhs : rhs }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID ? lhs : rhs }
        if lhs.source != rhs.source { return lhs.source < rhs.source ? lhs : rhs }
        if lhs.profileID != rhs.profileID { return lhs.profileID < rhs.profileID ? lhs : rhs }
        if lhs.points != rhs.points { return lhs.points < rhs.points ? lhs : rhs }
        return lhs.reasons.lexicographicallyPrecedes(rhs.reasons) ? lhs : rhs
    }

    private static func scorableText(from input: String) -> String {
        var result = input
        result = replacing(pattern: "(?s)```.*?```", in: result)
        result = replacing(pattern: "`[^`\\n]*`", in: result)
        result = replacing(pattern: "(?is)<(?:system-reminder|environment_context|recommended_plugins|agents-instructions|developer)[^>]*>.*?</(?:system-reminder|environment_context|recommended_plugins|agents-instructions|developer)>", in: result)

        let excludedPrefixes = [
            ">", "system:", "developer:", "assistant:", "# agents.md",
            "<system", "<developer", "<environment_context", "<recommended_plugins"
        ]
        return result
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let lowered = trimmed.lowercased()
                return !trimmed.isEmpty && !excludedPrefixes.contains(where: lowered.hasPrefix)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: " "
        )
    }

    private static func looksLikeMetaDiscussion(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let discussionMarkers = [
            "욕설 기준", "욕설 목록", "욕설을 감지", "욕을 감지", "욕을 어떻게",
            "욕이라는", "욕으로 분류", "욕설로 분류", "비속어", "swear word",
            "swearing", "profanity", "분노 rate", "분노율"
        ]
        return discussionMarkers.contains(where: lowered.contains)
    }
}

public struct AlertGate: Codable, Equatable, Sendable {
    private var armed: Bool
    private var previousScore: Double
    private var processedEventTimestamps: [String: Date]

    public init(armed: Bool = true, previousScore: Double = 0) {
        self.armed = armed
        self.previousScore = previousScore
        self.processedEventTimestamps = [:]
    }

    /// Returns true once when the score crosses 100. The gate rearms only after
    /// cooling to 50 or below. Historical/startup evaluations pass false for
    /// allowAlert, which records a hot state without producing a stale alert.
    public mutating func update(score: Double, allowAlert: Bool) -> Bool {
        guard score.isFinite else { return false }
        let normalized = min(100, max(0, score))
        if normalized <= 50 { armed = true }

        let crossed = previousScore < 100 && normalized >= 100
        previousScore = normalized

        guard allowAlert else {
            if normalized >= 100 { armed = false }
            return false
        }
        guard armed, crossed else { return false }
        armed = false
        return true
    }

    /// Evaluates threshold crossings at the exact timestamps of newly received
    /// events, then records the decayed score at `date`. This prevents polling
    /// latency from hiding a brief peak at 100. `notificationDeviceID` assigns a
    /// converged crossing to its originating device; two offline devices can
    /// still notify independently before their event sets converge.
    public mutating func update(
        events: [ScoredEvent],
        newEventIDs: Set<String>,
        at date: Date,
        halfLife: Double,
        allowAlert: Bool,
        notificationDeviceID: String? = nil
    ) -> Bool {
        guard halfLife > 0, halfLife.isFinite, date.timeIntervalSinceReferenceDate.isFinite else {
            return false
        }

        let ordered = ScoreEngine.orderedEvents(events, at: date)
        processedEventTimestamps = processedEventTimestamps.filter {
            date.timeIntervalSince($0.value) <= 120
        }
        let unprocessedIDs = newEventIDs.subtracting(processedEventTimestamps.keys)
        var shouldAlert = false
        var gateArmed = armed
        let result = ScoreEngine.reduce(ordered: ordered, at: date, halfLife: halfLife) {
            event, scoreBeforeEvent, scoreAfterEvent in
            guard unprocessedIDs.contains(event.id) else { return }
            if scoreBeforeEvent <= 50 { gateArmed = true }

            let age = date.timeIntervalSince(event.timestamp)
            let fresh = age >= 0 && age <= 60
            let crossed = scoreBeforeEvent < 100 && scoreAfterEvent >= 100
            if crossed {
                let ownsNotification = notificationDeviceID == nil || notificationDeviceID == event.deviceID
                if gateArmed, allowAlert, fresh, ownsNotification { shouldAlert = true }
                gateArmed = false
            }
        }

        if result.score <= 50 { gateArmed = true }
        if result.score >= 100 { gateArmed = false }
        armed = gateArmed
        previousScore = result.score
        for event in ordered where newEventIDs.contains(event.id) {
            processedEventTimestamps[event.id] = event.timestamp
        }
        return shouldAlert
    }
}
