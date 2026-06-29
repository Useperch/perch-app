//
//  DashboardContentFit.swift
//  leanring-buddy
//
//  Shared "how many rows fit in this card" math, so every list-like widget reflows the
//  same way the news/list widget does: resizing a card taller surfaces more rows and
//  shrinking it surfaces fewer, rather than flipping between a fixed collapsed/expanded
//  pair. Extracted from `DashboardListWidgetView` so the bespoke widgets (Needs you,
//  Today) trade height for content with identical behavior.
//

import CoreGraphics

/// Pure layout math for fitting a vertical list of rows inside a widget card of a given
/// pegboard row span. No SwiftUI here — just the geometry every list-like widget shares.
enum DashboardContentFit {

    /// How many rows fit in a card `rowSpan` cells tall.
    ///
    /// The card's usable height is its peg-cell height (minus the inter-cell gap), minus
    /// the card's vertical padding and the header block above the rows. Rows are
    /// separated by a padded divider, so `n` rows occupy
    /// `n·rowHeight + (n−1)·dividerHeight`. Solving for `n` and flooring gives the count.
    ///
    /// - Parameters:
    ///   - rowSpan: the card's height in pegboard cells (the live span while resizing).
    ///   - rowHeight: the height of one content row.
    ///   - dividerHeight: the height a between-row divider adds (rule + its padding); pass
    ///     `0` for widgets that don't draw dividers.
    ///   - headerBlockHeight: the header label plus the gap beneath it, above the rows.
    ///   - cardVerticalPadding: the card's combined top + bottom inset (see
    ///     `DashboardWidgetCard`, default `32` each side).
    static func rowsThatFit(
        inRowSpan rowSpan: Int,
        rowHeight: CGFloat,
        dividerHeight: CGFloat,
        headerBlockHeight: CGFloat,
        cardVerticalPadding: CGFloat = 32 * 2
    ) -> Int {
        let cardHeight = CGFloat(rowSpan) * DashboardTheme.Metrics.pegSpacing
            - DashboardTheme.Metrics.cellGap
        let availableHeight = cardHeight - cardVerticalPadding - headerBlockHeight

        // `n` rows + `(n−1)` dividers ≤ availableHeight  ⇒  add one divider to both sides
        // so the division yields the row count directly.
        let fitCount = Int(((availableHeight + dividerHeight) / (rowHeight + dividerHeight))
            .rounded(.down))
        return max(1, fitCount)
    }
}
