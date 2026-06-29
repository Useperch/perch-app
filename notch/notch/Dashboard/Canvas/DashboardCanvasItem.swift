//
//  DashboardCanvasItem.swift
//  leanring-buddy
//
//  The placement record for a single widget on the pegboard canvas: which widget
//  (`kind`) sits where (`gridColumn`/`gridRow`) and how big it is (`columnSpan`/
//  `rowSpan`), all measured in whole pegboard cells. These small Codable values are
//  what get persisted to `support/dashboard-layout.json` — never the views.
//
//  Everything here is immutable: edits go through `with(...)` helpers that return a
//  fresh copy (per the project's immutability rule).
//

import Foundation

/// One widget's position + size on the canvas, in pegboard-cell coordinates. The
/// *content* of the widget lives separately in a `DashboardWidget` (owned by
/// `DashboardWidgetStore`); this record only references it by `widgetID`, so multiple
/// custom widgets of the same source can each have their own placement.
struct DashboardCanvasItem: Identifiable, Codable, Equatable {
    /// Stable, content-independent identity for this placement (its own UUID string).
    let id: String
    /// Foreign key into `DashboardWidgetStore.widgets` — which widget sits here.
    let widgetID: String
    let gridColumn: Int
    let gridRow: Int
    let columnSpan: Int
    let rowSpan: Int
    /// Set true once the user drags or resizes this item, so the auto-ranking reflow
    /// (Wave 5) leaves hand-placed widgets where the user put them.
    let isPinned: Bool

    init(
        id: String = UUID().uuidString,
        widgetID: String,
        gridColumn: Int,
        gridRow: Int,
        columnSpan: Int,
        rowSpan: Int,
        isPinned: Bool = false
    ) {
        self.id = id
        self.widgetID = widgetID
        self.gridColumn = gridColumn
        self.gridRow = gridRow
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
        self.isPinned = isPinned
    }

    /// A copy moved to a new grid origin. Moving pins the item (user-placed).
    func movedTo(gridColumn newColumn: Int, gridRow newRow: Int) -> DashboardCanvasItem {
        DashboardCanvasItem(
            id: id,
            widgetID: widgetID,
            gridColumn: newColumn,
            gridRow: newRow,
            columnSpan: columnSpan,
            rowSpan: rowSpan,
            isPinned: true
        )
    }

    /// A copy resized to a new span (callers are responsible for clamping to the
    /// source's `minimumSpan` before calling). Resizing pins the item.
    func resizedTo(columnSpan newColumnSpan: Int, rowSpan newRowSpan: Int) -> DashboardCanvasItem {
        DashboardCanvasItem(
            id: id,
            widgetID: widgetID,
            gridColumn: gridColumn,
            gridRow: gridRow,
            columnSpan: newColumnSpan,
            rowSpan: newRowSpan,
            isPinned: true
        )
    }

    /// A copy resized to a new span *without* pinning — used by the expand/collapse
    /// toggle (Wave 2), which grows the card automatically rather than by user drag.
    func resizedUnpinnedTo(columnSpan newColumnSpan: Int, rowSpan newRowSpan: Int) -> DashboardCanvasItem {
        DashboardCanvasItem(
            id: id,
            widgetID: widgetID,
            gridColumn: gridColumn,
            gridRow: gridRow,
            columnSpan: newColumnSpan,
            rowSpan: newRowSpan,
            isPinned: isPinned
        )
    }

    /// The default arrangement, mirroring the dashboard's original layout: the
    /// header across the top, then Needs you · Today · Focus, then Notes spanning the
    /// bottom row. Used on first launch and whenever the saved layout is missing/unreadable.
    /// Each item's `widgetID` is the matching builtin widget's id (its `source.rawValue`),
    /// which `DashboardWidgetStore.seedBuiltinsIfEmpty()` seeds in lockstep.
    static var defaultSeedLayout: [DashboardCanvasItem] {
        [
            // Daily Brief sits at the very top — full-width hero card.
            DashboardCanvasItem(widgetID: DashboardWidgetSource.builtinDailyBrief.rawValue, gridColumn: 0, gridRow: 0, columnSpan: 12, rowSpan: 5),
            DashboardCanvasItem(widgetID: DashboardWidgetSource.builtinGreeting.rawValue,   gridColumn: 0, gridRow: 6, columnSpan: 6,  rowSpan: 3),
            DashboardCanvasItem(widgetID: DashboardWidgetSource.builtinWeather.rawValue,    gridColumn: 9, gridRow: 6, columnSpan: 3,  rowSpan: 2),
            DashboardCanvasItem(widgetID: DashboardWidgetSource.builtinNeedsYou.rawValue,   gridColumn: 0, gridRow: 10, columnSpan: 6, rowSpan: 5),
            DashboardCanvasItem(widgetID: DashboardWidgetSource.builtinToday.rawValue,      gridColumn: 6, gridRow: 10, columnSpan: 3, rowSpan: 5),
            DashboardCanvasItem(widgetID: DashboardWidgetSource.builtinFocus.rawValue,      gridColumn: 9, gridRow: 10, columnSpan: 3, rowSpan: 5),
            DashboardCanvasItem(widgetID: DashboardWidgetSource.builtinNotes.rawValue,      gridColumn: 0, gridRow: 15, columnSpan: 12, rowSpan: 3)
        ]
    }
}

/// The full persisted canvas state: every item plus the saved pan + zoom, so the
/// board reopens exactly where the user left it. Pan is stored as two Doubles
/// (rather than CGSize) to keep the JSON simple and portable.
struct DashboardLayoutSnapshot: Codable {
    var items: [DashboardCanvasItem]
    var panX: Double
    var panY: Double
    var zoom: Double

    static var defaultSnapshot: DashboardLayoutSnapshot {
        // A small top-left margin so the seeded content isn't flush to the window
        // corner at the default zoom.
        DashboardLayoutSnapshot(
            items: DashboardCanvasItem.defaultSeedLayout,
            panX: 62,
            panY: 40,
            zoom: Double(DashboardTheme.Metrics.defaultZoom)
        )
    }
}
