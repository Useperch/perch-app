//
//  DailyBriefView.swift
//  notch
//
//  The redesigned Daily Brief: a fixed, scrolling editorial page (title card → summary →
//  catch-up / priorities → calendar → news + comic) on a clean light background. The title
//  card paints instantly from local facts; every other section fills in live as its source
//  resolves (see `DailyBriefViewModel`).
//
//  This is a brand-new surface that sits alongside the legacy pegboard dashboard — it does
//  not touch `DashboardView`/`DashboardCanvasView`. It's hosted by `DailyBriefWindowController`.
//

import SwiftUI

struct DailyBriefView: View {
    @StateObject private var viewModel = DailyBriefViewModel()

    var body: some View {
        ScrollView {
            // Center a fixed-width reading column with greedy spacers — a plain
            // `.frame(maxWidth:)` doesn't reliably cap the greedy title card.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                column
                    .frame(maxWidth: DailyBriefStyle.contentWidth)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DailyBriefStyle.pagePadding)
            .padding(.top, 28)
            .padding(.bottom, 56)
        }
        .background(DailyBriefStyle.pageBackground)
        .onAppear { viewModel.loadIfNeeded() }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: DailyBriefStyle.sectionSpacing) {
                DailyBriefTitleCard(
                    firstName: viewModel.firstName,
                    dateLine: viewModel.dateLine,
                    weekdayName: viewModel.weekdayName,
                    artwork: viewModel.artwork
                )

                DailyBriefSummaryRow(
                    summary: viewModel.synthesis?.summary ?? "",
                    isSynthesizing: viewModel.isSynthesizing,
                    caption: viewModel.artwork.caption
                )

                Rectangle()
                    .fill(DailyBriefStyle.hairline)
                    .frame(height: 1)

                DailyBriefColumns()

                DailyBriefCalendarWidget(
                    entries: viewModel.calendarEntries,
                    isLoading: viewModel.isLoadingCalendar
                )

                DailyBriefNewsSection(
                    headlines: viewModel.headlines,
                    isLoading: viewModel.isLoadingNews,
                    comic: viewModel.comic
                )
        }
    }
}
