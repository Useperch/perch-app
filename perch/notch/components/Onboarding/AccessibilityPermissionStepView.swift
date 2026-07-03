//
//  AccessibilityPermissionStepView.swift
//  notch
//
//  The onboarding Accessibility step, with stale-grant detection.
//
//  macOS ties an Accessibility grant to the app's code signature. When an older
//  copy of Perch (different signing cert) left an entry in the Accessibility
//  list, System Settings shows Perch as ON but AXIsProcessTrusted() keeps
//  returning false for the running app — and flipping the toggle does NOT fix
//  it, because macOS keeps the stale entry's signature requirement. The only
//  fix is removing Perch from the list and re-adding it.
//
//  Without this detection the user "grants" the permission, onboarding moves
//  on, and the hotkeys are silently dead. So instead of advancing on click,
//  this step polls AXIsProcessTrusted() until the grant actually validates,
//  and after a grace period surfaces the remove-and-re-add fix.
//

import SwiftUI

struct AccessibilityPermissionStepView: View {
    /// Called once AXIsProcessTrusted() actually returns true (or immediately
    /// if the permission was already live).
    let onComplete: () -> Void
    let onSkip: () -> Void

    private enum Phase {
        case request
        case waiting
        case staleGuidance
    }

    /// How long to poll after the user acts before suggesting the stale-entry
    /// fix. Long enough to find the toggle in System Settings; a valid grant
    /// still auto-advances at any time, so showing the fix early is harmless.
    private static let staleGuidanceDelay = 20

    @State private var phase: Phase = .request
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch phase {
            case .request:
                PermissionRequestView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Grant Accessibility Access",
                    description: "Perch listens for the ⌃⌥ talk shortcut (and double-tap ⌃ to type) system-wide. macOS calls this “Accessibility.” Without it the hotkeys can't work — and macOS won't ask on its own, so grant it here.",
                    privacyNote: "Perch only watches for its own shortcut keys to know when you want to talk — it never logs your keystrokes, and nothing is linked to your account.",
                    onAllow: requestPermission,
                    onSkip: finish(with: onSkip)
                )

            case .waiting:
                waitingView

            case .staleGuidance:
                staleGuidanceView
            }
        }
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: - Phases

    private var waitingView: some View {
        VStack(spacing: 28) {
            Image(systemName: "hand.raised.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 56)
                .foregroundColor(.effectiveAccent)
                .padding(.top, 32)

            Text("Turn On Perch in Accessibility")
                .font(.title)
                .fontWeight(.semibold)

            Text("In the Accessibility list that just opened, switch Perch on. This screen continues automatically as soon as macOS applies the permission.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            ProgressView()
                .controlSize(.small)

            HStack {
                Button("Skip for Now", action: finish(with: onSkip))
                    .buttonStyle(.bordered)
                Button("Open Accessibility Settings") {
                    WindowPositionManager.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private var staleGuidanceView: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 52)
                .foregroundColor(.effectiveAccent)
                .padding(.top, 32)

            Text("Permission Not Taking?")
                .font(.title)
                .fontWeight(.semibold)

            Text("If Perch already shows as ON in System Settings but this screen hasn't moved on, macOS is holding on to an entry from an older copy of Perch — and toggling it won't help.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Open System Settings → Privacy & Security → Accessibility")
                Text("2. Select Perch and remove it with the − button")
                Text("3. Click + and add this Perch again, then switch it on")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal)

            Text("Perch continues automatically once the permission is active.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Button("Skip for Now", action: finish(with: onSkip))
                    .buttonStyle(.bordered)
                Button("Reveal Perch in Finder") {
                    WindowPositionManager.revealAppInFinder()
                }
                .buttonStyle(.bordered)
                Button("Open Accessibility Settings") {
                    WindowPositionManager.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    // MARK: - Permission flow

    private func requestPermission() {
        if WindowPositionManager.requestAccessibilityPermission() == .alreadyGranted {
            onComplete()
            return
        }
        withAnimation(.easeInOut(duration: 0.4)) { phase = .waiting }
        beginPolling()
    }

    private func beginPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            var secondsElapsed = 0
            while !Task.isCancelled {
                if WindowPositionManager.hasAccessibilityPermission() {
                    onComplete()
                    return
                }
                if secondsElapsed >= Self.staleGuidanceDelay, phase != .staleGuidance {
                    withAnimation(.easeInOut(duration: 0.4)) { phase = .staleGuidance }
                }
                try? await Task.sleep(for: .seconds(1))
                secondsElapsed += 1
            }
        }
    }

    /// Wraps a step-exit callback so the poll loop can't fire a late
    /// onComplete after the user chose to move on.
    private func finish(with exit: @escaping () -> Void) -> () -> Void {
        {
            pollTask?.cancel()
            exit()
        }
    }
}
