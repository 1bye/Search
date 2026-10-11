import AppKit
import XCTest
@testable import Search

@MainActor
final class PageTransitionTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "page-transition-\(getpid())", 1)
        super.setUp()
    }

    private func project(_ point: CGPoint, through t: CATransform3D) -> CGPoint {
        let w = point.x * t.m14 + point.y * t.m24 + t.m44
        return CGPoint(x: (point.x * t.m11 + point.y * t.m21 + t.m41) / w,
                       y: (point.x * t.m12 + point.y * t.m22 + t.m42) / w)
    }

    func testCubeFacesMeetAndFinishAtFullSizeInBothDirections() {
        let size = CGSize(width: 1000, height: 600)
        for direction: CGFloat in [-1, 1] {
            for p: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                let old = PageCube.transform(progress: p, incoming: false, direction: direction, size: size)
                let new = PageCube.transform(progress: p, incoming: true, direction: direction, size: size)
                for y: CGFloat in [-300, 300] {
                    let a = project(CGPoint(x: direction * 500, y: y), through: old)
                    let b = project(CGPoint(x: -direction * 500, y: y), through: new)
                    XCTAssertEqual(a.x, b.x, accuracy: 0.001)
                    XCTAssertEqual(a.y, b.y, accuracy: 0.001)
                    XCTAssertLessThanOrEqual(abs(a.y), 300.001)
                }
            }
            for incoming in [false, true] {
                for anchor in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5)] {
                    let t = PageCube.transform(progress: incoming ? 1 : 0, incoming: incoming,
                                               direction: direction, size: size, anchor: anchor)
                    let point = CGPoint(x: 123, y: 234)
                    let result = project(point, through: t)
                    XCTAssertEqual(point.x, result.x, accuracy: 0.001)
                    XCTAssertEqual(point.y, result.y, accuracy: 0.001)
                }
            }
        }
    }

    func testRapidSwitchAndResizeRemoveOldFacesAndAnimations() throws {
        guard !Motion.reduced else { throw XCTSkip("Reduce Motion disables cube transitions") }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let stage = StageView(frame: window.contentView!.bounds)
        window.contentView = stage
        let a = NSView(), b = NSView(), c = NSView()
        let first = UUID(), second = UUID(), third = UUID()
        stage.show(a, transition: .cube, selection: first)
        stage.show(b, transition: .cube, selection: second)
        XCTAssertTrue(a.superview === stage)
        XCTAssertNotNil(b.layer?.animation(forKey: "pageCube"))
        stage.show(c, transition: .cube, selection: third)
        XCTAssertNil(a.superview)
        XCTAssertNil(a.layer?.animation(forKey: "pageCube"))
        XCTAssertTrue(b.superview === stage)
        XCTAssertTrue(c.superview === stage)
        stage.frame.size.width = 700
        stage.needsLayout = true
        stage.layoutSubtreeIfNeeded()
        XCTAssertNil(b.superview)
        XCTAssertNil(c.layer?.animation(forKey: "pageCube"))
        XCTAssertFalse(c.layer?.sublayers?.contains { $0.animation(forKey: "shade") != nil } ?? false)
        XCTAssertEqual(c.frame, stage.bounds)
        stage.show(a, transition: .none, selection: first)
        XCTAssertNil(c.superview)
        XCTAssertNil(a.layer?.animation(forKey: "pageCube"))
        window.contentView = nil
    }

    func testCubeFinishesAndSameTabNeverAnimates() async throws {
        guard !Motion.reduced else { throw XCTSkip("Reduce Motion disables cube transitions") }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let stage = StageView(frame: window.contentView!.bounds)
        window.contentView = stage
        let a = NSView(), b = NSView()
        let first = UUID(), second = UUID()
        stage.show(a, transition: .cube, selection: first)
        stage.show(b, transition: .cube, selection: second)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(a.superview)
        XCTAssertTrue(b.superview === stage)
        XCTAssertNil(b.layer?.animation(forKey: "pageCube"))
        XCTAssertFalse(b.layer?.sublayers?.contains { $0.animation(forKey: "shade") != nil } ?? false)
        stage.show(a, transition: .cube, selection: second)
        XCTAssertNil(b.superview)
        XCTAssertNil(a.layer?.animation(forKey: "pageCube"))
        window.contentView = nil
    }

    func testTransitionChoicePersists() {
        let prefs = Preferences()
        let original = prefs.pageTransition
        defer { prefs.pageTransition = original }
        prefs.pageTransition = .cube
        XCTAssertEqual(Preferences().pageTransition, .cube)
        prefs.pageTransition = .none
        XCTAssertEqual(Preferences().pageTransition, .none)
    }
}
