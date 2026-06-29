//
//  Header.swift
//  notch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct Header: View {
    @EnvironmentObject var vm: ViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = ViewCoordinator.shared
    var body: some View {
        ZStack {
            // The physical-notch cutout is visual only — it must not participate in
            // the tab bar's horizontal layout or it eats/clips the Agents tab.
            if vm.notchState == .open {
                Rectangle()
                    .fill(NSScreen.screen(withUUID: coordinator.selectedScreenUUID)?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear)
                    .frame(width: vm.closedNotchSize.width)
                    .mask {
                        NotchShape()
                    }
            }

            HStack(spacing: 8) {
                if vm.notchState == .open {
                    TabSelectionView()
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 0)

                if vm.notchState == .open {
                    headerTrailingActions
                }
            }
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    @ViewBuilder
    private var headerTrailingActions: some View {
        if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
            OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            if Defaults[.showMirror] {
                Button(action: {
                    vm.toggleCameraPreview()
                }) {
                    Capsule()
                        .fill(.black)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: "web.camera")
                                .foregroundColor(.white)
                                .padding()
                                .imageScale(.medium)
                        }
                }
                .buttonStyle(PlainButtonStyle())
            }
            if Defaults[.settingsIconInNotch] {
                Button(action: {
                    withAnimation(.smooth) {
                        coordinator.currentView =
                            coordinator.currentView == .settings ? .home : .settings
                    }
                }) {
                    Capsule()
                        .fill(.black)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: coordinator.currentView == .settings ? "xmark" : "gear")
                                .foregroundColor(.white)
                                .padding()
                                .imageScale(.medium)
                        }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    Header().environmentObject(ViewModel())
}