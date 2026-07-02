//
//  DashboardSettingsModels.swift
//  Perch
//
//  Navigation model + the shared, persistent store for the dashboard's settings.
//
//  Sidebar: three sections (Visuals / Accessibility / Permissions). Only Visuals is
//  further split by scope (Dashboard / Perch); that split is a switcher shown in the
//  middle detail pane, not in the sidebar.
//
//  The store is a single shared instance saved to `support/dashboard-settings.json`
//  (via PerchSupportPaths, like DashboardLayoutStore), so choices persist across
//  launches and the dashboard background reacts to them live.
//

import Foundation
import SwiftUI

// MARK: - Sidebar navigation

/// Top-level settings sections — the three sidebar buttons.
enum DashboardSettingsSection: String, CaseIterable, Identifiable {
    case visuals
    case accessibility
    case permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visuals: return "Visuals"
        case .accessibility: return "Accessibility"
        case .permissions: return "Permissions"
        }
    }

    var systemIconName: String {
        switch self {
        case .visuals: return "paintbrush"
        case .accessibility: return "accessibility"
        case .permissions: return "lock.shield"
        }
    }
}

/// The Dashboard / Perch split — used ONLY inside the Visuals detail pane.
enum DashboardSettingsScope: String, CaseIterable, Identifiable {
    case dashboard
    case perch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .perch: return "Perch"
        }
    }
}

// MARK: - Persisted values

/// The full set of settings values, encoded to disk as one JSON document.
struct DashboardSettingsValues: Codable, Equatable {
    // Visuals · Dashboard
    var theme: String = "Dark"
    var fontStyle: String = "Editorial"
    var backgroundTint: String = "Graphite"
    var glassTranslucency: Double = 0.72

    // Visuals · Perch
    var cursorColor: String = "Blue"
    var accentFollowsCursor: Bool = true
    var triangleSize: String = "Medium"

    // Accessibility (not scoped)
    var reduceTransparency: Bool = false
    var increaseContrast: Bool = false
    var textSize: String = "Medium"
    var reduceMotion: Bool = false
    var voiceFeedback: Bool = true
    var captions: Bool = false

    // Permissions (not scoped)
    var dashboardNotifications: Bool = true
}

// MARK: - Shared store

/// Single source of truth for settings. Loads on first access, autosaves on change,
/// and is observed by both the dashboard (for live background changes) and the
/// settings page (for the controls).
@MainActor
final class DashboardSettingsStore: ObservableObject {
    static let shared = DashboardSettingsStore()

    @Published var values: DashboardSettingsValues {
        didSet {
            guard values != oldValue else { return }
            persist()
        }
    }

    private init() {
        values = Self.loadFromDisk() ?? DashboardSettingsValues()
    }

    // MARK: Persistence (mirrors DashboardLayoutStore)

    private static var settingsFileURL: URL {
        PerchSupportPaths.file("dashboard-settings.json")
    }

    private static func loadFromDisk() -> DashboardSettingsValues? {
        guard let savedData = try? Data(contentsOf: settingsFileURL) else { return nil }
        return try? JSONDecoder().decode(DashboardSettingsValues.self, from: savedData)
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encodedData = try encoder.encode(values)
            try encodedData.write(to: Self.settingsFileURL, options: .atomic)
        } catch {
            NSLog("[Dashboard] Failed to save settings: \(error.localizedDescription)")
        }
    }

    // MARK: Option lists (for the segmented pickers)

    static let themeOptions = ["Light", "Dark", "Auto"]
    static let fontOptions = ["Editorial", "Modern", "System"]
    static let tintOptions = ["Graphite", "Slate", "Warm", "Blue", "Green"]
    static let cursorColorOptions = ["Red", "Blue", "Yellow", "Green"]
    static let sizeOptions = ["Small", "Medium", "Large"]
}
