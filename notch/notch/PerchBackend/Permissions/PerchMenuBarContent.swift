//
//  PerchMenuBarContent.swift
//  notch
//
//  The full menu-bar dropdown, rendered as a SwiftUI window rather than a native
//  AppKit menu. The window presentation is what lets the three permission rows show
//  real switch toggles — a native `MenuBarExtra` menu collapses every `Toggle` into a
//  checkmark item and ignores `.toggleStyle(.switch)`. Here we lay the dropdown out by
//  hand: switch-style Eyes/Ears/Hands rows on top, then the usual action rows
//  (Settings / Check for Updates / Restart / Quit) styled to read like menu items.
//

import SwiftUI
import Sparkle

struct PerchMenuBarContent: View {
    @ObservedObject var toggles: PerchCapabilityToggles
    let updater: SPUUpdater

    /// Closes the dropdown window after an action row is chosen. The toggle rows
    /// deliberately do NOT dismiss — keeping the window open is the whole point of the
    /// switch presentation, so several abilities can be flipped in one visit.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PerchPermissionsMenuContent(toggles: toggles)

            menuDivider

            actionRow(title: "Settings", systemImage: "gearshape") {
                dismiss()
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }

            CheckForUpdatesMenuRow(updater: updater) { dismiss() }

            menuDivider

            actionRow(title: "Restart", systemImage: "arrow.clockwise") {
                dismiss()
                ApplicationRelauncher.restart()
            }

            actionRow(title: "Quit", systemImage: "power", isDestructive: true) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
        .frame(width: 260)
    }

    private var menuDivider: some View {
        Divider()
            .padding(.vertical, 4)
    }

    private func actionRow(
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PerchMenuRowButtonStyle(isDestructive: isDestructive))
    }
}

/// The "Check for Updates…" row, kept separate so it can disable itself while Sparkle
/// reports that no check is currently possible — matching the old native menu item.
private struct CheckForUpdatesMenuRow: View {
    @StateObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater
    private let onChosen: () -> Void

    init(updater: SPUUpdater, onChosen: @escaping () -> Void) {
        self.updater = updater
        self.onChosen = onChosen
        _checkForUpdatesViewModel = StateObject(
            wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button {
            onChosen()
            updater.checkForUpdates()
        } label: {
            Label("Check for Updates…", systemImage: "sparkle.magnifyingglass")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PerchMenuRowButtonStyle())
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

/// A button styled to read like a native menu row: full-width, subtle hover highlight,
/// and a pointer cursor on hover (per the project's interactive-element rule).
private struct PerchMenuRowButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(isDestructive ? DS.Colors.destructiveText : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.12) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
