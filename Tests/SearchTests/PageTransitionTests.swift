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
                let old = PageMotion.transform(progress: p, incoming: false, direction: direction, size: size)
                let new = PageMotion.transform(progress: p, incoming: true, direction: direction, size: size)
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
                    let t = PageMotion.transform(progress: incoming ? 1 : 0, incoming: incoming,
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
        XCTAssertNotNil(b.layer?.animation(forKey: "pageTransition"))
        stage.show(c, transition: .cube, selection: third)
        XCTAssertNil(a.superview)
        XCTAssertNil(a.layer?.animation(forKey: "pageTransition"))
        XCTAssertTrue(b.superview === stage)
        XCTAssertTrue(c.superview === stage)
        stage.frame.size.width = 700
        stage.needsLayout = true
        stage.layoutSubtreeIfNeeded()
        XCTAssertNil(b.superview)
        XCTAssertNil(c.layer?.animation(forKey: "pageTransition"))
        XCTAssertFalse(c.layer?.sublayers?.contains { $0.animation(forKey: "shade") != nil } ?? false)
        XCTAssertEqual(c.frame, stage.bounds)
        stage.show(a, transition: .none, selection: first)
        XCTAssertNil(c.superview)
        XCTAssertNil(a.layer?.animation(forKey: "pageTransition"))
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
        XCTAssertNil(b.layer?.animation(forKey: "pageTransition"))
        XCTAssertFalse(b.layer?.sublayers?.contains { $0.animation(forKey: "shade") != nil } ?? false)
        stage.show(a, transition: .cube, selection: second)
        XCTAssertNil(b.superview)
        XCTAssertNil(a.layer?.animation(forKey: "pageTransition"))
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

    func testEveryStyleReturnsToFullSizeWithExtremeTuning() {
        let size = CGSize(width: 1000, height: 600)
        for style in PageTransition.allCases {
            for zoom in [-0.3, 0.3] {
                let tuning = PageTransitionTuning(speed: 3, offset: 0.5, zoom: zoom, perspective: 2)
                for incoming in [false, true] {
                    for direction: CGFloat in [-1, 1] {
                        for anchor in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5)] {
                            let end = PageMotion.transform(progress: incoming ? 1 : 0, incoming: incoming,
                                                           direction: direction, size: size, anchor: anchor,
                                                           style: style, tuning: tuning)
                            let point = CGPoint(x: 123, y: 234)
                            let result = project(point, through: end)
                            XCTAssertEqual(point.x, result.x, accuracy: 0.001, style.title)
                            XCTAssertEqual(point.y, result.y, accuracy: 0.001, style.title)
                            for p: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                                let t = PageMotion.transform(progress: p, incoming: incoming, direction: direction,
                                                             size: size, anchor: anchor, style: style, tuning: tuning)
                                let projected = project(point, through: t)
                                XCTAssertTrue(projected.x.isFinite && projected.y.isFinite, style.title)
                            }
                        }
                    }
                }
            }
        }
    }

    func testStylesAndControlsChangeTheMotion() {
        let size = CGSize(width: 1000, height: 600)
        func point(_ style: PageTransition, _ tuning: PageTransitionTuning = .init()) -> CGPoint {
            project(CGPoint(x: 100, y: 100), through: PageMotion.transform(
                progress: 0.5, incoming: true, direction: 1, size: size, style: style, tuning: tuning))
        }
        XCTAssertEqual(point(.fade), CGPoint(x: 100, y: 100))
        XCTAssertEqual(point(.slide), CGPoint(x: 600, y: 100))
        XCTAssertEqual(point(.zoom, .defaults(for: .zoom)).y, 85, accuracy: 0.001)
        XCTAssertEqual(point(.fade, .init(zoom: 0.3)).y, 130, accuracy: 0.001)
        XCTAssertGreaterThan(point(.cube, .init(offset: 0.3)).x, point(.cube).x)
        XCTAssertLessThan(point(.cube, .init(perspective: 2)).y, point(.cube, .init(perspective: 0)).y)
        let fade = PageMotion.animation(style: .fade, tuning: .init(speed: 2), incoming: true,
                                        direction: 1, size: size, anchor: .zero)
        XCTAssertEqual(fade.duration, 0.15)
        XCTAssertTrue(fade.animations?.contains { ($0 as? CABasicAnimation)?.keyPath == "opacity" } == true)
    }

    func testTuningIsClampedAndSavedSeparatelyForEachStyle() {
        let stored = Store.settings.data(forKey: "pages.transition.tuning")
        let prefs = Preferences()
        let original = prefs.pageTransition
        defer {
            Store.settings.set(stored, forKey: "pages.transition.tuning")
            prefs.pageTransition = original
        }
        prefs.pageTransition = .cube
        prefs.pageTransitionTuning = .init(speed: 0.5, offset: 0.2, zoom: -0.1, perspective: 1.5)
        prefs.pageTransition = .slide
        prefs.pageTransitionTuning = .init(speed: 2, offset: 0.4, zoom: 0.2)
        let reloaded = Preferences()
        XCTAssertEqual(reloaded.pageTransitionTuning.speed, 2)
        reloaded.pageTransition = .cube
        XCTAssertEqual(reloaded.pageTransitionTuning, .init(speed: 0.5, offset: 0.2, zoom: -0.1, perspective: 1.5))
        reloaded.resetPageTransitionTuning()
        XCTAssertEqual(reloaded.pageTransitionTuning, .defaults(for: .cube))
        reloaded.pageTransition = .slide
        XCTAssertEqual(reloaded.pageTransitionTuning.speed, 2)
        reloaded.pageTransitionTuning = .init(speed: -.infinity, offset: 9, zoom: -9, perspective: .nan)
        XCTAssertEqual(reloaded.pageTransitionTuning, .init(speed: 1, offset: 0.5, zoom: -0.3, perspective: 1))
        XCTAssertEqual(Preferences().pageTransitionTuning, reloaded.pageTransitionTuning)
    }

    func testCustomDurationAndInterruptedStylesCleanUp() async throws {
        guard !Motion.reduced else { throw XCTSkip("Reduce Motion disables page transitions") }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let stage = StageView(frame: window.contentView!.bounds)
        window.contentView = stage
        let a = NSView(), b = NSView(), c = NSView()
        stage.show(a, transition: .cube, selection: UUID())
        stage.show(b, transition: .cube, selection: UUID(), tuning: .init(speed: 0.25))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(a.superview === stage, "Slow transitions must last longer than the old fixed duration")
        for style in [PageTransition.slide, .fade, .zoom] {
            stage.show(c, transition: style, selection: UUID(), tuning: .init(speed: 3))
            XCTAssertNil(a.superview)
            try await Task.sleep(for: .milliseconds(180))
            XCTAssertNil(b.superview)
            XCTAssertNil(c.layer?.animation(forKey: "pageTransition"))
            XCTAssertEqual(c.layer?.opacity, 1)
            stage.show(b, transition: style, selection: UUID(), tuning: .init(speed: 0.25))
        }
        stage.show(c, transition: .none, selection: UUID())
        XCTAssertNil(b.superview)
        XCTAssertNil(c.layer?.animation(forKey: "pageTransition"))
        window.contentView = nil
    }
}
