import XCTest
@testable import Search

final class ShelfTapTests: XCTestCase {
    private let pair: [AnyHashable: CGPoint] = [1: CGPoint(x: 20, y: 50), 2: CGPoint(x: 40, y: 50)]

    func testQuickTapClosesOnceAfterBothFingersLift() {
        var tap = ShelfTapDetector()
        XCTAssertFalse(tap.update(pair, at: 0, began: [1, 2]))
        XCTAssertFalse(tap.update([2: pair[2]!], at: 0.1, ended: [1]))
        XCTAssertTrue(tap.update([:], at: 0.15, ended: [2]))
        XCTAssertFalse(tap.update([:], at: 0.16, ended: [1, 2]))
        XCTAssertFalse(tap.update(pair, at: 0.2, began: [1, 2]))
        XCTAssertTrue(tap.update([:], at: 0.3, ended: [1, 2]))
    }

    func testAddingSecondFingerToPointingFingerClosesWithoutSelecting() {
        var tap = ShelfTapDetector()
        var lift = ShelfLiftDetector()
        let first: [AnyHashable: CGPoint] = [1: CGPoint(x: 5, y: 50)]
        XCTAssertFalse(tap.update(first, at: 0, began: [1]))
        XCTAssertFalse(lift.update(first, began: [1]))
        XCTAssertFalse(lift.update([1: pair[1]!]))
        XCTAssertFalse(tap.update(pair, at: 2, began: [2]))
        XCTAssertFalse(lift.update(pair, began: [2]))
        XCTAssertTrue(tap.update([:], at: 2.1, ended: [1, 2]))
        XCTAssertFalse(lift.update([:], ended: [1, 2]))
    }

    func testOpeningSwipeLeftoversAndThirdFingerNeverClose() {
        for count in [3, 4] {
            var tap = ShelfTapDetector()
            let contacts = Dictionary(uniqueKeysWithValues: (1...count).map {
                (AnyHashable($0), CGPoint(x: CGFloat($0) * 20, y: 50))
            })
            XCTAssertFalse(tap.update(contacts, at: 0, began: Set(contacts.keys)))
            XCTAssertFalse(tap.update(pair, at: 0.05, ended: Set(contacts.keys).subtracting([1, 2])))
            XCTAssertFalse(tap.update([:], at: 0.1, ended: [1, 2]))
            XCTAssertFalse(tap.update(pair, at: 0.2, began: [1, 2]))
            XCTAssertTrue(tap.update([:], at: 0.3, ended: [1, 2]))
        }
        var tap = ShelfTapDetector()
        XCTAssertFalse(tap.update(pair, at: 0))
        XCTAssertFalse(tap.update([:], at: 0.1, ended: [1, 2]))
    }

    func testScrollMovementLongHoldAndFinalMovementDoNotClose() {
        for rejection in 0..<4 {
            var tap = ShelfTapDetector()
            XCTAssertFalse(tap.update(pair, at: 0, began: [1, 2]))
            if rejection == 0 { tap.disqualify() }
            if rejection == 1 {
                let moved = pair.mapValues { CGPoint(x: $0.x, y: $0.y + 5) }
                XCTAssertFalse(tap.update(moved, at: 0.1))
                XCTAssertFalse(tap.update(pair, at: 0.15))
            }
            let finals: [AnyHashable: CGPoint] = rejection == 3 ? [1: CGPoint(x: 25, y: 50)] : [:]
            XCTAssertFalse(tap.update([:], at: rejection == 2 ? 0.5 : 0.2,
                                      ended: [1, 2], finalPositions: finals))
            XCTAssertFalse(tap.update(pair, at: 1, began: [1, 2]))
            XCTAssertTrue(tap.update([:], at: 1.1, ended: [1, 2]))
        }
    }

    func testRestingThumbIsIgnoredButRestingTapFingerIsNotALift() {
        var tap = ShelfTapDetector()
        let thumb: [AnyHashable: CGPoint] = [9: CGPoint(x: 80, y: 10)]
        let withThumb = pair.merging(thumb) { first, _ in first }
        XCTAssertFalse(tap.update(withThumb, at: 0, resting: [9], began: [1, 2]))
        XCTAssertTrue(tap.update(thumb, at: 0.1, resting: [9], ended: [1, 2]))
        XCTAssertFalse(tap.update(pair, at: 1, began: [1, 2]))
        XCTAssertFalse(tap.update(pair, at: 1.05, resting: [1, 2]))
        XCTAssertFalse(tap.update([:], at: 1.1, ended: [1, 2]))
    }

    func testCancellationMissingEndsReplacementAndResetNeverClose() {
        for rejection in 0..<4 {
            var tap = ShelfTapDetector()
            XCTAssertFalse(tap.update(pair, at: 0, began: [1, 2]))
            switch rejection {
            case 0: XCTAssertFalse(tap.update(pair, at: 0.05, cancelled: true))
            case 1: XCTAssertFalse(tap.update([:], at: 0.05))
            case 2:
                XCTAssertFalse(tap.update([1: pair[1]!, 3: pair[2]!], at: 0.05, began: [3], ended: [2]))
            default: tap.reset()
            }
            XCTAssertFalse(tap.update([:], at: 0.1, ended: [1, 2, 3]))
        }
    }
}
