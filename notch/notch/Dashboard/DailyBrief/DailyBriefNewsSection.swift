//
//  DailyBriefNewsSection.swift
//  notch
//
//  "Top news this morning:" — the headline list on the left (live web headlines, each a
//  clickable link) and the day's comic on the right (XKCD, async-loaded). The comic is
//  optional: if its fetch failed the section renders headlines full-width, never a broken
//  image frame.
//

import SwiftUI

struct DailyBriefNewsSection: View {
    let headlines: [DailyBriefHeadline]
    let isLoading: Bool
    let comic: DailyBriefComic?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Top news this morning:")
                .font(DailyBriefStyle.heading(size: 24))
                .foregroundColor(DailyBriefStyle.headingInk)

            HStack(alignment: .top, spacing: 36) {
                headlineList
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let comic {
                    DailyBriefComicView(comic: comic)
                }
            }
        }
    }

    @ViewBuilder
    private var headlineList: some View {
        if headlines.isEmpty {
            Text(isLoading ? "Fetching this morning's headlines…" : "No headlines right now.")
                .font(DailyBriefStyle.body(size: 17))
                .foregroundColor(DailyBriefStyle.captionInk)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(headlines) { headline in
                    DailyBriefHeadlineRow(headline: headline)
                }
            }
        }
    }
}

private struct DailyBriefHeadlineRow: View {
    let headline: DailyBriefHeadline
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
                .font(DailyBriefStyle.body(size: 17))
                .foregroundColor(DailyBriefStyle.captionInk)
            Text(headline.title)
                .font(DailyBriefStyle.body(size: 17))
                .foregroundColor(DailyBriefStyle.bodyInk)
                .underline(isHovering && headline.url != nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if headline.url != nil {
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .onTapGesture {
            guard let urlString = headline.url, let url = URL(string: urlString) else { return }
            NSWorkspace.shared.open(url)
        }
    }
}

private struct DailyBriefComicView: View {
    let comic: DailyBriefComic

    // A fixed panel so the comic occupies the SAME footprint every day, regardless of the
    // strip's native dimensions — the image is fitted + centered inside, so a wide single
    // panel and a tall multi-panel strip both read as a consistent "comic of the day" card.
    private let panelWidth: CGFloat = 280
    private let panelHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 10) {
            Text(comic.title.uppercased())
                .font(DailyBriefStyle.italicSans(size: 11, weight: .bold))
                .foregroundColor(DailyBriefStyle.bodyInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: panelWidth)

            Image(nsImage: comic.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
                .frame(width: panelWidth, height: panelHeight)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DailyBriefStyle.hairline, lineWidth: 1)
                )
                .help(comic.altText)
        }
    }
}
