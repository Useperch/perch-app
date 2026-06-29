//
//  PerchCursorMetrics.swift
//  leanring-buddy
//
//  Shared sizing for the Perch triangle so the main cursor and every
//  background-agent indicator read as the same Perch — change it in one place.
//

import CoreGraphics

enum PerchCursorMetrics {
    /// On-screen size of the main Perch triangle while it follows the cursor.
    static let triangleSize: CGFloat = 22

    /// Smaller size for the "resting"/secondary triangles: the cursor while
    /// docked beside the notch, and each background-agent swarm indicator. These
    /// two stay matched so the subagent reads as the same little parked Perch.
    static let compactTriangleSize: CGFloat = 16
}
