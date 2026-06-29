//
//  PerchPermissionsMenuContent.swift
//  notch
//
//  The "Permissions" block at the top of the menu-bar dropdown. Three switch toggles —
//  Eyes / Ears / Hands — each backed by `PerchCapabilityToggles`, so flipping one
//  immediately gates the matching ability (screen capture / microphone / desktop
//  actuation) and persists the choice.
//
//  These render as real switches (not checkmarks), which is why the dropdown is hosted
//  as a SwiftUI window via `.menuBarExtraStyle(.window)` — see `PerchMenuBarContent`.
//  A one-line description for each ability rides along as a hover tooltip via `.help`.
//

import SwiftUI

struct PerchPermissionsMenuContent: View {
    @ObservedObject var toggles: PerchCapabilityToggles

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permissions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 2)

            permissionToggleRow(
                title: "Vision",
                help: "Vision — lets Perch see your screen. Sends a screenshot when you hold ⌃⌥ or open it.",
                isOn: $toggles.isEyesEnabled)

            permissionToggleRow(
                title: "Microphone",
                help: "Microphone — lets Perch hear you. Uses the microphone for push-to-talk voice.",
                isOn: $toggles.isEarsEnabled)

            permissionToggleRow(
                title: "Accessibility",
                help: "Accessibility — lets Perch act for you. Moves the cursor, clicks, and types.",
                isOn: $toggles.isHandsEnabled)
        }
    }

    private func permissionToggleRow(
        title: String,
        help: String,
        isOn: Binding<Bool>
    ) -> some View {
        // Label on the left, switch pushed to the right edge. A labelless Toggle keeps
        // the switch hard against the trailing edge regardless of the title's length.
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .help(help)
    }
}
