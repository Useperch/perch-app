//
//  VoiceLiveActivity.swift
//  notch
//
//  The collapsed-notch "live activity" shown while the voice agent is active:
//  a status word on the left ("Listening" / "Thinking" / "Speaking") and the
//  multicolored Siri orb on the right, flanking the physical notch. Mirrors the
//  left-ear · black-center · right-ear layout used by `MusicLiveActivity`.
//
//  The tracing line around the notch outline is drawn separately by
//  `NotchVoiceOutline` (overlaid on the notch shape in `ContentView`).
//

import SwiftUI

struct VoiceLiveActivity: View {
    @EnvironmentObject var vm: ViewModel
    @EnvironmentObject var companionManager: CompanionManager
    @ObservedObject var musicManager = MusicManager.shared

    /// The two "ears" flanking the physical notch MUST be equal width: the closed
    /// notch content is centered over the physical notch, so unequal ears would
    /// shove the black center off the real notch. Equal ears keep the notch
    /// centered, the status word on the left, and the orb on the right.
    /// `ContentView.computedChinWidth` references these for the hover/drop chin.
    static let earWidth: CGFloat = 104
    static let earGap: CGFloat = 14

    // Back-compat aliases used by ContentView's chin-width math.
    static var leftEarWidth: CGFloat { earWidth }
    static var rightEarWidth: CGFloat { earWidth }

    /// The orb diameter, kept a little smaller than the notch height so it has
    /// breathing room above and below.
    private var orbDiameter: CGFloat { max(14, vm.effectiveClosedNotchHeight - 14) }

    private var voiceAuraPalette: VoiceAuraPalette { .blue }

    var body: some View {
        HStack(spacing: 0) {
            // Left ear: status word pushed out toward the far left.
            VoiceStatusText(label: statusLabel)
                .frame(width: Self.earWidth, alignment: .leading)
                .padding(.leading, Self.earGap)

            // Center: the physical notch (pure black, exact notch width).
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width)

            // Right ear: the Siri orb pushed out toward the far right.
            SiriSphereView(
                voiceState: companionManager.voiceState,
                microphonePowerLevel: companionManager.currentAudioPowerLevel,
                ttsPowerLevel: companionManager.ttsAudioPowerLevel,
                palette: voiceAuraPalette,
                diameter: orbDiameter
            )
            .frame(width: Self.earWidth, alignment: .trailing)
            .padding(.trailing, Self.earGap)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private var statusLabel: String {
        switch companionManager.voiceState {
        case .listening: return "Listening…"
        case .processing: return "Thinking…"
        case .responding: return "Speaking…"
        case .idle: return ""
        }
    }
}

/// Resolves the voice-aura color family from the now-playing state: the album
/// art's dominant accent while music plays, the default blue otherwise. Shared
/// by the orb (`VoiceLiveActivity`) and the tracing line (`ContentView`).
enum VoiceAuraPaletteResolver {
    @MainActor
    static func resolve(musicManager: MusicManager) -> VoiceAuraPalette {
        let musicActive = musicManager.isPlaying || !musicManager.isPlayerIdle
        guard musicActive else { return .blue }
        return .from(accent: Color(nsColor: musicManager.avgColor))
    }
}

/// The status word with a gentle left-to-right shimmer sweep, matching the
/// system font used across the notch. Subtle — the orb and line carry the motion.
private struct VoiceStatusText: View {
    let label: String

    private let font = Font.system(size: 13, weight: .semibold)
    private let sweepDuration: TimeInterval = 2.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timelineContext in
            let phase = (timelineContext.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: sweepDuration)) / sweepDuration // 0…1

            Text(label)
                .font(font)
                .foregroundStyle(.white)
                .lineLimit(1)
                // A brighter band that sweeps across, clipped to the glyphs.
                .overlay {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.85), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 34)
                        .offset(x: CGFloat(phase) * (geometry.size.width + 34) - 34)
                        .blendMode(.plusLighter)
                    }
                    .mask {
                        Text(label).font(font).lineLimit(1)
                    }
                }
                .id(label)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.15), value: label)
    }
}
