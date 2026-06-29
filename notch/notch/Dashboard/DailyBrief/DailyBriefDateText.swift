//
//  DailyBriefDateText.swift
//  notch
//
//  The Daily Brief's date + weekday strings, in one place so the title card and any
//  other surface always render them identically. Computed live from the current date so
//  they stay correct across the day on a long-lived window.
//

import Foundation

enum DailyBriefDateText {

    /// The weekday for the title, e.g. "Sunday" (drives "Your Sunday Brief").
    static func weekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    /// The header date with an ordinal day suffix, e.g. "June 28th, 2026".
    static func ordinalDateLine(for date: Date) -> String {
        let calendar = Calendar.current
        let dayOfMonth = calendar.component(.day, from: date)

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        let monthName = monthFormatter.string(from: date)

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let year = yearFormatter.string(from: date)

        return "\(monthName) \(dayOfMonth)\(ordinalSuffix(for: dayOfMonth)), \(year)"
    }

    /// The English ordinal suffix for a day-of-month (1 → "st", 2 → "nd", 11 → "th", …).
    private static func ordinalSuffix(for dayOfMonth: Int) -> String {
        // 11th, 12th, 13th are special-cased — they take "th" despite ending in 1/2/3.
        let isTeen = (11...13).contains(dayOfMonth % 100)
        if isTeen { return "th" }
        switch dayOfMonth % 10 {
        case 1:  return "st"
        case 2:  return "nd"
        case 3:  return "rd"
        default: return "th"
        }
    }
}
