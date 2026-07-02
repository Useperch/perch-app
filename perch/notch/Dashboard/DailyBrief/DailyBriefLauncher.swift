//
//  DailyBriefLauncher.swift
//  notch
//
//  The single entry point for opening the redesigned Daily Brief page. It holds the window
//  controller so the window (and its loaded brief) survives between opens. Both triggers —
//  the closed-notch "Daily Brief" pill and the swipe-down gesture on the open notch — call
//  `open()`.
//
//  The legacy pegboard dashboard's `DashboardLauncher` is intentionally left intact but no
//  longer wired to a trigger, so the two surfaces can be compared until the old one is removed.
//

import AppKit

@MainActor
enum DailyBriefLauncher {
    private static var controller: DailyBriefWindowController?

    static func open() {
        if controller == nil {
            controller = DailyBriefWindowController()
        }
        // notch is a menu-bar/notch app, so bring it forward to surface the window.
        NSApp.activate(ignoringOtherApps: true)
        controller?.show()
    }
}
