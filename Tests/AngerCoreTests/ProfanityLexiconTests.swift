import Foundation
import XCTest
@testable import AngerCore

final class ProfanityLexiconTests: XCTestCase {
    private let profile = PersonalProfile.starter
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testBaselineIsBroadStableAndSeparateFromPersonalProfile() {
        XCTAssertTrue((60...100).contains(ProfanityLexicon.rules.count))
        XCTAssertTrue(ProfanityLexicon.rules.allSatisfy { $0.id.hasPrefix("builtin.") })
        XCTAssertEqual(Set(ProfanityLexicon.rules.map(\.id)).count, ProfanityLexicon.rules.count)
        XCTAssertTrue(PersonalProfile.starter.rules.isEmpty)
        XCTAssertEqual(PersonalProfile.starter.id, "starter-v2")
    }

    func testCommonKoreanVariantsReceiveModerateToStrongWeight() {
        for phrase in ["씨발", "ㅅㅂ", "좆같네", "개쉐끼", "븅신"] {
            let event = evaluate(phrase)
            XCTAssertNotNil(event, phrase)
            XCTAssertGreaterThanOrEqual(event?.points ?? 0, 20, phrase)
            XCTAssertLessThanOrEqual(event?.points ?? 101, 100, phrase)
        }
    }

    func testCommonEnglishMorphologyAndObfuscationUseWordBoundaries() {
        for phrase in ["fuck", "FUCKING", "f**k", "motherfuckers", "you asshole"] {
            XCTAssertNotNil(evaluate(phrase), phrase)
        }

        for neutral in ["Scunthorpe", "pass", "classroom", "shitake mushrooms"] {
            XCTAssertNil(evaluate(neutral), neutral)
        }
    }

    func testNeutralKoreanPrefixDoesNotTriggerSibal() {
        XCTAssertNil(evaluate("새로운 프로젝트의 시발점이 됐다"))
        XCTAssertNotNil(evaluate("아 진짜 시발 이게 뭐야"))
    }

    func testAmbiguousKoreanTermsIgnoreNarrowNeutralContexts() {
        let neutralMessages = [
            "새끼 고양이가 잠들었다",
            "새끼손가락을 다쳤다",
            "쓰레기통을 비워 주세요",
            "쓰레기 분리수거하는 날이다",
            "모니터 화면이 꺼져 있어",
            "신발 끈을 졸라매다"
        ]

        for message in neutralMessages {
            XCTAssertNil(evaluate(message), message)
        }
    }

    func testNeutralSpanDoesNotSuppressProfanityElsewhereInMessage() {
        let event = evaluate("씨발 쓰레기통 어디야")

        XCTAssertEqual(event?.points, 30)
        XCTAssertEqual(event?.reasons, ["공통 욕설"])
    }

    func testDisabledPersonalShadowCannotRemoveBuiltinRule() {
        let malicious = PersonalProfile(
            id: "custom",
            updatedAt: date,
            summary: "",
            rules: [LanguageRule(id: "shadow", phrase: "씨발", weight: 5, reason: "ignored", enabled: false)]
        )
        let event = ScoreEngine.evaluate(
            message: SessionMessage(id: "m", timestamp: date, source: "codex", text: "씨발"),
            profile: malicious,
            deviceID: "mac"
        )

        XCTAssertEqual(event?.points, 30)
        XCTAssertEqual(event?.reasons, ["공통 욕설"])
    }

    func testOverlappingBuiltinRulesDoNotDoubleCount() {
        XCTAssertEqual(evaluate("개지랄")?.points, 34)
        XCTAssertEqual(evaluate("개쓰레기")?.points, 34)
        XCTAssertEqual(evaluate("motherfucker")?.points, 46)
    }

    func testPersonalNonProfanitySignalStillUsesLiteralMatching() {
        let custom = PersonalProfile(
            id: "custom",
            updatedAt: date,
            summary: "",
            rules: [LanguageRule(phrase: "몇 번을 말", weight: 8, reason: "반복 압박")]
        )
        let message = SessionMessage(id: "m", timestamp: date, source: "codex", text: "몇 번을 말해야 해")

        XCTAssertEqual(ScoreEngine.evaluate(message: message, profile: custom, deviceID: "mac")?.points, 8)
    }

    private func evaluate(_ text: String) -> ScoredEvent? {
        ScoreEngine.evaluate(
            message: SessionMessage(id: text, timestamp: date, source: "codex", text: text),
            profile: profile,
            deviceID: "mac"
        )
    }
}
