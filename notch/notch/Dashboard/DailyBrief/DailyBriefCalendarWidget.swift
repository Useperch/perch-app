//
//  DailyBriefCalendarWidget.swift
//  notch
//
//  Today's agenda as a simple timeline inside a soft panel (the mockup's "calendar widget"
//  block, made real). Each row is a time label + the event title; it shows a quiet state
//  while the fetch is in flight and an explicit "Nothing scheduled today." when the day is
//  clear.
//

import SwiftUI

struct DailyBriefCalendarWidget: View {
    let entries: [DailyBriefCalendarEntry]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DailyBriefStyle.panelFill)
        )
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            Text(isLoading ? "Loading today's calendar…" : "Nothing scheduled today.")
                .font(DailyBriefStyle.body(size: 17))
                .foregroundColor(DailyBriefStyle.captionInk)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 {
                        Rectangle()
                            .fill(DailyBriefStyle.hairline)
                            .frame(height: 1)
                            .padding(.vertical, 10)
                    }
                    DailyBriefCalendarRow(entry: entry)
                }
            }
        }
    }
}

private struct DailyBriefCalendarRow: View {
    let entry: DailyBriefCalendarEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(entry.timeLabel)
                .font(DailyBriefStyle.body(size: 16))
                .foregroundColor(DailyBriefStyle.captionInk)
                .frame(width: 84, alignment: .leading)
            Text(entry.title)
                .font(DailyBriefStyle.body(size: 17))
                .foregroundColor(DailyBriefStyle.bodyInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
