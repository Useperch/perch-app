//
//  ChromeRecordingCoordinator.swift
//  leanring-buddy
//
//  UI-facing state for Chrome record-and-replay. The user demonstrates a web task
//  in the headful sub-browser; this coordinator tracks the capture lifecycle
//  (recording → synthesizing → saved/failed), the live preview frame, and the
//  saved skill's details for the Agents tab control.
//
//  It holds NO socket of its own: `BrowserSubagentManager` owns the single IPC
//  client and event loop, sends the `record.*` RPCs, and forwards `record.*`
//  events here. That keeps one connection and one event stream for the whole app.
//

import AppKit
import SwiftUI

/// The details of a just-saved recorded skill, shown in the Agents tab.
struct SavedChromeSkill: Equatable {
    let slug: String
    let title: String
    let path: String
}

@MainActor
final class ChromeRecordingCoordinator: ObservableObject {

    /// The current capture lifecycle state. Drives the record/stop control.
    @Published private(set) var state: ChromeRecordingState = .idle

    /// The latest live preview frame of the recording window, if any.
    @Published private(set) var previewImage: NSImage?

    /// The most recently saved skill (set when `record.stop` resolves).
    @Published private(set) var lastSavedSkill: SavedChromeSkill?

    /// A user-facing error message when synthesis failed.
    @Published private(set) var errorMessage: String?

    /// The id of the active recording (nil when idle/terminal).
    private(set) var activeRecordingId: String?

    /// True while a recording is starting, capturing, or synthesizing — the control
    /// shows live status, and a second recording cannot start.
    var isBusy: Bool {
        state == .starting || state == .recording || state == .synthesizing
    }

    // MARK: - Lifecycle transitions (driven by the manager)

    /// Called the instant Record is pressed — before the (potentially multi-second)
    /// sidecar spawn + headful-window launch — so the UI reacts immediately.
    func markStarting() {
        previewImage = nil
        lastSavedSkill = nil
        errorMessage = nil
        state = .starting
    }

    /// Called right after the `record.start` RPC returns its recordingId.
    ///
    /// A slow or hung `record.start` can return AFTER the user already pressed Stop
    /// (which cancels and leaves `.cancelled`). Only promote to `.recording` if we're
    /// still in `.starting`, so a late return never resurrects a cancelled recording.
    func markStarted(recordingId: String) {
        guard state == .starting else { return }
        activeRecordingId = recordingId
        state = .recording
    }

    /// Called when the `record.stop` RPC is sent — synthesis is underway.
    func markSynthesizing() {
        state = .synthesizing
    }

    /// Called when the `record.stop` RPC resolves with the saved skill.
    func markSaved(_ savedSkill: SavedChromeSkill) {
        lastSavedSkill = savedSkill
        activeRecordingId = nil
        state = .saved
    }

    /// Called when a recording is cancelled.
    func markCancelled() {
        activeRecordingId = nil
        previewImage = nil
        state = .cancelled
    }

    /// Called when synthesis fails (RPC error or `record.error` event).
    func markFailed(_ message: String) {
        errorMessage = message
        activeRecordingId = nil
        state = .failed
    }

    // MARK: - Event sink (forwarded by the manager)

    func handle(_ event: BrowserSubagentEvent) {
        switch event {
        case let .recordState(recordingId, recordingState):
            guard isForActiveRecording(recordingId) else { break }
            // The sidecar's intermediate states; terminal states are set when the
            // stop RPC resolves so the saved-skill payload arrives with them.
            if recordingState == .recording || recordingState == .synthesizing {
                state = recordingState
            } else if recordingState == .cancelled {
                markCancelled()
            }

        case let .recordFrame(recordingId, jpegBase64):
            guard isForActiveRecording(recordingId) else { break }
            if let imageData = Data(base64Encoded: jpegBase64),
               let image = NSImage(data: imageData) {
                previewImage = image
            }

        case let .recordSaved(recordingId, slug, path, title):
            guard isForActiveRecording(recordingId) else { break }
            markSaved(SavedChromeSkill(slug: slug, title: title, path: path))

        case let .recordError(recordingId, message):
            guard isForActiveRecording(recordingId) else { break }
            markFailed(message)

        default:
            break
        }
    }

    /// True only for events belonging to the recording we're currently tracking.
    /// A reconnect or a stale event from a prior recording carries a different id,
    /// and applying it would corrupt the live UI state — so those are dropped.
    private func isForActiveRecording(_ recordingId: String) -> Bool {
        recordingId == activeRecordingId
    }
}
