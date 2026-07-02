//
//  DashboardGreetingIntro.swift
//  Perch
//
//  The open-dashboard greeting splash. When the Daily Dashboard is shown, the serif
//  greeting ("Good <morning/afternoon/evening>, <Name>") appears centered on the glass
//  for about a second, then glides up to the exact spot where the greeting widget lives
//  on the canvas — handing the screen off to the live dashboard underneath.
//
//  It reuses `DashboardGreetingContent` so the splash text is pixel-identical to the
//  widget it lands on, and reads the live pan/zoom off `DashboardCanvasModel` so the
//  glide targets the greeting widget's real on-screen position (not a guess). Honors the
//  "Reduce motion" setting by holding the centered greeting and skipping the glide.
//

import SwiftUI

struct DashboardGreetingIntro: View {
    /// The dashboard's resolved background tint, painted opaque here so the splash hides
    /// the canvas widgets behind it and reads as a clean, empty surface during the hold.
    let scrimColor: Color
    /// The live canvas model — read (never mutated) to find the greeting widget's spot so
    /// the glide lands the splash exactly where the real greeting will appear.
    @ObservedObject var canvasModel: DashboardCanvasModel
    /// Called once the splash finishes; the parent removes this overlay (revealing the
    /// live dashboard) with its own cross-fade.
    var onFinished: () -> Void

    @ObservedObject private var settingsStore = DashboardSettingsStore.shared

    /// Captured once so the date/salutation are computed a single time for the whole splash.
    @State private var now = Date()
    /// Measured size of the greeting text block, used to center it precisely before the glide.
    @State private var greetingBlockSize: CGSize = .zero
    /// Drives the entrance fade + slight scale-in.
    @State private var hasAppeared = false
    /// Flips true after the hold; drives the glide from screen-center into the widget's spot.
    @State private var hasGlidedIntoPlace = false

    private var reduceMotion: Bool { settingsStore.values.reduceMotion }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                // Opaque tint occludes the canvas so only the greeting shows during the
                // hold; the parent cross-fades the whole overlay away once we finish.
                scrimColor
                    .ignoresSafeArea()

                DashboardGreetingContent(now: now)
                    .fixedSize()
                    .background(greetingBlockSizeReader)
                    // Anchor at top-left so `offset` positions the block's top-left corner
                    // and the landing shrink (to the canvas's zoom) collapses toward it —
                    // matching how the real widget is positioned + scaled on the canvas.
                    .scaleEffect(greetingScale, anchor: .topLeading)
                    .offset(greetingOffset(in: proxy.size))
                    .opacity(hasAppeared ? 1.0 : 0.0)
            }
        }
        .task { await runSplash() }
    }

    // MARK: Placement

    /// The greeting's top-left offset: centered in the window during the hold, then the
    /// greeting widget's real on-canvas origin once it glides into place.
    private func greetingOffset(in containerSize: CGSize) -> CGSize {
        let centeredOffset = CGSize(
            width: max(0, (containerSize.width - greetingBlockSize.width) / 2),
            height: max(0, (containerSize.height - greetingBlockSize.height) / 2)
        )
        // With Reduce motion on we never glide — the greeting just holds dead-center.
        guard !reduceMotion, hasGlidedIntoPlace else { return centeredOffset }

        let landing = greetingWidgetScreenOrigin()
        return CGSize(width: landing.x, height: landing.y)
    }

    /// Combined scale: a gentle scale-in on entrance, then a shrink to the canvas's zoom
    /// as it lands so the splash text matches the on-canvas greeting's rendered size.
    private var greetingScale: CGFloat {
        let entranceScale: CGFloat = hasAppeared ? 1.0 : 0.97
        let landedScale: CGFloat = (hasGlidedIntoPlace && !reduceMotion) ? canvasModel.zoomScale : 1.0
        return entranceScale * landedScale
    }

    /// Where the greeting widget's text sits on screen right now, in window points. Mirrors
    /// the canvas transform `screen = (world + pan) · zoom` (anchored top-left), using the
    /// greeting card's world origin (its grid cell, inset by half the cell gap). Falls back
    /// to the default seed position if the greeting widget isn't on the canvas.
    private func greetingWidgetScreenOrigin() -> CGPoint {
        let pegSpacing = DashboardTheme.Metrics.pegSpacing
        let halfCellGap = DashboardTheme.Metrics.cellGap / 2
        let zoom = canvasModel.zoomScale

        let greetingItem = canvasModel.items.first { item in
            item.widgetID == DashboardWidgetSource.builtinGreeting.rawValue
        }

        // Default seed: grid (0, 0). Used as the fallback world cell too.
        let gridColumn = greetingItem?.gridColumn ?? 0
        let gridRow = greetingItem?.gridRow ?? 0

        let worldX = CGFloat(gridColumn) * pegSpacing + halfCellGap
        let worldY = CGFloat(gridRow) * pegSpacing + halfCellGap

        return CGPoint(
            x: (worldX + canvasModel.panOffset.width) * zoom,
            y: (worldY + canvasModel.panOffset.height) * zoom
        )
    }

    /// Reports the rendered size of the greeting block so it can be centered exactly.
    private var greetingBlockSizeReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: GreetingBlockSizeKey.self, value: proxy.size)
        }
        .onPreferenceChange(GreetingBlockSizeKey.self) { measuredSize in
            greetingBlockSize = measuredSize
        }
    }

    // MARK: Timeline

    /// Entrance → hold front-and-center for ~1s → glide into the widget's spot → hand back
    /// to the parent to reveal the live dashboard.
    private func runSplash() async {
        // Home the board so the greeting widget — both where this splash glides and where
        // the live greeting appears after the hand-off — is on-screen, even if the board
        // was left scrolled far away. Runs under the opaque scrim, so the board
        // repositions invisibly and the user only sees the greeting land somewhere visible.
        canvasModel.homeBoardToGreeting()

        withAnimation(.easeOut(duration: 0.45)) { hasAppeared = true }

        // "Front and center for a second."
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Reduce motion: no glide — hand straight back so the parent cross-fades.
        guard !reduceMotion else {
            onFinished()
            return
        }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) {
            hasGlidedIntoPlace = true
        }
        // Let the glide settle before the parent cross-fades to the live greeting.
        try? await Task.sleep(nanoseconds: 600_000_000)
        onFinished()
    }
}

/// Carries the measured greeting-block size out of the layout pass.
private struct GreetingBlockSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
