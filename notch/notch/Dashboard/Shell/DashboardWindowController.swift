//
//  DashboardWindowController.swift
//  Perch
//
//  Owns the standalone Daily Dashboard window: a standard, resizable application
//  window (title bar + traffic-light controls) whose content is backed by an
//  NSVisualEffectView, so the warm cream background reads as "somewhat opaque" with
//  the desktop blurring faintly behind it. Hosts `DashboardView`.
//
//  The title bar is transparent and the content fills under it (full-size content
//  view), so the gradient flows behind the traffic lights — a normal modern-Mac
//  window, just chromeless on top.
//
//  Opened on demand from the notch Home tab's "Dashboard" button: that button
//  posts `.perchShowDashboard`, which CompanionAppDelegate observes and forwards
//  to `show()`. The delegate owns this controller's lifecycle.
//

import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController {

    private var dashboardWindow: NSWindow?

    /// Default window size. The content column caps at 1080pt; the extra width is
    /// breathing room so cards aren't flush to the window edge.
    private let defaultWindowSize = NSSize(width: 1180, height: 840)

    /// Smallest the user can shrink the window before content gets cramped.
    private let minimumWindowSize = NSSize(width: 760, height: 560)

    // MARK: Presentation

    /// Builds the window if needed, brings it to front, and (when explicitly opening the
    /// board) re-centers it and replays the opening greeting splash.
    ///
    /// `replayGreeting` distinguishes the two callers:
    ///  • `true` (default) — the user explicitly opened the dashboard (notch button), so
    ///    an already-built window re-centers and replays the greeting, like a fresh open.
    ///  • `false` — we are only REVEALING the board so a widget the agent just created/
    ///    edited is visible. An already-open window is left exactly where the user put it
    ///    and the greeting does NOT replay, so landing a widget doesn't look like the
    ///    dashboard "restarting". (A first-ever open still builds a fresh window, which
    ///    plays its greeting once from its initial state — that's a genuine first open.)
    func show(replayGreeting: Bool = true) {
        if let existingWindow = dashboardWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            guard replayGreeting else { return }
            existingWindow.center()
            // Re-arm the opening greeting splash on each re-open of an existing window
            // (a fresh window plays it from its initial state — see DashboardView).
            NotificationCenter.default.post(name: .perchDashboardDidPresent, object: nil)
            return
        }

        let window = makeDashboardWindow()
        dashboardWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Hides the window without destroying it (state is preserved for re-show).
    func hide() {
        dashboardWindow?.orderOut(nil)
    }

    // MARK: Window construction

    private func makeDashboardWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Standard window chrome, but let the cream background flow under the bar.
        window.title = "Daily"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // The pegboard canvas owns empty-space drags (panning is via scroll; future
        // drag-to-pan would conflict with window-background dragging), so don't let a
        // drag on the canvas move the whole window.
        window.isMovableByWindowBackground = false
        window.minSize = minimumWindowSize

        // Translucent background: the window itself is non-opaque so the
        // NSVisualEffectView content can blur the desktop behind it.
        window.isOpaque = false
        window.backgroundColor = .clear
        // Closing should hide, not deallocate, so we can re-show the same window.
        window.isReleasedWhenClosed = false

        window.contentView = makeContentView()
        return window
    }

    /// The window's content: a blur layer (behind-window vibrancy) with the SwiftUI
    /// dashboard hosted on top.
    private func makeContentView() -> NSView {
        let blurView = NSVisualEffectView()
        // `.hudWindow` is Apple's dark, heavily-tinted HUD glass (the volume OSD /
        // Control Center look). The MATERIAL carries the tint + blur — we layer only
        // a thin scrim on top (see DashboardView), never an opaque fill, so the
        // desktop genuinely blurs through instead of flattening to grey.
        blurView.material = .hudWindow
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        // Force dark appearance so the material renders as dark smoked glass
        // regardless of the system's light/dark setting.
        blurView.appearance = NSAppearance(named: .darkAqua)

        let hostingView = NSHostingView(rootView: DashboardView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        blurView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: blurView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: blurView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: blurView.bottomAnchor)
        ])

        return blurView
    }
}

extension Notification.Name {
    /// Posted by `DashboardWindowController.show()` each time an already-built dashboard
    /// window is re-shown, so `DashboardView` can replay the opening greeting splash.
    /// Defined here (a dashboard file) rather than alongside the notch notifications so
    /// the dashboard files stay self-contained for the standalone preview harness.
    static let perchDashboardDidPresent = Notification.Name("perchDashboardDidPresent")
}
