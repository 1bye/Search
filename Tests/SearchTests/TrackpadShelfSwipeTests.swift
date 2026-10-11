import XCTest
@testable import Search

final class TrackpadShelfSwipeTests: XCTestCase {
    private func contacts(_ count: Int, dx: CGFloat = 0, dy: CGFloat = 0) -> [AnyHashable: CGPoint] {
        Dictionary(uniqueKeysWithValues: (0..<count).map {
            (AnyHashable($0), CGPoint(x: 30 + CGFloat($0) * 15 + dx, y: 50 + dy))
        })
    }

    func testThreeFingerDownFiresOnceUntilEveryFingerLifts() {
        var swipe = ShelfSwipeDetector()
        XCTAssertFalse(swipe.update(contacts(3), fingers: 3))
        XCTAssertFalse(swipe.update(contacts(3, dy: -3), fingers: 3))
        XCTAssertTrue(swipe.update(contacts(3, dy: -9), fingers: 3))
        XCTAssertFalse(swipe.update(contacts(3, dy: -20), fingers: 3))
        XCTAssertFalse(swipe.update(contacts(2, dy: -20), fingers: 3))
        XCTAssertFalse(swipe.update(contacts(3, dy: -30), fingers: 3))
        XCTAssertFalse(swipe.update([:], fingers: 3))
        XCTAssertFalse(swipe.update(contacts(3), fingers: 3))
        XCTAssertTrue(swipe.update(contacts(3, dy: -9), fingers: 3))
    }

    func testTwoFingerScrollingNeverFires() {
        var swipe = ShelfSwipeDetector()
        XCTAssertFalse(swipe.update(contacts(2), fingers: 3))
        XCTAssertFalse(swipe.update(contacts(2, dy: -60), fingers: 3))
    }

    func testFourFingerChoiceWaitsForAllFourFingers() {
        var swipe = ShelfSwipeDetector()
        XCTAssertFalse(swipe.update(contacts(3), fingers: 4))
        XCTAssertFalse(swipe.update(contacts(3, dy: -20), fingers: 4))
        XCTAssertFalse(swipe.update(contacts(4, dy: -20), fingers: 4))
        XCTAssertTrue(swipe.update(contacts(4, dy: -30), fingers: 4))
    }

    func testExtraOrReplacedFingerCannotShiftTheCenterAndTrigger() {
        var swipe = ShelfSwipeDetector()
        XCTAssertFalse(swipe.update(contacts(3), fingers: 3))
        XCTAssertFalse(swipe.update(contacts(4, dy: -15), fingers: 3))
        XCTAssertFalse(swipe.update(contacts(3, dy: -30), fingers: 3))
        swipe.reset()
        XCTAssertFalse(swipe.update(contacts(3), fingers: 3))
        var replacement = contacts(3, dy: -30)
        replacement[0] = nil
        replacement[10] = CGPoint(x: 90, y: 20)
        XCTAssertFalse(swipe.update(replacement, fingers: 3))
        XCTAssertFalse(swipe.update(contacts(3, dy: -40), fingers: 3))
    }

    func testHorizontalUpwardAndPinchingAreNotDownwardSwipes() {
        var swipe = ShelfSwipeDetector()
        XCTAssertFalse(swipe.update(contacts(3), fingers: 3))
        XCTAssertFalse(swipe.update(contacts(3, dx: 30, dy: -10), fingers: 3))
        swipe.reset()
        XCTAssertFalse(swipe.update(contacts(3), fingers: 3))
        XCTAssertFalse(swipe.update(contacts(3, dy: 30), fingers: 3))
        swipe.reset()
        XCTAssertFalse(swipe.update(contacts(3), fingers: 3))
        var pinch = contacts(3, dy: -25)
        pinch[0] = CGPoint(x: 30, y: 65)
        XCTAssertFalse(swipe.update(pinch, fingers: 3))
    }

    func testCancelledSequenceCanStartFresh() {
        var swipe = ShelfSwipeDetector()
        XCTAssertFalse(swipe.update(contacts(3), fingers: 3))
        swipe.reset()
        XCTAssertFalse(swipe.update(contacts(3, dy: -25), fingers: 3))
        XCTAssertTrue(swipe.update(contacts(3, dy: -35), fingers: 3))
    }
}
