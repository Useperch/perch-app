//
//  DashboardSettingsControls.swift
//  Perch
//
//  Reusable building blocks for the settings detail pane: grouped containers,
//  setting rows, and the small controls (segmented picker, color swatches,
//  toggles, permission/integration rows) they hold. All styled for the light
//  settings card on the dark glass.
//

import AppKit
import SwiftUI

// MARK: - Pointer cursor helper

extension View {
    /// Show the pointing-hand cursor on hover (project convention for every
    /// interactive element).
    func dashboardPointerOnHover() -> some View {
        onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Group container

/// A titled group of setting rows inside a rounded, slightly-inset container.
struct DashboardSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(DashboardTheme.Fonts.sans(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundColor(DashboardTheme.Colors.textLabel)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DashboardTheme.Colors.settingsInset)
            )
        }
    }
}

/// A hairline between rows inside a group.
struct DashboardSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(DashboardTheme.Colors.divider)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

// MARK: - Generic row (label + trailing control)

struct DashboardSettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DashboardTheme.Fonts.sans(size: 14, weight: .medium))
                    .foregroundColor(DashboardTheme.Colors.textBody)
                if let subtitle {
                    Text(subtitle)
                        .font(DashboardTheme.Fonts.sans(size: 12))
                        .foregroundColor(DashboardTheme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

// MARK: - Segmented picker

struct DashboardSettingsSegmented: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Text(option)
                    .font(DashboardTheme.Fonts.sans(size: 12.5, weight: .medium))
                    .foregroundColor(isSelected ? .white : DashboardTheme.Colors.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelected ? DashboardTheme.Colors.sage : Color.clear)
                    )
                    .contentShape(Capsule(style: .continuous))
                    .onTapGesture { selection = option }
                    .dashboardPointerOnHover()
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(DashboardTheme.Colors.settingsTrack))
    }
}

// MARK: - Toggle

struct DashboardSettingsToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(DashboardTheme.Colors.sage)
            .dashboardPointerOnHover()
    }
}

// MARK: - Color swatches

/// A named, selectable color swatch (e.g. cursor color or background tint).
struct DashboardSettingsSwatch: Identifiable {
    var id: String { name }
    let name: String
    let color: Color
}

struct DashboardSettingsSwatchPicker: View {
    let swatches: [DashboardSettingsSwatch]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(swatches) { swatch in
                let isSelected = swatch.name == selection
                Circle()
                    .fill(swatch.color)
                    .frame(width: 24, height: 24)
                    .overlay(
                        // Selection ring sits just outside the swatch.
                        Circle()
                            .stroke(swatch.color, lineWidth: 2)
                            .padding(-3)
                            .opacity(isSelected ? 1 : 0)
                    )
                    .help(swatch.name)
                    .contentShape(Circle())
                    .onTapGesture { selection = swatch.name }
                    .dashboardPointerOnHover()
            }
        }
    }
}

// MARK: - Permission row

struct DashboardSettingsPermissionRow: View {
    let title: String
    var subtitle: String? = nil
    let isGranted: Bool

    var body: some View {
        DashboardSettingsRow(title: title, subtitle: subtitle) {
            if isGranted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Granted")
                        .font(DashboardTheme.Fonts.sans(size: 13, weight: .semibold))
                }
                .foregroundColor(DashboardTheme.Colors.grantedGreen)
            } else {
                Text("Grant")
                    .font(DashboardTheme.Fonts.sans(size: 13, weight: .semibold))
                    .foregroundColor(DashboardTheme.Colors.sage)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(DashboardTheme.Colors.sage.opacity(0.5), lineWidth: 1)
                    )
                    .contentShape(Capsule(style: .continuous))
                    .dashboardPointerOnHover()
            }
        }
    }
}

// MARK: - Integration row

struct DashboardSettingsIntegrationRow: View {
    let title: String
    let systemIconName: String
    let isConnected: Bool

    var body: some View {
        DashboardSettingsRow(title: title) {
            Text(isConnected ? "Connected" : "Connect")
                .font(DashboardTheme.Fonts.sans(size: 13, weight: .semibold))
                .foregroundColor(isConnected
                                 ? DashboardTheme.Colors.textTertiary
                                 : DashboardTheme.Colors.sage)
                .dashboardPointerOnHover()
        }
    }
}
