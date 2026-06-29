//
//  DashboardCanvasView.swift
//  leanring-buddy
//
//  The infinite pegboard canvas: a dot grid behind a freely arrangeable layer of
//  widgets. The whole widget layer is pan/zoom-transformed as one unit (so dots and
//  cards stay aligned), and a small AppKit accessor view hands the model the window +
//  bounds it needs to turn scroll events into pan and ⌘+scroll into zoom.
//
//  Owns the single `DashboardCanvasModel` for the surface.
//

import AppKit
import SwiftUI

struct DashboardCanvasView: View {
    /// Owned by `DashboardView` so the floating "+" add-widget button shares it.
    @ObservedObject var model: DashboardCanvasModel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // The pegboard fills the viewport and never intercepts clicks. It only
                // appears while a widget is being dragged or resized — the rest of the
                // time the board reads as a clean surface, and the grid shows up exactly
                // when it's useful for aligning.
                DashboardPegboardBackground(panOffset: model.panOffset, zoomScale: model.zoomScale)
                    .allowsHitTesting(false)
                    .opacity(model.dragSession == nil ? 0 : 1)
                    .animation(.easeInOut(duration: 0.18), value: model.dragSession == nil)

                widgetLayer
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            // Keep the transformed/over-panned content from spilling outside the window.
            .clipped()
            // Invisible AppKit view that installs the scroll monitor for this window.
            .background(DashboardCanvasEventCatcher(model: model))
        }
    }

    /// All widgets, positioned in world coordinates, then pan/zoom-transformed as one.
    private var widgetLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.items) { item in
                DashboardWidgetHost(item: item, model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // screen = (world + pan) · zoom  — scale first (anchored top-left), then
        // translate by pan·zoom so the math matches the pegboard's dot placement.
        .scaleEffect(model.zoomScale, anchor: .topLeading)
        .offset(x: model.panOffset.width * model.zoomScale, y: model.panOffset.height * model.zoomScale)
    }
}

// MARK: - Scroll-event accessor

/// A zero-content AppKit view whose only job is to give the model a handle on the
/// dashboard window (for gating scroll events) and on its own bounds (for converting
/// the cursor location). The actual scroll handling lives in `DashboardCanvasModel`'s
/// local event monitor — this view never draws or intercepts anything itself.
private struct DashboardCanvasEventCatcher: NSViewRepresentable {
    let model: DashboardCanvasModel

    func makeNSView(context: Context) -> NSView {
        let accessorView = NSView()
        // NSViewRepresentable methods run on the main actor, so this is safe. The
        // monitor reads `view.window` lazily at event time, so attaching before the
        // view is in a window is fine.
        model.attach(view: accessorView)
        return accessorView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        model.attach(view: nsView)
    }
}
