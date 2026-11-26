import AppKit

/// Core Animation motion for cards (SPEC §4.2): springs on position, fades on
/// opacity. Model values are set immediately, so hit-testing and dragging use
/// the final frame from the first frame on.
@MainActor enum CardAnimator {
    static let entranceDuration: CFTimeInterval = 0.25
    static let exitDuration: CFTimeInterval = 0.18

    /// Moves `view` to `frame`. With `from`, it springs from that frame;
    /// otherwise from wherever it currently appears (retargets mid-flight).
    static func move(_ view: NSView, to frame: CGRect, from: CGRect? = nil, animated: Bool) {
        guard let layer = view.layer else { view.frame = frame; return }
        let startPosition: CGPoint
        if let from {
            withoutActions { view.frame = from }
            startPosition = layer.position
        } else {
            startPosition = layer.presentation()?.position ?? layer.position
        }
        withoutActions { view.frame = frame }
        let endPosition = layer.position
        guard animated, startPosition != endPosition else {
            layer.removeAnimation(forKey: "move")
            return
        }
        let spring = CASpringAnimation(perceptualDuration: entranceDuration, bounce: 0.12)
        spring.keyPath = "position"
        spring.fromValue = NSValue(point: startPosition)
        spring.toValue = NSValue(point: endPosition)
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "move")
    }

    static func fadeIn(_ view: NSView) {
        guard let layer = view.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.12
        layer.add(fade, forKey: "fadeIn")
    }

    /// Fades and scales down around the centre; calls `completion` at the end.
    static func exit(_ view: NSView, completion: @escaping @MainActor () -> Void) {
        guard let layer = view.layer else { completion(); return }
        let b = layer.bounds
        let cx = b.width * (0.5 - layer.anchorPoint.x), cy = b.height * (0.5 - layer.anchorPoint.y)
        var t = CATransform3DMakeTranslation(cx, cy, 0)
        t = CATransform3DScale(t, 0.86, 0.86, 1)
        t = CATransform3DTranslate(t, -cx, -cy, 0)
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        scale.toValue = NSValue(caTransform3D: t)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        run([scale, fade], on: layer, duration: exitDuration, timing: .easeIn, completion: completion)
    }

    /// Slides past the screen edge (swipe away / evicted on the edge side).
    static func slideOut(_ view: NSView, to frame: CGRect, completion: @escaping @MainActor () -> Void) {
        guard let layer = view.layer else { completion(); return }
        let start = layer.presentation()?.position ?? layer.position
        let end = CGPoint(x: start.x + (frame.minX - view.frame.minX), y: start.y)
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: start)
        move.toValue = NSValue(point: end)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        run([move, fade], on: layer, duration: 0.2, timing: .easeIn, completion: completion)
    }

    private static func run(_ animations: [CAAnimation], on layer: CALayer, duration: CFTimeInterval, timing: CAMediaTimingFunctionName, completion: @escaping @MainActor () -> Void) {
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: timing)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        layer.add(group, forKey: "exit")
        CATransaction.commit()
    }

    static func withoutActions(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
