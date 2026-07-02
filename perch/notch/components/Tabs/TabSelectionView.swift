//
//  TabSelectionView.swift
//  notch
//
//  Created by Hugo Persson on 2024-08-25.
//

import AppKit
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let homeTab = TabModel(label: "Home", icon: "house.fill", view: .home)
let shelfTab = TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)

struct TabSelectionView: View {
    @ObservedObject var coordinator = ViewCoordinator.shared
    @Namespace var animation

    private var visibleTabs: [TabModel] {
        [homeTab]
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(visibleTabs) { tab in
                let isSelected = coordinator.currentView == tab.view
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(isSelected ? .white : .gray)
                .background {
                    // The sliding pill marks the selected tab. matchedGeometryEffect
                    // must have exactly ONE source per id — applying it to every tab
                    // (as before) gave SwiftUI multiple sources for "capsule" and
                    // collapsed the trailing tab's frame, so the Agents tab vanished.
                    if isSelected {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Opens the Daily Dashboard, now ported to run fully inside notch — no Perch app
/// required. It holds the window controller so the window survives between opens. Without
/// Perch's sidecar there's no live-data transport, so the dashboard shows its local
/// widgets and graceful empty states (same as Perch's standalone dashboard preview).
@MainActor
enum DashboardLauncher {
    private static var controller: DashboardWindowController?

    static func open() {
        if controller == nil {
            controller = DashboardWindowController()
        }
        // notch is a menu-bar/notch app, so bring it forward to surface the window.
        NSApp.activate(ignoringOtherApps: true)
        controller?.show()
    }
}

#Preview {
    Header().environmentObject(ViewModel())
}
