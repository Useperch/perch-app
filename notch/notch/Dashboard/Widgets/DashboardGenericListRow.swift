//
//  DashboardGenericListRow.swift
//  leanring-buddy
//
//  One tappable row inside a data-driven widget (an email, a calendar event, a news
//  headline). Styled to match the bespoke "Needs you" rows — a serif title line with a
//  trailing timestamp, and a sans-serif summary beneath. Clicking a row that carries a
//  URL opens it (the same target the agent uses for "open the top headline").
//

import AppKit
import SwiftUI

struct DashboardGenericListRow: View {
    let item: DashboardWidgetItem
    /// Called when the row is clicked. The list view supplies this so it can also log
    /// the interaction for ranking (Wave 5); the default just opens the URL.
    var onActivate: (DashboardWidgetItem) -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            onActivate(item)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(item.title)
                        .font(DashboardTheme.Fonts.serif(size: 18, weight: .medium))
                        .foregroundColor(DashboardTheme.Colors.textPrimary)
                        // Short headline summaries can run past a narrow card's width;
                        // allow a second line so they read cleanly instead of clipping
                        // to "…".
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let timestampLabel {
                        Text(timestampLabel)
                            .font(DashboardTheme.Fonts.sans(size: 12))
                            .foregroundColor(DashboardTheme.Colors.textTertiary)
                    }
                }

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DashboardTheme.Fonts.sans(size: 14))
                        .foregroundColor(DashboardTheme.Colors.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 0.7 : 1.0)
        .onHover { hovering in
            isHovering = hovering
            // A clickable row that opens something gets the pointer cursor; an inert
            // row (no URL) keeps the canvas's default.
            if hovering && item.url != nil {
                NSCursor.pointingHand.push()
            } else if !hovering {
                NSCursor.pop()
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    /// A short clock label for the row's timestamp, if present.
    private var timestampLabel: String? {
        guard let timestamp = item.timestamp else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: timestamp)
    }
}
