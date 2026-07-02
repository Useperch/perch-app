//
//  DashboardWidgetKind.swift
//  Perch
//
//  The catalog of widgets that can sit on the Daily Dashboard pegboard canvas.
//  Each case knows how to build its content view, whether it wears card chrome,
//  and its default / minimum footprint (measured in pegboard cells).
//
//  This is the seam between the *layout* (a `DashboardCanvasItem` only stores a
//  `kind` raw value + grid position/span) and the *content* (the existing
//  `Dashboard*Widget` views). Keeping the mapping here means the persisted layout
//  is just small Codable values — no views are serialized.
//
//  This enum now carries only *metadata* (chrome + footprint). The bespoke views are
//  constructed by `DashboardWidgetHost`, which injects each one's dependencies (the live
//  widget for data-bound builtins, the content row span for reflow, and the local
//  state/focus models via the environment).
//

import SwiftUI

/// A widget that can be placed on the dashboard canvas. The raw value is the
/// stable identifier persisted in `dashboard-layout.json`.
enum DashboardWidgetKind: String, Codable, CaseIterable {
    case greeting
    case weather
    case needsYou
    case today
    case focus
    case notes
    case dailyBrief

    /// The header sits directly on the glass (no card); every other widget brings
    /// its own `DashboardWidgetCard`. Either way the host never wraps it again —
    /// this flag only drives the drag shadow + resize-handle styling.
    var wearsCardChrome: Bool {
        switch self {
        case .greeting, .weather, .dailyBrief: return false
        default: return true
        }
    }

    /// Default footprint in pegboard cells `(columns, rows)` when first seeded.
    var defaultSpan: (columns: Int, rows: Int) {
        switch self {
        case .greeting:    return (7, 3)
        case .weather:     return (3, 2)
        case .needsYou:    return (6, 4)
        case .today:       return (3, 4)
        case .focus:       return (3, 4)
        case .notes:       return (6, 2)
        case .dailyBrief:  return (10, 5)
        }
    }

    /// Smallest footprint the user can shrink the widget to (so content stays legible).
    var minimumSpan: (columns: Int, rows: Int) {
        switch self {
        case .greeting:    return (4, 2)
        case .weather:     return (2, 2)
        case .needsYou:    return (4, 3)
        case .today:       return (2, 3)
        case .focus:       return (2, 3)
        case .notes:       return (3, 2)
        case .dailyBrief:  return (6, 3)
        }
    }
}
