//
//  DailyBriefButton.swift
//  notch
//
//  Default-state control that opens the Daily Dashboard, tinted with the
//  current song's album accent color.
//

import SwiftUI

struct DailyBriefButton: View {
    @ObservedObject private var musicManager = MusicManager.shared

    private var accentColor: Color {
        NotchAccentColor.fromMusicAccent(musicManager.avgColor)
    }

    var body: some View {
        Button {
            DailyBriefLauncher.open()
        } label: {
            Text("Daily Brief")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(NotchAccentColor.labelColor(on: accentColor))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(accentColor))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}