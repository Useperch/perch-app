//
//  DailyComicService.swift
//  notch
//
//  Fetches the day's comic for the brief's news section from XKCD's public JSON API
//  (no key, stable, CORS-free). Rather than the *latest* strip (which is a coin-flip on
//  humor), it rotates through a hand-picked set of genuinely funny, classic XKCD comics —
//  one per day-of-year, fetched by number from `https://xkcd.com/<num>/info.0.json`.
//
//  The brief degrades gracefully: any failure yields `nil` and the news section renders
//  without a comic (never a broken image).
//

import AppKit

enum DailyComicService {

    /// Hand-picked classic XKCD strips that reliably land — mostly tech/nerd humor, which
    /// fits the audience. Rotated by day so the comic changes but is always a known-good one.
    /// (327 Bobby Tables · 149 sudo sandwich · 353 import antigravity · 303 Compiling ·
    ///  386 Duty Calls · 538 $5 wrench · 979 Wisdom of the Ancients · 1597 Git ·
    ///  1168 tar · 1132 Frequentists vs Bayesians · 936 Password Strength · 2347 Dependency ·
    ///  1838 Machine Learning · 1739 Fixing Problems · 1053 Ten Thousand · 1205 Is It Worth the Time ·
    ///  285 Wikipedian Protester · 1316 Inexplicable.)
    private static let funnyComicNumbers = [
        327, 149, 353, 303, 386, 538, 979, 1597, 1168, 1132,
        936, 2347, 1838, 1739, 1053, 1205, 285, 1316
    ]

    /// Fetch the day's curated comic. Returns `nil` on any network/parse/image failure so
    /// the caller can omit the comic without special-casing errors.
    static func fetchTodaysComic(for date: Date = Date()) async -> DailyBriefComic? {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
        let number = funnyComicNumbers[(dayOfYear - 1) % funnyComicNumbers.count]
        if let comic = await fetchComic(number: number) { return comic }
        // If that specific strip can't be reached, fall back to the latest one.
        return await fetchComic(number: nil)
    }

    /// Fetch one XKCD strip by number (or the latest when `number` is `nil`).
    private static func fetchComic(number: Int?) async -> DailyBriefComic? {
        let urlString = number.map { "https://xkcd.com/\($0)/info.0.json" } ?? "https://xkcd.com/info.0.json"
        guard let metadataURL = URL(string: urlString) else { return nil }
        do {
            let (metadataData, metadataResponse) = try await URLSession.shared.data(from: metadataURL)
            guard let httpResponse = metadataResponse as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
                  let imageURLString = metadata["img"] as? String,
                  let imageURL = URL(string: imageURLString) else {
                return nil
            }

            let (imageData, imageResponse) = try await URLSession.shared.data(from: imageURL)
            guard let imageHTTPResponse = imageResponse as? HTTPURLResponse,
                  (200...299).contains(imageHTTPResponse.statusCode),
                  let image = NSImage(data: imageData) else {
                return nil
            }

            let title = (metadata["safe_title"] as? String) ?? (metadata["title"] as? String) ?? "Today's comic"
            let altText = (metadata["alt"] as? String) ?? ""
            return DailyBriefComic(title: title, image: image, altText: altText)
        } catch {
            NSLog("[DailyBrief] comic fetch failed: \(error.localizedDescription)")
            return nil
        }
    }
}
