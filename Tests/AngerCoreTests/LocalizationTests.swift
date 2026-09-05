import XCTest
@testable import AngerCore

final class LocalizationTests: XCTestCase {
    func testExplicitLanguageOverridesResolvePredictably() {
        XCTAssertEqual(AppLanguage.korean.resolved, .korean)
        XCTAssertEqual(AppLanguage.english.resolved, .english)
        XCTAssertEqual(AppText(.korean)("한국어", "English"), "한국어")
        XCTAssertEqual(AppText(.english)("한국어", "English"), "English")
    }

    func testBuiltInReasonsLocalizeInBothDirections() {
        XCTAssertEqual(AppText(.english).reason("직접적인 모욕"), "Direct insult")
        XCTAssertEqual(AppText(.korean).reason("Direct insult"), "직접적인 모욕")
    }

    func testCalibrationErrorsHaveEnglishDescriptions() {
        XCTAssertEqual(
            CalibrationError.unsupportedCLI("Codex").description(language: .english),
            "The installed Codex CLI does not support the safe one-time analysis options. Update the CLI and try again."
        )
        XCTAssertEqual(
            CalibrationError.invalidResponse("빈 응답").description(language: .english),
            "The analysis response was invalid: Empty response."
        )
    }
}
