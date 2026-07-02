//
//  DailyBriefTitleCard.swift
//  notch
//
//  The brief's hero: the day's painting in a rounded card with three overlaid layers —
//  the matching header pair ("Made for Karthik" top-left, the date top-right, identical
//  type), and the large gold title ("Your <Weekday> Brief", the "Your" in italic Didot
//  over the weekday + "Brief" in roman). The painting's signature is part of the artwork
//  itself, so it isn't drawn here.
//
//  Built from a fixed-height image + `.overlay`s (NOT a GeometryReader on the card itself)
//  so it honors the reading column's width. The MAIN title line is sized + lightly tracked
//  to FILL the card width edge-to-edge — measured from the actual card width via a
//  GeometryReader that lives inside an overlay (so it reads the card's size without making
//  the card greedy).
//

import SwiftUI
import AppKit

struct DailyBriefTitleCard: View {
    let firstName: String
    let dateLine: String
    let weekdayName: String
    let artwork: DailyBriefArtwork

    /// A fixed, gently-landscape card height; the image fills the column width above it.
    private let cardHeight: CGFloat = 600
    private let cornerRadius: CGFloat = 18
    /// Horizontal breathing room the title keeps from the card edges when it fills.
    private let titleHorizontalInset: CGFloat = 40

    var body: some View {
        Image(artwork.imageName)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .clipped()
            .overlay(vignette)
            .overlay(topScrim, alignment: .top)
            .overlay(headerPair, alignment: .top)
            .overlay(titleStack)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: Layers

    /// A faint light wash at the very top so the dark header text stays legible even over
    /// a dark painting. Invisible over a light scene (light-on-light), so it never muddies
    /// a calm sky — it only lifts the headers when the art behind them is dark.
    private var topScrim: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.32), Color.white.opacity(0.0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 78)
        .blendMode(.softLight)
    }

    /// A whisper-soft vignette so the gold title and dark headers read on any lighting.
    private var vignette: some View {
        RadialGradient(
            colors: [Color.black.opacity(0.04), Color.black.opacity(0.20)],
            center: .center,
            startRadius: 0,
            endRadius: cardHeight * 0.9
        )
    }

    /// "Made for Karthik" and the date — one shared style so the pair matches exactly.
    private var headerPair: some View {
        HStack(alignment: .top) {
            Text("Made for \(firstName)")
            Spacer(minLength: 16)
            Text(dateLine)
        }
        .font(DailyBriefStyle.cardHeader())
        .foregroundColor(DailyBriefStyle.cardHeaderInk)
        .shadow(color: .white.opacity(0.25), radius: 2, y: 0)
        .padding(.horizontal, 26)
        .padding(.top, 20)
    }

    private var titleStack: some View {
        GeometryReader { proxy in
            let fillWidth = proxy.size.width - titleHorizontalInset * 2
            // Size the main line so "<Weekday> Brief" spans the full card width; a small
            // tracking spreads the letters for the editorial, justified feel.
            let mainSize = Self.fittedFontSize(
                for: "\(weekdayName) Brief",
                fontName: "Didot",
                targetWidth: fillWidth * 0.97,
                maxSize: 170
            )
            VStack(spacing: -mainSize * 0.05) {
                Text("Your")
                    .font(DailyBriefStyle.title(size: mainSize * 0.46, italic: true))
                    .lineLimit(1)
                Text("\(weekdayName) Brief")
                    .font(DailyBriefStyle.title(size: mainSize))
                    .tracking(mainSize * 0.012)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .foregroundColor(DailyBriefStyle.titleGold)
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            // Sit a touch above center — the skies in these paintings read in the upper half.
            .offset(y: -proxy.size.height * 0.03)
        }
    }

    // MARK: Type fitting

    /// The point size at which `text` (in `fontName`) is exactly `targetWidth` wide, capped
    /// at `maxSize`. Measured with AppKit so the title fills the card regardless of how long
    /// the weekday is ("Monday Brief" vs "Wednesday Brief" both span the width).
    private static func fittedFontSize(
        for text: String, fontName: String, targetWidth: CGFloat, maxSize: CGFloat
    ) -> CGFloat {
        let referenceSize: CGFloat = 100
        let font = NSFont(name: fontName, size: referenceSize)
            ?? NSFont.systemFont(ofSize: referenceSize)
        let measuredWidth = (text as NSString).size(withAttributes: [.font: font]).width
        guard measuredWidth > 1 else { return maxSize }
        return min(maxSize, referenceSize * targetWidth / measuredWidth)
    }
}
