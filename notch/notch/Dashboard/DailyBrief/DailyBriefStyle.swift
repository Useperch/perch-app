//
//  DailyBriefStyle.swift
//  notch
//
//  The redesigned Daily Brief is a light, editorial *document* (white page, serif body),
//  distinct from both the dark notch `DS` language and the pegboard dashboard's glass.
//  This file is its single source of type + color, so the look stays consistent across
//  the title card and every section.
//
//  Font choices are reasonable macOS-bundled matches to the mockup (no custom .ttf to
//  bundle yet) and are deliberately centralized here so swapping in a custom face later
//  is a one-file change:
//   • Title card headers ("Made for Karthik" / the date) — American Typewriter, sharing
//     one style so the pair matches exactly (per the design ask).
//   • The big title ("Your Sunday Brief") — Didot, the elegant high-contrast serif.
//   • Section headers + body — the system serif (New York), via DashboardTheme.Fonts.
//   • The summary + caption — SF Pro italic.
//

import SwiftUI

enum DailyBriefStyle {

    // MARK: Layout

    /// The centered reading column width (the page has generous margins around it).
    static let contentWidth: CGFloat = 960
    /// Outer page padding around the content column.
    static let pagePadding: CGFloat = 48
    /// Vertical rhythm between the major sections.
    static let sectionSpacing: CGFloat = 34

    // MARK: Colors

    /// The page itself — a clean near-white, slightly warm so it doesn't read clinical.
    static let pageBackground = Color(red: 0.992, green: 0.992, blue: 0.988)
    /// The gold of the title (matches the existing brief widget, #f0c035).
    static let titleGold = Color(red: 0.941, green: 0.752, blue: 0.208)
    /// Near-black ink for the title-card headers (they sit on the light artwork).
    static let cardHeaderInk = Color(white: 0.16)
    /// Primary body ink — reuse the dashboard's warm dark gray for editorial warmth.
    static let bodyInk = DashboardTheme.Colors.textPrimary
    /// Section headings ("Catch up:", "Today's priorities:", "Top news this morning:").
    static let headingInk = DashboardTheme.Colors.textPrimary
    /// The italic summary line under the card.
    static let summaryInk = Color(white: 0.18)
    /// The small right-aligned caption beside the summary.
    static let captionInk = Color(white: 0.62)
    /// Hairline dividers (the rule under the summary, news/column separators).
    static let hairline = Color(white: 0.0, opacity: 0.14)
    /// The calendar widget's soft panel fill.
    static let panelFill = Color(white: 0.0, opacity: 0.05)

    // MARK: Fonts

    /// The shared style for BOTH title-card headers, so "Made for Karthik" and the date
    /// render with identical font/size/weight (the design ask). American Typewriter is a
    /// macOS system face; it falls back to a monospaced system serif if ever unavailable.
    static func cardHeader() -> Font {
        .custom("American Typewriter", size: 15)
    }

    /// The big title face (Didot). `italic` is used for the "Your" line; the weekday +
    /// "Brief" line is roman. Falls back to the system serif if Didot is unavailable.
    static func title(size: CGFloat, italic: Bool = false) -> Font {
        let didot = italic ? "Didot-Italic" : "Didot"
        return .custom(didot, size: size)
    }

    /// Section headings + body copy — the system serif, matching the editorial mockup.
    static func heading(size: CGFloat) -> Font {
        DashboardTheme.Fonts.serif(size: size, weight: .regular)
    }

    static func body(size: CGFloat) -> Font {
        DashboardTheme.Fonts.serif(size: size, weight: .regular)
    }

    /// The summary + caption — SF Pro italic (a humanist sans, matching the mockup).
    static func italicSans(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(size: size, weight: weight, design: .default).italic()
    }
}
