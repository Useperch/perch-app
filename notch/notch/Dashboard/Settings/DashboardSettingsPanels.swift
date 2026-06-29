//
//  DashboardSettingsPanels.swift
//  leanring-buddy
//
//  The settings detail pane. Visuals shows a Dashboard/Perch switcher in the middle
//  and its controls drive the live dashboard background. Accessibility and
//  Permissions are not scoped. All controls bind to the shared, persisted store.
//

import SwiftUI

struct DashboardSettingsDetail: View {
    let section: DashboardSettingsSection
    /// The Dashboard/Perch scope — only meaningful for Visuals.
    @Binding var visualsScope: DashboardSettingsScope
    @ObservedObject var store: DashboardSettingsStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                switch section {
                case .visuals: visuals
                case .accessibility: accessibility
                case .permissions: permissions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }

    // Binding shortcut into the store's values.
    private var v: Binding<DashboardSettingsValues> { $store.values }

    // MARK: - Visuals (scoped: Dashboard / Perch switcher in the middle)

    private var visuals: some View {
        VStack(alignment: .leading, spacing: 24) {
            // The scope switcher lives here in the middle, centered — not in the sidebar.
            HStack {
                Spacer()
                DashboardSettingsSegmented(
                    options: DashboardSettingsScope.allCases.map { $0.title },
                    selection: Binding(
                        get: { visualsScope.title },
                        set: { newTitle in
                            visualsScope = DashboardSettingsScope.allCases
                                .first { $0.title == newTitle } ?? .dashboard
                        }
                    )
                )
                Spacer()
            }

            switch visualsScope {
            case .dashboard: visualsDashboard
            case .perch: visualsPerch
            }
        }
    }

    private var visualsDashboard: some View {
        VStack(alignment: .leading, spacing: 22) {
            DashboardSettingsGroup(title: "Appearance") {
                DashboardSettingsRow(title: "Theme") {
                    DashboardSettingsSegmented(options: DashboardSettingsStore.themeOptions, selection: v.theme)
                }
                DashboardSettingsDivider()
                DashboardSettingsRow(title: "Font", subtitle: "Editorial pairs a serif display with a sans body.") {
                    DashboardSettingsSegmented(options: DashboardSettingsStore.fontOptions, selection: v.fontStyle)
                }
            }

            DashboardSettingsGroup(title: "Background") {
                DashboardSettingsRow(title: "Tint", subtitle: "Live — changes the glass tint now.") {
                    DashboardSettingsSwatchPicker(swatches: backgroundTintSwatches, selection: v.backgroundTint)
                }
                DashboardSettingsDivider()
                DashboardSettingsRow(title: "Translucency", subtitle: "Live — how much desktop shows through.") {
                    Slider(value: v.glassTranslucency, in: 0...1)
                        .frame(width: 160)
                        .tint(DashboardTheme.Colors.sage)
                }
            }
        }
    }

    private var backgroundTintSwatches: [DashboardSettingsSwatch] {
        [
            DashboardSettingsSwatch(name: "Graphite", color: Color(white: 0.30)),
            DashboardSettingsSwatch(name: "Slate", color: Color(red: 0.30, green: 0.35, blue: 0.42)),
            DashboardSettingsSwatch(name: "Warm", color: DashboardTheme.Colors.textSecondary),
            DashboardSettingsSwatch(name: "Blue", color: DashboardTheme.Colors.perchCursorBlue),
            DashboardSettingsSwatch(name: "Green", color: DashboardTheme.Colors.sage)
        ]
    }

    private var visualsPerch: some View {
        VStack(alignment: .leading, spacing: 22) {
            DashboardSettingsGroup(title: "Cursor") {
                DashboardSettingsRow(title: "Cursor color", subtitle: "The accent Perch's pointer uses across the app.") {
                    DashboardSettingsSwatchPicker(swatches: cursorColorSwatches, selection: v.cursorColor)
                }
                DashboardSettingsDivider()
                DashboardSettingsRow(title: "Accent follows cursor", subtitle: "Match UI accents to the cursor color.") {
                    DashboardSettingsToggle(isOn: v.accentFollowsCursor)
                }
                DashboardSettingsDivider()
                DashboardSettingsRow(title: "Triangle size") {
                    DashboardSettingsSegmented(options: DashboardSettingsStore.sizeOptions, selection: v.triangleSize)
                }
            }
        }
    }

    private var cursorColorSwatches: [DashboardSettingsSwatch] {
        [
            DashboardSettingsSwatch(name: "Red", color: DashboardTheme.Colors.perchCursorRed),
            DashboardSettingsSwatch(name: "Blue", color: DashboardTheme.Colors.perchCursorBlue),
            DashboardSettingsSwatch(name: "Yellow", color: DashboardTheme.Colors.perchCursorYellow),
            DashboardSettingsSwatch(name: "Green", color: DashboardTheme.Colors.perchCursorGreen)
        ]
    }

    // MARK: - Accessibility (not scoped)

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 22) {
            DashboardSettingsGroup(title: "Display") {
                DashboardSettingsRow(title: "Reduce transparency", subtitle: "Live — makes the glass background solid.") {
                    DashboardSettingsToggle(isOn: v.reduceTransparency)
                }
                DashboardSettingsDivider()
                DashboardSettingsRow(title: "Increase contrast") {
                    DashboardSettingsToggle(isOn: v.increaseContrast)
                }
                DashboardSettingsDivider()
                DashboardSettingsRow(title: "Text size") {
                    DashboardSettingsSegmented(options: DashboardSettingsStore.sizeOptions, selection: v.textSize)
                }
            }

            DashboardSettingsGroup(title: "Motion & voice") {
                DashboardSettingsRow(title: "Reduce motion", subtitle: "Live — minimizes transitions.") {
                    DashboardSettingsToggle(isOn: v.reduceMotion)
                }
                DashboardSettingsDivider()
                DashboardSettingsRow(title: "Voice feedback", subtitle: "Perch speaks its answers aloud.") {
                    DashboardSettingsToggle(isOn: v.voiceFeedback)
                }
                DashboardSettingsDivider()
                DashboardSettingsRow(title: "Captions") {
                    DashboardSettingsToggle(isOn: v.captions)
                }
            }
        }
    }

    // MARK: - Permissions (not scoped)

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 22) {
            DashboardSettingsGroup(title: "System permissions") {
                DashboardSettingsPermissionRow(title: "Microphone", subtitle: "Push-to-talk voice capture.", isGranted: true)
                DashboardSettingsDivider()
                DashboardSettingsPermissionRow(title: "Accessibility", subtitle: "Global shortcut + desktop actions.", isGranted: true)
                DashboardSettingsDivider()
                DashboardSettingsPermissionRow(title: "Screen Recording", subtitle: "Screenshots for Perch's vision.", isGranted: true)
                DashboardSettingsDivider()
                DashboardSettingsPermissionRow(title: "Full Disk Access", subtitle: "Only for the browser sidecar.", isGranted: false)
            }

            DashboardSettingsGroup(title: "Active integrations") {
                DashboardSettingsIntegrationRow(title: "Gmail", systemIconName: "envelope", isConnected: true)
                DashboardSettingsDivider()
                DashboardSettingsIntegrationRow(title: "Google Calendar", systemIconName: "calendar", isConnected: true)
                DashboardSettingsDivider()
                DashboardSettingsIntegrationRow(title: "Notion", systemIconName: "doc.text", isConnected: false)
                DashboardSettingsDivider()
                DashboardSettingsIntegrationRow(title: "Slack", systemIconName: "number", isConnected: false)
            }

            DashboardSettingsGroup(title: "Notifications") {
                DashboardSettingsRow(title: "Allow notifications", subtitle: "Nudges for focus sessions and water.") {
                    DashboardSettingsToggle(isOn: v.dashboardNotifications)
                }
            }
        }
    }
}
