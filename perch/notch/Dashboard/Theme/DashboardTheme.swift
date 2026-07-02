//
//  DashboardTheme.swift
//  Perch
//
//  Design tokens for the standalone Daily Dashboard surface.
//
//  This is a SEPARATE, light visual language from the dark notch design system
//  (`DS.*` in DesignSystem.swift). It is intentionally NOT part of `DS` — the
//  dashboard is a warm, serif-forward "daily overview" window, while `DS` is the
//  notch's pure-black hardware language. Keeping these apart prevents the two
//  palettes from contaminating each other. Everything dashboard-scoped is prefixed
//  `Dashboard*`.
//
//  The source design (Claude Design project "Personal daily dashboard design" →
//  Daily.dc.html) specifies every color in CSS `oklch(...)`. SwiftUI's `Color`
//  can't parse oklch, so `Color(oklch:chroma:hue:)` below converts it faithfully
//  (oklch → OKLab → linear sRGB → gamma sRGB). This lets us paste the design's
//  exact numbers straight from the source — refinement is copy/paste.
//

import SwiftUI

// MARK: - OKLCH → Color conversion

extension Color {
    /// Build a `Color` from an `oklch(lightness chroma hue)` triple, matching the
    /// CSS color function used throughout the dashboard design source.
    ///
    /// - Parameters:
    ///   - oklchLightness: perceptual lightness, 0...1 (CSS `L`).
    ///   - chroma: colorfulness, ~0...0.4 (CSS `C`).
    ///   - hue: hue angle in degrees, 0...360 (CSS `H`).
    ///   - opacity: alpha, 0...1.
    init(oklch oklchLightness: Double, chroma: Double, hue: Double, opacity: Double = 1.0) {
        let hueRadians = hue * Double.pi / 180.0
        let labA = chroma * cos(hueRadians)
        let labB = chroma * sin(hueRadians)

        // OKLab → nonlinear LMS (Björn Ottosson's matrices).
        let longCone = oklchLightness + 0.3963377774 * labA + 0.2158037573 * labB
        let mediumCone = oklchLightness - 0.1055613458 * labA - 0.0638541728 * labB
        let shortCone = oklchLightness - 0.0894841775 * labA - 1.2914855480 * labB

        let longConeLinear = longCone * longCone * longCone
        let mediumConeLinear = mediumCone * mediumCone * mediumCone
        let shortConeLinear = shortCone * shortCone * shortCone

        // LMS → linear sRGB.
        let redLinear = 4.0767416621 * longConeLinear - 3.3077115913 * mediumConeLinear + 0.2309699292 * shortConeLinear
        let greenLinear = -1.2684380046 * longConeLinear + 2.6097574011 * mediumConeLinear - 0.3413193965 * shortConeLinear
        let blueLinear = -0.0041960863 * longConeLinear - 0.7034186147 * mediumConeLinear + 1.7076147010 * shortConeLinear

        self.init(
            .sRGB,
            red: Color.gammaEncodeSRGBChannel(redLinear),
            green: Color.gammaEncodeSRGBChannel(greenLinear),
            blue: Color.gammaEncodeSRGBChannel(blueLinear),
            opacity: opacity
        )
    }

    /// Apply the sRGB transfer function to one linear-light channel and clamp to 0...1.
    private static func gammaEncodeSRGBChannel(_ linearChannel: Double) -> Double {
        let clampedLinearChannel = min(max(linearChannel, 0.0), 1.0)
        let encoded: Double
        if clampedLinearChannel <= 0.0031308 {
            encoded = clampedLinearChannel * 12.92
        } else {
            encoded = 1.055 * pow(clampedLinearChannel, 1.0 / 2.4) - 0.055
        }
        return min(max(encoded, 0.0), 1.0)
    }
}

// MARK: - Dashboard design tokens

/// The top-level namespace for the Daily Dashboard's tokens.
/// Usage: `DashboardTheme.Colors.cardBackground`, `DashboardTheme.Metrics.cardCornerRadius`.
enum DashboardTheme {

    // MARK: Colors

    enum Colors {

        // ── Window background scrim (thin, over the .hudWindow material) ──
        // NOT an opaque fill — just a near-black scrim at low opacity (see
        // DashboardView.backgroundOpacity) layered over the vibrancy material for a
        // touch of depth + legibility. The material itself supplies the dark tint
        // and blur; a heavy fill here would flatten the glass back to grey.
        static let backgroundGradientTop = Color(oklch: 0.18, chroma: 0, hue: 0)
        static let backgroundGradientMiddle = Color(oklch: 0.14, chroma: 0, hue: 0)
        static let backgroundGradientBottom = Color(oklch: 0.10, chroma: 0, hue: 0)

        // ── Header text on the dark tint (sits directly on the glass, not in a
        //    card — so these are light, unlike the dark in-card text tiers) ──
        static let onTintPrimary = Color(white: 0.96)
        static let onTintSecondary = Color(white: 0.80)
        static let onTintTertiary = Color(white: 0.66)
        static let onTintNameAccent = Color(white: 0.90)
        /// Sage lightened so it reads on the dark glass (weather icon).
        static let sageOnTint = Color(oklch: 0.78, chroma: 0.06, hue: 150)

        // ── Card surfaces ────────────────────────────────────────────────
        /// Near-white warm fill for every widget card.
        static let cardBackground = Color(oklch: 0.995, chroma: 0.004, hue: 80)

        // ── Text tiers (warm grays) ──────────────────────────────────────
        /// Headings, contact names, serif display copy.
        static let textPrimary = Color(oklch: 0.34, chroma: 0.02, hue: 52)
        /// Agenda events, task labels.
        static let textBody = Color(oklch: 0.40, chroma: 0.02, hue: 52)
        /// Email descriptions, supporting copy.
        static let textSecondary = Color(oklch: 0.55, chroma: 0.018, hue: 55)
        /// Timestamps, low-emphasis captions.
        static let textTertiary = Color(oklch: 0.68, chroma: 0.018, hue: 55)
        /// Uppercase tracked labels (widget headers, the date line).
        static let textLabel = Color(oklch: 0.62, chroma: 0.022, hue: 58)
        /// The italic name in the greeting.
        static let greetingNameAccent = Color(oklch: 0.42, chroma: 0.03, hue: 50)
        /// Serif time stamps in the Today agenda.
        static let agendaTimeMuted = Color(oklch: 0.50, chroma: 0.025, hue: 62)

        // ── Sage accent family (the one accent hue, 150°) ────────────────
        /// Primary sage — the focus-ring progress arc.
        static let sage = Color(oklch: 0.56, chroma: 0.05, hue: 150)
        /// Widget header icons.
        static let sageHeaderIcon = Color(oklch: 0.58, chroma: 0.045, hue: 150)
        /// The weather block (icon + label).
        static let sageWeather = Color(oklch: 0.50, chroma: 0.045, hue: 150)
        /// "Begin a session" call-to-action text.
        static let sageCallToAction = Color(oklch: 0.52, chroma: 0.045, hue: 150)

        // ── Lines ─────────────────────────────────────────────────────────
        /// Hairline dividers between email rows; the focus-ring track.
        static let divider = Color(oklch: 0.93, chroma: 0.008, hue: 80)

        // ── Pegboard canvas (dots + drag/resize affordances on the dark glass) ──
        /// The little dots that make up the pegboard grid. Light, very low-opacity so
        /// they read as barely-there pinpoints over the dark tinted-glass background.
        static let pegDot = Color(white: 1.0, opacity: 0.24)
        /// The snapped-target ghost outline shown while dragging or resizing a card.
        static let snapPreview = Color(white: 1.0, opacity: 0.34)
        /// Fill of the small bottom-right resize handle (shown on hover).
        static let resizeHandle = Color(white: 1.0, opacity: 0.55)
        /// The top-center "grabber" pill on each (light) card — a subtle dark bar that
        /// invites dragging. (The header card, on dark glass, uses a light variant.)
        static let widgetGrabHandle = Color(white: 0.0, opacity: 0.14)
        /// The small hover-revealed close ("×") button at a card's top-right corner.
        /// Two variants so it reads on either surface: a dark disc on the light cards,
        /// a light disc on the dark-glass header card. Each darkens/brightens on hover.
        static let widgetCloseFillOnLight = Color(white: 0.0, opacity: 0.07)
        static let widgetCloseFillOnLightHover = Color(white: 0.0, opacity: 0.15)
        static let widgetCloseFillOnDark = Color(white: 1.0, opacity: 0.16)
        static let widgetCloseFillOnDarkHover = Color(white: 1.0, opacity: 0.30)
        /// The "×" glyph color on each surface.
        static let widgetCloseIconOnLight = Color(oklch: 0.50, chroma: 0.018, hue: 55)
        static let widgetCloseIconOnDark = Color(white: 0.92)
        /// Drop shadow cast by a card while it is being dragged (lifts off the board).
        static let dragShadow = Color(oklch: 0.05, chroma: 0, hue: 0, opacity: 0.40)

        // ── Weather block ────────────────────────────────────────────────
        static let weatherTemperature = Color(oklch: 0.44, chroma: 0.025, hue: 60)
        static let weatherSummary = Color(oklch: 0.60, chroma: 0.02, hue: 55)
        static let weatherDetail = Color(oklch: 0.68, chroma: 0.018, hue: 55)

        // ── Floating add button ──────────────────────────────────────────
        static let addButton = Color(oklch: 0.55, chroma: 0.07, hue: 150)
        static let addButtonHover = Color(oklch: 0.59, chroma: 0.08, hue: 150)
        static let addButtonShadow = Color(oklch: 0.50, chroma: 0.08, hue: 150, opacity: 0.55)

        // ── Card shadows (soft double shadow from the design) ────────────
        static let cardShadowSoft = Color(oklch: 0.50, chroma: 0.03, hue: 55, opacity: 0.06)
        static let cardShadowDeep = Color(oklch: 0.40, chroma: 0.03, hue: 50, opacity: 0.22)

        // ── Settings surfaces (inside the light settings card) ───────────
        /// Slightly-off-white fill for grouped control containers.
        static let settingsInset = Color(oklch: 0.965, chroma: 0.004, hue: 80)
        /// The recessed track behind segmented controls.
        static let settingsTrack = Color(oklch: 0.925, chroma: 0.006, hue: 80)
        /// Granted-permission / connected affirmative green.
        static let grantedGreen = Color(red: 0.204, green: 0.780, blue: 0.349)

        // ── Perch cursor presets ────────────────────────────────────────
        // Mirror DS.Colors.cursor* (Perch's canonical brand accents); duplicated
        // here only so the dashboard module stays self-contained.
        static let perchCursorRed = Color(red: 1.000, green: 0.263, blue: 0.220)
        static let perchCursorBlue = Color(red: 0.200, green: 0.502, blue: 1.000)
        static let perchCursorYellow = Color(red: 0.961, green: 0.725, blue: 0.129)
        static let perchCursorGreen = Color(red: 0.204, green: 0.780, blue: 0.349)
    }

    // MARK: Fonts

    /// The design pairs Spectral (serif) with Hanken Grotesk (sans). Those Google
    /// fonts aren't installed on macOS, so this starting point substitutes the
    /// system serif (New York) and SF Pro — close in spirit to the editorial feel.
    /// (Follow-up: bundle the real .ttf files for exact fidelity.)
    enum Fonts {
        /// Editorial serif display type (greeting, names, times, quote).
        static func serif(size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
            let baseFont = Font.system(size: size, weight: weight, design: .serif)
            return italic ? baseFont.italic() : baseFont
        }

        /// Sans body / label type.
        static func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            Font.system(size: size, weight: weight, design: .default)
        }
    }

    // MARK: Metrics

    /// Sizing constants mirroring the design's `grid-template-columns:repeat(4,1fr)`
    /// with `grid-auto-rows:172px` and `gap:24px` inside a `max-width:1080px` column.
    enum Metrics {
        static let contentMaxWidth: CGFloat = 1080
        static let columnCount: Int = 4
        static let gridGap: CGFloat = 24
        static let rowHeight: CGFloat = 172
        static let cardCornerRadius: CGFloat = 22

        // ── Pegboard canvas ──────────────────────────────────────────────
        /// World-space distance between adjacent pegs. A widget that spans N cells
        /// is N · pegSpacing wide/tall in world units. Cards snap their top-left to
        /// integer multiples of this.
        static let pegSpacing: CGFloat = 88
        /// Inset of a card within its cell footprint, so adjacent cards have a
        /// visible gap between them instead of touching (gap ≈ cellGap).
        static let cellGap: CGFloat = 16
        /// Radius of each pegboard dot at zoom 1.0 (scales gently with zoom).
        static let pegDotRadius: CGFloat = 1.8
        /// Side length of the bottom-right resize handle hit target.
        static let resizeHandleSize: CGFloat = 16
        /// Corner radius of the snap-preview ghost outline (matches the card).
        static let snapPreviewCornerRadius: CGFloat = 22

        // ── Zoom limits ──────────────────────────────────────────────────
        static let minZoom: CGFloat = 0.4
        static let maxZoom: CGFloat = 2.2
        static let defaultZoom: CGFloat = 1.0

        /// Width of a single grid column given the content width and gaps.
        static var singleColumnWidth: CGFloat {
            let totalGapWidth = gridGap * CGFloat(columnCount - 1)
            return (contentMaxWidth - totalGapWidth) / CGFloat(columnCount)
        }

        /// Width spanning `columnSpan` columns (including the gaps between them).
        static func width(forColumnSpan columnSpan: Int) -> CGFloat {
            let columnsWidth = singleColumnWidth * CGFloat(columnSpan)
            let interiorGapsWidth = gridGap * CGFloat(columnSpan - 1)
            return columnsWidth + interiorGapsWidth
        }

        /// Height spanning `rowSpan` rows (including the gaps between them).
        static func height(forRowSpan rowSpan: Int) -> CGFloat {
            let rowsHeight = rowHeight * CGFloat(rowSpan)
            let interiorGapsHeight = gridGap * CGFloat(rowSpan - 1)
            return rowsHeight + interiorGapsHeight
        }
    }
}
