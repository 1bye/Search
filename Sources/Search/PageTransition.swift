import AppKit

enum PageTransition: String, CaseIterable, Identifiable {
    case none, cube

    var id: String { rawValue }
    var title: String { self == .cube ? "Cube" : "None" }
}

enum PageCube {
    static let duration: TimeInterval = 0.3

    static func transform(progress: CGFloat, incoming: Bool, direction: CGFloat,
                          size: CGSize, anchor: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> CATransform3D {
        let angle = (incoming ? 1 - progress : -progress) * .pi / 2 * direction
        let radius = size.width / 2
        let turn = progress * .pi / 2
        // Back away just enough to keep the cube's front corner inside the page area.
        let retreat = radius * (sin(turn) + cos(turn) - 1)
        var face = CATransform3DMakeRotation(angle, 0, 1, 0)
        face.m41 = radius * sin(angle)
        face.m43 = radius * (cos(angle) - 1) - retreat
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / max(1, size.width * 3)
        let center = CGPoint(x: size.width * (0.5 - anchor.x), y: size.height * (0.5 - anchor.y))
        let centered = CATransform3DConcat(CATransform3DMakeTranslation(-center.x, -center.y, 0), face)
        return CATransform3DConcat(CATransform3DConcat(centered, perspective),
                                  CATransform3DMakeTranslation(center.x, center.y, 0))
    }

    static func animation(incoming: Bool, direction: CGFloat, size: CGSize, anchor: CGPoint) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = (0...30).map {
            NSValue(caTransform3D: transform(progress: CGFloat($0) / 30, incoming: incoming,
                                            direction: direction, size: size, anchor: anchor))
        }
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        return animation
    }
}
