//
//  DashboardNewsRow.swift
//  Perch
//
//  One headline inside a web/news widget. Unlike the generic list row (which pairs a
//  serif title with a sans summary), a news item is a single clean headline — so a flat
//  list of them reads as an undifferentiated wall of serif text with no sense of *where*
//  each story came from. This row fixes that: it draws the publisher (derived from the
//  link's domain) as a small kicker above the headline, the way an editorial feed does,
//  so the list is scannable at a glance and every headline is attributable to a source.
//
//  Clicking a row opens its URL — the same target the agent resolves for "open the top
//  headline".
//

import AppKit
import SwiftUI

struct DashboardNewsRow: View {
    let item: DashboardWidgetItem
    /// Called when the row is clicked. The list view supplies this so it can also log the
    /// interaction for ranking; the default just opens the URL.
    var onActivate: (DashboardWidgetItem) -> Void

    @State private var isHovering = false

    /// The outlet name shown as the kicker above the headline, derived from the item's URL
    /// (e.g. a techcrunch.com link → "TechCrunch"). `nil` when the item carries no URL.
    private var publisherName: String? {
        DashboardNewsPublisher.displayName(forURLString: item.url)
    }

    var body: some View {
        Button {
            onActivate(item)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                if let publisherName {
                    Text(publisherName)
                        .font(DashboardTheme.Fonts.sans(size: 11, weight: .semibold))
                        .foregroundColor(DashboardTheme.Colors.sageHeaderIcon)
                        .lineLimit(1)
                }

                Text(item.title)
                    .font(DashboardTheme.Fonts.serif(size: 17, weight: .medium))
                    .foregroundColor(DashboardTheme.Colors.textPrimary)
                    // A headline can run past a narrow card's width; allow a second line so
                    // it reads cleanly instead of clipping the first line to "…".
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isHovering ? 0.7 : 1.0)
        .onHover { hovering in
            isHovering = hovering
            // A clickable headline gets the pointer cursor; an inert row (no URL) keeps the
            // canvas's default.
            if hovering && item.url != nil {
                NSCursor.pointingHand.push()
            } else if !hovering {
                NSCursor.pop()
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

// MARK: - Publisher name derivation

/// Turns a headline's link into a short, human outlet name for the row's kicker.
///
/// The domain is the only attribution a web/news item carries, so we read the name off
/// the URL host: a small curated map gives the common outlets their proper casing
/// (techcrunch.com → "TechCrunch"), and anything else falls back to the bare
/// second-level domain, capitalized (example.com → "Example"). The map is deliberately
/// small — it only exists to case the handful of outlets that read wrong when naively
/// capitalized; an unmapped outlet still renders a sensible name.
enum DashboardNewsPublisher {

    static func displayName(forURLString urlString: String?) -> String? {
        guard let urlString,
              let host = URL(string: urlString)?.host?.lowercased(),
              !host.isEmpty
        else { return nil }

        let bareHost = stripLeadingSubdomain(from: host)
        if let curatedName = curatedDisplayNames[bareHost] {
            return curatedName
        }
        return capitalizedSecondLevelLabel(from: bareHost)
    }

    /// Strip a leading `www.`/`m.`/`amp.` subdomain so `www.cnbc.com` and `cnbc.com`
    /// resolve to the same outlet.
    private static func stripLeadingSubdomain(from host: String) -> String {
        for prefix in ["www.", "m.", "amp."] where host.hasPrefix(prefix) {
            return String(host.dropFirst(prefix.count))
        }
        return host
    }

    /// The registrable label just before the public suffix — `techcrunch` from
    /// `techcrunch.com`, `bbc` from `bbc.co.uk` — capitalized for display.
    private static func capitalizedSecondLevelLabel(from host: String) -> String? {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }

        // Two-part public suffixes (co.uk, com.au, …) push the registrable label one
        // position earlier than a plain `.com` would.
        let twoPartSuffixes: Set<String> = ["co.uk", "com.au", "co.jp", "co.in", "com.br"]
        let lastTwo = labels.suffix(2).joined(separator: ".")
        let registrableLabel = twoPartSuffixes.contains(lastTwo)
            ? labels[labels.count - 3 >= 0 ? labels.count - 3 : 0]
            : labels[labels.count - 2]

        guard let firstCharacter = registrableLabel.first else { return nil }
        return firstCharacter.uppercased() + registrableLabel.dropFirst()
    }

    /// Proper-cased names for outlets that a naive capitalize would get wrong.
    private static let curatedDisplayNames: [String: String] = [
        "techcrunch.com": "TechCrunch",
        "thenextweb.com": "The Next Web",
        "theverge.com": "The Verge",
        "arstechnica.com": "Ars Technica",
        "wired.com": "WIRED",
        "cnbc.com": "CNBC",
        "cnn.com": "CNN",
        "bbc.com": "BBC",
        "bbc.co.uk": "BBC",
        "nytimes.com": "The New York Times",
        "wsj.com": "The Wall Street Journal",
        "washingtonpost.com": "The Washington Post",
        "theguardian.com": "The Guardian",
        "ft.com": "Financial Times",
        "bloomberg.com": "Bloomberg",
        "reuters.com": "Reuters",
        "apnews.com": "AP",
        "theinformation.com": "The Information",
        "venturebeat.com": "VentureBeat",
        "engadget.com": "Engadget",
        "gizmodo.com": "Gizmodo",
        "businessinsider.com": "Business Insider",
        "forbes.com": "Forbes",
        "axios.com": "Axios",
        "abc7.com": "ABC7",
        "macrumors.com": "MacRumors",
        "9to5mac.com": "9to5Mac",
        "androidpolice.com": "Android Police"
    ]
}
