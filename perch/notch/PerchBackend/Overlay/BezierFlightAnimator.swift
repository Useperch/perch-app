//
//  BezierFlightAnimator.swift
//  Perch
//
//  A standalone, reusable port of `BlueCursorView.animateBezierFlightArc`: it
//  flies a point along a quadratic bezier arc, reporting position, a
//  tangent-facing rotation, and a mid-flight scale "swoop" each frame. Used by
//  the background-agent swarm so each spawning/merging triangle can travel to
//  (or back from) its top-right slot with the same feel as the main cursor's
//  element-pointing flight. Each in-flight triangle owns its own animator so
//  concurrent flights never share a timer.
//
//  Plain (non-actor) class on purpose: the `Timer` fires on the main run loop,
//  exactly like the original cursor flight, so the per-frame callbacks land on
//  the main thread and may safely touch SwiftUI `@State`.
//

import Foundation

final class BezierFlightAnimator {

    private var flightTimer: Timer?

    /// Flies from `startPosition` to `endPosition` along an upward-arcing
    /// quadratic bezier curve.
    ///
    /// - onUpdate: called each frame with the current `(position, rotationDegrees,
    ///   scale)`. `rotationDegrees` faces the direction of travel; `scale` grows
    ///   to ~1.3x at the apex and returns to 1.0x on landing.
    /// - onComplete: called once when the flight lands.
    func fly(
        from startPosition: CGPoint,
        to endPosition: CGPoint,
        onUpdate: @escaping (CGPoint, Double, CGFloat) -> Void,
        onComplete: @escaping () -> Void
    ) {
        flightTimer?.invalidate()

        let deltaX = endPosition.x - startPosition.x
        let deltaY = endPosition.y - startPosition.y
        let distance = hypot(deltaX, deltaY)

        // Flight duration scales with distance — short hops are quick, long
        // flights more dramatic. Clamped to keep the spawn "quick but satisfying".
        let flightDurationSeconds = min(max(distance / 900.0, 0.5), 1.1)
        let frameInterval: Double = 1.0 / 60.0
        let totalFrames = max(Int(flightDurationSeconds / frameInterval), 1)
        var currentFrame = 0

        // Control point for the quadratic bezier arc: the midpoint lifted upward
        // (negative Y in SwiftUI) so the triangle flies in a parabolic arc.
        let midPoint = CGPoint(
            x: (startPosition.x + endPosition.x) / 2.0,
            y: (startPosition.y + endPosition.y) / 2.0
        )
        let arcHeight = min(distance * 0.2, 80.0)
        let controlPoint = CGPoint(x: midPoint.x, y: midPoint.y - arcHeight)

        flightTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            currentFrame += 1

            if currentFrame > totalFrames {
                self?.flightTimer?.invalidate()
                self?.flightTimer = nil
                onUpdate(endPosition, 0.0, 1.0)
                onComplete()
                return
            }

            let linearProgress = Double(currentFrame) / Double(totalFrames)

            // Smoothstep easeInOut: 3t² - 2t³ (Hermite interpolation).
            let t = linearProgress * linearProgress * (3.0 - 2.0 * linearProgress)

            // Quadratic bezier: B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
            let oneMinusT = 1.0 - t
            let bezierX = oneMinusT * oneMinusT * startPosition.x
                        + 2.0 * oneMinusT * t * controlPoint.x
                        + t * t * endPosition.x
            let bezierY = oneMinusT * oneMinusT * startPosition.y
                        + 2.0 * oneMinusT * t * controlPoint.y
                        + t * t * endPosition.y
            let position = CGPoint(x: bezierX, y: bezierY)

            // Rotation: face the tangent. B'(t) = 2(1-t)(P1-P0) + 2t(P2-P1).
            // +90° because the triangle's tip points up at 0° rotation.
            let tangentX = 2.0 * oneMinusT * (controlPoint.x - startPosition.x)
                         + 2.0 * t * (endPosition.x - controlPoint.x)
            let tangentY = 2.0 * oneMinusT * (controlPoint.y - startPosition.y)
                         + 2.0 * t * (endPosition.y - controlPoint.y)
            let rotationDegrees = atan2(tangentY, tangentX) * (180.0 / .pi) + 90.0

            // Scale pulse: sin curve peaks at the flight's midpoint.
            let scalePulse = sin(linearProgress * .pi)
            let scale = 1.0 + CGFloat(scalePulse) * 0.3

            onUpdate(position, rotationDegrees, scale)
        }
    }

    /// Stops any in-progress flight.
    func cancel() {
        flightTimer?.invalidate()
        flightTimer = nil
    }

    deinit {
        flightTimer?.invalidate()
    }
}
