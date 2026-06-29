//
//  MitosisSplitView.swift
//  leanring-buddy
//
//  The gooey "mitosis" metaball used when a background agent buds off Perch
//  (spawn) and when it rejoins (merge). Two blobs joined by a liquid bridge
//  that necks down and snaps as they separate — the classic cell-division look.
//
//  Technique (the well-known SwiftUI Canvas metaball recipe): draw two filled
//  circles into a layer, blur the layer, then alpha-threshold it. Where the two
//  blurred circles overlap, their summed alpha clears the threshold and paints
//  solid — fusing them with a bridge. As the circles separate, the bridge thins
//  and snaps. Pure SwiftUI, no dependency.
//

import SwiftUI

struct MitosisSplitView: View {
    /// 0 = fully fused single blob, 1 = fully separated (bridge snapped).
    /// Animate 0→1 for a spawn split, 1→0 for a merge fuse.
    let separationProgress: CGFloat
    /// The blob color (the spawning agent's slot color).
    let blobColor: Color
    /// Direction, in radians, from the origin toward the agent's parking slot —
    /// the child blob buds off along this axis. (SwiftUI coords: +x right, +y down.)
    let directionAngleRadians: Double

    /// Diameter of each blob, matched to the cursor triangle so the split reads
    /// at cursor scale.
    private let blobDiameter: CGFloat = PerchCursorMetrics.compactTriangleSize * 0.9
    /// How far apart the two blob centers travel at full separation.
    static let maximumSeparation: CGFloat = 34
    /// Fraction of the separation the child blob travels (the parent recoils the
    /// rest). Callers use `childOffsetAtFullSeparation` to align a follow-on
    /// animation with where the budded child ends up.
    static let childSeparationFraction: CGFloat = 0.65
    /// How far the child blob's center sits from the origin at full separation —
    /// the hand-off point for the triangle's flight to its slot.
    static var childOffsetAtFullSeparation: CGFloat { maximumSeparation * childSeparationFraction }
    /// Canvas footprint — generous enough that the blurred bridge never clips.
    private let canvasSize: CGFloat = 96

    var body: some View {
        Canvas { graphicsContext, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let separationDistance = separationProgress * Self.maximumSeparation
            let offsetX = CGFloat(cos(directionAngleRadians)) * separationDistance
            let offsetY = CGFloat(sin(directionAngleRadians)) * separationDistance

            // The parent recoils slightly backward while the child buds forward,
            // so the split looks like an active division rather than a slide.
            let parentCenter = CGPoint(x: center.x - offsetX * 0.35, y: center.y - offsetY * 0.35)
            let childCenter = CGPoint(
                x: center.x + offsetX * Self.childSeparationFraction,
                y: center.y + offsetY * Self.childSeparationFraction
            )

            // Blur is applied first (closest to the drawn circles), then the
            // alpha threshold turns the blurred overlap into a solid gooey shape.
            graphicsContext.addFilter(.alphaThreshold(min: 0.5, color: blobColor))
            graphicsContext.addFilter(.blur(radius: 7))

            graphicsContext.drawLayer { layerContext in
                let parentRadius = blobDiameter / 2
                layerContext.fill(
                    Path(ellipseIn: CGRect(
                        x: parentCenter.x - parentRadius,
                        y: parentCenter.y - parentRadius,
                        width: blobDiameter,
                        height: blobDiameter
                    )),
                    with: .color(.white)
                )

                // The child pinches a touch smaller as it separates, emphasising
                // the "necking" before the snap.
                let childRadius = parentRadius * (1.0 - 0.15 * separationProgress)
                layerContext.fill(
                    Path(ellipseIn: CGRect(
                        x: childCenter.x - childRadius,
                        y: childCenter.y - childRadius,
                        width: childRadius * 2,
                        height: childRadius * 2
                    )),
                    with: .color(.white)
                )
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .shadow(color: blobColor.opacity(0.6), radius: 6, x: 0, y: 0)
    }
}
