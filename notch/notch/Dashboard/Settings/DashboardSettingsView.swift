//
//  DashboardSettingsView.swift
//  leanring-buddy
//
//  The settings page shell: a light card on the dark glass holding the sidebar
//  (Visuals / Accessibility / Permissions) beside the detail pane for the current
//  section. Uses the shared, persisted settings store so changes stick and the
//  dashboard background reacts live.
//

import SwiftUI

struct DashboardSettingsView: View {
    /// Dismisses the settings page, returning to the dashboard.
    var onClose: () -> Void

    @ObservedObject private var store = DashboardSettingsStore.shared
    @State private var selectedSection: DashboardSettingsSection = .visuals
    @State private var visualsScope: DashboardSettingsScope = .dashboard

    var body: some View {
        VStack(spacing: 20) {
            header
            settingsCard
        }
        .frame(maxWidth: DashboardTheme.Metrics.contentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 64)
        .padding(.bottom, 56)
    }

    // MARK: Header (title + close, on the glass)

    private var header: some View {
        HStack(alignment: .center) {
            Text("Settings")
                .font(DashboardTheme.Fonts.serif(size: 30, weight: .ultraLight))
                .foregroundColor(DashboardTheme.Colors.onTintPrimary)
            Spacer()
            closeButton
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DashboardTheme.Colors.onTintSecondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .dashboardPointerOnHover()
    }

    // MARK: The light card (sidebar | detail)

    private var settingsCard: some View {
        HStack(spacing: 0) {
            DashboardSettingsSidebar(selectedSection: $selectedSection)
                .frame(width: 210, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(20)

            Rectangle()
                .fill(DashboardTheme.Colors.divider)
                .frame(width: 1)

            DashboardSettingsDetail(
                section: selectedSection,
                visualsScope: $visualsScope,
                store: store
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(DashboardTheme.Colors.cardBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: DashboardTheme.Colors.cardShadowDeep, radius: 30, x: 0, y: 20)
    }
}
