//
//  SiriSphereView.swift
//  notch
//
//  The multicolored "Siri orb" shown on the right side of the notch while the
//  voice agent is active. A blue-family conic disc with a bright specular core,
//  whose behavior changes per voice state:
//    • listening  → pulses/scales to the live microphone level
//    • thinking   → calm slow breathe + swirl (no audio to react to)
//    • speaking   → "repulsion magnet": the bright core is pushed out to the rim
//                   and back, driven by Perch's real TTS playback amplitude
//
//  Colors come from `VoiceAuraVisualStyle` (a documented blue-family exception
//  to the one-accent rule). See DESIGN.md.
//

import SwiftUI

struct SiriSphereView: View {
    let voiceState: CompanionVoiceState
    /// Live microphone power (0…1) — used while listening.
    let microphonePowerLevel: CGFloat
    /// Live TTS playback power (0…1) — used while speaking.
    let ttsPowerLevel: CGFloat
    /// Color family for the orb (blue by default; the album accent while music plays).
    var palette: VoiceAuraPalette = .blue
    var diameter: CGFloat = 20

    var body: some View {
        // ~36 fps cap matches the project's ambient-motion guidance.
        TimelineView(.animation(minimumInterval: 1.0 / 36.0)) { timelineContext in
            let elapsedSeconds = timelineContext.date.timeIntervalSinceReferenceDate
            let metrics = sphereMetrics(at: elapsedSeconds)

            ZStack {
                // The blue-family disc (rotates slowly so the hues drift like Siri).
                Circle()
                    .fill(
                        AngularGradient(
                            colors: palette.sphereRing,
                            center: .center,
                            angle: .degrees(metrics.rotationDegrees)
                        )
                    )

                // The bright specular core. Its bright band sits near the center at
                // rest; during "speaking" it is pushed outward toward the rim.
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: .white.opacity(0.95), location: 0.0),
                                .init(color: palette.coreTint.opacity(0.5), location: metrics.coreInnerLocation),
                                .init(color: .clear, location: metrics.coreOuterLocation)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter / 2
                        )
                    )
                    .blendMode(.screen)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(metrics.scale)
            .shadow(color: palette.glow.opacity(metrics.glowOpacity), radius: metrics.glowRadius)
        }
    }

    // MARK: - Per-frame metrics

    private struct SphereMetrics {
        var rotationDegrees: Double
        var scale: CGFloat
        var coreInnerLocation: CGFloat
        var coreOuterLocation: CGFloat
        var glowOpacity: Double
        var glowRadius: CGFloat
    }

    private func sphereMetrics(at elapsedSeconds: TimeInterval) -> SphereMetrics {
        // A continuous, slow rotation so the disc's colors drift (no hard loop seam
        // because the ring's first and last color match).
        let rotationDegrees = (elapsedSeconds * 40).truncatingRemainder(dividingBy: 360)

        switch voiceState {
        case .listening:
            let eased = pow(microphonePowerLevel, 0.7)
            return SphereMetrics(
                rotationDegrees: rotationDegrees,
                scale: 1.0 + eased * 0.5,
                coreInnerLocation: 0.10,
                coreOuterLocation: 0.46,
                glowOpacity: 0.5 + Double(eased) * 0.3,
                glowRadius: 4 + eased * 4
            )

        case .processing:
            // Calm breathing, no audio signal to react to.
            let breathe = CGFloat((sin(elapsedSeconds * 2.0) + 1) / 2)
            return SphereMetrics(
                rotationDegrees: rotationDegrees,
                scale: 1.0 + breathe * 0.1,
                coreInnerLocation: 0.10,
                coreOuterLocation: 0.46,
                glowOpacity: 0.5,
                glowRadius: 4
            )

        case .responding:
            // Repulsion: push the bright core's band outward toward the rim with
            // the voice. Locations stay strictly increasing and within 0…1.
            let eased = pow(ttsPowerLevel, 0.6)
            let coreInner = 0.10 + eased * 0.34
            let coreOuter = min(0.94, 0.46 + eased * 0.18)
            return SphereMetrics(
                rotationDegrees: rotationDegrees,
                scale: 1.05 + eased * 0.12,
                coreInnerLocation: coreInner,
                coreOuterLocation: coreOuter,
                glowOpacity: 0.5 + Double(eased) * 0.3,
                glowRadius: 5 + eased * 4
            )

        case .idle:
            return SphereMetrics(
                rotationDegrees: rotationDegrees,
                scale: 1.0,
                coreInnerLocation: 0.10,
                coreOuterLocation: 0.46,
                glowOpacity: 0.4,
                glowRadius: 4
            )
        }
    }
}
