//
//  DashboardDailyBriefWidget.swift
//  leanring-buddy
//
//  The Daily Brief hero card on the dashboard: a full-bleed painting with the
//  "The / <Weekday> Brief" headline centered in Melodrama gold, and today's date
//  in the bottom-right corner. No card chrome — it sits directly on the glass.
//

import SwiftUI

struct DashboardDailyBriefWidget: View {

    private var today: Date { Date() }

    /// e.g. "Monday Brief"
    private var weekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: today)
    }

    /// e.g. "06/25/2026"
    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: today)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                paintingBackground

                // Subtle vignette so the headline reads on any lighting in the painting.
                RadialGradient(
                    colors: [Color.black.opacity(0.05), Color.black.opacity(0.32)],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.6
                )
                .ignoresSafeArea()

                // Centered headline.
                VStack(spacing: 0) {
                    Text("The")
                        .font(.custom("Melodrama", size: melodramaSmallSize(in: proxy.size)))
                        .foregroundColor(briefGold)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)

                    Text("\(weekdayName) Brief")
                        .font(.custom("Melodrama", size: melodramaLargeSize(in: proxy.size)))
                        .foregroundColor(briefGold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.45), radius: 8, y: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Nudge slightly above center so the headline reads closer to the
                // visual center of the painting (sky tends to sit in the upper half).
                .offset(y: proxy.size.height * -0.04)

                // Date — bottom-right.
                Text(dateLabel)
                    .font(.custom("Melodrama", size: 13))
                    .foregroundColor(briefGold)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.bottom, 14)
                    .padding(.trailing, 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    // MARK: Painting

    private var paintingBackground: some View {
        Image("daily-brief-painting")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .clipped()
    }

    // MARK: Type scale

    /// "The" sits at roughly 1/3 the size of the main headline.
    private func melodramaSmallSize(in size: CGSize) -> CGFloat {
        max(16, size.height * 0.11)
    }

    private func melodramaLargeSize(in size: CGSize) -> CGFloat {
        max(36, size.height * 0.32)
    }

    // MARK: Colors

    private let briefGold = Color(red: 0.941, green: 0.752, blue: 0.208) // #f0c035
}
