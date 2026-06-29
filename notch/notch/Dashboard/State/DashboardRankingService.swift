//
//  DashboardRankingService.swift
//  leanring-buddy
//
//  Assigns a per-item importance (0...1) to a freshly-fetched widget's items. The
//  providers already return their items in a meaningful order — Exa by relevance to
//  the query, Gmail by recency, Calendar by start time — so the reliable, zero-cost
//  ranking is to map that order onto a descending importance score. Keeping this
//  deterministic (rather than spending a Claude call on every refresh) protects the
//  "fast/cheap" bar; the cross-WIDGET ranking that learns from time-of-day and habit
//  is a separate concern handled in Wave 5 (`DashboardRankingEngine`).
//
//  The item importance produced here is the INPUT that Wave 5's engine aggregates
//  into a widget-level score, so this is the single place item relevance is decided.
//

import Foundation

@MainActor
struct DashboardRankingService {

    /// Rank fetched items: keep provider order, assign a descending importance so the
    /// first item is the most important. Returns a new array (never mutates inputs).
    static func rank(items: [DashboardWidgetItem]) -> [DashboardWidgetItem] {
        guard !items.isEmpty else { return [] }
        let count = Double(items.count)
        return items.enumerated().map { index, item in
            // Linear falloff from ~1.0 (first) toward a small floor (last), so even
            // the last item keeps a non-zero score for the Wave 5 aggregate.
            let importance = max(0.1, 1.0 - (Double(index) / count))
            return DashboardWidgetItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                detail: item.detail,
                url: item.url,
                importance: importance,
                timestamp: item.timestamp
            )
        }
    }
}
