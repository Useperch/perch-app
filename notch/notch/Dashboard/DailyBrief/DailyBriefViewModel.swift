//
//  DailyBriefViewModel.swift
//  notch
//
//  Drives the Daily Brief page. The title-card facts (name, date, weekday, artwork) are
//  computed locally; the body content is currently curated SAMPLE data
//  (`DailyBriefSampleData`) so the page always reads well while we dial in the look. The
//  comic is still fetched live (XKCD) because it's reliable and adds a real daily touch.
//
//  To go back to live data, swap the sample assignments in `populate()` for the live path
//  (parallel `DashboardDataService.shared.fetch(plan:)` for email/calendar/news + a
//  `DailyBriefGenerator` Claude call for the prose). That live pipeline is retained in
//  `DailyBriefGenerator.swift` for when we flip it back on.
//

import SwiftUI

@MainActor
final class DailyBriefViewModel: ObservableObject {

    // MARK: Instant, local facts (the title card renders from these immediately)

    @Published private(set) var firstName: String
    @Published private(set) var weekdayName: String
    @Published private(set) var dateLine: String
    @Published private(set) var artwork: DailyBriefArtwork

    // MARK: Body content (sample for now; comic is live)

    @Published private(set) var synthesis: DailyBriefSynthesis?
    @Published private(set) var isSynthesizing = false
    /// Unused in sample mode (the live catch-up fallback); kept so the view API is stable.
    @Published private(set) var emails: [DashboardWidgetItem] = []
    @Published private(set) var calendarEntries: [DailyBriefCalendarEntry] = []
    @Published private(set) var headlines: [DailyBriefHeadline] = []
    @Published private(set) var comic: DailyBriefComic?

    @Published private(set) var isLoadingCalendar = false
    @Published private(set) var isLoadingNews = false

    private var hasLoaded = false

    init(date: Date = Date()) {
        self.firstName = DashboardGreetingText.accountFirstName
        self.weekdayName = DailyBriefDateText.weekdayName(for: date)
        self.dateLine = DailyBriefDateText.ordinalDateLine(for: date)
        self.artwork = DailyBriefArtworkLibrary.artwork(for: date)
        populate()
    }

    /// Fill the body from the curated sample set. Synchronous — the page is fully
    /// populated the instant it appears. (The Catch-up / Priorities lists are owned by the
    /// editable `DailyBriefStore`, which seeds itself from the same sample on first launch.)
    private func populate() {
        synthesis = DailyBriefSynthesis(
            summary: DailyBriefSampleData.summary,
            catchUp: [],
            priorities: []
        )
        calendarEntries = DailyBriefSampleData.calendar
        headlines = DailyBriefSampleData.headlines
    }

    /// Fetch the live elements once: today's comic, and real, diverse news headlines (so
    /// clicking a headline opens the actual article). News falls back to the sample set if
    /// the live provider has nothing.
    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        Task { comic = await DailyComicService.fetchTodaysComic() }
        Task { await loadLiveNews() }
    }

    /// One real headline per topic, fetched concurrently, so the news reads as a diverse
    /// spread of the morning with each item linking to its actual article.
    private func loadLiveNews() async {
        isLoadingNews = true
        async let tech = Self.topHeadline(query: "latest technology news today")
        async let world = Self.topHeadline(query: "top world news today")
        async let markets = Self.topHeadline(query: "stock market news today")
        async let science = Self.topHeadline(query: "science news today")
        async let sports = Self.topHeadline(query: "sports news today")
        let liveHeadlines = await [tech, world, markets, science, sports].compactMap { $0 }
        // Only replace the sample if we actually got live, linkable results.
        if !liveHeadlines.isEmpty {
            headlines = liveHeadlines
        }
        isLoadingNews = false
    }

    /// Fetch the single top web-news result for a topic, keeping only items that carry a
    /// real article URL (so the headline is clickable through to the source).
    private static func topHeadline(query: String) async -> DailyBriefHeadline? {
        let plan = DashboardWidgetFetchPlan(
            provider: .webNews, query: query, limit: 3, refreshCadenceSeconds: 0
        )
        let items = await DashboardDataService.shared.fetch(plan: plan)
        guard let item = items.first(where: { !($0.url ?? "").isEmpty }) else { return nil }
        return DailyBriefHeadline(id: item.url ?? item.id, title: item.title, url: item.url)
    }
}
