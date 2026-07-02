//
//  DashboardSettingsSidebar.swift
//  Perch
//
//  The settings sidebar: three buttons — Visuals, Accessibility, Permissions.
//  Selecting one drives the detail pane. (The Dashboard/Perch split lives in the
//  middle pane for Visuals only, not here.)
//

import SwiftUI

struct DashboardSettingsSidebar: View {
    @Binding var selectedSection: DashboardSettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(DashboardSettingsSection.allCases) { section in
                sectionButton(section)
            }
            Spacer(minLength: 0)
        }
    }

    private func sectionButton(_ section: DashboardSettingsSection) -> some View {
        let isSelected = selectedSection == section
        return HStack(spacing: 10) {
            Image(systemName: section.systemIconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected
                                 ? DashboardTheme.Colors.sage
                                 : DashboardTheme.Colors.textTertiary)
                .frame(width: 18)
            Text(section.title)
                .font(DashboardTheme.Fonts.sans(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected
                                 ? DashboardTheme.Colors.textPrimary
                                 : DashboardTheme.Colors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? DashboardTheme.Colors.sage.opacity(0.14) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedSection = section }
        .dashboardPointerOnHover()
    }
}
