//
//  DailyBriefModel.swift
//  notch
//
//  Value types for the redesigned Daily Brief — a fixed, magazine-style page (title
//  card → summary → catch-up / priorities → calendar → news + comic). These are the
//  shaped, view-ready structures the `DailyBriefViewModel` publishes; the raw provider
//  payloads (`DashboardWidgetItem`) are mapped into these before they reach the view.
//
//  Per the project's immutability rule these are plain value types — the view model
//  replaces them wholesale rather than mutating in place.
//

import AppKit

/// The Claude-synthesized prose of the brief: the one/two-line summary, the morning
/// catch-up triage bullets, and today's priority checklist. Produced by
/// `DailyBriefGenerator` from the day's email / Slack / calendar context.
struct DailyBriefSynthesis: Equatable {
    /// One or two warm, present-tense sentences capturing the shape of the day.
    let summary: String
    /// Short triage bullets — what came in overnight that wants attention.
    let catchUp: [String]
    /// Actionable to-dos derived from the inbox / calendar / messages.
    let priorities: [String]

    static let empty = DailyBriefSynthesis(summary: "", catchUp: [], priorities: [])
}

/// One user-editable line in the brief's two editable lists (Catch up, Today's
/// priorities). `isChecked` is only meaningful for the priorities checklist; catch-up
/// rows ignore it. Codable so the list persists across relaunches.
struct DailyBriefItem: Identifiable, Codable, Equatable {
    let id: String
    var text: String
    var isChecked: Bool

    init(id: String = UUID().uuidString, text: String, isChecked: Bool = false) {
        self.id = id
        self.text = text
        self.isChecked = isChecked
    }
}

/// One curated painting in the daily-rotating title-card library: the asset-catalog
/// image name plus the short caption that sits beside the summary ("A calm scene for a
/// calm day"). The painting's signature is part of the artwork itself, so it is not a
/// separate field.
struct DailyBriefArtwork: Equatable {
    let imageName: String
    let caption: String
}

/// One of today's calendar events, already formatted for the timeline (e.g. "7:00 PM"
/// + "Sean's birthday bash"). `startTime` is kept for ordering and the all-day check.
struct DailyBriefCalendarEntry: Identifiable, Equatable {
    let id: String
    let timeLabel: String
    let title: String
    /// When the event starts; `nil` for all-day entries (rendered without a time).
    let startTime: Date?
}

/// One headline in the "Top news this morning" list: the AI-summarized title and its
/// click-through URL (opened with `NSWorkspace`).
struct DailyBriefHeadline: Identifiable, Equatable {
    let id: String
    let title: String
    let url: String?
}

/// The day's comic for the news section. The image is loaded once (XKCD's public API)
/// and held as an `NSImage`; `altText` is the comic's hover/caption line.
struct DailyBriefComic: Equatable {
    let title: String
    let image: NSImage
    let altText: String

    static func == (lhs: DailyBriefComic, rhs: DailyBriefComic) -> Bool {
        lhs.title == rhs.title && lhs.altText == rhs.altText
    }
}
