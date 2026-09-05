import XCTest
@testable import AngerCore

final class FlameMotionTests: XCTestCase {
    func testApprovedBandsAndCadence() {
        for (score, expected) in [(0.0, 0), (32, 0), (33, 1), (65, 1), (66, 2), (100, 2)] {
            XCTAssertEqual(FlameMotion.level(score), expected)
        }
        XCTAssertEqual(FlameMotion.frequency(0), 0.42, accuracy: 0.0001)
        XCTAssertEqual(FlameMotion.frequency(33), 0.8, accuracy: 0.0001)
        XCTAssertEqual(FlameMotion.frequency(66), 1.4, accuracy: 0.0001)
        XCTAssertEqual(FlameMotion.frequency(100), 3.2, accuracy: 0.0001)
        for score in 1...100 {
            XCTAssertGreaterThan(FlameMotion.frequency(Double(score)), FlameMotion.frequency(Double(score - 1)))
        }
        XCTAssertEqual(FlameMotion.frequency(-10), FlameMotion.frequency(0))
        XCTAssertEqual(FlameMotion.frequency(110), FlameMotion.frequency(100))
    }
}
