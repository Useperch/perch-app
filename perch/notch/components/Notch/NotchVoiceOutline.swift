//
//  NotchVoiceOutline.swift
//  notch
//
//  Two strands that each trace one side of the notch: left strand from the
//  top-left corner down the side and across to bottom-center; right strand
//  mirrored. They share the same path geometry as NotchShape (verified to be
//  identical point-for-point) but stop at the center bottom — no top-edge
//  segment, so no horizontal artifact at the screen top.
//

import SwiftUI

/// One half of the notch outline: top corner → side → bottom curve → bottom center.
/// Path is geometrically identical to the corresponding half of NotchShape.
/// `bottomExtension` extends the path beyond rect.height so the outline reaches
/// the physical notch bottom even when the overlay frame is slightly short.
struct NotchVoiceOutlineStrand: Shape {
    enum Side { case left, right }

    let side: Side
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    var bottomExtension: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w  = rect.width
        let h  = rect.height + bottomExtension
        let tR = topCornerRadius
        let bR = bottomCornerRadius
        let centerX = w / 2

        switch side {
        case .left:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(
                to:      CGPoint(x: tR,      y: tR),
                control: CGPoint(x: tR,      y: 0))
            path.addLine(to: CGPoint(x: tR, y: h - bR))
            path.addQuadCurve(
                to:      CGPoint(x: tR + bR, y: h),
                control: CGPoint(x: tR,      y: h))
            path.addLine(to: CGPoint(x: centerX, y: h))

        case .right:
            path.move(to: CGPoint(x: w, y: 0))
            path.addQuadCurve(
                to:      CGPoint(x: w - tR,      y: tR),
                control: CGPoint(x: w - tR,      y: 0))
            path.addLine(to: CGPoint(x: w - tR, y: h - bR))
            path.addQuadCurve(
                to:      CGPoint(x: w - tR - bR, y: h),
                control: CGPoint(x: w - tR,      y: h))
            path.addLine(to: CGPoint(x: centerX, y: h))
        }
        return path
    }
}

struct NotchVoiceOutline: View {
    /// How far the black notch fill is grown downward (in `ContentView`) so the
    /// outline can sit on the fill's bottom edge rather than floating in the
    /// wallpaper below it. The strands trace the grown fill exactly, so they no
    /// longer need their own `bottomExtension` overshoot.
    static let fillBottomExtension: CGFloat = 6

    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    var palette: VoiceAuraPalette = .blue
    var isActive: Bool = true

    private let drawInDuration:   TimeInterval = 0.32
    private let condenseDuration: TimeInterval = 0.34

    @State private var target:             CGFloat = 0
    @State private var phaseStartProgress: CGFloat = 0
    @State private var phaseStartDate:     Date?   = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            let now   = ctx.date
            let progress = currentProgress(asOf: now)
            let clock = now.timeIntervalSinceReferenceDate

            let breathe        = (sin(clock * 1.35) + 1) / 2
            let restingOpacity = 0.80 + 0.20 * breathe

            let bandDrift = CGFloat(sin(clock * 0.55) * 0.18)
            let lineGradient = LinearGradient(
                colors: [palette.lineTop, palette.lineMid, palette.lineBottom],
                startPoint: UnitPoint(x: 0.5, y: 0.0 + bandDrift),
                endPoint:   UnitPoint(x: 0.5, y: 1.0 + bandDrift)
            )

            let hueShift   = sin(clock * 0.85) * 10
            let strokeStyle = StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)

            ZStack {
                NotchVoiceOutlineStrand(
                    side: .left,
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    bottomExtension: 0
                )
                .trim(from: 0, to: progress)
                .stroke(lineGradient, style: strokeStyle)

                NotchVoiceOutlineStrand(
                    side: .right,
                    topCornerRadius: topCornerRadius,
                    bottomCornerRadius: bottomCornerRadius,
                    bottomExtension: 0
                )
                .trim(from: 0, to: progress)
                .stroke(lineGradient, style: strokeStyle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .hueRotation(.degrees(hueShift))
            .opacity(progress < 1 ? 1.0 : restingOpacity)
            .shadow(color: palette.glow.opacity(0.7), radius: 4)
            .onAppear { beginPhase(active: isActive, initial: true) }
            .onChange(of: isActive) { _, active in beginPhase(active: active, initial: false) }
        }
    }

    private func beginPhase(active: Bool, initial: Bool) {
        let now = Date()
        phaseStartProgress = initial ? 0 : currentProgress(asOf: now)
        phaseStartDate = now
        target = active ? 1 : 0
    }

    private func currentProgress(asOf now: Date) -> CGFloat {
        guard let phaseStartDate else { return target }
        let drawingIn = target >= phaseStartProgress
        let duration  = drawingIn ? drawInDuration : condenseDuration
        let t         = max(0, min(1, now.timeIntervalSince(phaseStartDate) / duration))
        let eased: Double = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        return phaseStartProgress + (target - phaseStartProgress) * CGFloat(eased)
    }
}
