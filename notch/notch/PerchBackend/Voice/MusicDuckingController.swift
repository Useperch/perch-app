//
//  MusicDuckingController.swift
//  notch
//
//  Quiets the user's music/media while Perch is mid-exchange (the user is
//  talking to Perch, or Perch is speaking its reply) and restores it the
//  moment the exchange ends. This ducks ONLY the music app — via the same
//  per-app `MusicManager` the notch already uses — so Perch's own spoken
//  reply is never turned down with it (unlike lowering the whole system
//  output volume).
//

import Foundation

@MainActor
final class MusicDuckingController {
    /// While ducked, the music app plays at this fraction of the volume it had
    /// the moment ducking began — quiet enough to clearly hear Perch (and the
    /// user) over it, loud enough that the music is obviously still playing.
    private static let duckedVolumeFraction: Double = 0.2

    /// The volume (0…1) the music app had at the instant ducking began. Captured
    /// so the exact pre-duck level can be restored afterward, and used as the
    /// "currently ducked" flag (non-nil ⇒ ducked). We restore from this stored
    /// value rather than re-reading `MusicManager`, because `MusicManager.volume`
    /// reflects the lowered level once ducking has taken effect.
    private var musicVolumeBeforeDucking: Double?

    private let musicManager: MusicManager

    init(musicManager: MusicManager = .shared) {
        self.musicManager = musicManager
    }

    /// Whether Perch is currently holding the music app's volume down.
    var isDucked: Bool { musicVolumeBeforeDucking != nil }

    /// Quiets the music app so Perch (and the user) can be heard over it.
    /// No-op when music isn't playing, the active player doesn't support volume
    /// control, it's already silent, or it's already ducked.
    func duckForPerchVoice() {
        guard !isDucked else { return }
        guard musicManager.isPlaying, musicManager.volumeControlSupported else { return }

        let musicVolumeBeforeDucking = musicManager.volume
        // Nothing audible to duck — don't capture a level we'd later "restore"
        // the music up to, in case it was deliberately silenced.
        guard musicVolumeBeforeDucking > 0 else { return }

        self.musicVolumeBeforeDucking = musicVolumeBeforeDucking
        musicManager.setVolume(to: musicVolumeBeforeDucking * Self.duckedVolumeFraction)
    }

    /// Restores the music app to the volume it had before Perch ducked it.
    /// No-op when Perch hasn't ducked anything.
    func restoreAfterPerchVoice() {
        guard let musicVolumeBeforeDucking else { return }
        self.musicVolumeBeforeDucking = nil
        musicManager.setVolume(to: musicVolumeBeforeDucking)
    }
}
