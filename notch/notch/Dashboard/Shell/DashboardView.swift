//
//  DashboardView.swift
//  leanring-buddy
//
//  Root SwiftUI view for the standalone Daily Dashboard window. Shows either the
//  dashboard (greeting/weather header + widget grid + add button) or the settings
//  page, over the shared dark tinted-glass background (the window's blur backing
//  lives in DashboardWindowController). A small settings bar at the top-right opens
//  the settings page.
//
//  This surface is intentionally NOT notch-anchored and uses its own theme
//  (`DashboardTheme`), separate from the dark `DS` notch language.
//

import SwiftUI

struct DashboardView: View {
    /// Live settings — the background tint/translucency and motion respond to these.
    @ObservedObject private var settingsStore = DashboardSettingsStore.shared

    /// The pegboard's brain, owned here so both the canvas and the floating "+" button
    /// (which adds widgets) share the one model + widget store.
    @StateObject private var canvasModel = DashboardCanvasModel(widgetStore: .shared)

    /// Local widget content owned by the user (Notes) and the Focus timer, injected into
    /// the environment so the bespoke widget views can read/edit them.
    /// Shared singletons (so the agent path can drive the same state later) — observed,
    /// like `settingsStore`, since the view doesn't own their lifecycle.
    @ObservedObject private var localStore = DashboardLocalStore.shared
    @ObservedObject private var focusModel = DashboardFocusModel.shared

    /// Whether the settings page is showing in place of the dashboard.
    @State private var isShowingSettings = false

    /// Whether the greeting intro splash is playing. Starts true so it runs on the first
    /// open, and is re-armed on every `.perchShowDashboard` (each time the window is
    /// brought to front) so the greeting plays whenever the dashboard is opened.
    @State private var isPlayingGreetingIntro = true

    var body: some View {
        ZStack {
            backgroundGradient

            if isShowingSettings {
                DashboardSettingsView(onClose: { isShowingSettings = false })
                    .transition(.opacity)
            } else {
                // The infinite pegboard canvas: greeting/weather header and every
                // widget live on it as movable, resizable items.
                DashboardCanvasView(model: canvasModel)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            // The settings bar lives only on the dashboard; the settings page has its
            // own close control.
            if !isShowingSettings {
                DashboardSettingsBar(onOpen: { isShowingSettings = true })
                    .padding(.top, 18)
                    .padding(.trailing, 24)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Pinned over the canvas (does not pan/zoom). Opens the "describe a widget"
            // input and adds the resulting data-driven widget to the board.
            if !isShowingSettings {
                DashboardAddWidgetButton(canvasModel: canvasModel)
                    .padding(24)
            }
        }
        .overlay {
            // The opening greeting: shows "Good <time>, <Name>" front and center, then
            // glides into the greeting widget's spot before revealing the live dashboard.
            // Added last so it sits over the canvas, settings bar, and add button.
            if isPlayingGreetingIntro {
                DashboardGreetingIntro(
                    scrimColor: scrimColor,
                    canvasModel: canvasModel,
                    onFinished: { isPlayingGreetingIntro = false }
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            settingsStore.values.reduceMotion ? nil : .easeInOut(duration: 0.22),
            value: isShowingSettings
        )
        // Cross-fade the splash away when it hands off to the live dashboard.
        .animation(
            settingsStore.values.reduceMotion ? nil : .easeInOut(duration: 0.3),
            value: isPlayingGreetingIntro
        )
        // Re-arm the greeting each time an existing dashboard window is re-opened (a fresh
        // window already plays it from `isPlayingGreetingIntro`'s initial `true`).
        .onReceive(NotificationCenter.default.publisher(for: .perchDashboardDidPresent)) { _ in
            isPlayingGreetingIntro = true
        }
        // The bespoke Notes/Focus widgets read these via @EnvironmentObject.
        .environmentObject(localStore)
        .environmentObject(focusModel)
    }

    // MARK: Background (driven live by settings)

    private var backgroundGradient: some View {
        // A tint scrim over the window's .hudWindow vibrancy material. Its color comes
        // from the chosen tint and its opacity from the translucency / reduce-
        // transparency settings — so changing those updates the glass immediately.
        scrimColor
            .opacity(scrimOpacity)
            .ignoresSafeArea()
    }

    /// Higher translucency = more desktop showing = a thinner scrim. "Reduce
    /// transparency" pins it solid.
    private var scrimOpacity: Double {
        if settingsStore.values.reduceTransparency { return 1.0 }
        return max(0.0, min(1.0, 1.0 - settingsStore.values.glassTranslucency))
    }

    /// The tint color painted over the glass. All variants stay dark so the light
    /// on-glass header text remains readable (a full light theme is a follow-up).
    private var scrimColor: Color {
        switch settingsStore.values.backgroundTint {
        case "Slate": return Color(red: 0.10, green: 0.13, blue: 0.18)
        case "Warm": return Color(oklch: 0.15, chroma: 0.025, hue: 60)
        case "Blue": return Color(red: 0.07, green: 0.11, blue: 0.20)
        case "Green": return Color(red: 0.07, green: 0.14, blue: 0.10)
        default: return Color(white: 0.07) // Graphite
        }
    }
}

// MARK: - Settings bar (top-right entry point)

/// The small top-right control that opens the settings page.
struct DashboardSettingsBar: View {
    var onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(DashboardTheme.Colors.onTintSecondary)
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(Color.white.opacity(isHovering ? 0.16 : 0.08))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Floating add-widget button

struct DashboardAddWidgetButton: View {
    @ObservedObject var canvasModel: DashboardCanvasModel

    @State private var isHovering = false

    var body: some View {
        // Clicking "+" drops a new draft widget (a card with a textbox inside) onto the
        // board and pans to reveal it; the user describes it there and it goes live.
        Button(action: { canvasModel.createDraftWidget() }) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 58, height: 58)
                .background(
                    Circle().fill(isHovering
                                  ? DashboardTheme.Colors.addButtonHover
                                  : DashboardTheme.Colors.addButton)
                )
                .shadow(color: DashboardTheme.Colors.addButtonShadow, radius: 13, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            // Every interactive element shows a pointer cursor (project convention).
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}
