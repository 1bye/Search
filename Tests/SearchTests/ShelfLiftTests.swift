import XCTest
@testable import Search

final class ShelfLiftTests: XCTestCase {
    private func contacts(_ count: Int, x: CGFloat = 0) -> [AnyHashable: CGPoint] {
        Dictionary(uniqueKeysWithValues: (1...count).map {
            (AnyHashable($0), CGPoint(x: x + CGFloat($0) * 20, y: 50))
        })
    }

    func testOpeningSwipeCanLiftEveryFingerWithoutSelecting() {
        for count in [3, 4] {
            var lift = ShelfLiftDetector()
            XCTAssertFalse(lift.update(contacts(count)))
            for remaining in (1..<count).reversed() {
                XCTAssertFalse(lift.update(contacts(remaining), ended: [AnyHashable(remaining + 1)]))
            }
            XCTAssertFalse(lift.update([:], ended: [1]))
        }
    }

    func testMovingThenLiftingTheSameFingerSelectsOnce() {
        var lift = ShelfLiftDetector()
        XCTAssertFalse(lift.update(contacts(1)))
        XCTAssertFalse(lift.update(contacts(1, x: 2)))
        XCTAssertFalse(lift.update(contacts(1, x: 2)))
        XCTAssertFalse(lift.update(contacts(1, x: 2), ended: [9]))
        XCTAssertTrue(lift.update([:], ended: [1]))
        XCTAssertFalse(lift.update([:], ended: [1]))
    }

    func testTappingOrTinyJitterDoesNotSelect() {
        var lift = ShelfLiftDetector()
        XCTAssertFalse(lift.update(contacts(1)))
        XCTAssertFalse(lift.update([:], ended: [1]))
        XCTAssertFalse(lift.update(contacts(1)))
        XCTAssertFalse(lift.update(contacts(1, x: 0.2)))
        XCTAssertFalse(lift.update(contacts(1, x: -0.2)))
        XCTAssertFalse(lift.update([:], ended: [1]))
    }

    func testSecondFingerDisarmsSelectionAndOneFingerCanResume() {
        var lift = ShelfLiftDetector()
        XCTAssertFalse(lift.update(contacts(1)))
        XCTAssertFalse(lift.update(contacts(1, x: 5)))
        XCTAssertFalse(lift.update(contacts(2, x: 5)))
        XCTAssertFalse(lift.update(contacts(2, x: 30)))
        XCTAssertFalse(lift.update(contacts(1, x: 30), ended: [2]))
        XCTAssertFalse(lift.update([:], ended: [1]))
        XCTAssertFalse(lift.update(contacts(2)))
        XCTAssertFalse(lift.update(contacts(1), ended: [2]))
        XCTAssertFalse(lift.update(contacts(1, x: 2)))
        XCTAssertTrue(lift.update([:], ended: [1]))
    }

    func testRestingIsNotLiftingAndRestingThumbDoesNotBlockSelection() {
        var lift = ShelfLiftDetector()
        XCTAssertFalse(lift.update(contacts(2), resting: [2]))
        XCTAssertFalse(lift.update(contacts(2, x: 5), resting: [2]))
        XCTAssertFalse(lift.update(contacts(2, x: 5), resting: [1, 2]))
        XCTAssertFalse(lift.update(contacts(2, x: 5), resting: [1, 2]))
        let thumb: [AnyHashable: CGPoint] = [2: CGPoint(x: 45, y: 50)]
        XCTAssertTrue(lift.update(thumb, resting: [2], ended: [1]))
    }

    func testCancellationMissingTouchesAndResetNeverSelect() {
        var lift = ShelfLiftDetector()
        XCTAssertFalse(lift.update(contacts(1)))
        XCTAssertFalse(lift.update(contacts(1, x: 5)))
        XCTAssertFalse(lift.update([:], ended: [1], cancelled: true))
        XCTAssertFalse(lift.update(contacts(1)))
        XCTAssertFalse(lift.update(contacts(1, x: 5)))
        XCTAssertFalse(lift.update([:]))
        XCTAssertFalse(lift.update([:], ended: [1]))
        XCTAssertFalse(lift.update(contacts(1)))
        XCTAssertFalse(lift.update(contacts(1, x: 5)))
        lift.reset()
        XCTAssertFalse(lift.update([:], ended: [1]))
    }

    func testAReplacementFingerCannotInheritSelection() {
        var lift = ShelfLiftDetector()
        XCTAssertFalse(lift.update(contacts(1)))
        XCTAssertFalse(lift.update(contacts(1, x: 5)))
        XCTAssertFalse(lift.update([2: CGPoint(x: 40, y: 50)], ended: [1]))
        XCTAssertFalse(lift.update([:], ended: [2]))
    }
}
