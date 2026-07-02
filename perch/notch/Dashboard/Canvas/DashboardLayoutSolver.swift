//
//  DashboardLayoutSolver.swift
//  Perch
//
//  Pure, view-free collision math for the pegboard. Two widgets may never occupy the
//  same cells, so when a drag/resize is committed the model runs the proposed
//  footprint through this solver:
//
//   • a MOVE that would land on top of another widget is nudged to the nearest free
//     spot (searched outward in rings from where it was dropped);
//   • a RESIZE that would grow into a neighbor is clamped to the largest footprint
//     that still fits (never below the widget's minimum span).
//
//  The board is an infinite integer grid (columns/rows may be negative), so there is
//  always free space — a move can always be resolved within a small search radius.
//

import Foundation

/// A widget's footprint in whole pegboard cells: the half-open ranges
/// `[column, column+columnSpan)` × `[row, row+rowSpan)`.
struct DashboardGridRect: Equatable {
    let column: Int
    let row: Int
    let columnSpan: Int
    let rowSpan: Int

    private var columnUpperBound: Int { column + columnSpan }
    private var rowUpperBound: Int { row + rowSpan }

    /// Whether two footprints share any cell.
    func intersects(_ other: DashboardGridRect) -> Bool {
        column < other.columnUpperBound &&
        columnUpperBound > other.column &&
        row < other.rowUpperBound &&
        rowUpperBound > other.row
    }
}

enum DashboardLayoutSolver {

    /// Find a non-overlapping origin for a widget of the given span, as close as
    /// possible to `(preferredColumn, preferredRow)`. Returns `nil` if nothing free is
    /// found within `searchRadius` cells (the caller then leaves the widget put).
    static func freePlacement(
        columnSpan: Int,
        rowSpan: Int,
        preferredColumn: Int,
        preferredRow: Int,
        obstacles: [DashboardGridRect],
        searchRadius: Int = 10
    ) -> (column: Int, row: Int)? {
        for ringRadius in 0...searchRadius {
            for candidate in ringCandidates(
                centerColumn: preferredColumn,
                centerRow: preferredRow,
                ringRadius: ringRadius
            ) {
                let candidateRect = DashboardGridRect(
                    column: candidate.column,
                    row: candidate.row,
                    columnSpan: columnSpan,
                    rowSpan: rowSpan
                )
                let overlapsSomething = obstacles.contains { $0.intersects(candidateRect) }
                if !overlapsSomething {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Clamp a desired span (same origin) down to the largest footprint that doesn't
    /// overlap any obstacle, never going below the minimum span. Shrinks whichever
    /// dimension currently has the most room above its minimum, one cell at a time.
    static func fittedSpan(
        column: Int,
        row: Int,
        desiredColumnSpan: Int,
        desiredRowSpan: Int,
        minimumColumnSpan: Int,
        minimumRowSpan: Int,
        obstacles: [DashboardGridRect]
    ) -> (columnSpan: Int, rowSpan: Int) {
        var columnSpan = max(minimumColumnSpan, desiredColumnSpan)
        var rowSpan = max(minimumRowSpan, desiredRowSpan)

        func fits(columnSpan candidateColumnSpan: Int, rowSpan candidateRowSpan: Int) -> Bool {
            let candidateRect = DashboardGridRect(
                column: column,
                row: row,
                columnSpan: candidateColumnSpan,
                rowSpan: candidateRowSpan
            )
            return !obstacles.contains { $0.intersects(candidateRect) }
        }

        while !fits(columnSpan: columnSpan, rowSpan: rowSpan)
                && (columnSpan > minimumColumnSpan || rowSpan > minimumRowSpan) {
            let columnRoom = columnSpan - minimumColumnSpan
            let rowRoom = rowSpan - minimumRowSpan
            if columnRoom >= rowRoom && columnSpan > minimumColumnSpan {
                columnSpan -= 1
            } else if rowSpan > minimumRowSpan {
                rowSpan -= 1
            } else if columnSpan > minimumColumnSpan {
                columnSpan -= 1
            } else {
                break
            }
        }
        return (columnSpan, rowSpan)
    }

    // MARK: Ring enumeration

    /// All cells whose Chebyshev distance from the center equals `ringRadius`, ordered
    /// closest-first (by Manhattan distance) so the nearest free spot wins.
    private static func ringCandidates(
        centerColumn: Int,
        centerRow: Int,
        ringRadius: Int
    ) -> [(column: Int, row: Int)] {
        if ringRadius == 0 {
            return [(column: centerColumn, row: centerRow)]
        }
        var candidates: [(column: Int, row: Int)] = []
        for columnDelta in -ringRadius...ringRadius {
            for rowDelta in -ringRadius...ringRadius where max(abs(columnDelta), abs(rowDelta)) == ringRadius {
                candidates.append((column: centerColumn + columnDelta, row: centerRow + rowDelta))
            }
        }
        return candidates.sorted { first, second in
            let firstDistance = abs(first.column - centerColumn) + abs(first.row - centerRow)
            let secondDistance = abs(second.column - centerColumn) + abs(second.row - centerRow)
            return firstDistance < secondDistance
        }
    }
}
