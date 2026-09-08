import XCTest
import AppKit
import QuartzCore
@testable import AngerRate

final class MenuFlameAnimatorTests: XCTestCase {
    func testCompositorOnlyAdvancesWhenEnabled() async {
        await MainActor.run {
            var time = 10.0
            let animator = MenuFlameAnimator(now: { time })
            XCTAssertFalse(animator.isAnimating)
            animator.running = true
            XCTAssertTrue(animator.isAnimating)
            time += 0.5
            XCTAssertEqual(animator.currentPhase, 0.21, accuracy: 0.0001)
            animator.reduceMotion = true
            XCTAssertEqual(animator.layer.mask?.speed, 0)
            let pausedPhase = animator.currentPhase
            time += 30
            XCTAssertEqual(animator.currentPhase, pausedPhase)
            animator.reduceMotion = false
            time += 0.5
            XCTAssertEqual(animator.currentPhase, 0.42, accuracy: 0.0001)
            animator.screenAwake = false
            time += 100
            XCTAssertEqual(animator.currentPhase, 0.42, accuracy: 0.0001)
            animator.running = false
            animator.screenAwake = true
            XCTAssertFalse(animator.isAnimating)
            time += 100
            XCTAssertEqual(animator.currentPhase, 0.42, accuracy: 0.0001)
        }
    }

    func testSpeedChangePreservesPhaseAndReusesCurrentScoreFrames() async {
        await MainActor.run {
            var time = 10.0
            let animator = MenuFlameAnimator(now: { time })
            animator.score = 33
            animator.running = true
            let original = animator.cachedFrames[0]
            time += 0.5
            XCTAssertEqual(animator.currentPhase, 0.4, accuracy: 0.0001)
            animator.score = 33.5
            XCTAssertEqual(animator.currentPhase, 0.4, accuracy: 0.0001)
            XCTAssertTrue(original === animator.cachedFrames[0])
            animator.score = 66
            XCTAssertEqual(animator.layer.mask?.timeOffset ?? -1, 0.4, accuracy: 0.0001)
            XCTAssertEqual(animator.layer.mask?.speed ?? -1, 1.4, accuracy: 0.0001)
            XCTAssertEqual(animator.currentPhase, 0.4, accuracy: 0.0001)
            time += 0.25
            XCTAssertEqual(animator.currentPhase, 0.75, accuracy: 0.0001)
        }
    }

    func testCachedFramesAndFallbackOnlyChangeAtVisualScoreBoundary() async {
        await MainActor.run {
            let animator = MenuFlameAnimator()
            var updates = 0
            animator.onImage = { image in
                updates += 1
                XCTAssertTrue(image.isTemplate)
                XCTAssertEqual(image.size, NSSize(width: 17, height: 21))
            }
            animator.score = 0.5
            XCTAssertEqual(updates, 0)
            animator.score = 32.99
            let lower = animator.cachedFrames[0]
            animator.score = 33
            XCTAssertFalse(lower === animator.cachedFrames[0])
            XCTAssertEqual(updates, 2)
            XCTAssertEqual(animator.cachedFrames.count, 24)
            for frame in animator.cachedFrames {
                XCTAssertEqual(frame.width, 34)
                XCTAssertEqual(frame.height, 42)
            }
            XCTAssertFalse(animator.isAnimating)
        }
    }

    func testAnimationIsARepeatingCachedContentsSequence() async {
        await MainActor.run {
            let animator = MenuFlameAnimator()
            animator.running = true
            let animation = animator.contentsAnimation
            XCTAssertEqual(animation?.keyPath, "contents")
            XCTAssertEqual(animation?.values?.count, 25)
            XCTAssertEqual(animation?.calculationMode, .discrete)
            XCTAssertEqual(animation?.repeatCount, .infinity)
            XCTAssertEqual(animation?.duration, 1)
            XCTAssertEqual(animation?.keyTimes?.first, 0)
            XCTAssertEqual(animation?.keyTimes?.last, 1)
        }
    }

    func testCompositorDoesNotRetainOwner() async {
        await MainActor.run {
            weak var released: MenuFlameAnimator?
            autoreleasepool {
                let animator = MenuFlameAnimator()
                animator.running = true
                released = animator
            }
            XCTAssertNil(released)
        }
    }
}
