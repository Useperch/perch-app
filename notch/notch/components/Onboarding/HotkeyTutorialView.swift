//
//  HotkeyTutorialView.swift
//  notch
//
//  The final teaching step of onboarding: shows the user how to actually summon
//  Perch once permissions are granted, and nudges them to try it. The three
//  shortcuts mirror the real key handling in GlobalPushToTalkShortcutMonitor —
//  hold ⌃⌥ to talk, tap Control twice to type, and Escape to stop.
//

import SwiftUI

struct HotkeyTutorialView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundColor(.effectiveAccent)
                    .padding(.top, 36)

                Text("How to reach Perch")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Perch stays out of the way until you call it.\nThree ways to start:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                HotkeyTutorialRow(
                    keys: ["⌃", "⌥"],
                    joiner: "+",
                    qualifier: "hold",
                    title: "Talk to Perch",
                    detail: "Hold Control + Option and speak. Release to send."
                )
                HotkeyTutorialRow(
                    keys: ["⌃", "⌃"],
                    joiner: nil,
                    qualifier: "tap twice",
                    title: "Type to Perch",
                    detail: "Press Control twice to open the text box."
                )
                HotkeyTutorialRow(
                    keys: ["esc"],
                    joiner: nil,
                    qualifier: nil,
                    title: "Stop Perch",
                    detail: "Press Escape to cancel Perch mid-response."
                )
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)

            Spacer()

            // Nudge the user to actually try it the moment they leave onboarding.
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.effectiveAccent)
                Text("Give it a go — hold ⌃⌥ and say hello.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                Capsule().fill(Color.effectiveAccent.opacity(0.12))
            )
            .padding(.bottom, 18)

            Button(action: onContinue) {
                Text("Let's go")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}

/// A single shortcut row: a keycap cluster on the left (with its qualifier
/// stacked underneath so it never crowds the keys), and the explanation on the right.
private struct HotkeyTutorialRow: View {
    let keys: [String]
    /// Optional glyph shown between keys, e.g. "+" for a held combo.
    let joiner: String?
    /// Optional qualifier shown under the keys, e.g. "hold" or "tap twice".
    let qualifier: String?
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                        if index > 0, let joiner = joiner {
                            Text(joiner)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        KeyCapView(symbol: key)
                    }
                }
                if let qualifier = qualifier {
                    Text(qualifier)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: 86)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

/// A small keyboard-key glyph, styled to read as a physical keycap.
private struct KeyCapView: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .frame(minWidth: 28, minHeight: 28)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            )
    }
}

#Preview {
    HotkeyTutorialView(onContinue: { })
        .frame(width: 400, height: 600)
}
