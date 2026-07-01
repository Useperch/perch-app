//
//  NotchChatTranscriptView.swift
//  notch
//
//  The typed-chat thread shown above the composer's input row when the user is
//  texting Perch. Renders `CompanionManager.typedChatMessages` as iMessage-style
//  bubbles — the user's messages right-aligned, Perch's replies left-aligned and
//  streamed in token-by-token. The thread scrolls internally and is height-capped
//  so the input row always stays on screen.
//

import SwiftUI

struct NotchChatTranscriptView: View {
    @EnvironmentObject var companionManager: CompanionManager
    @EnvironmentObject var vm: ViewModel

    /// The measured height of the bubble stack. The ScrollView is sized to this (up
    /// to the cap) so the thread is exactly as tall as its content and only starts
    /// scrolling once it would overflow — a ScrollView left to its own devices
    /// greedily fills all offered height, which would balloon the notch.
    @State private var measuredBubbleStackHeight: CGFloat = 0

    /// The composer's canonical blue, reused for the user's bubbles so the thread
    /// reads as part of the same voice-blue surface as the send button and caret.
    private static let userBubbleBlue = VoiceAuraPalette.blue.glow

    /// Cap the transcript height so the notch can grow to fit the thread but never
    /// runs past the usable screen — beyond this the thread scrolls internally while
    /// the notch height holds. Derived from the screen so the notch grows "as needed."
    private var maximumTranscriptHeight: CGFloat {
        let topNotchClearance = vm.effectiveClosedNotchHeight + 8
        // Room the rest of the composer needs below the transcript (input row +
        // paddings) plus a top/bottom margin off the screen edges.
        let spaceReservedForComposerChrome: CGFloat = 96
        let screenTopBottomMargin: CGFloat = 80
        let usableScreenHeight = (NSScreen.main?.visibleFrame.height ?? 900) - screenTopBottomMargin
        let available = usableScreenHeight - topNotchClearance - spaceReservedForComposerChrome
        // Never collapse to nothing on unusually short screens.
        return max(160, available)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(companionManager.typedChatMessages) { message in
                        bubbleRow(for: message)
                            .id(message.id)
                            // New bubbles rise in and fade rather than popping.
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 2)
                // Animate bubble insertions so they slide/fade in as a group.
                .animation(.smooth(duration: 0.3), value: companionManager.typedChatMessages.count)
                // Measure the real content height so the ScrollView can be sized to
                // it instead of greedily filling the offered space.
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: BubbleStackHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                )
            }
            // Exactly content-tall until it would overflow the cap, then it holds and
            // scrolls internally. This keeps the notch fitted to the messages.
            .frame(height: min(measuredBubbleStackHeight, maximumTranscriptHeight))
            // Smoothly grow/shrink the thread height (and, downstream, the notch
            // window that tracks it) instead of snapping to the new size.
            .animation(.smooth(duration: 0.3), value: measuredBubbleStackHeight)
            .onPreferenceChange(BubbleStackHeightPreferenceKey.self) { newHeight in
                measuredBubbleStackHeight = newHeight
            }
            // Keep the newest bubble in view as messages arrive and as the streaming
            // reply grows.
            .onChange(of: companionManager.typedChatMessages.last?.id) { _, _ in
                scrollToBottom(using: scrollProxy)
            }
            .onChange(of: companionManager.typedChatMessages.last?.text) { _, _ in
                scrollToBottom(using: scrollProxy)
            }
        }
    }

    private func scrollToBottom(using scrollProxy: ScrollViewProxy) {
        guard let lastMessageID = companionManager.typedChatMessages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo(lastMessageID, anchor: .bottom)
        }
    }

    // MARK: - Bubble row

    @ViewBuilder
    private func bubbleRow(for message: TypedChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack(spacing: 0) {
                Spacer(minLength: 32)
                userBubble(for: message)
            }
        case .assistant:
            HStack(spacing: 0) {
                assistantBubble(for: message)
                Spacer(minLength: 32)
            }
        }
    }

    private func userBubble(for message: TypedChatMessage) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !message.attachmentThumbnails.isEmpty {
                attachmentThumbnailRow(message.attachmentThumbnails)
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Self.userBubbleBlue)
        )
    }

    @ViewBuilder
    private func assistantBubble(for message: TypedChatMessage) -> some View {
        // A streaming reply with no text yet shows the "thinking" dots; once tokens
        // arrive it renders the (growing) text.
        Group {
            if message.isStreaming && message.text.isEmpty {
                ThinkingDotsView()
            } else {
                Text(message.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func attachmentThumbnailRow(_ thumbnails: [NSImage]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, thumbnail in
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

/// Carries the measured height of the bubble stack up so the ScrollView can be sized
/// to its content instead of greedily filling the offered height.
private struct BubbleStackHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Three dots that pulse in sequence — Perch's "typing…" indicator while a reply
/// is still being generated. Driven by `TimelineView` so it needs no stored timer.
private struct ThinkingDotsView: View {
    private let dotCount = 3
    private let cycleDuration: TimeInterval = 1.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timelineContext in
            let phase = timelineContext.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration // 0…1
            HStack(spacing: 4) {
                ForEach(0..<dotCount, id: \.self) { dotIndex in
                    Circle()
                        .fill(DS.Colors.textSecondary)
                        .frame(width: 6, height: 6)
                        .opacity(dotOpacity(dotIndex: dotIndex, phase: phase))
                }
            }
        }
    }

    /// Each dot brightens on its own slice of the cycle so the highlight walks
    /// left-to-right across the three dots.
    private func dotOpacity(dotIndex: Int, phase: Double) -> Double {
        let dotFraction = Double(dotIndex) / Double(dotCount)
        let distance = abs(phase - dotFraction)
        let wrappedDistance = min(distance, 1.0 - distance)
        return 0.3 + 0.7 * max(0, 1.0 - wrappedDistance * Double(dotCount))
    }
}
