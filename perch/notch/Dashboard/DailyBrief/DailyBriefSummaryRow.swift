//
//  DailyBriefSummaryRow.swift
//  notch
//
//  The row directly under the title card: the Claude-written one/two-line summary on the
//  left (italic), and the artwork's caption on the right (small, gray, italic) set off by
//  a thin vertical rule — matching the mockup. While the summary is still synthesizing it
//  shows a quiet placeholder rather than an empty gap.
//

import SwiftUI

struct DailyBriefSummaryRow: View {
    let summary: String
    let isSynthesizing: Bool
    let caption: String

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            summaryText
                .frame(maxWidth: .infinity, alignment: .leading)

            captionBlock
        }
    }

    @ViewBuilder
    private var summaryText: some View {
        if summary.isEmpty {
            Text(isSynthesizing ? "Pulling your day together…" : "")
                .font(DailyBriefStyle.italicSans(size: 19))
                .foregroundColor(DailyBriefStyle.captionInk)
        } else {
            Text(summary)
                .font(DailyBriefStyle.italicSans(size: 19))
                .foregroundColor(DailyBriefStyle.summaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
    }

    private var captionBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(caption)
                .font(DailyBriefStyle.italicSans(size: 14, weight: .regular))
                .foregroundColor(DailyBriefStyle.captionInk)
                .multilineTextAlignment(.trailing)
                .frame(width: 160, alignment: .trailing)

            Rectangle()
                .fill(DailyBriefStyle.hairline)
                .frame(width: 1, height: 40)
        }
    }
}
