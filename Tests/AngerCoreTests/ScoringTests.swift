import XCTest
@testable import AngerCore

final class ScoringTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    func testEvaluateMatchesPersonalRulesAndCapsOccurrences() {
        let profile = PersonalProfile(
            id: "profile",
            updatedAt: epoch,
            summary: "fixture",
            rules: [LanguageRule(id: "rule", phrase: "화나", weight: 12, reason: "강한 표현")]
        )
        let message = SessionMessage(
            id: "message",
            timestamp: epoch,
            source: "codex",
            text: "화나 화나 화나 화나"
        )

        let event = ScoreEngine.evaluate(message: message, profile: profile, deviceID: "mac-a")

        XCTAssertEqual(event?.id, "message")
        XCTAssertEqual(event?.points, 36)
        XCTAssertEqual(event?.reasons, ["강한 표현 ×3"])
    }

    func testEvaluateExcludesQuotesCodeWrappersAndMetaDiscussion() {
        let profile = PersonalProfile(
            id: "profile",
            updatedAt: epoch,
            summary: "fixture",
            rules: [LanguageRule(phrase: "시발", weight: 30, reason: "욕설")]
        )
        let excluded = [
            "> 시발이라고 썼다",
            "```\n시발\n```",
            "`시발`",
            "<system-reminder>시발</system-reminder>",
            "욕설 기준에 시발을 추가해줘"
        ]

        for (index, text) in excluded.enumerated() {
            let message = SessionMessage(id: "m\(index)", timestamp: epoch, source: "codex", text: text)
            XCTAssertNil(ScoreEngine.evaluate(message: message, profile: profile, deviceID: "mac"), text)
        }
    }

    func testScoreUsesHalfLifeAndDeterministicNearbyRepeatBonus() {
        let first = event(id: "a", at: epoch, points: 10, device: "mac-a")
        let second = event(id: "b", at: epoch.addingTimeInterval(60), points: 10, device: "mac-b")
        let now = epoch.addingTimeInterval(60)
        let expected = 10 * pow(0.5, 60.0 / 300.0) + 10 * 1.15

        let forward = ScoreEngine.score(events: [first, second], at: now, halfLife: 300)
        let reversed = ScoreEngine.score(events: [second, first, first], at: now, halfLife: 300)

        XCTAssertEqual(forward, expected, accuracy: 0.000_001)
        XCTAssertEqual(reversed, expected, accuracy: 0.000_001)
    }

    func testScoreCapsAtOneHundredAndRejectsInvalidHalfLife() {
        XCTAssertEqual(ScoreEngine.score(events: [event(id: "a", at: epoch, points: 200)], at: epoch, halfLife: 300), 100)
        XCTAssertEqual(ScoreEngine.score(events: [event(id: "a", at: epoch, points: 20)], at: epoch, halfLife: 0), 0)
    }

    func testScoreExcludesFutureAndNonfiniteEventsAndDecaysAfterCapping() {
        let now = epoch.addingTimeInterval(300)
        let current = event(id: "current", at: epoch, points: 200)
        let future = event(id: "future", at: now.addingTimeInterval(1), points: 100)
        let invalid = event(id: "invalid", at: epoch, points: .infinity)

        XCTAssertEqual(ScoreEngine.score(events: [current, future, invalid], at: now, halfLife: 300), 50, accuracy: 0.000_001)
    }

    func testEvaluateDoesNotDoubleCountOverlappingRulesOrNonfiniteWeight() {
        let profile = PersonalProfile(
            id: "profile",
            updatedAt: epoch,
            summary: "fixture",
            rules: [
                LanguageRule(phrase: "병신", weight: 40, reason: "short"),
                LanguageRule(phrase: "병신년", weight: 50, reason: "long"),
                LanguageRule(phrase: "문장", weight: .infinity, reason: "invalid")
            ]
        )
        let message = SessionMessage(id: "m", timestamp: epoch, source: "codex", text: "병신년 문장")

        let event = ScoreEngine.evaluate(message: message, profile: profile, deviceID: "mac")

        XCTAssertEqual(event?.points, 50)
        XCTAssertEqual(event?.reasons, ["long"])
    }

    func testAlertGateCrossingStartupSuppressionAndRearming() throws {
        var gate = AlertGate()
        XCTAssertFalse(gate.update(score: 100, allowAlert: false))
        XCTAssertFalse(gate.update(score: 99, allowAlert: true))
        XCTAssertFalse(gate.update(score: 100, allowAlert: true))
        XCTAssertFalse(gate.update(score: 51, allowAlert: true))
        XCTAssertFalse(gate.update(score: 50, allowAlert: true))
        XCTAssertTrue(gate.update(score: 100, allowAlert: true))
        XCTAssertFalse(gate.update(score: 100, allowAlert: true))

        let restored = try JSONDecoder().decode(AlertGate.self, from: JSONEncoder().encode(gate))
        XCTAssertEqual(restored, gate)
    }

    func testEventAlertGateCatchesPeakAfterPollingDelayExactlyOnce() {
        let events = [
            event(id: "a", at: epoch, points: 60),
            event(id: "b", at: epoch, points: 40)
        ]
        var gate = AlertGate()

        XCTAssertLessThan(ScoreEngine.score(events: events, at: epoch.addingTimeInterval(3), halfLife: 300), 100)
        XCTAssertTrue(gate.update(events: events, newEventIDs: ["a", "b"], at: epoch.addingTimeInterval(3), halfLife: 300, allowAlert: true))
        XCTAssertFalse(gate.update(events: events, newEventIDs: ["a", "b"], at: epoch.addingTimeInterval(4), halfLife: 300, allowAlert: true))
    }

    func testEventAlertGateDoesNotRoundNinetyNineIntoAlert() {
        var gate = AlertGate()
        let events = [event(id: "a", at: epoch, points: 99)]
        XCTAssertFalse(gate.update(events: events, newEventIDs: ["a"], at: epoch.addingTimeInterval(3), halfLife: 300, allowAlert: true))
    }

    func testEventAlertGateRearmsFromCooldownBeforeNewEvent() {
        var gate = AlertGate()
        let first = event(id: "a", at: epoch, points: 100)
        XCTAssertTrue(gate.update(events: [first], newEventIDs: ["a"], at: epoch, halfLife: 300, allowAlert: true))

        let second = event(id: "b", at: epoch.addingTimeInterval(300), points: 100)
        XCTAssertTrue(gate.update(events: [first, second], newEventIDs: ["b"], at: second.timestamp, halfLife: 300, allowAlert: true))
    }

    func testEventAlertGateIsDeterministicForSameTimestampAndSuppressesDelayedDuplicate() {
        let a = event(id: "a", at: epoch, points: 40)
        let b = event(id: "b", at: epoch, points: 60)
        var forward = AlertGate()
        var reverse = AlertGate()

        XCTAssertEqual(
            forward.update(events: [a, b], newEventIDs: ["a", "b"], at: epoch, halfLife: 300, allowAlert: true),
            reverse.update(events: [b, a], newEventIDs: ["b", "a"], at: epoch, halfLife: 300, allowAlert: true)
        )

        var delayed = AlertGate()
        XCTAssertFalse(delayed.update(events: [a, b], newEventIDs: ["a", "b"], at: epoch.addingTimeInterval(61), halfLife: 300, allowAlert: true))
        XCTAssertFalse(delayed.update(events: [a, b], newEventIDs: ["a", "b"], at: epoch.addingTimeInterval(62), halfLife: 300, allowAlert: true))
    }

    func testEventAlertGateSuppressesHistoricalStartupPeak() {
        var gate = AlertGate()
        let hot = event(id: "hot", at: epoch, points: 100)
        XCTAssertFalse(gate.update(events: [hot], newEventIDs: ["hot"], at: epoch, halfLife: 300, allowAlert: false))
        XCTAssertFalse(gate.update(events: [hot], newEventIDs: [], at: epoch.addingTimeInterval(1), halfLife: 300, allowAlert: true))
    }

    func testEventAlertGateOnlyNotifiesOnOwningDeviceButStillDisarmsForPeerPeak() {
        var gate = AlertGate()
        let peer = event(id: "peer", at: epoch, points: 100, device: "mac-b")
        XCTAssertFalse(gate.update(
            events: [peer], newEventIDs: ["peer"], at: epoch, halfLife: 300,
            allowAlert: true, notificationDeviceID: "mac-a"
        ))

        let local = event(id: "local", at: epoch.addingTimeInterval(1), points: 100, device: "mac-a")
        XCTAssertFalse(gate.update(
            events: [peer, local], newEventIDs: ["local"], at: local.timestamp, halfLife: 300,
            allowAlert: true, notificationDeviceID: "mac-a"
        ))
    }

    private func event(id: String, at date: Date, points: Double, device: String = "mac") -> ScoredEvent {
        ScoredEvent(id: id, timestamp: date, deviceID: device, source: "codex", points: points, reasons: [], profileID: "profile")
    }
}
