//
//  WorkflowDemonstrationRecorder.swift
//  leanring-buddy
//
//  Orchestrates the two halves of recording a demonstration: the screen video
//  (WorkflowScreenVideoRecorder, macOS 15+) and the moment timeline
//  (WorkflowDemonstrationMomentTap). start() kicks both; stop() returns the
//  RecordedDemonstration with sources derived from the timeline.
//
//  Video failure is NON-FATAL: a demonstration without a movie still has its
//  moment timeline, and the keyframe extractor falls back to a live screenshot
//  at analysis time. The run only degrades, never dies, on video problems.
//

import Foundation

@MainActor
final class WorkflowDemonstrationRecorder {

    private let momentTap = WorkflowDemonstrationMomentTap()
    /// WorkflowScreenVideoRecorder, stored as Any because the type is
    /// @available(macOS 15+) and stored properties can't carry availability.
    private var videoRecorderStorage: Any?
    /// The instant moment offsets are measured against. Set to the video's
    /// actual roll time when recording succeeds; falls back to start()'s call
    /// time otherwise.
    private var timelineAnchorDate = Date()

    func start() async {
        timelineAnchorDate = Date()

        if #available(macOS 15.0, *) {
            let videoRecorder = WorkflowScreenVideoRecorder()
            do {
                try await videoRecorder.start()
                videoRecorderStorage = videoRecorder
                if let videoStartDate = videoRecorder.recordingStartedAt {
                    timelineAnchorDate = videoStartDate
                }
            } catch {
                WorkflowDebugLog.log(
                    "demonstrationRecorder: video unavailable (\(error.localizedDescription)) — continuing with moments only"
                )
            }
        } else {
            WorkflowDebugLog.log(
                "demonstrationRecorder: video recording needs macOS 15 — continuing with moments only"
            )
        }

        let anchorDate = timelineAnchorDate
        momentTap.start(offsetProvider: { Date().timeIntervalSince(anchorDate) })
        WorkflowDebugLog.log("demonstrationRecorder: started (video=\(videoRecorderStorage != nil))")
    }

    func stop() async -> RecordedDemonstration {
        let moments = momentTap.stop()
        let durationSeconds = Date().timeIntervalSince(timelineAnchorDate)

        var videoFileURL: URL?
        if #available(macOS 15.0, *),
           let videoRecorder = videoRecorderStorage as? WorkflowScreenVideoRecorder {
            videoFileURL = await videoRecorder.stop()
        }
        videoRecorderStorage = nil

        let sources = WorkflowSourceDerivation.deriveSources(from: moments)
        WorkflowDebugLog.log(
            "demonstrationRecorder: stopped — \(moments.count) moments, "
                + "\(String(format: "%.1f", durationSeconds))s, video=\(videoFileURL?.lastPathComponent ?? "none"), "
                + "sources=[\(sources.map { "\($0.role.rawValue):\($0.applicationBundleIdentifier)" }.joined(separator: " "))]"
        )

        return RecordedDemonstration(
            videoFileURL: videoFileURL,
            recordingStartedAt: timelineAnchorDate,
            durationSeconds: durationSeconds,
            moments: moments,
            sources: sources
        )
    }
}
