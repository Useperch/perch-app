//
//  AgentSwarmLayout.swift
//  Perch
//
//  Shared geometry for the top-right background-agent swarm, in the notch
//  overlay's SwiftUI (top-left origin) coordinate space. Used by both the
//  swarm view (to place triangles) and the cursor overlay (to hit-test hover
//  over a triangle), so the two never drift apart.
//

import AppKit
import CoreGraphics

struct AgentSwarmLayout {
    /// The notch screen's frame (the overlay this layout belongs to).
    let screenFrame: CGRect

    /// Horizontal inset from the screen's right edge to a triangle's CENTER.
    static let rightEdgeInsetToCenter: CGFloat = 34
    /// Vertical inset from the bottom of the menu-bar strip to the FIRST
    /// triangle's center. The whole stack sits this far below the menu bar.
    static let topInsetToCenterBelowMenuBar: CGFloat = 40
    /// Center-to-center vertical spacing between stacked triangles.
    static let slotVerticalSpacing: CGFloat = 30
    /// Generous radius (from a triangle's center) treated as "hovering" it.
    static let hoverHitRadius: CGFloat = 28

    /// Parking position for a stack slot: pinned near the top-right, just below
    /// the menu-bar strip, stacking downward.
    func slotPosition(forSlotIndex slotIndex: Int) -> CGPoint {
        let x = screenFrame.width - Self.rightEdgeInsetToCenter
        let y = menuBarStripHeight()
            + Self.topInsetToCenterBelowMenuBar
            + CGFloat(slotIndex) * Self.slotVerticalSpacing
        return CGPoint(x: x, y: y)
    }

    /// The mitosis origin/destination when docked: center-x at the bottom edge
    /// of the notch strip (mirrors `NotchPanelManager.notchRect`).
    func notchBottomOrigin() -> CGPoint {
        CGPoint(x: screenFrame.width / 2, y: menuBarStripHeight())
    }

    /// Height of the menu-bar strip on the notch screen, in points.
    func menuBarStripHeight() -> CGFloat {
        let notchScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
        let safeAreaTop = notchScreen?.safeAreaInsets.top ?? 0
        return max(safeAreaTop, NSStatusBar.system.thickness)
    }
}
