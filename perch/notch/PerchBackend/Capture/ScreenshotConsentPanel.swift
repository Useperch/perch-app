//
//  ScreenshotConsentPanel.swift
//  Perch
//
//  Just-in-time screen-recording consent, shown as a small pop-up centered in the
//  MIDDLE of the screen (a floating panel — not an in-notch card and not a macOS
//  banner). Screen Recording is no longer requested up-front in onboarding; the
//  first time a turn needs a screenshot, Perch asks here with three choices:
//  Allow (once) / Always Allow (persists, never asks again) / Not Now.
//
//  CompanionManager presents it and awaits the choice; because it's its own window
//  it surfaces over anything (typed composer, voice, other apps) without the notch
//  layout getting in the way.
//

import AppKit
import SwiftUI

/// The user's answer to the screenshot consent pop-up.
enum ScreenshotConsent {
    /// Capture now and never ask again (persists `screenshotAlwaysAllow`).
    case always
    /// Capture just this once; ask again next time.
    case once
    /// Skip the screenshot for this turn.
    case no
}

@MainActor
final class ScreenshotConsentPanel {
    static let shared = ScreenshotConsentPanel()

    private var panel: NSPanel?
    private var completion: ((ScreenshotConsent) -> Void)?

    private init() {}

    /// Shows the centered consent pop-up and calls `onResolved` exactly once with
    /// the user's choice. If one is somehow already up (a turn cancelled without an
    /// answer), resolve that stale one `.no` and take over so nothing deadlocks.
    func present(question: String, onResolved: @escaping (ScreenshotConsent) -> Void) {
        resolve(.no)
        completion = onResolved

        let card = ScreenshotConsentContentView(
            question: question,
            onAllow: { [weak self] in self?.resolve(.once) },
            onAlways: { [weak self] in self?.resolve(.always) },
            onNotNow: { [weak self] in self?.resolve(.no) }
        )

        let hostingView = NSHostingView(rootView: card)
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)

        let consentPanel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        consentPanel.isFloatingPanel = true
        consentPanel.level = .modalPanel
        consentPanel.backgroundColor = .clear
        consentPanel.isOpaque = false
        consentPanel.hasShadow = true
        consentPanel.isMovableByWindowBackground = false
        consentPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        consentPanel.contentView = hostingView
        consentPanel.setContentSize(hostingView.fittingSize)
        consentPanel.center() // horizontally centered, slightly above vertical center
        consentPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        panel = consentPanel
    }

    /// Delivers the choice to the waiting caller (once) and dismisses the pop-up.
    private func resolve(_ consent: ScreenshotConsent) {
        panel?.orderOut(nil)
        panel = nil
        let pendingCompletion = completion
        completion = nil
        pendingCompletion?(consent)
    }
}

/// The centered consent card: eye glyph, title, the question being asked, and the
/// three actions. Self-contained (rounded dark surface + hairline border) since it
/// lives in its own floating panel, not inside the notch.
struct ScreenshotConsentContentView: View {
    let question: String
    let onAllow: () -> Void
    let onAlways: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.fill")
                .font(.system(size: 24))
                .foregroundColor(.effectiveAccent)

            Text("Let Perch see your screen?")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.72))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                consentButton("Not now", filled: false, action: onNotNow)
                consentButton("Allow", filled: true, action: onAllow)
                consentButton("Always", filled: false, action: onAlways)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(white: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var subtitle: String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? "Perch will take one screenshot to answer what's on your screen."
            : "Perch will take one screenshot to answer:\n\u{201C}\(trimmed)\u{201D}"
    }

    private func consentButton(
        _ label: String,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(filled ? NotchAccentColor.labelColor(on: .effectiveAccent) : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(filled ? Color.effectiveAccent : Color.white.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
