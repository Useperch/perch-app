//
//  BackgroundAgentSwarmView.swift
//  leanring-buddy
//
//  Renders the stack of background-agent indicator triangles at the top-right
//  of the notch screen, one per active agent, each in its slot color (blue →
//  red → green → yellow → repeat). Lives as a sibling of the main cursor inside
//  the notch screen's overlay window, so the mitosis spawn/merge shares the
//  cursor's coordinate space. Owns only layout + hosting; each triangle runs
//  its own spawn/park/merge animation (see `AgentTriangleView`).
//

import AppKit
import SwiftUI

struct BackgroundAgentSwarmView: View {
    /// This overlay's screen frame (the notch screen). Drives slot geometry.
    let screenFrame: CGRect
    /// The active-agent model. Observed so the stack updates as agents come/go.
    @ObservedObject var indicatorStore: BackgroundAgentIndicatorStore
    /// Whether the main cursor is docked beside the notch (chooses spawn origin).
    let isCursorDocked: Bool
    /// On-demand source for the live main-cursor position (mitosis origin when
    /// undocked).
    let cursorPositionProbe: CursorPositionProbe

    private var layout: AgentSwarmLayout { AgentSwarmLayout(screenFrame: screenFrame) }

    var body: some View {
        ZStack {
            ForEach(indicatorStore.activeIndicators) { indicator in
                AgentTriangleView(
                    indicator: indicator,
                    slotPosition: layout.slotPosition(forSlotIndex: indicator.slotIndex),
                    notchBottomOrigin: layout.notchBottomOrigin(),
                    isCursorDocked: isCursorDocked,
                    cursorPositionProbe: cursorPositionProbe,
                    onParked: { agentId in
                        indicatorStore.markParked(id: agentId)
                    },
                    onMergeComplete: { agentId in
                        indicatorStore.removeIndicator(id: agentId)
                    }
                )
                .id(indicator.id)
            }
        }
        .allowsHitTesting(false)
    }
}
