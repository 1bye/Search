import AppKit

enum PageTransition: String, CaseIterable, Identifiable {
    case none, cube, slide, fade, zoom

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct PageTransitionTuning: Codable, Equatable {
    var speed: Double = 1
    var offset: Double = 0
    var zoom: Double = 0
    var perspective: Double = 1

    static func defaults(for style: PageTransition) -> Self {
        Self(zoom: style == .zoom ? -0.15 : 0)
    }

    var clamped: Self {
        func limit(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        return Self(speed: limit(speed, 0.25...3, fallback: 1),
                    offset: limit(offset, 0...0.5, fallback: 0),
                    zoom: limit(zoom, -0.3...0.3, fallback: 0),
                    perspective: limit(perspective, 0...2, fallback: 1))
    }

    var duration: TimeInterval { 0.3 / clamped.speed }
}

enum PageMotion {
    static func transform(progress: CGFloat, incoming: Bool, direction: CGFloat,
                          size: CGSize, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5),
                          style: PageTransition = .cube, tuning: PageTransitionTuning = .init()) -> CATransform3D {
        guard style != .none else { return CATransform3DIdentity }
        let tuning = tuning.clamped
        let p = min(1, max(0, progress))
        let travel = (incoming ? 1 - p : -p) * direction
        var face = CATransform3DIdentity
        var perspective = CATransform3DIdentity
        if style == .cube {
            let angle = travel * .pi / 2
            let radius = size.width / 2
            let turn = p * .pi / 2
            // Back away just enough to keep the cube's front corner inside the page area.
            let retreat = radius * (sin(turn) + cos(turn) - 1)
            face = CATransform3DMakeRotation(angle, 0, 1, 0)
            face.m41 = radius * sin(angle)
            face.m43 = radius * (cos(angle) - 1) - retreat
            perspective.m34 = -CGFloat(tuning.perspective) / max(1, size.width * 3)
        } else if style == .slide {
            face.m41 = travel * size.width
        }
        face.m41 += travel * size.width * CGFloat(tuning.offset)
        let scale = 1 + CGFloat(tuning.zoom) * sin(.pi * p)
        let projected = CATransform3DConcat(CATransform3DConcat(face, perspective),
                                          CATransform3DMakeScale(scale, scale, 1))
        let center = CGPoint(x: size.width * (0.5 - anchor.x), y: size.height * (0.5 - anchor.y))
        let centered = CATransform3DConcat(CATransform3DMakeTranslation(-center.x, -center.y, 0), projected)
        return CATransform3DConcat(centered, CATransform3DMakeTranslation(center.x, center.y, 0))
    }

    static func animation(style: PageTransition, tuning: PageTransitionTuning,
                          incoming: Bool, direction: CGFloat, size: CGSize, anchor: CGPoint) -> CAAnimationGroup {
        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = (0...30).map {
            NSValue(caTransform3D: self.transform(progress: CGFloat($0) / 30, incoming: incoming,
                                                 direction: direction, size: size, anchor: anchor,
                                                 style: style, tuning: tuning))
        }
        transform.duration = tuning.duration
        var animations: [CAAnimation] = [transform]
        if (style == .fade || style == .zoom), incoming {
            // Keep the outgoing page opaque underneath for a true crossfade.
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = tuning.duration
            animations.append(fade)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = tuning.duration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        return group
    }
}
