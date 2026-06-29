//
//  DashboardWidgetCard.swift
//  leanring-buddy
//
//  Reusable chrome for every Daily Dashboard widget: the rounded card container
//  (with the design's soft double shadow) and the small-caps icon + label header
//  that sits at the top of each card.
//

import SwiftUI

/// The rounded, shadowed card that hosts a single widget's content.
struct DashboardWidgetCard<Content: View>: View {
    /// Inset of the content from the card edges. The design uses slightly different
    /// padding per widget (32×34 for tall cards, 26 for small ones).
    var horizontalPadding: CGFloat = 34
    var verticalPadding: CGFloat = 32

    @ViewBuilder let content: () -> Content

    var body: some View {
        // The host always lays a card out at a fixed grid footprint (see
        // `DashboardWidgetHost.cardBody`), so the `GeometryReader` here just reads that
        // exact size. We then pin the content to the card's top-left and *hard-clamp* it
        // to that size before clipping. This is the fix for cards whose content is taller
        // than their footprint (e.g. a news list with more headlines than fit): a greedy
        // `.frame(maxHeight: .infinity)` reports the *content's* height when the content
        // overflows, which let the host's fixed frame center the oversized card and push
        // its top edge up past its grid cell. Clamping to `proxy.size` keeps the card
        // exactly its footprint, so overflow is cut cleanly at the bottom and the top
        // stays pinned to its row — resizing only ever grows the card down and right.
        GeometryReader { proxy in
            content()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                .clipped()
        }
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.Metrics.cardCornerRadius, style: .continuous)
                .fill(DashboardTheme.Colors.cardBackground)
        )
        // Round the card's corners. The clamp + `.clipped()` above already cut the content
        // to the footprint; this shapes the visible card (and is applied before the
        // shadow, so the shadow still casts outside the card).
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Metrics.cardCornerRadius, style: .continuous))
        // The design's two-layer shadow: a tight contact shadow plus a soft,
        // far-cast ambient shadow.
        .shadow(color: DashboardTheme.Colors.cardShadowSoft, radius: 1, x: 0, y: 1)
        .shadow(color: DashboardTheme.Colors.cardShadowDeep, radius: 22, x: 0, y: 16)
    }
}

/// The uppercase, letter-spaced section label with a leading SF Symbol that opens
/// every widget (e.g. an envelope + "NEEDS YOU").
struct DashboardWidgetHeader: View {
    let systemIconName: String
    let title: String
    /// The design slightly tightens tracking on the narrower one-column cards.
    var letterSpacing: CGFloat = 0.22 * 11.5

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemIconName)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(DashboardTheme.Colors.sageHeaderIcon)

            Text(title.uppercased())
                .font(DashboardTheme.Fonts.sans(size: 11.5, weight: .semibold))
                .tracking(letterSpacing)
                .foregroundColor(DashboardTheme.Colors.textLabel)
        }
    }
}
