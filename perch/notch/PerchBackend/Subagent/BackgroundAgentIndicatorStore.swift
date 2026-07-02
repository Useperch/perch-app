//
//  BackgroundAgentIndicatorStore.swift
//  Perch
//
//  The model behind the top-right "agent swarm" indicator: one spinning
//  Perch triangle per active background agent. Owned by `CompanionManager`
//  and fed by the browser-subagent lifecycle. The overlay's
//  `BackgroundAgentSwarmView` observes this store and renders/animates the
//  triangles (mitosis spawn, top-right parking, reverse-mitosis merge).
//
//  The store is deliberately geometry-free — it only tracks WHICH agents are
//  active, their stack slot, and their animation phase. All on-screen
//  positions are computed by the overlay, which is the only place that knows
//  the notch screen's coordinate space.
//

import Foundation

/// Where an agent indicator is in its on-screen lifecycle.
enum BackgroundAgentIndicatorPhase: Equatable {
    /// Just spawned — the overlay is running the mitosis split + flight to slot.
    case spawning
    /// Sitting in its top-right slot, spinning slowly.
    case parked
    /// The agent finished — the overlay is flying it back and merging it away.
    case merging
}

/// One active background agent, rendered as a single spinning triangle.
struct BackgroundAgentIndicator: Identifiable, Equatable {
    /// Stable id of the underlying agent (subagent id). Drives SwiftUI identity.
    let id: String
    /// Vertical stack position (0 = top). Also selects the color via the cycle.
    let slotIndex: Int
    /// The triangle's color, derived from `slotIndex` and frozen for its lifetime.
    let indicatorColor: PerchCursorColor
    /// Current on-screen lifecycle phase.
    var phase: BackgroundAgentIndicatorPhase
}

/// Holds the list of active background-agent indicators. All mutations return a
/// fresh array (never mutate in place) so SwiftUI sees clean value changes and
/// callers never observe a half-updated list.
@MainActor
final class BackgroundAgentIndicatorStore: ObservableObject {

    @Published private(set) var activeIndicators: [BackgroundAgentIndicator] = []

    /// The color cycle by slot index: blue → red → green → yellow → repeat.
    private static let slotColorCycle: [PerchCursorColor] = [.blue, .red, .green, .yellow]

    /// The color a triangle in `slotIndex` should use.
    static func color(forSlotIndex slotIndex: Int) -> PerchCursorColor {
        slotColorCycle[slotIndex % slotColorCycle.count]
    }

    /// Adds a new agent indicator in the lowest free slot, starting in the
    /// `.spawning` phase. No-op if an indicator with this id already exists
    /// (a duplicate lifecycle event must not spawn a second triangle).
    func addIndicator(id agentIdentifier: String) {
        guard !activeIndicators.contains(where: { $0.id == agentIdentifier }) else { return }

        let assignedSlotIndex = lowestFreeSlotIndex()
        let newIndicator = BackgroundAgentIndicator(
            id: agentIdentifier,
            slotIndex: assignedSlotIndex,
            indicatorColor: Self.color(forSlotIndex: assignedSlotIndex),
            phase: .spawning
        )
        activeIndicators = activeIndicators + [newIndicator]
    }

    /// Marks an indicator as having finished its spawn animation and parked.
    func markParked(id agentIdentifier: String) {
        activeIndicators = activeIndicators.map { indicator in
            guard indicator.id == agentIdentifier else { return indicator }
            var updated = indicator
            updated.phase = .parked
            return updated
        }
    }

    /// Begins the merge-away animation for a finished agent. The triangle keeps
    /// its slot reserved until `removeIndicator` fires, so a concurrent spawn
    /// takes a different slot.
    func beginMerging(id agentIdentifier: String) {
        activeIndicators = activeIndicators.map { indicator in
            guard indicator.id == agentIdentifier else { return indicator }
            var updated = indicator
            updated.phase = .merging
            return updated
        }
    }

    /// Removes an indicator once its merge animation has fully completed,
    /// freeing its slot for reuse.
    func removeIndicator(id agentIdentifier: String) {
        activeIndicators = activeIndicators.filter { $0.id != agentIdentifier }
    }

    /// The lowest slot index not currently occupied, so a finished middle agent
    /// leaves a reusable gap and the stack stays tight with stable colors.
    private func lowestFreeSlotIndex() -> Int {
        let occupiedSlotIndices = Set(activeIndicators.map { $0.slotIndex })
        var candidateSlotIndex = 0
        while occupiedSlotIndices.contains(candidateSlotIndex) {
            candidateSlotIndex += 1
        }
        return candidateSlotIndex
    }
}
