import XCTest
@testable import Search

final class GestureShelfTests: XCTestCase {
    func testEveryFastDeltaAppliesAndBreaksAwayFromAttraction() {
        let target = CGRect(x: 0, y: 0, width: 180, height: 140)
        var pointer = MagneticPointer(point: CGPoint(x: 90, y: 70))
        pointer.move(dx: 0, dy: 0, at: -0.008, gain: 4)
        for tick in 0..<10 {
            pointer.move(dx: 2, dy: 0, at: Double(tick) * 0.008, gain: 4)
            pointer.attract(to: target, at: Double(tick) * 0.008, dt: 0.008, strength: 1)
        }
        XCTAssertEqual(pointer.point.x, 170, accuracy: 0.001)
        pointer.attract(to: target, at: 1, dt: 0.03, strength: 1)
        let before = pointer.point.x
        pointer.move(dx: -4, dy: 0, at: 1.001, gain: 4)
        XCTAssertEqual(pointer.point.x, before - 16, accuracy: 0.001)
    }

    func testPauseSettlesButZeroAttractionStaysFree() {
        let target = CGRect(x: 0, y: 0, width: 180, height: 140)
        var assisted = MagneticPointer(point: CGPoint(x: 140, y: 90))
        var free = assisted
        for tick in 0..<90 {
            assisted.attract(to: target, at: Double(tick) / 60, dt: 1 / 60, strength: 0.35)
            free.attract(to: target, at: Double(tick) / 60, dt: 1 / 60, strength: 0)
        }
        XCTAssertEqual(assisted.point.x, 90, accuracy: 0.2)
        XCTAssertEqual(assisted.point.y, 70, accuracy: 0.2)
        XCTAssertEqual(free.point, CGPoint(x: 140, y: 90))
    }

    func testNearestUsesVisibleCardsAndKeepsBoundaryStable() {
        let layout = ShelfLayout(count: 24, size: CGSize(width: 912, height: 320))
        let first = layout.frame(0, scroll: 0), second = layout.frame(1, scroll: 0)
        let boundary = (first.midX + second.midX) / 2
        XCTAssertEqual(layout.nearest(to: CGPoint(x: boundary + 0.1, y: first.midY), scroll: 0, keeping: 0), 0)
        XCTAssertEqual(layout.nearest(to: CGPoint(x: second.midX, y: second.midY), scroll: 0, keeping: 0), 1)
        let last = layout.frame(23, scroll: layout.maxScroll)
        XCTAssertEqual(layout.nearest(to: CGPoint(x: last.midX, y: last.midY), scroll: layout.maxScroll, keeping: 0), 23)
        XCTAssertGreaterThanOrEqual(last.minY, 0)
        XCTAssertLessThanOrEqual(last.maxY, layout.size.height)
    }

    @MainActor
    func testShelfKeepsAllTabsInOrderAndNavigatesPastSecondRow() {
        let ids = (0..<24).map { _ in UUID() }
        let switcher = TabSwitcher()
        switcher.openShelf(row: ids + [ids[0]], current: ids[0])
        XCTAssertEqual(switcher.candidates, ids)
        XCTAssertTrue(switcher.gesture)
        for _ in 0..<4 { switcher.move(.down) }
        XCTAssertEqual(switcher.selectedID, ids[20])
        switcher.move(.right)
        XCTAssertEqual(switcher.finish(), ids[21])
        XCTAssertFalse(switcher.visible)
        XCTAssertFalse(switcher.gesture)
        XCTAssertFalse(switcher.gesturePointer.captured)
        switcher.step(row: ids, current: ids[0], backwards: false)
        XCTAssertEqual(switcher.candidates.count, 10)
        XCTAssertFalse(switcher.gesture)
        switcher.cancel()
    }
}
