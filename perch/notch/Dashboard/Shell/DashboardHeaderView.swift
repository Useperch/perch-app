//
//  DashboardHeaderView.swift
//  Perch
//
//  The Daily Dashboard's two header widgets, each its own draggable/resizable canvas
//  item sitting directly on the glass (no card chrome): the serif greeting (real date +
//  time-of-day salutation + the macOS account's name) and the weather readout (live
//  conditions from the keyless `weather` provider, showing a quiet placeholder while the
//  first reading is still loading — never a fabricated temperature).
//

import SwiftUI

/// The serif greeting block — its own draggable/resizable widget on the canvas. Computed
/// from the current date/time and the signed-in account name; no fixtures.
struct DashboardGreetingView: View {
    /// Re-evaluated each time the view appears so the date/salutation stay current across
    /// the day (the dashboard is a long-lived window).
    @State private var now = Date()

    var body: some View {
        DashboardGreetingContent(now: now)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { now = Date() }
    }
}

/// The greeting's text block (date line + salutation + name), left-aligned. Shared by the
/// on-canvas greeting widget (`DashboardGreetingView`) and the open-dashboard intro splash
/// (`DashboardGreetingIntro`) so both render identically — the splash glides this exact
/// block from screen-center into the widget's spot, so the hand-off is seamless.
struct DashboardGreetingContent: View {
    /// The moment the greeting is rendered for; drives the date line + salutation.
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(DashboardGreetingText.dateLine(for: now).uppercased())
                .font(DashboardTheme.Fonts.sans(size: 12, weight: .medium))
                .tracking(0.32 * 12)
                .foregroundColor(DashboardTheme.Colors.onTintSecondary)
                .padding(.bottom, 22)

            // The salutation in light serif, then the name on its own line in a heavier
            // italic serif accent.
            VStack(alignment: .leading, spacing: 0) {
                Text(DashboardGreetingText.salutation(for: now))
                    .font(DashboardTheme.Fonts.serif(size: 62, weight: .ultraLight))
                    .foregroundColor(DashboardTheme.Colors.onTintPrimary)
                Text(DashboardGreetingText.accountFirstName)
                    .font(DashboardTheme.Fonts.serif(size: 62, weight: .regular, italic: true))
                    .foregroundColor(DashboardTheme.Colors.onTintNameAccent)
            }
            .lineSpacing(0)
        }
    }
}

/// The greeting's computed strings, in one place so the canvas widget and the intro
/// splash always say exactly the same thing.
enum DashboardGreetingText {
    /// "Thursday, June 19" for the given date.
    static func dateLine(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }

    /// A time-of-day salutation ending in a comma, to match the design.
    static func salutation(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 0..<12:  return "Good morning,"
        case 12..<18: return "Good afternoon,"
        default:      return "Good evening,"
        }
    }

    /// The macOS account holder's first name (e.g. "Karthik"), falling back to a friendly
    /// default if the system name is empty.
    static var accountFirstName: String {
        let fullName = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        let firstName = fullName.split(separator: " ").first.map(String.init) ?? ""
        return firstName.isEmpty ? "there" : firstName
    }
}

/// The weather readout — its own draggable/resizable widget on the canvas. Renders the
/// widget's single live `cachedItem` (temperature/summary/location), showing a quiet
/// placeholder while the first reading loads so the header never reads as broken — and
/// never shows an invented temperature.
struct DashboardWeatherView: View {
    let widget: DashboardWidget
    @ObservedObject var widgetStore: DashboardWidgetStore

    private var liveWidget: DashboardWidget {
        widgetStore.widget(for: widget.id) ?? widget
    }

    /// The weather provider returns one item: `title` = temperature, `subtitle` = summary,
    /// `detail` = "City · H xx° · L yy°". While there's no live reading, show a neutral
    /// placeholder ("Checking conditions…" before the first fetch settles).
    private var temperature: String {
        liveWidget.cachedItems.first?.title ?? "—"
    }
    private var summary: String {
        let liveSummary = liveWidget.cachedItems.first?.subtitle
        if let liveSummary, !liveSummary.isEmpty { return liveSummary }
        return liveWidget.lastRefreshed == nil ? "Checking conditions…" : "Weather unavailable"
    }
    private var locationAndRange: String {
        let liveDetail = liveWidget.cachedItems.first?.detail
        return (liveDetail?.isEmpty == false ? liveDetail! : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "sun.max")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(DashboardTheme.Colors.sageOnTint)
                Text(temperature)
                    .font(DashboardTheme.Fonts.serif(size: 42, weight: .ultraLight))
                    .foregroundColor(DashboardTheme.Colors.onTintPrimary)
            }

            Text(summary)
                .font(DashboardTheme.Fonts.sans(size: 13))
                .foregroundColor(DashboardTheme.Colors.onTintSecondary)
                .padding(.top, 10)

            // Only shown once there's a real location/range — no empty line while loading.
            if !locationAndRange.isEmpty {
                Text(locationAndRange)
                    .font(DashboardTheme.Fonts.sans(size: 12))
                    .foregroundColor(DashboardTheme.Colors.onTintTertiary)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
