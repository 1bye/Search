import AppKit

/// Match each finger, so adding a finger or pinching cannot look like a swipe.
struct ShelfSwipeDetector {
    private var origins: [AnyHashable: CGPoint] = [:]
    private var blocked = false
    private var fired = false

    mutating func reset() { self = Self() }

    mutating func update(_ touches: [AnyHashable: CGPoint], fingers: Int) -> Bool {
        guard !touches.isEmpty else { reset(); return false }
        guard !blocked, !fired else { return false }
        guard touches.count == fingers else {
            if touches.count > fingers || !origins.isEmpty { blocked = true }
            return false
        }
        guard !origins.isEmpty else { origins = touches; return false }
        guard Set(origins.keys) == Set(touches.keys) else { blocked = true; return false }
        let deltas = touches.map { id, point in
            CGPoint(x: point.x - origins[id]!.x, y: point.y - origins[id]!.y)
        }
        let dx = deltas.reduce(0) { $0 + $1.x } / CGFloat(fingers)
        let dy = deltas.reduce(0) { $0 + $1.y } / CGFloat(fingers)
        // Eight physical trackpad points: intentional, short, and independent of pointer speed.
        guard dy <= -8, -dy > abs(dx) * 1.4,
              deltas.allSatisfy({ $0.y <= -4 }) else { return false }
        fired = true
        return true
    }
}

@MainActor
final class TrackpadShelfSwipe {
    private var detector = ShelfSwipeDetector()
    private var fingers = 3
    private var receivesTouches = false
    private var lastRecognized: TimeInterval = -.infinity

    func reset() {
        detector.reset()
        lastRecognized = -.infinity
    }

    /// Only events delivered to this browser window, never a global event tap.
    func take(_ event: NSEvent, browser: Browser) -> Bool {
        guard browser.prefs.gestureTabs, NSApp.isActive, let window = browser.window,
              window.isKeyWindow, event.window === window else { reset(); return false }
        if fingers != browser.prefs.gestureFingers {
            reset()
            fingers = browser.prefs.gestureFingers
        }
        let recognized: Bool
        switch event.type {
        case .gesture:
            if !event.touches(matching: .any, in: nil).isEmpty { receivesTouches = true }
            if !event.touches(matching: .cancelled, in: nil).isEmpty { detector.reset(); return false }
            let active = event.touches(matching: .touching, in: nil).filter { $0.type == .indirect && !$0.isResting }
            var positions: [AnyHashable: CGPoint] = [:]
            for touch in active {
                guard let id = touch.identity as? AnyHashable else { continue }
                positions[id] = CGPoint(x: touch.normalizedPosition.x * touch.deviceSize.width,
                                        y: touch.normalizedPosition.y * touch.deviceSize.height)
            }
            recognized = detector.update(positions, fingers: fingers)
        case .swipe:
            // Use the standard three-finger swipe only when raw touches are unavailable.
            // Otherwise its later arrival could toggle the shelf twice in one swipe.
            guard !receivesTouches, fingers == 3, abs(event.deltaY) > abs(event.deltaX), event.deltaY < 0,
                  event.timestamp - lastRecognized > 0.4 else { return false }
            recognized = true
        default: return false
        }
        guard recognized else { return false }
        lastRecognized = event.timestamp
        let wasOpen = browser.tabSwitcher.gesture
        browser.toggleTabShelf()
        return wasOpen || browser.tabSwitcher.gesture
    }
}
