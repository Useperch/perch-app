//
//  NotchHomeCenterColumn.swift
//  notch
//
//  Swaps the open-notch center between music controls (default) and a hidden
//  placeholder while an agent-driven alert renders in NotchHomeView's overlay.
//

import SwiftUI

struct NotchHomeCenterColumn: View {
    @EnvironmentObject var companionManager: CompanionManager
    @ObservedObject var notchAlertCoordinator: NotchAlertCoordinator
    @ObservedObject var serviceConnectionOfferCoordinator: ServiceConnectionOfferCoordinator

    /// Either open-notch surface (alert or agent-driven connect prompt) renders in
    /// NotchHomeView's overlay; the center column yields to whichever is present.
    private var isOverlaySurfaceVisible: Bool {
        notchAlertCoordinator.currentAlert != nil
            || serviceConnectionOfferCoordinator.currentOffer != nil
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if !isOverlaySurfaceVisible {
                MusicControlsView()
            }

            // Alert / connect prompt render in NotchHomeView overlay so they can
            // center in the full row (album art + middle band + calendar), not just
            // this column.
            if isOverlaySurfaceVisible {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .drawingGroup()
        .compositingGroup()
    }
}