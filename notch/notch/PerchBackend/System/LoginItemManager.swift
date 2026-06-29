//
//  LoginItemManager.swift
//  leanring-buddy
//
//  Single source of truth for whether Perch launches at login. Wraps
//  `SMAppService.mainApp` (the modern macOS login-item API, shown in System
//  Settings > General > Login Items) so the Settings toggle and the app's
//  first-run default both go through one place and never fight each other.
//

import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    /// Whether Perch is currently registered to launch at login, mirrored from
    /// the live `SMAppService` status.
    @Published private(set) var isEnabled: Bool

    /// Records that the user has explicitly chosen a login-item state, so the
    /// first-run auto-register never overrides their choice on a later launch.
    private static let userConfiguredDefaultsKey = "perch.loginItem.userConfigured"

    init() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    /// Re-reads the live status (the user may have toggled the login item in
    /// System Settings outside the app).
    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    /// Turns launch-at-login on or off, persisting that the user made an explicit
    /// choice so `reconcileFirstRunDefault()` stops auto-registering afterward.
    func setEnabled(_ shouldEnable: Bool) {
        let loginItemService = SMAppService.mainApp
        do {
            if shouldEnable {
                try loginItemService.register()
            } else {
                try loginItemService.unregister()
            }
            UserDefaults.standard.set(true, forKey: Self.userConfiguredDefaultsKey)
        } catch {
            print("⚠️ Perch: failed to \(shouldEnable ? "register" : "unregister") login item: \(error)")
        }
        refresh()
    }

    /// Called once at launch. On the very first run — before the user has made any
    /// explicit choice — register Perch as a login item so it starts on boot by
    /// default. After the user has toggled it in Settings, this no-ops so their
    /// choice wins.
    func reconcileFirstRunDefault() {
        let userHasConfiguredLoginItem = UserDefaults.standard.bool(forKey: Self.userConfiguredDefaultsKey)
        guard !userHasConfiguredLoginItem else {
            refresh()
            return
        }

        if SMAppService.mainApp.status != .enabled {
            do {
                try SMAppService.mainApp.register()
                print("🎯 Perch: registered as login item (first-run default)")
            } catch {
                print("⚠️ Perch: failed to register as login item: \(error)")
            }
        }
        refresh()
    }
}
