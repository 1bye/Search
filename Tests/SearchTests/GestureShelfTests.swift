import AppKit
import XCTest
@testable import Search

final class GestureShelfTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "gesture-shelf-\(getpid())", 1)
        super.setUp()
    }

    func testNewTabTargetStaysReachableBesideScrolledCards() {
        for count in [1, 24] {
            let layout = ShelfLayout(count: count, size: CGSize(width: count == 1 ? 232 : 968, height: 320))
            let target = layout.newTabFrame
            XCTAssertTrue(CGRect(origin: .zero, size: layout.size).contains(target))
            XCTAssertGreaterThan(target.minX, layout.tabsWidth)
            XCTAssertTrue(layout.targetsNewTab(at: CGPoint(x: target.midX, y: target.midY), keeping: false))
            let boundary = CGPoint(x: target.minX - 8, y: target.midY)
            XCTAssertFalse(layout.targetsNewTab(at: boundary, keeping: false))
            XCTAssertTrue(layout.targetsNewTab(at: boundary, keeping: true))
            for scroll in [CGFloat.zero, layout.maxScroll] {
                for index in 0..<count {
                    let card = layout.frame(index, scroll: scroll)
                    XCTAssertFalse(card.intersects(target))
                    XCTAssertFalse(layout.targetsNewTab(at: CGPoint(x: card.midX, y: card.midY), keeping: true))
                }
            }
        }
    }

    @MainActor
    func testNewTabTargetCanReturnToTheSameTabAndCancel() {
        let ids = (0..<7).map { _ in UUID() }
        let switcher = TabSwitcher()
        switcher.openShelf(row: ids, current: ids[4])
        switcher.move(.right)
        XCTAssertTrue(switcher.newTabSelected)
        switcher.move(.left)
        XCTAssertFalse(switcher.newTabSelected)
        XCTAssertEqual(switcher.selectedID, ids[4])
        switcher.pickNewTab()
        switcher.pick(ids[4])
        XCTAssertFalse(switcher.newTabSelected)
        switcher.pick(ids[6])
        switcher.move(.right)
        XCTAssertTrue(switcher.newTabSelected)
        switcher.cancel()
        XCTAssertFalse(switcher.newTabSelected)
        switcher.step(row: ids, current: ids[0], backwards: false)
        switcher.pickNewTab()
        XCTAssertFalse(switcher.newTabSelected)
        switcher.cancel()
    }

    @MainActor
    func testCommittingNewTabClosesShelfAndFocusesAnEmptyTab() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let existing = Tab(bench: true)
        browser.receive(existing)
        let count = browser.tabs.count
        let focus = browser.focusRequest
        browser.tabSwitcher.openShelf(row: [existing.id], current: existing.id)
        browser.tabSwitcher.pickNewTab()
        browser.commitTabSwitch()
        XCTAssertEqual(browser.tabs.count, count + 1)
        XCTAssertNotEqual(browser.activeID, existing.id)
        XCTAssertTrue(try XCTUnwrap(browser.active).isBlank)
        XCTAssertGreaterThan(browser.focusRequest, focus)
        XCTAssertFalse(browser.tabSwitcher.visible)
        XCTAssertFalse(browser.tabSwitcher.newTabSelected)
        XCTAssertFalse(browser.tabSwitcher.gesturePointer.captured)
    }

    @MainActor
    func testExplicitTabChoiceOverridesNewTabTarget() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let existing = Tab(bench: true)
        browser.receive(existing)
        let count = browser.tabs.count
        browser.tabSwitcher.openShelf(row: [existing.id], current: existing.id)
        browser.tabSwitcher.pickNewTab()
        browser.commitTabSwitch(picking: existing.id)
        XCTAssertEqual(browser.tabs.count, count)
        XCTAssertEqual(browser.activeID, existing.id)
        XCTAssertFalse(browser.tabSwitcher.visible)
        XCTAssertFalse(browser.tabSwitcher.newTabSelected)
    }

    @MainActor
    func testClosingHighlightedTabsKeepsShelfAndPicksNeighbours() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let tabs = (0..<3).map { _ in Tab(bench: true) }
        tabs.forEach { browser.receive($0) }
        browser.select(tabs[1])
        browser.tabSwitcher.openShelf(row: tabs.map(\.id), current: tabs[1].id)
        browser.closeShelfTab()
        XCTAssertEqual(browser.tabSwitcher.candidates, [tabs[0].id, tabs[2].id])
        XCTAssertEqual(browser.tabSwitcher.selectedID, tabs[2].id)
        XCTAssertTrue(browser.tabSwitcher.visible)
        XCTAssertTrue(browser.tabSwitcher.gesture)
        XCTAssertFalse(browser.tabs.contains { $0.id == tabs[1].id })
        browser.closeShelfTab()
        XCTAssertEqual(browser.tabSwitcher.candidates, [tabs[0].id])
        XCTAssertEqual(browser.tabSwitcher.selectedID, tabs[0].id)
        XCTAssertTrue(browser.tabSwitcher.visible)
        browser.tabSwitcher.cancel()
    }

    @MainActor
    func testClosingBackgroundTabDoesNotSwitchPageAndPlusDoesNothing() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let tabs = (0..<3).map { _ in Tab(bench: true) }
        tabs.forEach { browser.receive($0) }
        browser.select(tabs[0])
        browser.tabSwitcher.openShelf(row: tabs.map(\.id), current: tabs[0].id)
        browser.tabSwitcher.pick(tabs[1].id)
        browser.closeShelfTab()
        XCTAssertEqual(browser.activeID, tabs[0].id)
        XCTAssertEqual(browser.tabSwitcher.selectedID, tabs[2].id)
        let count = browser.tabs.count
        browser.tabSwitcher.pickNewTab()
        browser.closeShelfTab()
        XCTAssertEqual(browser.tabs.count, count)
        XCTAssertTrue(browser.tabSwitcher.newTabSelected)
        browser.tabSwitcher.cancel()
    }

    @MainActor
    func testClosingLastPageLeavesBlankCardAndClosingBlankDismisses() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let tab = Tab(bench: true)
        browser.receive(tab)
        tab.restore(url: URL(string: "about:blank")!, title: "Page")
        browser.tabSwitcher.openShelf(row: [tab.id], current: tab.id)
        browser.closeShelfTab()
        XCTAssertEqual(browser.tabs.count, 1)
        let blank = try XCTUnwrap(browser.active)
        XCTAssertTrue(blank.isBlank)
        XCTAssertNotEqual(blank.id, tab.id)
        XCTAssertEqual(browser.tabSwitcher.candidates, [blank.id])
        XCTAssertEqual(browser.tabSwitcher.selectedID, blank.id)
        XCTAssertTrue(browser.tabSwitcher.gesture)
        browser.closeShelfTab()
        XCTAssertFalse(browser.tabSwitcher.visible)
        XCTAssertFalse(browser.tabSwitcher.gesturePointer.captured)
    }

    @MainActor
    func testClosingPinnedPageKeepsPinAndShelfOnNextCard() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let pin = Tab(bench: true), other = Tab(bench: true)
        browser.receive(pin)
        browser.receive(other)
        browser.select(pin)
        pin.restore(url: URL(string: "about:blank")!, title: "Pinned")
        pin.pin = "P"
        browser.tabSwitcher.openShelf(row: [pin.id, other.id], current: pin.id)
        browser.closeShelfTab()
        XCTAssertTrue(browser.tabs.contains { $0 === pin })
        XCTAssertTrue(pin.asleep)
        XCTAssertEqual(browser.activeID, other.id)
        XCTAssertEqual(browser.tabSwitcher.selectedID, other.id)
        XCTAssertTrue(browser.tabSwitcher.visible)
        XCTAssertTrue(browser.tabSwitcher.gesture)
        pin.pin = nil
        browser.tabSwitcher.cancel()
    }

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
