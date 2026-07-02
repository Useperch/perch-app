//
//  DashboardRowLink.swift
//  Perch
//
//  Makes a widget row open its real source when clicked — an email row opens the actual
//  Gmail thread, a calendar row opens the event, and so on. Centralizing the tap + hover
//  affordance here keeps every list-like widget activating its rows identically (matching
//  `DashboardGenericListRow`): a pointer cursor + a subtle dim on hover, and a click that
//  opens the destination in the user's default app.
//
//  A row whose item carries no destination URL stays inert — no button, default cursor —
//  so a row with nothing to open never looks falsely clickable.
//

import AppKit
import SwiftUI

/// Wraps a widget row in a click-to-open affordance when it has a destination URL.
struct DashboardRowLink: ViewModifier {
    /// The source to open when the row is clicked (e.g. an email's Gmail link). A `nil`
    /// or unparseable string leaves the row inert.
    let destinationURLString: String?

    @State private var isHovering = false

    func body(content: Content) -> some View {
        if let destinationURL = destinationURLString.flatMap(URL.init(string:)) {
            Button {
                NSWorkspace.shared.open(destinationURL)
            } label: {
                content
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Match the generic list row's hover feedback so every clickable row reads the
            // same: a slight dim plus the pointer cursor that signals it opens something.
            .opacity(isHovering ? 0.7 : 1.0)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
        } else {
            content
        }
    }
}

extension View {
    /// Make this widget row open `destinationURLString` (the item's real source) when
    /// clicked. Inert when the string is `nil`/unparseable.
    func dashboardRowLink(opening destinationURLString: String?) -> some View {
        modifier(DashboardRowLink(destinationURLString: destinationURLString))
    }
}
