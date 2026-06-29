//
//  NotchAccentColor.swift
//  notch
//
//  Album-art accent helpers for notch action buttons (Daily Brief + alert CTAs).
//

import SwiftUI

enum NotchAccentColor {
    static func fromMusicAccent(_ averageColor: NSColor) -> Color {
        Color(nsColor: averageColor).ensureMinimumBrightness(factor: 0.55)
    }

    static func labelColor(on accentColor: Color) -> Color {
        accentColor.luminance > 0.62 ? Color.black.opacity(0.85) : .white
    }
}

private extension Color {
    var luminance: CGFloat {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return 0.5 }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }
}