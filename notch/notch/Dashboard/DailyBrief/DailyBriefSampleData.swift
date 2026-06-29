//
//  DailyBriefSampleData.swift
//  notch
//
//  Curated sample content for the Daily Brief while we dial in the look. Everything here
//  is illustrative (not fetched live): a brief one-line overview, a short morning catch-up,
//  a genuinely-different priorities checklist, a calm sample agenda, and a DIVERSE set of
//  headlines (one per topic — not five variations of the same story).
//
//  Swapping back to live data is a one-line change in `DailyBriefViewModel` (call the live
//  fetch/synthesis path instead of reading these constants).
//

import Foundation

enum DailyBriefSampleData {

    /// A very brief, present-tense overview of the day — a rough sketch, not a report.
    static let summary = "No meetings today, Karthik — a slow Sunday. Sean's birthday dinner at 7."

    /// Morning triage: what came in worth a glance. Terse phrases.
    static let catchUp = [
        "3 new Google Alerts for your name",
        "The Daily Upside — Wall Street's space play",
        "Maya confirmed tonight's reservation"
    ]

    /// Today's to-dos — deliberately DIFFERENT from catch-up (actions, not "read X").
    static let priorities = [
        "Buy Sean's birthday gift",
        "Finish Q2 KPIs for Sara",
        "Pay the Stripe invoice — due Friday"
    ]

    /// A calm sample agenda (all-day-free times; the brief just shows the timeline).
    static let calendar: [DailyBriefCalendarEntry] = [
        DailyBriefCalendarEntry(id: "s1", timeLabel: "10:00 AM", title: "Long run along the river", startTime: nil),
        DailyBriefCalendarEntry(id: "s2", timeLabel: "1:00 PM", title: "Lunch with Mom", startTime: nil),
        DailyBriefCalendarEntry(id: "s3", timeLabel: "4:30 PM", title: "Pick up Sean's cake", startTime: nil),
        DailyBriefCalendarEntry(id: "s4", timeLabel: "7:00 PM", title: "Sean's birthday dinner", startTime: nil)
    ]

    /// Diverse headlines — one per topic (tech, markets, space, sports, climate), so the
    /// news reads as a spread of the morning rather than one story repeated. Each routes to
    /// a live Google News search for its topic, so clicking opens real, current coverage
    /// (the sample headlines are illustrative, so they link to the topic, not a fixed URL).
    static let headlines: [DailyBriefHeadline] = [
        DailyBriefHeadline(id: "h1", title: "OpenAI debuts a small model that runs fully on-device", url: newsSearchURL("OpenAI on-device small model")),
        DailyBriefHeadline(id: "h2", title: "Markets edge higher as rate-cut bets firm up", url: newsSearchURL("stock market rate cut expectations")),
        DailyBriefHeadline(id: "h3", title: "NASA greenlights a lander for Jupiter's moon Europa", url: newsSearchURL("NASA Europa lander mission")),
        DailyBriefHeadline(id: "h4", title: "City clinch the title on the final day of the season", url: newsSearchURL("Manchester City Premier League title")),
        DailyBriefHeadline(id: "h5", title: "Negotiators reach a surprise overnight climate accord", url: newsSearchURL("global climate accord agreement"))
    ]

    /// A Google News search URL for a topic, so an illustrative headline still opens real,
    /// current news about that subject.
    private static func newsSearchURL(_ query: String) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return "https://news.google.com/search?q=\(encoded)"
    }
}
