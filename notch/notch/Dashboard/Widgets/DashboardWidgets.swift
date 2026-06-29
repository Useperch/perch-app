//
//  DashboardWidgets.swift
//  leanring-buddy
//
//  The bespoke content views for the Daily Dashboard's builtin widgets. Each keeps its
//  hand-built look but is wired to real data — never fabricated sample content:
//
//  • Needs you / Today render the widget's live `cachedItems` (priority mail / agenda),
//    reflowing to show more rows as the card grows — the same behavior as the news list
//    widget (`DashboardContentFit`). When there's no live data they show a quiet empty
//    state ("Gathering…" before the first fetch, then a real "all clear" message), never
//    invented rows.
//  • Notes is backed by `DashboardLocalStore` — the user's own editable, persisted text.
//  • Focus is a real countdown timer (`DashboardFocusModel`).
//
//  Layout and copy still mirror the design source (Daily.dc.html).
//

import AppKit
import SwiftUI

// MARK: - Shared empty state

/// The quiet placeholder shown by a data-bound builtin (Needs you / Today) when it has no
/// live items — so a slow or settled-but-empty fetch reads as intentional, never broken,
/// and never as fabricated rows. Matches the generic list widget's empty-state styling.
struct DashboardWidgetEmptyState: View {
    let message: String

    var body: some View {
        Text(message)
            .font(DashboardTheme.Fonts.sans(size: 13.5))
            .foregroundColor(DashboardTheme.Colors.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Gathering the latest…" before the first fetch lands, then the widget's own
    /// settled message (e.g. "Inbox is clear.") once a refresh has completed with no items.
    static func message(lastRefreshed: Date?, settledMessage: String) -> String {
        lastRefreshed == nil ? "Gathering the latest…" : settledMessage
    }
}

// MARK: - Needs you (priority emails) — live, reflows by height

struct DashboardNeedsYouWidget: View {
    let widget: DashboardWidget
    @ObservedObject var widgetStore: DashboardWidgetStore
    /// The card's live height in pegboard cells; more height surfaces more mail.
    var contentRowSpan: Int = DashboardWidgetSource.builtinNeedsYou.defaultSpan.rows

    /// One row's display fields, derived from either a live item or a sample fixture.
    private struct MailRow: Identifiable {
        let id: String
        let sender: String
        let time: String
        let summary: String
        /// The Gmail link for this message, so clicking the row opens the actual email.
        let destinationURLString: String?
    }

    /// Resolve the freshest widget copy (a passed-in value may be a frame behind a fetch).
    private var liveWidget: DashboardWidget {
        widgetStore.widget(for: widget.id) ?? widget
    }

    /// Live mail mapped to rows. Empty when the widget has no live items — the view shows
    /// a quiet empty state rather than inventing rows.
    private var allRows: [MailRow] {
        // The email provider maps subject → title and sender → subtitle; show the sender
        // prominently (matching the original design) with the subject as the summary line.
        liveWidget.cachedItems.map { item in
            MailRow(
                id: item.id,
                sender: (item.subtitle?.isEmpty == false ? item.subtitle! : item.title),
                time: Self.clockLabel(for: item.timestamp),
                summary: item.title,
                destinationURLString: item.url
            )
        }
    }

    private var visibleRows: [MailRow] {
        Array(allRows.prefix(Self.rowsThatFit(inRowSpan: contentRowSpan)))
    }

    var body: some View {
        DashboardWidgetCard {
            VStack(alignment: .leading, spacing: 0) {
                DashboardWidgetHeader(systemIconName: "envelope", title: "Needs you")
                    .padding(.bottom, 26)

                if visibleRows.isEmpty {
                    DashboardWidgetEmptyState(
                        message: DashboardWidgetEmptyState.message(
                            lastRefreshed: liveWidget.lastRefreshed, settledMessage: "Inbox is clear."
                        )
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, mailRow in
                            emailRow(mailRow)
                            if index < visibleRows.count - 1 {
                                Rectangle()
                                    .fill(DashboardTheme.Colors.divider)
                                    .frame(height: 1)
                                    .padding(.vertical, 20)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private func emailRow(_ mailRow: MailRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(mailRow.sender)
                    .font(DashboardTheme.Fonts.serif(size: 18, weight: .medium))
                    .foregroundColor(DashboardTheme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !mailRow.time.isEmpty {
                    Text(mailRow.time)
                        .font(DashboardTheme.Fonts.sans(size: 12))
                        .foregroundColor(DashboardTheme.Colors.textTertiary)
                }
            }
            Text(mailRow.summary)
                .font(DashboardTheme.Fonts.sans(size: 14))
                .foregroundColor(DashboardTheme.Colors.textSecondary)
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dashboardRowLink(opening: mailRow.destinationURLString)
    }

    /// How many mail rows fit at the current height (serif sender + sans summary, with a
    /// 20pt-padded divider between rows).
    private static func rowsThatFit(inRowSpan rowSpan: Int) -> Int {
        DashboardContentFit.rowsThatFit(
            inRowSpan: rowSpan,
            rowHeight: 22 + 5 + 18,
            dividerHeight: 1 + 20 * 2,
            headerBlockHeight: 16 + 26
        )
    }

    /// A short `h:mm` clock label for a row's timestamp, or empty when there isn't one.
    private static func clockLabel(for timestamp: Date?) -> String {
        guard let timestamp else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Today (agenda) — live, reflows by height

struct DashboardTodayWidget: View {
    let widget: DashboardWidget
    @ObservedObject var widgetStore: DashboardWidgetStore
    var contentRowSpan: Int = DashboardWidgetSource.builtinToday.defaultSpan.rows

    private struct AgendaRow: Identifiable {
        let id: String
        let startTime: String
        let title: String
        /// The calendar event link, so clicking the row opens the actual event.
        let destinationURLString: String?
    }

    private var liveWidget: DashboardWidget {
        widgetStore.widget(for: widget.id) ?? widget
    }

    /// Live agenda mapped to rows. Empty when the widget has no live events — the view
    /// shows a quiet empty state rather than inventing rows.
    private var allRows: [AgendaRow] {
        // The calendar provider maps event summary → title and the start time → subtitle.
        liveWidget.cachedItems.map { item in
            AgendaRow(
                id: item.id,
                startTime: Self.startLabel(for: item),
                title: item.title,
                destinationURLString: item.url
            )
        }
    }

    private var visibleRows: [AgendaRow] {
        Array(allRows.prefix(Self.rowsThatFit(inRowSpan: contentRowSpan)))
    }

    var body: some View {
        DashboardWidgetCard(horizontalPadding: 28) {
            VStack(alignment: .leading, spacing: 0) {
                DashboardWidgetHeader(systemIconName: "calendar", title: "Today")
                    .padding(.bottom, 26)

                if visibleRows.isEmpty {
                    DashboardWidgetEmptyState(
                        message: DashboardWidgetEmptyState.message(
                            lastRefreshed: liveWidget.lastRefreshed, settledMessage: "Nothing scheduled today."
                        )
                    )
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(visibleRows) { agendaRow in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(agendaRow.startTime)
                                    .font(DashboardTheme.Fonts.serif(size: 15, weight: .medium))
                                    .foregroundColor(DashboardTheme.Colors.agendaTimeMuted)
                                Text(agendaRow.title)
                                    .font(DashboardTheme.Fonts.sans(size: 14.5))
                                    .foregroundColor(DashboardTheme.Colors.textBody)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .dashboardRowLink(opening: agendaRow.destinationURLString)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// Agenda rows (time + title) are spaced 24pt apart with no divider rule.
    private static func rowsThatFit(inRowSpan rowSpan: Int) -> Int {
        DashboardContentFit.rowsThatFit(
            inRowSpan: rowSpan,
            rowHeight: 19 + 3 + 18,
            dividerHeight: 24,
            headerBlockHeight: 16 + 26
        )
    }

    /// Prefer a formatted clock time from the event's timestamp; fall back to the
    /// provider's start-time string.
    private static func startLabel(for item: DashboardWidgetItem) -> String {
        if let timestamp = item.timestamp {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: timestamp)
        }
        return item.subtitle ?? ""
    }
}

// MARK: - Focus (live countdown timer)

struct DashboardFocusWidget: View {
    @EnvironmentObject private var focusModel: DashboardFocusModel

    var body: some View {
        DashboardWidgetCard(horizontalPadding: 28) {
            VStack(alignment: .leading, spacing: 0) {
                DashboardWidgetHeader(systemIconName: "timer", title: "Focus")

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(DashboardTheme.Colors.divider, lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: focusModel.progress)
                            .stroke(
                                DashboardTheme.Colors.sage,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.3), value: focusModel.progress)
                        Text(focusModel.readout)
                            .font(DashboardTheme.Fonts.serif(size: 23, weight: .light))
                            .foregroundColor(DashboardTheme.Colors.textBody)
                            .monospacedDigit()
                    }
                    .frame(width: 100, height: 100)

                    HStack(spacing: 18) {
                        // The primary control: start ⇄ pause.
                        FocusControlButton(label: focusModel.callToActionLabel) {
                            beginOrToggleFocusSession()
                        }
                        // A quiet reset, shown once the timer has been touched.
                        if focusModel.remainingSeconds != focusModel.totalSeconds {
                            FocusControlButton(label: "Reset", isSecondary: true) {
                                focusModel.reset()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Toggle the timer, and — when this tap *begins* a fresh session (a full timer, or a
    /// restart after one finished) rather than resuming a paused one — open Apple Notes to
    /// a new note for the session. A mid-session Resume deliberately does not spawn a note.
    private func beginOrToggleFocusSession() {
        let isBeginningFreshSession = !focusModel.isRunning
            && (focusModel.remainingSeconds == focusModel.totalSeconds || focusModel.remainingSeconds == 0)
        focusModel.toggle()
        if isBeginningFreshSession {
            DashboardFocusNotesLauncher.openNewFocusNote()
        }
    }
}

/// A small text button for the Focus widget's controls, with the dashboard's pointer-on-
/// hover convention.
private struct FocusControlButton: View {
    let label: String
    var isSecondary: Bool = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(DashboardTheme.Fonts.sans(size: 13, weight: .semibold))
                .foregroundColor(isSecondary
                                 ? DashboardTheme.Colors.textTertiary
                                 : DashboardTheme.Colors.sageCallToAction)
                .opacity(isHovering ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Notes (editable, persisted)

struct DashboardNotesWidget: View {
    @EnvironmentObject private var localStore: DashboardLocalStore
    /// Local editing buffer, committed to the store (debounced) on every change so typing
    /// stays responsive and persistence coalesces.
    @State private var draftNotes: String = ""

    var body: some View {
        DashboardWidgetCard(verticalPadding: 28) {
            VStack(alignment: .leading, spacing: 0) {
                DashboardWidgetHeader(systemIconName: "pencil.and.outline", title: "Notes")
                    .padding(.bottom, 18)

                TextEditor(text: $draftNotes)
                    .font(DashboardTheme.Fonts.serif(size: 18, weight: .light, italic: true))
                    .foregroundColor(DashboardTheme.Colors.textSecondary)
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onChange(of: draftNotes) { _, updatedNotes in
                        localStore.updateNotes(updatedNotes)
                    }
            }
        }
        // Seed the editor from the store when the widget appears (and whenever the store
        // changes from elsewhere), without clobbering the user's in-progress edit.
        .onAppear { draftNotes = localStore.notes }
        .onChange(of: localStore.notes) { _, storeNotes in
            if storeNotes != draftNotes { draftNotes = storeNotes }
        }
    }
}
