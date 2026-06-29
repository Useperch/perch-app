//
//  NotchAlertContentView.swift
//  notch
//
//  Agent-authored alert surface for the open-notch home row: dynamic header,
//  subheader, accent CTA, and hover dismiss control.
//

import SwiftUI

struct NotchAlertContentView: View {
    let alert: NotchAlert
    var onAction: () -> Void
    var onDismiss: () -> Void

    @ObservedObject private var musicManager = MusicManager.shared
    @State private var isHoveringAlertArea = false

    private var accentColor: Color {
        NotchAccentColor.fromMusicAccent(musicManager.avgColor)
    }

    private var headerPointSize: CGFloat {
        let length = CGFloat(alert.header.count)
        let maxLength = CGFloat(NotchAlertCopyLimits.headerMaxCharacters)
        let progress = min(1, length / maxLength)
        return 20 - (progress * 4)
    }

    var body: some View {
        ZStack {
            VStack(alignment: .center, spacing: 6) {
                Text(alert.header)
                    .font(.system(size: headerPointSize, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)

                if !alert.subheader.isEmpty {
                    Text(alert.subheader)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                }

                Button(action: onAction) {
                    Text(alert.buttonLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(NotchAccentColor.labelColor(on: accentColor))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(accentColor))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .onHover { isHovering in
                    if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            if isHoveringAlertArea {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color(white: 0.55))
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovering in
                            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                        }
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { isHoveringAlertArea = $0 }
    }
}