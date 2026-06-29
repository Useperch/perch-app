//
//  DashboardCanvasModel.swift
//  leanring-buddy
//
//  The brain of the pegboard canvas: it owns the placed widgets, the pan offset and
//  zoom scale, and the in-flight drag/resize session. It also installs the scroll
//  monitor that turns trackpad/mouse scrolling into pan (and ⌘+scroll into zoom),
//  and debounces saves of the whole arrangement to disk.
//
//  Coordinate model — one transform, used everywhere:
//
//      screenPoint = (worldPoint + panOffset) · zoomScale     (anchor: top-left)
//
//  `worldPoint` is in points at zoom 1.0; pegs sit at integer multiples of
//  `pegSpacing`. The widget layer applies this transform with
//  `.scaleEffect(zoomScale, anchor: .topLeading).offset(panOffset · zoomScale)`,
//  and the pegboard background draws its dots with the exact same formula, so dots
//  and cards stay locked together.
//

import AppKit
import SwiftUI

extension Notification.Name {
    /// Posted to open the Daily Dashboard window (the notch Home tab's "Dashboard"
    /// button and the agent applier both post it; `CompanionAppDelegate` observes it
    /// and shows the window). Defined here, with the other dashboard notifications, so
    /// the dashboard files stay self-contained for the standalone preview harness.
    static let perchShowDashboard = Notification.Name("perchShowDashboard")
    /// Posted to REVEAL the Daily Dashboard so a widget the agent just created/edited
    /// is visible — distinct from `.perchShowDashboard` (the user explicitly opening
    /// the board). This one only ensures the window is frontmost: it does NOT re-center
    /// the window or replay the opening greeting splash, so landing a widget while the
    /// board is already open no longer looks like the dashboard "restarting". The agent
    /// applier and the dashboard-request dispatch post this; `CompanionAppDelegate`
    /// observes it and calls `show(replayGreeting: false)`.
    static let perchRevealDashboard = Notification.Name("perchRevealDashboard")
    /// Posted when the user submits the on-board "+" compose textbox. Carries the
    /// typed description in `userInfo["spec"]`. `CompanionManager` observes it and
    /// hands the spec to the main agent's dashboard family (the same path a spoken
    /// "add a widget" takes), so there is ONE creation brain. Defined here (next to
    /// its poster) rather than alongside the other `perch*` names so the dashboard
    /// files stay self-contained for the standalone preview harness.
    static let perchDashboardComposeSubmit = Notification.Name("perchDashboardComposeSubmit")
}

@MainActor
final class DashboardCanvasModel: ObservableObject {

    // MARK: Published canvas state

    /// Every widget placed on the board.
    @Published private(set) var items: [DashboardCanvasItem]
    /// Pan offset in world units (see the transform in the file header).
    @Published private(set) var panOffset: CGSize
    /// Zoom scale, clamped to `[minZoom, maxZoom]`.
    @Published private(set) var zoomScale: CGFloat
    /// The widget currently being dragged or resized, for live preview. `nil` when idle.
    @Published private(set) var dragSession: DragSession?

    // MARK: Drag/resize session

    struct DragSession: Equatable {
        enum Mode { case move, resize }
        let itemID: String
        let mode: Mode
        /// Live cursor translation since the gesture began, in WORLD units
        /// (callers divide the on-screen translation by `zoomScale`).
        var worldTranslation: CGSize
    }

    // MARK: Private collaborators

    /// The AppKit view backing the canvas, used to gate scroll events to the
    /// dashboard window and to convert the cursor into canvas-local coordinates.
    private weak var attachedView: NSView?
    /// The installed scroll-wheel monitor (removed on `detach`/`deinit`).
    private var scrollMonitor: Any?
    /// Debounce handle for persistence.
    private var pendingSaveTask: Task<Void, Never>?

    /// How strongly ⌘+scroll changes the zoom per scroll unit (multiplicative).
    private let zoomSensitivityPerScrollUnit: CGFloat = 0.0035

    /// The widget content/spec store. The canvas needs it to resolve each placement's
    /// `widgetID` into a `DashboardWidgetSource` for sizing (minimum span, etc.).
    let widgetStore: DashboardWidgetStore

    /// The periodic refresh loop for data-driven widgets (mirrors WorkflowScheduler's
    /// 30s tick). Cancelled in `deinit`.
    private var refreshLoopTask: Task<Void, Never>?
    /// Widget ids with a fetch in flight, so a slow refresh can't stack duplicate
    /// fetches on the next tick.
    private var refreshingWidgetIDs: Set<String> = []

    // MARK: Init

    init(widgetStore: DashboardWidgetStore) {
        self.widgetStore = widgetStore
        let snapshot = DashboardLayoutStore.load()
        self.items = snapshot.items
        self.panOffset = CGSize(width: snapshot.panX, height: snapshot.panY)
        self.zoomScale = DashboardCanvasModel.clampZoom(CGFloat(snapshot.zoom))
        self.dragSession = nil
        startRefreshLoop()
        // Register with the agent applier so an agent-created widget can be placed on
        // the live board, and place any widget the agent added while the board was
        // closed (an orphan with no canvas item yet).
        DashboardAgentApplier.shared.attach(canvasModel: self)
        reconcileOrphanPlacements()
    }

    // MARK: Widget resolution

    /// The data source backing a placement record, used for sizing. Falls back to
    /// `.custom` (generic list spans) if the widget was removed out from under the item.
    func source(for item: DashboardCanvasItem) -> DashboardWidgetSource {
        widgetStore.widget(for: item.widgetID)?.source ?? .custom
    }

    deinit {
        refreshLoopTask?.cancel()
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
        }
    }

    // MARK: Widget creation + live data (data-driven widgets)

    /// The "+" flow, step 1: drop a new *draft* widget (an in-card textbox) at a free
    /// cell. The user types their description into it; `finalizeDraft` turns it live.
    func createDraftWidget() {
        let draftWidget = DashboardWidget(
            id: UUID().uuidString,
            title: "New widget",
            source: .draft
        )
        widgetStore.add(draftWidget)
        placeNewItem(widgetID: draftWidget.id, source: .draft)
    }

    /// The "+" flow, step 2: hand the typed description to the main agent's dashboard
    /// family (the same brain a spoken "add a widget" uses), then discard the draft
    /// textbox card. The agent decides the source + fetch plan + refresh cadence and
    /// applies the widget back via `DashboardAgentApplier` — so there is ONE creation
    /// path, and this model no longer interprets anything itself.
    func finalizeDraft(widgetID: String, spec: String) {
        let trimmedSpec = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop the draft card; the real widget arrives from the agent shortly and is
        // placed at the next free cell. (Self-contained: we don't reach the subagent
        // manager from here — CompanionManager observes this and dispatches the task.)
        removeWidget(widgetID: widgetID)
        guard !trimmedSpec.isEmpty else { return }
        NotificationCenter.default.post(
            name: .perchDashboardComposeSubmit, object: nil, userInfo: ["spec": trimmedSpec]
        )
    }

    /// Place an agent-created widget on the board: fit an already-placed card to the new
    /// source's footprint (a replaced draft), or drop a fresh card at the next free cell.
    /// Called by `DashboardAgentApplier` after the widget is written to the store.
    func placeOrFitAgentWidget(widgetID: String, source: DashboardWidgetSource) {
        if items.contains(where: { $0.widgetID == widgetID }) {
            resizeItemToSourceDefault(widgetID: widgetID, source: source)
        } else {
            placeNewItem(widgetID: widgetID, source: source)
        }
    }

    /// Place any store widget that has no canvas item yet (an "orphan"). The agent can
    /// add a widget to the store while the board is closed; this self-heals the board's
    /// geometry when it next comes up. Builtins and existing widgets are already placed,
    /// so they are untouched.
    func reconcileOrphanPlacements() {
        let placedWidgetIDs = Set(items.map { $0.widgetID })
        for widget in widgetStore.widgets where !placedWidgetIDs.contains(widget.id) {
            placeNewItem(widgetID: widget.id, source: widget.source)
        }
    }

    /// Remove a widget (e.g. discarding a draft) and its canvas placement.
    func removeWidget(widgetID: String) {
        widgetStore.remove(id: widgetID)
        withAnimation(.easeOut(duration: 0.2)) {
            items = items.filter { $0.widgetID != widgetID }
        }
        scheduleSave()
    }

    /// Fetch + rank one widget's items and write them back to the store. Any widget that
    /// carries a fetch plan is refreshable — that includes the bespoke builtins wired to
    /// live data (Weather, Needs you, Today), not just the generic list widgets.
    func refreshWidget(_ widget: DashboardWidget) async {
        guard let fetchPlan = widget.fetchPlan else { return }
        guard !refreshingWidgetIDs.contains(widget.id) else { return }
        refreshingWidgetIDs.insert(widget.id)
        defer { refreshingWidgetIDs.remove(widget.id) }

        let fetchedItems = await DashboardDataService.shared.fetch(plan: fetchPlan)
        let rankedItems = DashboardRankingService.rank(items: fetchedItems)
        widgetStore.updateItems(widgetID: widget.id, items: rankedItems, lastRefreshed: Date())
    }

    /// Refresh every widget with a fetch plan whose cadence has elapsed (or that has
    /// never been fetched). Driven by the 30s refresh loop and run once at launch.
    func refreshDueWidgets() async {
        let now = Date()
        for widget in widgetStore.widgets where widget.fetchPlan != nil {
            guard let fetchPlan = widget.fetchPlan else { continue }
            let isDue = widget.lastRefreshed.map {
                now.timeIntervalSince($0) >= Double(fetchPlan.refreshCadenceSeconds)
            } ?? true
            if isDue {
                await refreshWidget(widget)
            }
        }
    }

    private func startRefreshLoop() {
        refreshLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDueWidgets()
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30s tick
            }
        }
    }

    // MARK: Expand / collapse (data-driven widgets)

    /// Toggle a data-driven widget's expand state: the visible item count grows/shrinks
    /// (in the list view) AND the card's row span grows/shrinks to fit, without pinning
    /// the item (so Wave 5's auto-reflow can still move it).
    func toggleExpanded(_ widget: DashboardWidget) {
        let willExpand = !widget.expanded
        widgetStore.setExpanded(widgetID: widget.id, expanded: willExpand)
        resizeForExpansion(widgetID: widget.id, source: widget.source, expanded: willExpand)
    }

    private func resizeForExpansion(widgetID: String, source: DashboardWidgetSource, expanded: Bool) {
        guard let item = items.first(where: { $0.widgetID == widgetID }) else { return }
        let baseRows = source.defaultSpan.rows
        // Expanded shows ~8 items vs ~3, so give it extra rows; collapsed returns to
        // the source's default height.
        let targetRows = expanded ? baseRows + 3 : baseRows
        let fittedSpan = DashboardLayoutSolver.fittedSpan(
            column: item.gridColumn,
            row: item.gridRow,
            desiredColumnSpan: item.columnSpan,
            desiredRowSpan: targetRows,
            minimumColumnSpan: source.minimumSpan.columns,
            minimumRowSpan: source.minimumSpan.rows,
            obstacles: obstacleRects(excludingItemID: item.id)
        )
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            replace(
                itemID: item.id,
                with: item.resizedUnpinnedTo(columnSpan: fittedSpan.columnSpan, rowSpan: fittedSpan.rowSpan)
            )
        }
        scheduleSave()
    }

    /// Resize a widget's card to its source's default footprint (fitted so it can't
    /// overlap a neighbor), without pinning it. Used when a draft becomes a live widget.
    private func resizeItemToSourceDefault(widgetID: String, source: DashboardWidgetSource) {
        guard let item = items.first(where: { $0.widgetID == widgetID }) else { return }
        let target = source.defaultSpan
        let fittedSpan = DashboardLayoutSolver.fittedSpan(
            column: item.gridColumn,
            row: item.gridRow,
            desiredColumnSpan: target.columns,
            desiredRowSpan: target.rows,
            minimumColumnSpan: source.minimumSpan.columns,
            minimumRowSpan: source.minimumSpan.rows,
            obstacles: obstacleRects(excludingItemID: item.id)
        )
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            replace(
                itemID: item.id,
                with: item.resizedUnpinnedTo(columnSpan: fittedSpan.columnSpan, rowSpan: fittedSpan.rowSpan)
            )
        }
        scheduleSave()
    }

    /// Drop a newly-created widget's card at the first free cell below the existing
    /// content (nudged to avoid overlap), at the source's default span.
    private func placeNewItem(widgetID: String, source: DashboardWidgetSource) {
        let span = source.defaultSpan
        let bottomRow = items.map { $0.gridRow + $0.rowSpan }.max() ?? 0
        let placement = DashboardLayoutSolver.freePlacement(
            columnSpan: span.columns,
            rowSpan: span.rows,
            preferredColumn: 0,
            preferredRow: bottomRow,
            obstacles: obstacleRects(excludingItemID: "")
        ) ?? (column: 0, row: bottomRow)
        let newItem = DashboardCanvasItem(
            widgetID: widgetID,
            gridColumn: placement.column,
            gridRow: placement.row,
            columnSpan: span.columns,
            rowSpan: span.rows
        )
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            items = items + [newItem]
        }
        // The free cell is usually below the existing content (off the viewport), so
        // pan the board to bring the new card into view near the top-left.
        revealItem(gridColumn: placement.column, gridRow: placement.row)
        scheduleSave()
    }

    /// Home the board so the greeting widget sits at its designed top-left margin. The
    /// opening greeting splash glides into the greeting widget's on-screen origin, so if
    /// the board was left scrolled far away that origin — and the "Good <time>, <Name>"
    /// intro text that lands on it — could sit off-screen. Calling this as the splash
    /// begins (under its opaque scrim, so the board never visibly jumps) guarantees the
    /// intro greeting, and the live greeting widget revealed after it, are always visible
    /// when the dashboard opens.
    func homeBoardToGreeting() {
        let greetingItem = items.first { item in
            item.widgetID == DashboardWidgetSource.builtinGreeting.rawValue
        }
        let greetingGridColumn = greetingItem?.gridColumn ?? 0
        let greetingGridRow = greetingItem?.gridRow ?? 0
        let pegSpacing = DashboardTheme.Metrics.pegSpacing

        // The designed top-left margin: the default snapshot's pan, which places a
        // grid-(0,0) widget at a comfortable inset from the window corner. Offset by the
        // greeting's grid cell so that cell — wherever it currently lives — lands at that
        // same margin (and everything else shifts with it).
        let designedTopLeftMargin = DashboardLayoutSnapshot.defaultSnapshot
        panOffset = CGSize(
            width: CGFloat(designedTopLeftMargin.panX) - CGFloat(greetingGridColumn) * pegSpacing,
            height: CGFloat(designedTopLeftMargin.panY) - CGFloat(greetingGridRow) * pegSpacing
        )
        scheduleSave()
    }

    /// Pan the canvas so the cell at `(gridColumn, gridRow)` sits near the top-left of
    /// the viewport. screen = (world + pan)·zoom  ⇒  pan = screen/zoom − world.
    private func revealItem(gridColumn: Int, gridRow: Int) {
        let pegSpacing = DashboardTheme.Metrics.pegSpacing
        let worldX = CGFloat(gridColumn) * pegSpacing
        let worldY = CGFloat(gridRow) * pegSpacing
        let desiredScreenInset: CGFloat = 80
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            panOffset = CGSize(
                width: desiredScreenInset / zoomScale - worldX,
                height: desiredScreenInset / zoomScale - worldY
            )
        }
    }

    // MARK: Scroll-monitor lifecycle

    /// Called by the canvas's AppKit accessor view once it is in the window. Stores
    /// the view (for coordinate conversion) and installs the scroll monitor once.
    func attach(view: NSView) {
        attachedView = view
        guard scrollMonitor == nil else { return }
        // One monitor for both gestures: scroll wheel (pan, and ⌘+scroll zoom) and
        // trackpad pinch (`.magnify`, which macOS delivers as its own event type).
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            // The monitor sees every matching event in the app; we only act on those
            // over the dashboard canvas and pass everything else through untouched.
            guard let self else { return event }
            switch event.type {
            case .magnify:
                return self.handleMagnify(event)
            default:
                return self.handleScroll(event)
            }
        }
    }

    /// Removes the scroll monitor (e.g. when the canvas disappears).
    func detach() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
        attachedView = nil
    }

    // MARK: Scroll / pinch handling (pan + ⌘ zoom + trackpad pinch zoom)

    /// The cursor location for `event`, in canvas screen space (top-left origin, to
    /// match the SwiftUI transform), or `nil` if the event isn't over this canvas's
    /// window/bounds — in which case the caller passes the event through untouched.
    private func cursorScreenPoint(for event: NSEvent) -> CGPoint? {
        guard let attachedView, event.window === attachedView.window else { return nil }

        // AppKit point (bottom-left origin) within the canvas view.
        let pointInViewBottomLeft = attachedView.convert(event.locationInWindow, from: nil)
        let viewBounds = attachedView.bounds
        guard viewBounds.contains(pointInViewBottomLeft) else { return nil }

        // Flip to a top-left origin to match the SwiftUI screen-space transform.
        return CGPoint(
            x: pointInViewBottomLeft.x,
            y: viewBounds.height - pointInViewBottomLeft.y
        )
    }

    /// Returns `nil` to consume the event when it falls on the canvas, otherwise the
    /// original event so other windows' scroll views keep working.
    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard let cursorScreenPoint = cursorScreenPoint(for: event) else { return event }

        if event.modifierFlags.contains(.command) {
            zoom(byScrollDelta: event.scrollingDeltaY, towardScreenPoint: cursorScreenPoint)
        } else {
            pan(byScreenDeltaX: event.scrollingDeltaX, screenDeltaY: event.scrollingDeltaY)
        }
        scheduleSave()
        return nil
    }

    /// Trackpad pinch: zoom toward the cursor by the gesture's incremental
    /// magnification. Consumes the event when over the canvas, else passes it through.
    private func handleMagnify(_ event: NSEvent) -> NSEvent? {
        guard let cursorScreenPoint = cursorScreenPoint(for: event) else { return event }
        zoom(byMagnification: event.magnification, towardScreenPoint: cursorScreenPoint)
        scheduleSave()
        return nil
    }

    /// Pan the canvas so content follows the scroll gesture. Screen deltas are
    /// converted to world units by dividing out the zoom.
    /// (If panning feels inverted on your input device, negate these two terms.)
    private func pan(byScreenDeltaX screenDeltaX: CGFloat, screenDeltaY: CGFloat) {
        panOffset = CGSize(
            width: panOffset.width + screenDeltaX / zoomScale,
            height: panOffset.height + screenDeltaY / zoomScale
        )
    }

    /// Zoom toward the cursor: the world point under the cursor stays pinned while
    /// the scale changes, so the board zooms where you're pointing.
    private func zoom(byScrollDelta scrollDelta: CGFloat, towardScreenPoint cursorScreenPoint: CGPoint) {
        let oldZoom = zoomScale
        // Clamp the per-event delta so a single coarse wheel notch can't leap scale.
        let clampedDelta = max(-40, min(40, scrollDelta))
        let newZoom = DashboardCanvasModel.clampZoom(oldZoom * (1 + clampedDelta * zoomSensitivityPerScrollUnit))
        guard newZoom != oldZoom else { return }

        // world = cursor/zoom − pan  (invert the transform at the cursor)
        let worldUnderCursorX = cursorScreenPoint.x / oldZoom - panOffset.width
        let worldUnderCursorY = cursorScreenPoint.y / oldZoom - panOffset.height
        // Re-solve pan at the new zoom so that same world point maps back to the cursor.
        panOffset = CGSize(
            width: cursorScreenPoint.x / newZoom - worldUnderCursorX,
            height: cursorScreenPoint.y / newZoom - worldUnderCursorY
        )
        zoomScale = newZoom
    }

    /// Zoom toward the cursor for a trackpad pinch. `magnification` is the gesture's
    /// incremental delta for this frame (≈±0.01–0.05; positive = pinch out / zoom in),
    /// applied multiplicatively so the pinch feels the same at any current scale. Like
    /// the scroll zoom, it keeps the world point under the cursor pinned in place.
    private func zoom(byMagnification magnification: CGFloat, towardScreenPoint cursorScreenPoint: CGPoint) {
        let oldZoom = zoomScale
        let newZoom = DashboardCanvasModel.clampZoom(oldZoom * (1 + magnification))
        guard newZoom != oldZoom else { return }

        // world = cursor/zoom − pan  (invert the transform at the cursor)
        let worldUnderCursorX = cursorScreenPoint.x / oldZoom - panOffset.width
        let worldUnderCursorY = cursorScreenPoint.y / oldZoom - panOffset.height
        // Re-solve pan at the new zoom so that same world point maps back to the cursor.
        panOffset = CGSize(
            width: cursorScreenPoint.x / newZoom - worldUnderCursorX,
            height: cursorScreenPoint.y / newZoom - worldUnderCursorY
        )
        zoomScale = newZoom
    }

    private static func clampZoom(_ proposedZoom: CGFloat) -> CGFloat {
        min(max(proposedZoom, DashboardTheme.Metrics.minZoom), DashboardTheme.Metrics.maxZoom)
    }

    // MARK: Drag / resize (driven by the widget hosts)

    /// Update the live drag/resize preview as the gesture changes.
    func updateDragSession(itemID: String, mode: DragSession.Mode, worldTranslation: CGSize) {
        // Lock the mode to whatever STARTED this drag. The resize handle sits inside the
        // card, so its resize gesture and the card's move gesture both fire for one
        // physical drag on the handle. Without this lock the session's mode would
        // flip-flop between .move and .resize every event — and the .move frames would
        // relocate the card's origin toward the cursor, so the card would shift on all
        // sides while it grew instead of only extending right/bottom ("the size gets
        // messed up"). The resize gesture's smaller activation threshold makes it claim
        // the drag first, so a drag begun on the handle stays a resize for its lifetime.
        let lockedMode = (dragSession?.itemID == itemID) ? dragSession!.mode : mode
        dragSession = DragSession(itemID: itemID, mode: lockedMode, worldTranslation: worldTranslation)
    }

    /// Commit whichever gesture is in flight, exactly once. Both the move and resize
    /// gestures' `onEnded` route here; the FIRST call commits using the drag's locked
    /// mode and clears the session, so the second call (from the overlapping gesture on
    /// the same physical drag) finds no session and is a harmless no-op. This prevents a
    /// resize from also committing as a move on release.
    func commitDragSession(itemID: String, worldTranslation: CGSize) {
        guard let session = dragSession, session.itemID == itemID else { return }
        switch session.mode {
        case .move:
            commitMove(itemID: itemID, worldTranslation: worldTranslation)
        case .resize:
            commitResize(itemID: itemID, worldTranslation: worldTranslation)
        }
    }

    /// Commit a move: snap to pegs, resolve collisions, animate into place, persist.
    func commitMove(itemID: String, worldTranslation: CGSize) {
        guard let item = items.first(where: { $0.id == itemID }),
              let target = resolvedMoveTarget(itemID: itemID, worldTranslation: worldTranslation) else {
            dragSession = nil
            return
        }
        // Spring so the card visibly snaps from the cursor to its resolved cell.
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            replace(itemID: itemID, with: item.movedTo(gridColumn: target.column, gridRow: target.row))
            dragSession = nil
        }
        scheduleSave()
    }

    /// Commit a resize: snap span, clamp so it can't overlap a neighbor, animate, persist.
    func commitResize(itemID: String, worldTranslation: CGSize) {
        guard let item = items.first(where: { $0.id == itemID }),
              let span = resolvedResizeSpan(itemID: itemID, worldTranslation: worldTranslation) else {
            dragSession = nil
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            replace(itemID: itemID, with: item.resizedTo(columnSpan: span.columnSpan, rowSpan: span.rowSpan))
            dragSession = nil
        }
        scheduleSave()
    }

    /// Cancel an in-flight gesture without committing (no geometry change).
    func cancelDragSession() {
        dragSession = nil
    }

    // MARK: Collision-aware resolution (shared by the live ghost + the commit)

    /// Where a moved widget will actually land: the snapped drop cell, nudged to the
    /// nearest free spot if that cell is occupied. `nil` only if the item is gone.
    func resolvedMoveTarget(itemID: String, worldTranslation: CGSize) -> (column: Int, row: Int)? {
        guard let item = items.first(where: { $0.id == itemID }) else { return nil }
        let pegSpacing = DashboardTheme.Metrics.pegSpacing
        let newOriginWorldX = CGFloat(item.gridColumn) * pegSpacing + worldTranslation.width
        let newOriginWorldY = CGFloat(item.gridRow) * pegSpacing + worldTranslation.height
        let snappedColumn = Int((newOriginWorldX / pegSpacing).rounded())
        let snappedRow = Int((newOriginWorldY / pegSpacing).rounded())

        let freeSpot = DashboardLayoutSolver.freePlacement(
            columnSpan: item.columnSpan,
            rowSpan: item.rowSpan,
            preferredColumn: snappedColumn,
            preferredRow: snappedRow,
            obstacles: obstacleRects(excludingItemID: itemID)
        )
        // No free spot within range → keep the widget where it already is.
        return freeSpot ?? (column: item.gridColumn, row: item.gridRow)
    }

    /// The span a resized widget will actually take: the snapped span, shrunk until it
    /// no longer overlaps a neighbor (never below the kind's minimum).
    func resolvedResizeSpan(itemID: String, worldTranslation: CGSize) -> (columnSpan: Int, rowSpan: Int)? {
        guard let item = items.first(where: { $0.id == itemID }) else { return nil }
        let pegSpacing = DashboardTheme.Metrics.pegSpacing
        let columnDelta = Int((worldTranslation.width / pegSpacing).rounded())
        let rowDelta = Int((worldTranslation.height / pegSpacing).rounded())
        let minimumSpan = source(for: item).minimumSpan

        return DashboardLayoutSolver.fittedSpan(
            column: item.gridColumn,
            row: item.gridRow,
            desiredColumnSpan: item.columnSpan + columnDelta,
            desiredRowSpan: item.rowSpan + rowDelta,
            minimumColumnSpan: minimumSpan.columns,
            minimumRowSpan: minimumSpan.rows,
            obstacles: obstacleRects(excludingItemID: itemID)
        )
    }

    /// Footprints of every widget except the one being moved/resized.
    private func obstacleRects(excludingItemID excludedItemID: String) -> [DashboardGridRect] {
        items.compactMap { other in
            other.id == excludedItemID
                ? nil
                : DashboardGridRect(
                    column: other.gridColumn,
                    row: other.gridRow,
                    columnSpan: other.columnSpan,
                    rowSpan: other.rowSpan
                  )
        }
    }

    /// Immutable replacement of one item by id (per the no-mutation rule).
    private func replace(itemID: String, with updatedItem: DashboardCanvasItem) {
        items = items.map { $0.id == itemID ? updatedItem : $0 }
    }

    // MARK: Persistence (debounced)

    private var currentSnapshot: DashboardLayoutSnapshot {
        DashboardLayoutSnapshot(
            items: items,
            panX: Double(panOffset.width),
            panY: Double(panOffset.height),
            zoom: Double(zoomScale)
        )
    }

    /// Coalesce rapid changes (a drag, a flurry of scroll events) into a single
    /// write ~0.4s after the last change.
    private func scheduleSave() {
        pendingSaveTask?.cancel()
        let snapshot = currentSnapshot
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            DashboardLayoutStore.save(snapshot)
        }
    }
}
