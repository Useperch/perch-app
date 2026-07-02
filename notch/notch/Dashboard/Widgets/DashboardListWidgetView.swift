//
//  DashboardListWidgetView.swift
//  Perch
//
//  The generic, data-driven widget body used by every non-builtin widget (email,
//  calendar, web/news, and other custom widgets). It renders the widget's cached,
//  ranked items as a list inside the shared card chrome, matching the look of the
//  bespoke "Needs you" widget so a live email widget is visually indistinguishable from
//  the original mock one.
//
//  Collapsed it shows the top few items; expanded it shows more (and the canvas grows
//  the widget's span — wired in `DashboardWidgetHost`). An empty widget shows a quiet
//  placeholder rather than a blank card, so a failed/slow fetch never reads as broken.
//

import AppKit
import SwiftUI

struct DashboardListWidgetView: View {
    let widget: DashboardWidget
    /// Observed so the row list re-renders the instant a fetch updates `cachedItems`.
    @ObservedObject var widgetStore: DashboardWidgetStore
    /// The panel's pixel density, so the row dividers draw as a true single-physical-pixel
    /// hairline (`1 / displayScale` points) instead of a 1pt line that anti-aliases into a
    /// soft, uneven 2px rule on Retina.
    @Environment(\.displayScale) private var displayScale
    /// The widget's live height in pegboard cells. As the user resizes the card the
    /// host feeds the new span here, and the list shows more/fewer rows to fill it —
    /// so a bigger widget surfaces more headlines and a smaller one fewer.
    var contentRowSpan: Int = DashboardWidgetSource.webNews.defaultSpan.rows
    /// Called when a row is activated, so the host can both open the URL and log the
    /// interaction for ranking. Defaults to a plain URL open.
    var onActivateItem: (DashboardWidgetItem) -> Void = DashboardListWidgetView.openItemURL
    /// Called when the expand chevron is tapped (the host also resizes the canvas span).
    var onToggleExpanded: () -> Void = {}

    /// Resolve the freshest copy from the store (the passed-in `widget` may be a frame
    /// behind after a fetch).
    private var liveWidget: DashboardWidget {
        widgetStore.widget(for: widget.id) ?? widget
    }

    private var visibleItems: [DashboardWidgetItem] {
        Array(liveWidget.cachedItems.prefix(rowsThatFit))
    }

    /// How many rows fit at the current height, accounting for the extra line each row
    /// draws beyond its serif title. News rows (web/news) draw a small publisher kicker
    /// *above* the headline; generic rows whose items carry a subtitle draw a sans summary
    /// line *beneath* it; a plain title-only row draws neither. Sizing each correctly is
    /// what keeps the list from leaving a large empty band (over-reserving) or clipping the
    /// last row (under-reserving) as the card is resized.
    private var rowsThatFit: Int {
        Self.rowsThatFit(inRowSpan: contentRowSpan, extraRowLineHeight: rowExtraLineHeight)
    }

    /// The height a row adds beyond its single serif title line, given *these* items.
    private var rowExtraLineHeight: CGFloat {
        // News rows: a ~11pt sans kicker (~13pt line) plus the 3pt gap above the headline.
        if liveWidget.source.isHeadlineOnly { return 3 + 13 }
        // Generic rows: a ~14pt sans summary (~18pt line) plus its 5pt gap, but only when
        // the items actually carry a subtitle to render.
        let rowsRenderSummaryLine = liveWidget.cachedItems.contains { ($0.subtitle?.isEmpty == false) }
        return rowsRenderSummaryLine ? (5 + 18) : 0
    }

    var body: some View {
        DashboardWidgetCard {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 22)

                if visibleItems.isEmpty {
                    emptyState
                } else {
                    rowList
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Header (icon + title + expand chevron)

    private var header: some View {
        // Render the title block exactly as every other widget does — a bare
        // `DashboardWidgetHeader` at its natural ~16pt height — so its top sits at the
        // same place as Focus/Notes/etc. The expand chevron is a taller (22pt) hit
        // target, so it's floated as a trailing overlay (vertically centered on the
        // label) rather than placed inline: an inline chevron would inflate the header
        // row to its own height and center the shorter label inside it, dropping the
        // "TECH NEWS" label (and everything below it) lower than the other widgets'.
        DashboardWidgetHeader(
            systemIconName: liveWidget.source.headerIconName,
            title: liveWidget.title
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            expandChevron
        }
    }

    private var expandChevron: some View {
        ExpandChevronButton(isExpanded: liveWidget.expanded, onToggle: onToggleExpanded)
    }

    // MARK: Rows

    private var rowList: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                // News/web widgets render the dedicated publisher-kicker + headline row;
                // every other data-driven source uses the generic title + summary row.
                if liveWidget.source.isHeadlineOnly {
                    DashboardNewsRow(item: item, onActivate: onActivateItem)
                } else {
                    DashboardGenericListRow(item: item, onActivate: onActivateItem)
                }
                if index < visibleItems.count - 1 {
                    rowDivider
                }
            }
        }
    }

    /// A crisp full-width hairline between rows. Rendered at `1 / displayScale` points (one
    /// physical pixel) and pinned to the full content width so every separator is the same
    /// weight, instead of the soft, uneven anti-aliased rule a 1pt line produced when it
    /// landed on a fractional pixel row boundary.
    private var rowDivider: some View {
        Rectangle()
            .fill(DashboardTheme.Colors.divider)
            .frame(maxWidth: .infinity)
            .frame(height: 1.0 / displayScale)
            .padding(.vertical, 16)
    }

    private var emptyState: some View {
        Text(emptyStateMessage)
            .font(DashboardTheme.Fonts.sans(size: 13.5))
            .foregroundColor(DashboardTheme.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyStateMessage: String {
        if liveWidget.lastRefreshed == nil {
            return "Gathering the latest…"
        }
        return "Nothing to show right now."
    }

    // MARK: Responsive row count

    /// How many rows fit in a card of `rowSpan` cells, via the shared `DashboardContentFit`
    /// math so this widget and the bespoke list-like builtins reflow identically.
    ///
    /// A row is a serif title line (~22pt) plus `extraRowLineHeight` for whatever second
    /// line that source draws — a publisher kicker above (news) or a sans summary beneath
    /// (email/calendar); a plain title-only row passes `0`. Sizing the extra line correctly
    /// keeps the count from over- or under-estimating each row's height. The divider between
    /// rows is a 1pt rule with 16pt padding each side. The header block is the label
    /// (~16pt) plus the 22pt gap beneath it (see `header`).
    static func rowsThatFit(inRowSpan rowSpan: Int, extraRowLineHeight: CGFloat) -> Int {
        let titleLineHeight: CGFloat = 22
        return DashboardContentFit.rowsThatFit(
            inRowSpan: rowSpan,
            rowHeight: titleLineHeight + extraRowLineHeight,
            dividerHeight: 1 + 16 * 2,
            headerBlockHeight: 16 + 22
        )
    }

    // MARK: Default row action

    /// Opens the row's URL in the user's default app. Shared so the agent path and the
    /// row path open links identically.
    static func openItemURL(_ item: DashboardWidgetItem) {
        guard let urlString = item.url, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Expand chevron

/// A small chevron that flips between "show more" and "show less". Pointer cursor on
/// hover like every interactive element.
private struct ExpandChevronButton: View {
    let isExpanded: Bool
    let onToggle: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DashboardTheme.Colors.textTertiary)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(Color.black.opacity(isHovering ? 0.06 : 0.0))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
