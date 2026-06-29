//
//  DailyBriefArtworkLibrary.swift
//  notch
//
//  The curated set of title-card paintings that rotate by day. Each entry pairs an
//  asset-catalog image name with the short caption shown beside the brief's summary.
//  `artwork(for:)` picks one deterministically from the day-of-year, so the card is
//  stable for a given day but changes from one day to the next.
//
//  Growing the set is a two-step, no-code-logic change: drop a public-domain painting
//  into `Assets.xcassets` and append one entry here. The rotation works with whatever
//  number of entries are present (1…N). Curate calm, light-toned paintings — the header
//  text sits directly on the art (matching the mockup), so a bright scene keeps it legible.
//

import Foundation

enum DailyBriefArtworkLibrary {

    /// The curated paintings, in no particular order. Seeded with the one existing
    /// `daily-brief-painting` asset (Monet, "Vétheuil"); append more as they're bundled.
    static let artworks: [DailyBriefArtwork] = [
        DailyBriefArtwork(
            imageName: "daily-brief-painting",
            caption: "A calm scene for a calm day"
        )
    ]

    /// The painting for a given day. Deterministic on the day-of-year so the card is
    /// stable through the day and advances each morning. Falls back to the first entry
    /// if (somehow) the library is empty, so the title card never renders blank.
    static func artwork(for date: Date) -> DailyBriefArtwork {
        guard !artworks.isEmpty else {
            return DailyBriefArtwork(imageName: "daily-brief-painting", caption: "")
        }
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let index = (dayOfYear - 1) % artworks.count
        return artworks[index]
    }
}
