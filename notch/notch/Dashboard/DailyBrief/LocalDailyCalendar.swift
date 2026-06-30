//
//  LocalDailyCalendar.swift
//  notch
//
//  The local-calendar fallback for the Daily Brief's agenda. When the cloud `.calendar`
//  provider (Composio) has no connected account, the brief reads today's events straight
//  from the macOS Calendar (EventKit) instead — so a user whose Google/iCloud calendars
//  live in Calendar.app still sees a real agenda with no extra setup.
//
//  It reuses the app's existing `CalendarService` (the same full-access request + event
//  fetch the notch calendar uses) and maps each `EventModel` into the SAME
//  `DashboardWidgetItem` shape the cloud provider returns, so the brief's agenda mapping
//  and the Claude synthesis consume one uniform item type regardless of the source.
//

import EventKit
import Foundation

@MainActor
enum LocalDailyCalendar {

    /// Today's local calendar events as widget items, ordered by the underlying service
    /// (start ascending). Returns `[]` when Calendar access isn't granted or the day is
    /// clear — never throws, so the caller degrades to a quiet empty agenda.
    ///
    /// On first use, if access is undetermined, this requests it (the app already declares
    /// the Calendar entitlement + usage strings), so the user sees the system prompt once
    /// and the agenda fills in on grant. If access was denied, it stays empty (no prompt).
    static func todaysEvents(for date: Date = Date()) async -> [DashboardWidgetItem] {
        guard await ensureReadAccess() else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        // Empty `calendars` means "all calendars". Only event entities are returned here:
        // reminder access is never requested, so `CalendarService` won't include reminders.
        let events = await calendarService.events(from: startOfDay, to: endOfDay, calendars: [])

        return events.map { event in
            DashboardWidgetItem(
                id: event.id,
                title: event.title,
                subtitle: (event.location?.isEmpty == false) ? event.location : nil,
                // All-day events carry no meaningful time, so they render as "All day" and
                // sort to the top — match the cloud provider by dropping their timestamp.
                timestamp: event.isAllDay ? nil : event.start
            )
        }
    }

    /// A fresh service per call (it holds an `EKEventStore`); cheap and avoids shared state.
    private static var calendarService: CalendarService { CalendarService() }

    /// True once we hold read access to events. Requests it once when undetermined; returns
    /// `false` for denied/restricted (so we never re-prompt a user who said no).
    private static func ensureReadAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            if status == .fullAccess { return true }
        } else {
            if status == .authorized { return true }
        }
        guard status == .notDetermined else { return false }
        return (try? await calendarService.requestAccess(to: .event)) ?? false
    }
}
