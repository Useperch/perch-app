//
//  AgentTriangleView.swift
//  Perch
//
//  One background-agent indicator: a 16pt Perch triangle (same size as the
//  main cursor) that spawns via a gooey mitosis split, flies to its top-right
//  parking slot and spins slowly, then on completion flies back and merges
//  away (reverse mitosis). Owns its full animation lifecycle internally; the
//  swarm view just hands it its slot, its origin points, and completion hooks.
//

import SwiftUI

struct AgentTriangleView: View {
    /// The store-backed model for this agent (id, slot color, phase).
    let indicator: BackgroundAgentIndicator
    /// Where this triangle parks, in the overlay's SwiftUI coordinates.
    let slotPosition: CGPoint
    /// The mitosis origin/destination when the cursor is docked: the bottom of
    /// the notch. (When undocked, the live cursor position is used instead.)
    let notchBottomOrigin: CGPoint
    /// Whether the main cursor is docked beside the notch right now. Chooses the
    /// spawn origin and merge destination (notch vs live cursor).
    let isCursorDocked: Bool
    /// The live main-cursor position snapshot source, read on demand at the
    /// spawn and merge moments (never per frame).
    let cursorPositionProbe: CursorPositionProbe
    /// Called when the spawn animation has finished and the triangle has parked.
    let onParked: (String) -> Void
    /// Called when the merge animation has fully completed and the triangle
    /// should be removed.
    let onMergeComplete: (String) -> Void

    /// The internal on-screen stage, finer-grained than the store's phase so the
    /// view can sequence mitosis → flight → park (and the reverse).
    private enum AnimationStage {
        case splitting        // gooey mitosis split running at the origin
        case flyingToSlot     // triangle arcing toward its parking slot
        case parked           // sitting in slot, spinning slowly
        case flyingToOrigin   // triangle arcing back toward the merge point
        case fusing           // reverse mitosis fusing back into Perch/notch
    }

    @State private var stage: AnimationStage = .splitting

    // Flight state (driven by the bezier animator while in flight).
    @State private var flyingPosition: CGPoint = .zero
    @State private var flyingRotationDegrees: Double = 0
    @State private var flyingScale: CGFloat = 1.0

    // Mitosis state (the gooey split/fuse at the origin point).
    @State private var mitosisCenter: CGPoint = .zero
    @State private var mitosisDirectionRadians: Double = 0
    @State private var mitosisSeparationProgress: CGFloat = 0

    // Continuous slow spin while parked.
    @State private var parkedSpinRotationDegrees: Double = 0
    @State private var hasStartedParkedSpin = false

    /// Set if the agent finishes (phase → .merging) before this triangle has
    /// parked. The spawn's completion handler reads this live flag (not a stale
    /// captured `indicator`) to start the merge as soon as it lands.
    @State private var mergeRequested = false

    @State private var flightAnimator = BezierFlightAnimator()

    /// Duration of the mitosis split/fuse — "quick but satisfying".
    private let mitosisSplitDuration: Double = 0.45
    private let mitosisFuseDuration: Double = 0.4

    private var triangleColor: Color {
        indicator.indicatorColor.color
    }

    var body: some View {
        ZStack {
            switch stage {
            case .splitting, .fusing:
                MitosisSplitView(
                    separationProgress: mitosisSeparationProgress,
                    blobColor: triangleColor,
                    directionAngleRadians: mitosisDirectionRadians
                )
                .position(mitosisCenter)

            case .flyingToSlot, .flyingToOrigin:
                triangleShape
                    .rotationEffect(.degrees(flyingRotationDegrees))
                    .scaleEffect(flyingScale)
                    .position(flyingPosition)

            case .parked:
                triangleShape
                    .rotationEffect(.degrees(parkedSpinRotationDegrees))
                    .position(slotPosition)
            }
        }
        .allowsHitTesting(false)
        .onAppear { startSpawnSequence() }
        .onChange(of: indicator.phase) { newPhase in
            // The store flips us to .merging when the agent finishes. Record the
            // request, then merge now if we've parked — otherwise the spawn's
            // completion handler picks it up via `mergeRequested` once it lands.
            guard newPhase == .merging else { return }
            mergeRequested = true
            if stage == .parked {
                startMergeSequence()
            }
        }
        .onDisappear {
            flightAnimator.cancel()
        }
    }

    private var triangleShape: some View {
        Triangle()
            .fill(triangleColor)
            .frame(width: PerchCursorMetrics.compactTriangleSize, height: PerchCursorMetrics.compactTriangleSize)
            .shadow(color: triangleColor.opacity(0.7), radius: 8, x: 0, y: 0)
    }

    // MARK: - Spawn (mitosis split → fly to slot → park)

    private func startSpawnSequence() {
        let origin = currentOriginPoint()
        mitosisCenter = origin
        mitosisDirectionRadians = angle(from: origin, to: slotPosition)
        mitosisSeparationProgress = 0
        stage = .splitting

        // Run the gooey split, then hand off to the flight on the animation's own
        // completion (not a parallel wall-clock timer that could drift or fire after
        // the view is gone). The guard still skips the hand-off if state moved on.
        withAnimation(.easeIn(duration: mitosisSplitDuration)) {
            mitosisSeparationProgress = 1
        } completion: {
            guard stage == .splitting else { return }
            flyToSlot(from: childHandoffPoint(origin: origin, towards: slotPosition))
        }
    }

    private func flyToSlot(from startPoint: CGPoint) {
        flyingPosition = startPoint
        flyingScale = 1.0
        stage = .flyingToSlot
        flightAnimator.fly(
            from: startPoint,
            to: slotPosition,
            onUpdate: { position, rotation, scale in
                flyingPosition = position
                flyingRotationDegrees = rotation
                flyingScale = scale
            },
            onComplete: {
                flyingScale = 1.0
                stage = .parked
                startParkedSpinIfNeeded()
                onParked(indicator.id)
                // Handle the race where the agent already finished while we were
                // still spawning: merge immediately now that we've parked.
                if mergeRequested {
                    startMergeSequence()
                }
            }
        )
    }

    // MARK: - Merge (fly back → reverse mitosis → remove)

    private func startMergeSequence() {
        guard stage == .parked else { return }
        let destination = currentOriginPoint()
        flyingPosition = slotPosition
        flyingScale = 1.0
        stage = .flyingToOrigin
        flightAnimator.fly(
            from: slotPosition,
            to: destination,
            onUpdate: { position, rotation, scale in
                flyingPosition = position
                flyingRotationDegrees = rotation
                flyingScale = scale
            },
            onComplete: {
                fuseInto(destination: destination)
            }
        )
    }

    private func fuseInto(destination: CGPoint) {
        mitosisCenter = destination
        mitosisDirectionRadians = angle(from: destination, to: slotPosition)
        mitosisSeparationProgress = 1
        stage = .fusing
        // Finish the merge on the fuse animation's own completion. The guard prevents
        // a late callback from notifying completion after the view was torn down or
        // re-spawned (the old wall-clock timer had no such guard).
        withAnimation(.easeOut(duration: mitosisFuseDuration)) {
            mitosisSeparationProgress = 0
        } completion: {
            guard stage == .fusing else { return }
            onMergeComplete(indicator.id)
        }
    }

    // MARK: - Parked spin

    private func startParkedSpinIfNeeded() {
        guard !hasStartedParkedSpin else { return }
        hasStartedParkedSpin = true
        // Slow, continuous full rotation (3s per turn), forever.
        withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
            parkedSpinRotationDegrees = 360
        }
    }

    // MARK: - Geometry helpers

    /// The current mitosis origin/destination: the live cursor when undocked,
    /// the bottom of the notch when docked.
    private func currentOriginPoint() -> CGPoint {
        isCursorDocked ? notchBottomOrigin : cursorPositionProbe.currentBuddyPosition
    }

    /// Where the budded child blob ends up at full separation — the point the
    /// triangle's flight begins from, so the blob→triangle hand-off doesn't pop.
    private func childHandoffPoint(origin: CGPoint, towards target: CGPoint) -> CGPoint {
        let directionRadians = angle(from: origin, to: target)
        let offset = MitosisSplitView.childOffsetAtFullSeparation
        return CGPoint(
            x: origin.x + CGFloat(cos(directionRadians)) * offset,
            y: origin.y + CGFloat(sin(directionRadians)) * offset
        )
    }

    private func angle(from start: CGPoint, to end: CGPoint) -> Double {
        atan2(Double(end.y - start.y), Double(end.x - start.x))
    }
}
