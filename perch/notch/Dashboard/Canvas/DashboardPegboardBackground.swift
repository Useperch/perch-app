//
//  DashboardPegboardBackground.swift
//  Perch
//
//  The pegboard: a field of faint dots that the widgets snap to. It draws only the
//  dots inside the current viewport (computed by inverting the canvas transform), so
//  the board feels infinite in every direction without ever drawing more than a
//  screenful of dots.
//
//  It shares the exact transform used by the widget layer —
//  `screen = (world + panOffset) · zoomScale` — so a dot always sits under a widget's
//  snapped corner regardless of pan or zoom.
//

import SwiftUI

struct DashboardPegboardBackground: View {
    let panOffset: CGSize
    let zoomScale: CGFloat

    var body: some View {
        Canvas { context, size in
            let pegSpacing = DashboardTheme.Metrics.pegSpacing
            // Guard against a degenerate scale (zoom is clamped ≥ minZoom, but be safe).
            guard zoomScale > 0.01, pegSpacing > 0 else { return }

            // Invert the transform to find which world coordinates are on screen:
            //   screen ∈ [0, size]  ⇒  world = screen / zoom − pan
            let worldMinX = -panOffset.width
            let worldMaxX = size.width / zoomScale - panOffset.width
            let worldMinY = -panOffset.height
            let worldMaxY = size.height / zoomScale - panOffset.height

            let firstColumn = Int((worldMinX / pegSpacing).rounded(.down))
            let lastColumn = Int((worldMaxX / pegSpacing).rounded(.up))
            let firstRow = Int((worldMinY / pegSpacing).rounded(.down))
            let lastRow = Int((worldMaxY / pegSpacing).rounded(.up))
            guard firstColumn <= lastColumn, firstRow <= lastRow else { return }

            let dotRadius = max(0.6, DashboardTheme.Metrics.pegDotRadius * zoomScale)
            let dotColor = DashboardTheme.Colors.pegDot

            // Cards are inset by half the cell gap inside their cell (see
            // `DashboardWidgetHost`'s `.offset(cellGap/2)`), so a card's snapped top-left
            // corner sits at `cell origin + cellGap/2`, not at the bare cell corner. Shift
            // the dots by the same half-gap so a dot lands under each card's snapped corner
            // rather than floating in the gap between cards.
            let halfCellGap = DashboardTheme.Metrics.cellGap / 2

            for column in firstColumn...lastColumn {
                for row in firstRow...lastRow {
                    let screenX = (CGFloat(column) * pegSpacing + halfCellGap + panOffset.width) * zoomScale
                    let screenY = (CGFloat(row) * pegSpacing + halfCellGap + panOffset.height) * zoomScale
                    let dotRect = CGRect(
                        x: screenX - dotRadius,
                        y: screenY - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
                }
            }
        }
    }
}
