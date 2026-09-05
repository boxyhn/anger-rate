import XCTest
@testable import AngerCore

final class TemperatureDisplayTests: XCTestCase {
    func testScoreEndpointsMapToBaselineAndBoilingPoint() {
        XCTAssertEqual(TemperatureDisplay.value(score: 0, unit: .celsius), 36.5, accuracy: 0.0001)
        XCTAssertEqual(TemperatureDisplay.value(score: 100, unit: .celsius), 100, accuracy: 0.0001)
        XCTAssertEqual(TemperatureDisplay.value(score: 0, unit: .fahrenheit), 97.7, accuracy: 0.0001)
        XCTAssertEqual(TemperatureDisplay.value(score: 100, unit: .fahrenheit), 212, accuracy: 0.0001)
    }

    func testMappingIsLinearAndClampsInvalidScores() {
        XCTAssertEqual(TemperatureDisplay.value(score: 50, unit: .celsius), 68.25, accuracy: 0.0001)
        XCTAssertEqual(TemperatureDisplay.value(score: -20, unit: .celsius), 36.5, accuracy: 0.0001)
        XCTAssertEqual(TemperatureDisplay.value(score: 140, unit: .celsius), 100, accuracy: 0.0001)
        XCTAssertEqual(TemperatureDisplay.value(score: .nan, unit: .celsius), 36.5, accuracy: 0.0001)
    }

    func testFormattingUsesOneDecimalOnlyWhenNeeded() {
        XCTAssertEqual(TemperatureDisplay.formatted(score: 0, unit: .celsius), "36.5°C")
        XCTAssertEqual(TemperatureDisplay.formatted(score: 100, unit: .celsius), "100°C")
        XCTAssertEqual(TemperatureDisplay.formatted(score: 0, unit: .fahrenheit), "97.7°F")
        XCTAssertEqual(TemperatureDisplay.formatted(score: 100, unit: .fahrenheit), "212°F")
        XCTAssertEqual(TemperatureDisplay.formatted(score: 99.99, unit: .celsius), "99.9°C")
        XCTAssertEqual(TemperatureDisplay.formatted(score: 99.99, unit: .fahrenheit), "211.9°F")
        XCTAssertEqual(TemperatureDisplay.formattedRise(points: 20, unit: .celsius), "+12.7°C")
        XCTAssertEqual(TemperatureDisplay.formattedRise(points: 20, unit: .fahrenheit), "+22.9°F")
    }
}
