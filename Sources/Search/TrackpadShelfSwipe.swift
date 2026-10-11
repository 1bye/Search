import AppKit

/// Match each finger, so adding a finger or pinching cannot look like a swipe.
struct ShelfSwipeDetector {
    private var origins: [AnyHashable: CGPoint] = [:]
    private var participants: Set<AnyHashable> = []
    private var blocked = false
    private var fired = false

    mutating func reset() { self = Self() }

    mutating func update(_ touches: [AnyHashable: CGPoint], fingers: Int,
                         resting: Set<AnyHashable> = []) -> Bool {
        let active = touches.filter { !resting.contains($0.key) }
        // Resting swipe fingers are still down. An unrelated resting thumb can stay down.
        if participants.isDisjoint(with: Set(touches.keys)) { reset() }
        participants.formUnion(active.keys)
        guard !blocked, !fired else { return false }
        guard active.count == fingers else {
            if active.count > fingers || !origins.isEmpty { blocked = true }
            return false
        }
        guard !origins.isEmpty else {
            origins = active
            participants = Set(active.keys)
            return false
        }
        guard Set(origins.keys) == Set(active.keys) else { blocked = true; return false }
        let deltas = active.map { id, point in
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

struct ShelfLiftDetector {
    private var finger: AnyHashable?
    private var origin = CGPoint.zero
    private var armed = false

    mutating func reset() { self = Self() }

    mutating func update(_ touches: [AnyHashable: CGPoint], resting: Set<AnyHashable> = [],
                         began: Set<AnyHashable> = [], ended: Set<AnyHashable> = [],
                         cancelled: Bool = false) -> Bool {
        guard !cancelled else { reset(); return false }
        let active = touches.filter { !resting.contains($0.key) }
        guard active.count <= 1 else { reset(); return false }
        if let finger, ended.contains(finger), touches[finger] == nil {
            let select = armed && active.isEmpty
            reset()
            return select
        }
        guard let (id, point) = active.first else {
            // A resting finger is still down; only a real end can select.
            if let finger, touches[finger] != nil { return false }
            reset()
            return false
        }
        if finger != id {
            reset()
            // A finger left over from opening or scrolling cannot become a selection gesture.
            guard began.contains(id) else { return false }
            finger = id
            origin = point
        } else if hypot(point.x - origin.x, point.y - origin.y) >= 1 {
            armed = true
        }
        return false
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
            guard !event.touches(matching: .any, in: nil).isEmpty else { return false }
            receivesTouches = true
            if browser.tabSwitcher.gesturePointer.takeLift(event) {
                browser.commitTabSwitch()
                detector.reset()
                return true
            }
            if !event.touches(matching: .cancelled, in: nil).isEmpty { detector.reset(); return false }
            let touching = event.touches(matching: .touching, in: nil).filter { $0.type == .indirect }
            var positions: [AnyHashable: CGPoint] = [:]
            var resting: Set<AnyHashable> = []
            for touch in touching {
                guard let id = touch.identity as? AnyHashable else { continue }
                positions[id] = CGPoint(x: touch.normalizedPosition.x * touch.deviceSize.width,
                                        y: touch.normalizedPosition.y * touch.deviceSize.height)
                if touch.isResting { resting.insert(id) }
            }
            recognized = detector.update(positions, fingers: fingers, resting: resting)
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
