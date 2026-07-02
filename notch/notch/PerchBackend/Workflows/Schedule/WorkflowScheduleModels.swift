//
//  WorkflowScheduleModels.swift
//  Perch
//
//  Pure value types for "Repeat this": a saved schedule that re-runs a
//  persisted workflow playbook on a time-based trigger (hourly / daily /
//  weekly). The only non-trivial logic is `nextFireDate(after:)`, which
//  delegates to Calendar so DST and month boundaries are handled correctly.
//
//  Pure (Foundation only) so the CLI harness (scripts/check-workflow-share.sh)
//  can compile and exercise the real scheduling math.
//

import Foundation

enum WorkflowScheduleFrequency: String, Codable, CaseIterable {
    case hourly
    case daily
    case weekly
}

/// One saved repeat-trigger for a playbook. Immutable — `markingFired(at:)`
/// returns an updated copy instead of mutating.
struct WorkflowSchedule: Codable, Identifiable, Equatable {
    let id: UUID
    /// The playbook this schedule re-runs, by its on-disk slug.
    let playbookSlug: String
    /// The playbook's title, denormalized for display without a disk read.
    let playbookTitle: String
    let frequency: WorkflowScheduleFrequency
    /// Minute past the hour (hourly) or minute of `hourOfDay` (daily/weekly).
    let minute: Int
    /// 0–23. Ignored for hourly schedules.
    let hourOfDay: Int
    /// Calendar weekday units, 1 (Sunday) – 7 (Saturday). Weekly only.
    let weekday: Int?
    let createdAt: Date
    /// When the scheduler last started a run for this schedule. Due-ness is
    /// computed from this anchor, so a machine asleep through several slots
    /// fires exactly once on wake (no backfill loop).
    let lastFiredAt: Date?

    /// The next instant this schedule should fire, strictly after
    /// `referenceDate`.
    func nextFireDate(after referenceDate: Date, calendar: Calendar = .current) -> Date {
        var matchingComponents = DateComponents()
        switch frequency {
        case .hourly:
            matchingComponents.minute = minute
        case .daily:
            matchingComponents.hour = hourOfDay
            matchingComponents.minute = minute
        case .weekly:
            // Default to Monday if a weekly schedule somehow lost its weekday.
            matchingComponents.weekday = weekday ?? 2
            matchingComponents.hour = hourOfDay
            matchingComponents.minute = minute
        }
        return calendar.nextDate(
            after: referenceDate,
            matching: matchingComponents,
            matchingPolicy: .nextTime
        ) ?? referenceDate.addingTimeInterval(3600)
    }

    /// A copy with `lastFiredAt` advanced to `firedAt`.
    func markingFired(at firedAt: Date) -> WorkflowSchedule {
        WorkflowSchedule(
            id: id,
            playbookSlug: playbookSlug,
            playbookTitle: playbookTitle,
            frequency: frequency,
            minute: minute,
            hourOfDay: hourOfDay,
            weekday: weekday,
            createdAt: createdAt,
            lastFiredAt: firedAt
        )
    }

    /// "every hour at :15" / "every day at 9:00 AM" / "every Monday at 9:00 AM"
    /// — shown in the schedule surface's confirmation line.
    var humanReadableDescription: String {
        switch frequency {
        case .hourly:
            return String(format: "every hour at :%02d", minute)
        case .daily:
            return "every day at \(formattedTimeOfDay)"
        case .weekly:
            return "every \(weekdayName) at \(formattedTimeOfDay)"
        }
    }

    private var formattedTimeOfDay: String {
        let isMorning = hourOfDay < 12
        var displayHour = hourOfDay % 12
        if displayHour == 0 { displayHour = 12 }
        return String(format: "%d:%02d %@", displayHour, minute, isMorning ? "AM" : "PM")
    }

    private var weekdayName: String {
        let weekdayNames = [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
        ]
        let weekdayIndex = (weekday ?? 2) - 1
        guard weekdayNames.indices.contains(weekdayIndex) else { return "Monday" }
        return weekdayNames[weekdayIndex]
    }
}
