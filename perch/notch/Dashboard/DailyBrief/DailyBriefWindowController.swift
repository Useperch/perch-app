//
//  DailyBriefWindowController.swift
//  notch
//
//  Owns the standalone Daily Brief window: a light, resizable application window whose
//  content is the editorial `DailyBriefView` on a clean white page. Unlike the legacy
//  pegboard dashboard (dark vibrancy glass), this is an opaque light surface — the brief
//  reads like a printed page, so it forces a light appearance regardless of the system theme.
//
//  The title bar is transparent and the content fills under it, so the page flows behind
//  the traffic-light controls. Closing hides (does not destroy) the window so re-opening is
//  instant and preserves the loaded brief.
//

import AppKit
import SwiftUI

@MainActor
final class DailyBriefWindowController {

    private var briefWindow: NSWindow?

    /// A comfortable reading size for the single-column page.
    private let defaultWindowSize = NSSize(width: 1140, height: 1060)
    private let minimumWindowSize = NSSize(width: 940, height: 760)

    /// Builds the window if needed and brings it to front, re-centering an already-built
    /// window so an explicit open feels like a fresh present.
    func show() {
        if let existingWindow = briefWindow {
            existingWindow.center()
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = makeWindow()
        briefWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Hides the window without destroying it (state preserved for re-show).
    func hide() {
        briefWindow?.orderOut(nil)
    }

    // MARK: Window construction

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Daily Brief"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = minimumWindowSize
        // A printed-page light surface — force light so the warm white never inverts.
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(white: 0.992, alpha: 1.0)
        // Closing should hide, not deallocate, so we can re-show the same window.
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: DailyBriefView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        let containerView = NSView()
        containerView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        window.contentView = containerView
        return window
    }
}
