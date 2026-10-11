import SwiftUI

/// Every input delta is applied. Attraction changes with speed, never with a step threshold.
struct MagneticPointer {
    var point: CGPoint
    private(set) var speed: CGFloat = 0
    private(set) var lastInput: TimeInterval = -.infinity
    private(set) var vertical: CGFloat = 0

    mutating func move(dx: CGFloat, dy: CGFloat, at now: TimeInterval, gain: CGFloat) {
        let elapsed = min(0.04, max(0.008, now - lastInput))
        point.x += dx * gain
        point.y += dy * gain
        speed = hypot(dx, dy) * gain / elapsed
        lastInput = now
        vertical = dy
    }

    mutating func attract(to target: CGRect, at now: TimeInterval, dt: TimeInterval, strength: CGFloat) {
        guard strength > 0 else { return }
        let dx = target.midX - point.x, dy = target.midY - point.y
        let distance = hypot(dx, dy)
        let idle = now - lastInput
        let slow = max(0, 1 - speed / 700)
        let nearby = max(0, 1 - distance / (min(target.width, target.height) * 0.7))
        let rate = idle > 0.11 ? 25 * strength : 3 * strength * slow * nearby
        let pull = 1 - exp(-dt * rate)
        point.x += dx * pull
        point.y += dy * pull
        if idle > 0.11, distance < 0.2 { point = CGPoint(x: target.midX, y: target.midY) }
    }
}

struct ShelfLayout {
    var count: Int
    var size: CGSize
    var columns: Int { min(5, max(1, count)) }
    var cardWidth: CGFloat { (size.width - CGFloat(columns - 1) * 8) / CGFloat(columns) }
    var previewHeight: CGFloat { (cardWidth - 16) * 0.62 }
    var cardHeight: CGFloat { previewHeight + 39 }
    var contentHeight: CGFloat { CGFloat((count + columns - 1) / columns) * (cardHeight + 8) - 8 }
    var maxScroll: CGFloat { max(0, contentHeight - size.height) }

    func frame(_ index: Int, scroll: CGFloat) -> CGRect {
        CGRect(x: CGFloat(index % columns) * (cardWidth + 8),
               y: CGFloat(index / columns) * (cardHeight + 8) - scroll,
               width: cardWidth, height: cardHeight)
    }

    func nearest(to point: CGPoint, scroll: CGFloat, keeping current: Int?) -> Int? {
        func score(_ index: Int) -> CGFloat {
            let rect = frame(index, scroll: scroll)
            return pow((point.x - rect.midX) / rect.width, 2) + pow((point.y - rect.midY) / rect.height, 2)
        }
        let visible = (0..<count).filter {
            let rect = frame($0, scroll: scroll)
            return rect.midY >= 0 && rect.midY <= size.height
        }
        guard let best = visible.min(by: { score($0) < score($1) }) else { return nil }
        if let current, visible.contains(current), score(current) <= score(best) + 0.025 { return current }
        return best
    }
}

@MainActor
final class GestureShelfState: ObservableObject {
    @Published private(set) var point = CGPoint.zero
    @Published private(set) var scroll: CGFloat = 0
    @Published private(set) var captured = false
    private var pointer = MagneticPointer(point: .zero)
    private var lift = ShelfLiftDetector()
    private var layout = ShelfLayout(count: 0, size: .zero)
    private weak var switcher: TabSwitcher?
    private weak var prefs: Preferences?
    private weak var window: NSWindow?
    private var mouseWasAccepted = false
    private var savedCursor: CGPoint?
    private var monitor: Any?
    private var termination: NSObjectProtocol?
    private var timer: Timer?
    private var lastTick: TimeInterval = 0

    func start(browser: Browser, size: CGSize) {
        stop()
        switcher = browser.tabSwitcher
        prefs = browser.prefs
        window = browser.window
        resize(size)
        guard let window, window.isKeyWindow, NSApp.isActive else {
            browser.tabSwitcher.cancel()
            return
        }
        mouseWasAccepted = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        // Park inside this window so relative events keep arriving even if opened from the menu.
        savedCursor = CGEvent(source: nil)?.location
        let center = window.convertPoint(toScreen: CGPoint(x: window.frame.width / 2, y: window.frame.height / 2))
        if let screen = NSScreen.screens.first {
            CGWarpMouseCursorPosition(CGPoint(x: center.x, y: screen.frame.maxY - center.y))
        }
        captured = CGAssociateMouseAndMouseCursorPosition(0) == .success
        if captured { NSCursor.hide() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self, weak browser] event in
            guard let self, let browser, self.captured, let window = self.window else { return event }
            guard NSApp.isActive, window.isKeyWindow else { browser.tabSwitcher.cancel(); return event }
            if let other = event.window, other !== window { browser.tabSwitcher.cancel(); return event }
            switch event.type {
            case .mouseMoved, .leftMouseDragged:
                self.pointer.move(dx: event.deltaX, dy: event.deltaY, at: ProcessInfo.processInfo.systemUptime,
                                  gain: CGFloat(browser.prefs.gestureSpeed))
                self.clampPointer()
                self.choose()
                self.point = self.pointer.point
            case .leftMouseDown: browser.commitTabSwitch()
            case .rightMouseDown: browser.tabSwitcher.cancel()
            case .scrollWheel:
                // Two fingers scroll the collection; one finger moves the pointer.
                self.scroll = min(self.layout.maxScroll, max(0, self.scroll - event.scrollingDeltaY))
                self.choose()
            default: break
            }
            return nil
        }
        termination = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        lastTick = ProcessInfo.processInfo.systemUptime
        let clock = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer = clock
        RunLoop.main.add(clock, forMode: .common)
    }

    func takeLift(_ event: NSEvent) -> Bool {
        guard captured, switcher?.gesture == true else { return false }
        var positions: [AnyHashable: CGPoint] = [:]
        var resting: Set<AnyHashable> = []
        for touch in event.touches(matching: .touching, in: nil) where touch.type == .indirect {
            guard let id = touch.identity as? AnyHashable else { continue }
            positions[id] = CGPoint(x: touch.normalizedPosition.x * touch.deviceSize.width,
                                    y: touch.normalizedPosition.y * touch.deviceSize.height)
            if touch.isResting { resting.insert(id) }
        }
        let ended = Set(event.touches(matching: .ended, in: nil)
            .filter { $0.type == .indirect }.compactMap { $0.identity as? AnyHashable })
        let cancelled = !event.touches(matching: .cancelled, in: nil).isEmpty
        return lift.update(positions, resting: resting, ended: ended, cancelled: cancelled)
    }

    func resize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, let switcher else { return }
        layout = ShelfLayout(count: switcher.candidates.count, size: size)
        centerSelection()
    }

    func centerSelection() {
        guard let switcher, let id = switcher.selectedID,
              let index = switcher.candidates.firstIndex(of: id), layout.size.width > 0 else { return }
        let rect = layout.frame(index, scroll: scroll)
        if rect.minY < 0 { scroll += rect.minY }
        if rect.maxY > layout.size.height { scroll += rect.maxY - layout.size.height }
        scroll = min(layout.maxScroll, max(0, scroll))
        let target = layout.frame(index, scroll: scroll)
        pointer = MagneticPointer(point: CGPoint(x: target.midX, y: target.midY))
        point = pointer.point
    }

    private func choose() {
        guard let switcher else { return }
        let current = switcher.selectedID.flatMap { switcher.candidates.firstIndex(of: $0) }
        if let index = layout.nearest(to: pointer.point, scroll: scroll, keeping: current) {
            switcher.pick(switcher.candidates[index])
        }
    }

    private func clampPointer() {
        pointer.point.x = min(layout.size.width - 7, max(7, pointer.point.x))
        pointer.point.y = min(layout.size.height - 7, max(7, pointer.point.y))
    }

    private func tick() {
        guard let switcher, switcher.gesture, let prefs else { stop(); return }
        guard window?.isKeyWindow == true, NSApp.isActive else { switcher.cancel(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.04, now - lastTick)
        lastTick = now
        // Edge scrolling only follows fresh movement toward that edge, never a resting dot.
        if now - pointer.lastInput < 0.08 {
            let y = pointer.point.y, edge: CGFloat = 32
            let pressure: CGFloat = pointer.vertical > 0 ? max(0, (y - layout.size.height + edge) / edge)
                : pointer.vertical < 0 ? -max(0, (edge - y) / edge) : 0
            let next = min(layout.maxScroll, max(0, scroll + pressure * 900 * dt))
            if next != scroll { scroll = next; choose() }
        }
        if let id = switcher.selectedID, let index = switcher.candidates.firstIndex(of: id) {
            let target = layout.frame(index, scroll: scroll)
            pointer.attract(to: target, at: now, dt: dt, strength: CGFloat(prefs.gesturePull))
        }
        clampPointer()
        if point != pointer.point { point = pointer.point }
    }

    func stop() {
        lift.reset()
        timer?.invalidate(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let termination { NotificationCenter.default.removeObserver(termination) }; termination = nil
        if captured {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
            captured = false
        }
        if let savedCursor { CGWarpMouseCursorPosition(savedCursor) }; savedCursor = nil
        window?.acceptsMouseMovedEvents = mouseWasAccepted
        window = nil
    }
}

struct GestureShelf: View {
    @ObservedObject var browser: Browser
    @ObservedObject var switcher: TabSwitcher
    @ObservedObject var pointer: GestureShelfState

    var body: some View {
        GeometryReader { geometry in
            let columns = min(5, switcher.candidates.count)
            let width = min(CGFloat(columns) * 176 + CGFloat(columns - 1) * 8, geometry.size.width - 48)
            let tentative = ShelfLayout(count: switcher.candidates.count, size: CGSize(width: width, height: 1))
            let height = min(tentative.contentHeight, max(140, geometry.size.height - 84))
            let layout = ShelfLayout(count: switcher.candidates.count, size: CGSize(width: width, height: height))
            ZStack {
                Color.black.opacity(0.24).ignoresSafeArea().onTapGesture { switcher.cancel() }
                ZStack(alignment: .topLeading) {
                    ForEach(Array(switcher.candidates.enumerated()), id: \.element) { index, id in
                        if let tab = browser.tabs.first(where: { $0.id == id }) {
                            let frame = layout.frame(index, scroll: pointer.scroll)
                            TabSwitcherCard(browser: browser, switcher: switcher, tab: tab,
                                            width: layout.cardWidth, previewHeight: layout.previewHeight,
                                            height: layout.cardHeight)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(id == switcher.selectedID ? Palette.faint : Color.clear))
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }
                    if pointer.captured {
                        Circle().fill(Color(red: 0.83, green: 1, blue: 0.9))
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                            .background(Circle().fill(Color.green.opacity(0.18)).padding(-5))
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
                            .position(pointer.point)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: width, height: height)
                .clipped()
                .onAppear { pointer.start(browser: browser, size: layout.size) }
                .onChange(of: layout.size) { _, size in pointer.resize(size) }
                .padding(18)
                .frame(width: width + 36)
                .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.hairline))
                .shadow(color: .black.opacity(0.18), radius: 30, y: 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear { pointer.stop() }
        .task { switcher.capturePreviews(from: browser.tabs, current: browser.activeID) }
    }
}
