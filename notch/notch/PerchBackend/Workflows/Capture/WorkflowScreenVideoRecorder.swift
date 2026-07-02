//
//  WorkflowScreenVideoRecorder.swift
//  Perch
//
//  Records the user's demonstration as an actual screen movie (.mov on disk)
//  using ScreenCaptureKit's SCRecordingOutput. The keyframe extractor later
//  cuts frames out of this movie at the moment timestamps.
//
//  macOS 15+ only (SCRecordingOutput's floor) — the demonstration recorder
//  gates on availability and degrades to moment-only capture below it. Uses
//  the SAME Screen Recording TCC grant the screenshot path already holds.
//
//  Records the cursor's display only, at near-native resolution (≤3024 px long
//  edge — the extraction stage's hard-won lesson: low-res text is illegible
//  and vision models confabulate instead of failing), 10 fps (keystroke-paced
//  demos need no more; keeps a minute of video in the tens of MB). Perch's
//  own windows are excluded so notch surfaces never appear in the evidence.
//

import AppKit
import AVFoundation
import ScreenCaptureKit

enum WorkflowVideoRecorderError: Error, LocalizedError {
    case noDisplayAvailable

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display available to record."
        }
    }
}

@available(macOS 15.0, *)
@MainActor
final class WorkflowScreenVideoRecorder: NSObject {

    /// Long-edge cap in pixels for the recorded movie.
    private static let maxRecordedLongEdgePixels = 3024
    /// 10 fps — plenty for UI demonstrations, cheap to decode.
    private static let minimumFrameInterval = CMTime(value: 1, timescale: 10)
    /// How long stop() waits for the movie file to finalize.
    private static let finishTimeoutSeconds: TimeInterval = 5

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private(set) var outputFileURL: URL?
    /// Wall-clock instant the movie began — taken when startCapture() returns.
    /// Moment offsets are measured against THIS so they line up with video
    /// time. (Deliberately NOT gated on the recordingOutputDidStartRecording
    /// delegate callback: on two verified real runs that callback never fired
    /// while the file was being written the whole time — the old 5s gate
    /// declared failure, leaked the rolling stream, and every analysis fell
    /// back to a single post-demo screenshot. SCRecordingOutput writes from
    /// startCapture onward; the ≤0.3s anchor slack is absorbed by the
    /// keyframe planner's +0.3s effect delay and decode tolerance.)
    private(set) var recordingStartedAt: Date?

    private var finishContinuation: CheckedContinuation<Void, Never>?

    /// Starts recording the cursor's display. Returns once the movie is
    /// actually rolling (recordingStartedAt is set) or throws on failure.
    func start() async throws {
        let recordingsDirectory = PerchSupportPaths.directory("workflows")
            .appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(
            at: recordingsDirectory, withIntermediateDirectories: true
        )
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let destinationURL = recordingsDirectory.appendingPathComponent(
            "demonstration-\(timestampFormatter.string(from: Date())).mov"
        )
        outputFileURL = destinationURL

        let shareableContent = try await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !shareableContent.displays.isEmpty else {
            throw WorkflowVideoRecorderError.noDisplayAvailable
        }

        // Record the display the cursor is on (where the demonstration is
        // happening). NSScreen frames are AppKit-coordinate like mouseLocation;
        // SCDisplay frames are CG-coordinate — match via display ID.
        let mouseLocation = NSEvent.mouseLocation
        var nsScreenByDisplayID: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID {
                nsScreenByDisplayID[screenNumber] = screen
            }
        }
        let cursorDisplay = shareableContent.displays.first(where: { display in
            nsScreenByDisplayID[display.displayID]?.frame.contains(mouseLocation) ?? false
        }) ?? shareableContent.displays[0]

        // Exclude Perch's own windows (notch surfaces, overlay) from the movie.
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let ownAppWindows = shareableContent.windows.filter { window in
            window.owningApplication?.bundleIdentifier == ownBundleIdentifier
        }
        let contentFilter = SCContentFilter(
            display: cursorDisplay, excludingWindows: ownAppWindows
        )

        let backingScaleFactor = nsScreenByDisplayID[cursorDisplay.displayID]?
            .backingScaleFactor ?? 2.0
        let nativePixelWidth = Double(cursorDisplay.width) * backingScaleFactor
        let nativePixelHeight = Double(cursorDisplay.height) * backingScaleFactor
        let downscaleFactor = min(
            1.0,
            Double(Self.maxRecordedLongEdgePixels) / max(nativePixelWidth, nativePixelHeight)
        )

        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = Int(nativePixelWidth * downscaleFactor)
        streamConfiguration.height = Int(nativePixelHeight * downscaleFactor)
        streamConfiguration.minimumFrameInterval = Self.minimumFrameInterval
        streamConfiguration.showsCursor = true

        let createdStream = SCStream(
            filter: contentFilter, configuration: streamConfiguration, delegate: nil
        )

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = destinationURL
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264
        let createdRecordingOutput = SCRecordingOutput(
            configuration: recordingConfiguration, delegate: self
        )

        try createdStream.addRecordingOutput(createdRecordingOutput)
        stream = createdStream
        recordingOutput = createdRecordingOutput

        do {
            try await createdStream.startCapture()
        } catch {
            // Never leave a half-started stream behind.
            stream = nil
            recordingOutput = nil
            outputFileURL = nil
            throw error
        }

        recordingStartedAt = Date()
        WorkflowDebugLog.log(
            "videoRecorder: rolling — \(streamConfiguration.width)x\(streamConfiguration.height) → \(destinationURL.lastPathComponent)"
        )
    }

    /// Stops the capture and waits for the movie file to finalize. Returns the
    /// finished file's URL (nil when recording never produced one).
    func stop() async -> URL? {
        guard let activeStream = stream else { return nil }
        stream = nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finishContinuation = continuation
            Task { @MainActor [weak self] in
                do {
                    try await activeStream.stopCapture()
                } catch {
                    WorkflowDebugLog.log(
                        "videoRecorder: stopCapture error — \(error.localizedDescription)"
                    )
                }
                // Safety valve: don't hang forever if the finish callback
                // never arrives — the file is usually written by now anyway.
                try? await Task.sleep(
                    nanoseconds: UInt64(Self.finishTimeoutSeconds * 1_000_000_000)
                )
                guard let self, let pendingContinuation = self.finishContinuation else { return }
                self.finishContinuation = nil
                pendingContinuation.resume()
            }
        }

        recordingOutput = nil
        let finishedFileURL = outputFileURL
        if let finishedFileURL,
           FileManager.default.fileExists(atPath: finishedFileURL.path) {
            WorkflowDebugLog.log("videoRecorder: finished \(finishedFileURL.lastPathComponent)")
            return finishedFileURL
        }
        WorkflowDebugLog.log("videoRecorder: no movie file was produced")
        return nil
    }
}

@available(macOS 15.0, *)
extension WorkflowScreenVideoRecorder: SCRecordingOutputDelegate {

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        // Informational only — see recordingStartedAt's comment for why this
        // callback must not gate anything (it never fired on real runs).
        Task { @MainActor in
            WorkflowDebugLog.log("videoRecorder: didStartRecording callback arrived")
        }
    }

    nonisolated func recordingOutput(
        _ recordingOutput: SCRecordingOutput, didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            WorkflowDebugLog.log("videoRecorder: FAILED — \(error.localizedDescription)")
            self.finishContinuation?.resume()
            self.finishContinuation = nil
            self.outputFileURL = nil
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.finishContinuation?.resume()
            self.finishContinuation = nil
        }
    }
}
