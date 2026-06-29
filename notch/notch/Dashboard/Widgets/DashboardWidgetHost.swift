//
//  DashboardWidgetHost.swift
//  leanring-buddy
//
//  Wraps one widget on the pegboard canvas and gives it its interactive behavior:
//  drag-to-move (snapping to pegs) and a bottom-right handle to expand/shrink it.
//  While a gesture is in flight the card follows the cursor continuously and a dashed
//  "ghost" outline shows where it will land when released.
//
//  The host positions itself in WORLD coordinates inside the canvas's transformed
//  layer (see `DashboardCanvasView`/`DashboardCanvasModel`), so it only ever works in
//  unscaled points; the parent's `.scaleEffect`/`.offset` handles zoom and pan. Drag
//  translations are read in `.global` space (immune to the scale) and divided by the
//  zoom to convert back to world units.
//

import AppKit
import SwiftUI

struct DashboardWidgetHost: View {
    let item: DashboardCanvasItem
    @ObservedObject var model: DashboardCanvasModel

    @State private var isHovering = false
    /// Tracks hover over the close ("×") button itself, so it can darken on hover
    /// independently of the card-wide hover state.
    @State private var isHoveringCloseButton = false

    private var pegSpacing: CGFloat { DashboardTheme.Metrics.pegSpacing }
    private var cellGap: CGFloat { DashboardTheme.Metrics.cellGap }

    /// The live gesture for THIS item, if any (other items' sessions don't affect us).
    private var activeSession: DashboardCanvasModel.DragSession? {
        guard let session = model.dragSession, session.itemID == item.id else { return nil }
        return session
    }

    /// The data source backing this placement (resolved from its `widgetID`), which
    /// drives content, chrome, and sizing.
    private var widgetSource: DashboardWidgetSource {
        model.source(for: item)
    }

    /// Snappy spring for the discrete cell-to-cell jumps while dragging/resizing.
    private var snapAnimation: Animation { .spring(response: 0.16, dampingFraction: 0.72) }

    var body: some View {
        let geometry = liveGeometry()

        cardBody(geometry)
            // Inset the card within its cell footprint (gap between neighbors), then
            // place the footprint at its live grid origin in world space. The parent's
            // scale/offset turns this into the final on-screen placement.
            .offset(x: cellGap / 2, y: cellGap / 2)
            .offset(x: geometry.liveOriginX, y: geometry.liveOriginY)
            // The card snaps between whole cells (see liveGeometry); animate each jump so
            // dragging feels like it clicks into the grid.
            .animation(snapAnimation, value: geometry.liveOriginX)
            .animation(snapAnimation, value: geometry.liveOriginY)
            .animation(snapAnimation, value: geometry.cardWidth)
            .animation(snapAnimation, value: geometry.cardHeight)
    }

    // MARK: Card

    private func cardBody(_ geometry: LiveGeometry) -> some View {
        widgetContent(geometry)
            // Pin to the cell's top-left so the card always grows down and right from its
            // grid origin — never centered (which would push the top up past its row if the
            // content were ever larger than the footprint).
            .frame(width: geometry.cardWidth, height: geometry.cardHeight, alignment: .topLeading)
            // A small "grabber" pill at the top center — the affordance that invites you
            // to drag the widget around (the whole card is draggable; this just signals
            // it). Shown only on hover (or while actually moving) so the board stays clean.
            .overlay(alignment: .top) {
                if isHovering || activeSession?.mode == .move {
                    grabHandle
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isHovering || activeSession?.mode == .resize {
                    resizeHandle
                }
            }
            // A small "×" at the top-right that removes the widget. Shown only on hover
            // (and hidden while a move/resize gesture is in flight) so the board stays
            // clean and the button can't be hit mid-drag.
            .overlay(alignment: .topTrailing) {
                if isHovering && activeSession == nil {
                    closeButton
                }
            }
            // A "pin to notch" grip at the top-left, shown on hover for data-driven
            // widgets (the only kind the notch can render natively). Dragging it onto the
            // notch pins this widget there — its own `.onDrag` so it starts a system drag
            // session rather than the card's in-canvas move.
            .overlay(alignment: .topLeading) {
                if isHovering && activeSession == nil && widgetSource.isDataDriven {
                    pinToNotchHandle
                }
            }
            // Lift the card off the board with a shadow while it's being dragged.
            .shadow(
                color: (widgetSource.wearsCardChrome && activeSession != nil)
                    ? DashboardTheme.Colors.dragShadow : .clear,
                radius: activeSession != nil ? 18 : 0,
                x: 0,
                y: activeSession != nil ? 10 : 0
            )
            .contentShape(Rectangle())
            .gesture(moveGesture)
            .onHover { hovering in
                isHovering = hovering
                // Grab affordance: an open hand over a movable card (canvas convention).
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    /// The widget's content, chosen by its source: builtin sources render their bespoke
    /// view (reflowing by the live span); data-driven sources render the generic ranked
    /// list; an unresolved widget (removed out from under its placement) renders nothing.
    @ViewBuilder
    private func widgetContent(_ geometry: LiveGeometry) -> some View {
        if let builtinKind = widgetSource.builtinKind {
            builtinContent(builtinKind, geometry: geometry)
        } else if widgetSource.isDraft {
            DashboardWidgetComposeView(
                onSubmit: { spec in
                    model.finalizeDraft(widgetID: item.widgetID, spec: spec)
                },
                onDiscard: { model.removeWidget(widgetID: item.widgetID) }
            )
        } else if widgetSource == .generated, let widget = model.widgetStore.widget(for: item.widgetID) {
            DashboardGeneratedWidgetView(widget: widget, widgetStore: model.widgetStore)
        } else if widgetSource.isDataDriven, let widget = model.widgetStore.widget(for: item.widgetID) {
            DashboardListWidgetView(
                widget: widget,
                widgetStore: model.widgetStore,
                contentRowSpan: geometry.contentRowSpan,
                onToggleExpanded: { model.toggleExpanded(widget) }
            )
        } else {
            Color.clear
        }
    }

    /// Build a builtin widget's bespoke view, injecting its dependencies: the live widget
    /// (for the data-bound builtins' `cachedItems`), the content row span (so the view
    /// reflows as the card resizes), and — for Notes/Focus — the local state and focus
    /// models from the environment. A missing widget falls back to an empty builtin so the
    /// view still renders (its quiet empty state) rather than a blank card.
    @ViewBuilder
    private func builtinContent(_ kind: DashboardWidgetKind, geometry: LiveGeometry) -> some View {
        let widget = model.widgetStore.widget(for: item.widgetID)
        switch kind {
        case .greeting:
            DashboardGreetingView()
        case .weather:
            DashboardWeatherView(
                widget: widget ?? .builtin(.builtinWeather, title: "Weather"),
                widgetStore: model.widgetStore
            )
        case .needsYou:
            DashboardNeedsYouWidget(
                widget: widget ?? .builtin(.builtinNeedsYou, title: "Needs you"),
                widgetStore: model.widgetStore,
                contentRowSpan: geometry.contentRowSpan
            )
        case .today:
            DashboardTodayWidget(
                widget: widget ?? .builtin(.builtinToday, title: "Today"),
                widgetStore: model.widgetStore,
                contentRowSpan: geometry.contentRowSpan
            )
        case .focus:
            DashboardFocusWidget()
        case .notes:
            DashboardNotesWidget()
        case .dailyBrief:
            DashboardDailyBriefWidget()
        }
    }

    /// The top-center grabber pill. It's purely an affordance — the whole card is
    /// draggable, and since the pill carries no gesture of its own, grabbing it just
    /// hands the drag to the card's move gesture. That makes it a reliable drag point
    /// even on widgets whose content (links, toggles, text fields) would otherwise
    /// swallow a drag.
    private var grabHandle: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(widgetSource.wearsCardChrome
                  ? DashboardTheme.Colors.widgetGrabHandle
                  : DashboardTheme.Colors.onTintTertiary.opacity(0.5))
            .frame(width: 30, height: 5)
            .padding(.top, 9)
    }

    /// The hover-revealed close ("×") button. Tapping it removes the widget (and its
    /// canvas placement) via the model. It carries its own tap gesture, so a click here
    /// deletes rather than starting a drag.
    private var closeButton: some View {
        Button {
            model.removeWidget(widgetID: item.widgetID)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(closeButtonIconColor)
                .frame(width: 18, height: 18)
                .background(Circle().fill(closeButtonFillColor))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .onHover { hovering in
            isHoveringCloseButton = hovering
            // Pointer cursor signals clickability (per the dashboard hover convention).
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    /// The hover-revealed "pin to notch" grip. Dragging it begins a system drag carrying
    /// this widget's id; dropping on the notch pins the widget there (see
    /// `DashboardWidgetNotchDrag` + the notch's `NotchWidgetDropView`). It carries its own
    /// `.onDrag`, so grabbing it starts the cross-window drag rather than the card's
    /// in-canvas move gesture.
    private var pinToNotchHandle: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(closeButtonIconColor)
            .frame(width: 18, height: 18)
            .background(Circle().fill(closeButtonFillColor))
            .contentShape(Circle())
            .padding(6)
            .help("Drag onto the notch to pin this widget there")
            .onHover { hovering in
                // Open-hand grip signals "drag me" (the canvas convention for movable bits).
                if hovering {
                    NSCursor.openHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDrag {
                // Resolve the live widget so the drag can carry its full data (the
                // cross-app snapshot for notch) plus its id (Perch's own notch).
                guard let widget = model.widgetStore.widget(for: item.widgetID) else {
                    return NSItemProvider()
                }
                return DashboardWidgetNotchDrag.beginDrag(widget: widget)
            }
    }

    /// Disc fill behind the "×", matched to the card surface (dark disc on light cards,
    /// light disc on the dark-glass header card) and darker/brighter while hovered.
    private var closeButtonFillColor: Color {
        if widgetSource.wearsCardChrome {
            return isHoveringCloseButton
                ? DashboardTheme.Colors.widgetCloseFillOnLightHover
                : DashboardTheme.Colors.widgetCloseFillOnLight
        } else {
            return isHoveringCloseButton
                ? DashboardTheme.Colors.widgetCloseFillOnDarkHover
                : DashboardTheme.Colors.widgetCloseFillOnDark
        }
    }

    /// "×" glyph color, matched to the card surface.
    private var closeButtonIconColor: Color {
        widgetSource.wearsCardChrome
            ? DashboardTheme.Colors.widgetCloseIconOnLight
            : DashboardTheme.Colors.widgetCloseIconOnDark
    }

    private var resizeHandle: some View {
        let handleSize = DashboardTheme.Metrics.resizeHandleSize
        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DashboardTheme.Colors.resizeHandle)
                .frame(width: handleSize, height: handleSize)
                .overlay(
                    Image(systemName: "arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.black.opacity(0.55))
                )
        }
        .padding(6)
        .contentShape(Rectangle())
        // High priority so a drag that begins on the handle is recognized as a resize
        // before the card's move gesture (which spans the whole card, including under
        // the handle) can claim it — see `updateDragSession`'s mode lock.
        .highPriorityGesture(resizeGesture)
        .onHover { hovering in
            if hovering {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: Gestures

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                model.updateDragSession(
                    itemID: item.id,
                    mode: .move,
                    worldTranslation: worldTranslation(from: value.translation)
                )
            }
            .onEnded { value in
                model.commitDragSession(itemID: item.id, worldTranslation: worldTranslation(from: value.translation))
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                model.updateDragSession(
                    itemID: item.id,
                    mode: .resize,
                    worldTranslation: worldTranslation(from: value.translation)
                )
            }
            .onEnded { value in
                model.commitDragSession(itemID: item.id, worldTranslation: worldTranslation(from: value.translation))
            }
    }

    /// Convert an on-screen drag translation into world units by dividing out zoom.
    private func worldTranslation(from screenTranslation: CGSize) -> CGSize {
        let zoom = max(model.zoomScale, 0.01)
        return CGSize(width: screenTranslation.width / zoom, height: screenTranslation.height / zoom)
    }

    // MARK: Live geometry

    /// All the derived sizes/positions for the current frame, in world units. Because
    /// the card snaps to whole cells even mid-drag, every value here is cell-aligned.
    private struct LiveGeometry {
        var liveOriginX: CGFloat
        var liveOriginY: CGFloat
        var cardWidth: CGFloat
        var cardHeight: CGFloat
        /// The span (in cells) the content should render for — drives how much info a
        /// widget shows. Updates live as the widget is resized.
        var contentColumnSpan: Int
        var contentRowSpan: Int
    }

    private func liveGeometry() -> LiveGeometry {
        let session = activeSession
        let isMoving = session?.mode == .move
        let isResizing = session?.mode == .resize
        let moveTranslation = isMoving ? (session?.worldTranslation ?? .zero) : .zero
        let resizeTranslation = isResizing ? (session?.worldTranslation ?? .zero) : .zero

        // SNAP-WHILE-DRAGGING: instead of tracking the cursor continuously, the card
        // jumps to whole cells — to its collision-resolved grid slot while moving, and
        // to the clamped whole-cell span while resizing. The cursor still drives the
        // gesture; we just quantize the result to the grid so it's always aligned.
        var originColumn = item.gridColumn
        var originRow = item.gridRow
        var spanColumns = item.columnSpan
        var spanRows = item.rowSpan

        if isMoving, let target = model.resolvedMoveTarget(itemID: item.id, worldTranslation: moveTranslation) {
            originColumn = target.column
            originRow = target.row
        }
        if isResizing, let span = model.resolvedResizeSpan(itemID: item.id, worldTranslation: resizeTranslation) {
            spanColumns = span.columnSpan
            spanRows = span.rowSpan
        }

        return LiveGeometry(
            liveOriginX: CGFloat(originColumn) * pegSpacing,
            liveOriginY: CGFloat(originRow) * pegSpacing,
            cardWidth: CGFloat(spanColumns) * pegSpacing - cellGap,
            cardHeight: CGFloat(spanRows) * pegSpacing - cellGap,
            contentColumnSpan: spanColumns,
            contentRowSpan: spanRows
        )
    }
}
