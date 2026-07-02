//
//  DashboardWidgetModel.swift
//  Perch
//
//  The dynamic widget data model that turns the Daily Dashboard from a fixed set of
//  bespoke widgets into a list of user-addable, data-driven widgets. A `DashboardWidget`
//  carries its own identity, the plain-English description the user typed, where its
//  data comes from (`source`), how to fetch it (`fetchPlan`), and the last ranked items
//  it surfaced (`cachedItems`).
//
//  This is intentionally separate from the *placement* record (`DashboardCanvasItem`),
//  which only stores geometry and a `widgetID` foreign key into the widget list. One
//  widget = its content + spec + data; one canvas item = where that widget sits.
//
//  Everything here is a value type with copy-on-write update helpers (`withItems`,
//  `withExpanded`, …) per the project's immutability rule — callers never mutate a
//  widget in place; they replace it with a fresh copy in the store.
//

import Foundation

/// Where a widget's content comes from. The `builtin*` cases preserve the original
/// five bespoke widgets (rendered by `DashboardWidgetKind`); the data-driven cases
/// (`email/calendar/webNews/custom`) render through the generic list view and pull
/// live items.
enum DashboardWidgetSource: String, Codable, CaseIterable {
    case builtinGreeting
    case builtinWeather
    case builtinNeedsYou
    case builtinToday
    case builtinFocus
    case builtinNotes
    case builtinDailyBrief
    case email
    case calendar
    case webNews
    /// Posts from X (Twitter), via Composio recent search.
    case x
    /// A generic connected-app widget: the fetch plan's `query` carries a JSON
    /// `{ "slug": "<COMPOSIO_TOOL_SLUG>", "args": { ... } }` chosen by the two-stage
    /// interpreter from the live capability manifest, so the dashboard can surface ANY
    /// connected toolkit (GitHub, Sheets, Drive, …), not just the hardcoded providers.
    case composioTool
    case custom
    /// An agent-authored interactive widget: its content is a self-contained HTML/CSS/JS
    /// document (written by the sidecar's widget generator against the dashboard design
    /// tokens) rendered live in a sandboxed web view. Used for novel interactive tools (a
    /// timer, a calculator, a checklist) that have no native or data-feed home.
    case generated
    /// A just-created, not-yet-described widget: renders an in-card textbox the user
    /// types their description into, then transforms into a real data-driven widget.
    case draft

    /// The legacy bespoke `DashboardWidgetKind` for builtin sources; `nil` for
    /// data-driven and draft sources (which don't use the old enum's views).
    var builtinKind: DashboardWidgetKind? {
        switch self {
        case .builtinGreeting:    return .greeting
        case .builtinWeather:     return .weather
        case .builtinNeedsYou:    return .needsYou
        case .builtinToday:       return .today
        case .builtinFocus:       return .focus
        case .builtinNotes:       return .notes
        case .builtinDailyBrief:  return .dailyBrief
        default:                  return nil
        }
    }

    /// True for the original bespoke widgets that render their own hand-built views.
    var isBuiltin: Bool { builtinKind != nil }

    /// True for live widgets that fetch a ranked item list (email/calendar/news/custom).
    var isDataDriven: Bool {
        switch self {
        case .email, .calendar, .webNews, .x, .composioTool, .custom: return true
        default: return false
        }
    }

    /// True while the widget is still just a textbox awaiting the user's description.
    var isDraft: Bool { self == .draft }

    /// True for web/news-backed sources whose items are a single headline with no
    /// subtitle. These render as a publisher kicker + serif headline (`DashboardNewsRow`)
    /// rather than the generic title-over-summary row, so a list of headlines reads as an
    /// attributable news feed instead of an undifferentiated wall of serif text.
    var isHeadlineOnly: Bool { self == .webNews || self == .custom }

    /// The provider key sent to the sidecar's `dashboard.fetch` RPC. `nil` when the
    /// source isn't backed by a remote fetch (greeting, focus, notes).
    ///
    /// Note this is keyed off the *data binding*, not the renderer: the bespoke
    /// `builtinWeather` widget keeps its hand-built look but pulls live conditions from
    /// the `"weather"` provider. (Needs you / Today reuse the `.email` / `.calendar`
    /// providers via their fetch plan's `provider`, so they don't need a key here.)
    var fetchProviderKey: String? {
        switch self {
        case .email:          return "email"
        case .calendar:       return "calendar"
        case .webNews:        return "webNews"
        case .x:              return "x"
        case .composioTool:   return "composio"  // generic connected-app tool (slug+args in query)
        case .custom:         return "webNews"   // generic custom widgets default to web search
        case .builtinWeather: return "weather"
        default:              return nil
        }
    }

    /// Default footprint in pegboard cells `(columns, rows)` when first placed.
    var defaultSpan: (columns: Int, rows: Int) {
        if let kind = builtinKind { return kind.defaultSpan }
        if self == .draft { return (4, 3) }
        return (4, 4)   // data-driven list widget
    }

    /// Smallest footprint the user can shrink the widget to before content clips.
    var minimumSpan: (columns: Int, rows: Int) {
        if let kind = builtinKind { return kind.minimumSpan }
        return (3, 3)
    }

    /// The header sits on the glass without card chrome; everything else wears a card.
    var wearsCardChrome: Bool {
        builtinKind?.wearsCardChrome ?? true
    }

    /// The SF Symbol shown in the generic list header.
    var headerIconName: String {
        switch self {
        case .email:    return "envelope"
        case .calendar: return "calendar"
        case .webNews:  return "newspaper"
        case .x:        return "at"
        case .composioTool: return "puzzlepiece.extension"
        case .custom:   return "sparkles"
        case .generated: return "wand.and.stars"
        default:        return "square.grid.2x2"
        }
    }
}

/// A single ranked entry inside a data-driven widget (one email, event, or headline).
/// `url` is the click target (opened with `NSWorkspace`), and the same value the agent
/// resolves against when the user says "open the top headline".
struct DashboardWidgetItem: Identifiable, Codable, Equatable {
    /// Stable per-item id — a provider id when available, else a hash of url+title — so
    /// re-fetches don't churn SwiftUI identity for unchanged items.
    let id: String
    let title: String
    let subtitle: String?
    let detail: String?
    let url: String?
    /// Relevance 0...1 produced by the ranking step; drives ordering + widget score.
    let importance: Double
    let timestamp: Date?

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        detail: String? = nil,
        url: String? = nil,
        importance: Double = 0.5,
        timestamp: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.url = url
        self.importance = importance
        self.timestamp = timestamp
    }
}

/// The plan for fetching a data-driven widget's items: which provider, the search/query
/// string, how many items, and how often to refresh. Produced once at widget creation by
/// the main agent's dashboard tool family from the user's request, then applied via
/// `DashboardAgentApplier`.
struct DashboardWidgetFetchPlan: Codable, Equatable {
    let provider: DashboardWidgetSource
    let query: String
    let limit: Int
    let refreshCadenceSeconds: Int
}

/// An agent-authored interactive widget's rendered document (for `source == .generated`):
/// a self-contained HTML string — inline CSS + JS, no external resources — that the
/// sidecar's widget generator produced from the user's request and the dashboard design
/// tokens. Stored on the widget so it persists across launches and renders instantly
/// without re-generating.
struct GeneratedWidgetDocument: Codable, Equatable {
    /// The sanitized, self-contained HTML body the sandboxed web view renders (wrapped in
    /// the design-token + CSP shell by `DashboardGeneratedWidgetChrome` at render time).
    let html: String
    /// A short title for the card; the generated body may also carry its own heading.
    let title: String
    /// When the document was generated (kept for a future "regenerate this widget").
    let generatedAt: Date
}

/// One widget on the dashboard: its identity, the description that created it, its data
/// source + fetch plan, expand state, learned importance, and the last ranked items.
struct DashboardWidget: Identifiable, Codable, Equatable {
    /// Stable widget id. Builtins use their `source.rawValue` (deterministic, so the
    /// seeded layout's `widgetID` foreign keys always resolve); custom widgets use a
    /// fresh UUID string.
    let id: String
    var title: String
    /// The plain-English spec the user typed ("most important tech news on X"). Empty
    /// for builtins.
    var naturalLanguageSpec: String
    var source: DashboardWidgetSource
    /// How to fetch live items; `nil` for builtins and routine cards.
    var fetchPlan: DashboardWidgetFetchPlan?
    /// Expanded widgets show a longer list and grow their canvas span (Wave 2).
    var expanded: Bool
    /// Learned ranking score (Wave 5); higher floats toward the top-left of the board.
    var importanceScore: Double
    var lastRefreshed: Date?
    /// The last fetched + ranked items, cached so the board renders instantly on open.
    var cachedItems: [DashboardWidgetItem]
    /// For `source == .generated`: the agent-authored HTML document rendered in a
    /// sandboxed web view. `nil` for every other source. Optional so widgets persisted
    /// before this field decode cleanly (missing key → nil).
    var generatedDocument: GeneratedWidgetDocument?

    init(
        id: String,
        title: String,
        naturalLanguageSpec: String = "",
        source: DashboardWidgetSource,
        fetchPlan: DashboardWidgetFetchPlan? = nil,
        expanded: Bool = false,
        importanceScore: Double = 0.5,
        lastRefreshed: Date? = nil,
        cachedItems: [DashboardWidgetItem] = [],
        generatedDocument: GeneratedWidgetDocument? = nil
    ) {
        self.id = id
        self.title = title
        self.naturalLanguageSpec = naturalLanguageSpec
        self.source = source
        self.fetchPlan = fetchPlan
        self.expanded = expanded
        self.importanceScore = importanceScore
        self.lastRefreshed = lastRefreshed
        self.cachedItems = cachedItems
        self.generatedDocument = generatedDocument
    }

    // MARK: Copy-on-write updates (never mutate a shared instance in place)

    func withItems(_ items: [DashboardWidgetItem], lastRefreshed: Date?) -> DashboardWidget {
        var copy = self
        copy.cachedItems = items
        copy.lastRefreshed = lastRefreshed
        return copy
    }

    func withExpanded(_ expanded: Bool) -> DashboardWidget {
        var copy = self
        copy.expanded = expanded
        return copy
    }

    func withImportance(_ score: Double) -> DashboardWidget {
        var copy = self
        copy.importanceScore = score
        return copy
    }

    // MARK: Builtin seeding

    /// Builds a builtin widget whose id is its source raw value (so the seeded layout's
    /// `widgetID` foreign keys resolve deterministically). A `fetchPlan` may be supplied
    /// for builtins that pull live data (Weather, Needs you, Today) while keeping their
    /// bespoke renderer; builtins without one (Greeting, Focus, Notes) stay local.
    static func builtin(
        _ source: DashboardWidgetSource,
        title: String,
        fetchPlan: DashboardWidgetFetchPlan? = nil
    ) -> DashboardWidget {
        DashboardWidget(id: source.rawValue, title: title, source: source, fetchPlan: fetchPlan)
    }

    /// The six builtin widgets seeded on first launch. The titles are display-only;
    /// the bespoke views carry their own copy. Weather / Needs you / Today carry a fetch
    /// plan so the shared refresh loop populates them with live data (the bespoke views
    /// render that live data, or a quiet empty state when there is none); the rest are
    /// local-only.
    static var defaultBuiltins: [DashboardWidget] {
        [
            .builtin(.builtinGreeting, title: "Greeting"),
            .builtin(
                .builtinWeather,
                title: "Weather",
                // The weather provider returns a single normalized item; refresh twice
                // an hour is plenty for conditions + the day's high/low.
                fetchPlan: DashboardWidgetFetchPlan(
                    provider: .builtinWeather, query: "", limit: 1, refreshCadenceSeconds: 1800
                )
            ),
            .builtin(
                .builtinNeedsYou,
                title: "Needs you",
                // Live priority mail via the existing Gmail (`email`) provider.
                fetchPlan: DashboardWidgetFetchPlan(
                    provider: .email, query: "is:important newer_than:7d", limit: 8,
                    refreshCadenceSeconds: 600
                )
            ),
            .builtin(
                .builtinToday,
                title: "Today",
                // Live agenda via the existing Google Calendar (`calendar`) provider.
                fetchPlan: DashboardWidgetFetchPlan(
                    provider: .calendar, query: "", limit: 8, refreshCadenceSeconds: 1800
                )
            ),
            .builtin(.builtinFocus, title: "Focus"),
            .builtin(.builtinNotes, title: "Notes"),
            .builtin(.builtinDailyBrief, title: "Daily Brief")
        ]
    }
}
