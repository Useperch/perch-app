//
//  WorkflowVideoKeyframeExtractor.swift
//  leanring-buddy
//
//  Cuts the keyframes the analysis stage sends to Claude out of the recorded
//  demonstration movie: one frame just after each significant moment plus
//  periodic context samples (planned by WorkflowKeyframePlanner, capped at 14).
//  Frames around COPY moments — where small on-screen text must be READ, not
//  just seen — additionally get left/right close-up tiles, the proven antidote
//  to low-resolution confabulation from the extraction era.
//
//  When the demonstration has no movie (video unavailable/failed), falls back
//  to a single live screenshot of the current screen so analysis still has
//  visual evidence.
//
//  Every image actually sent is dumped to
//  ~/Library/Application Support/Perch/workflows/last-analysis-frames/ so a
//  bad playbook can be diagnosed by LOOKING at what the model saw.
//

import AppKit
import AVFoundation
import CoreGraphics
import Foundation

@MainActor
enum WorkflowVideoKeyframeExtractor {

    /// Longest edge for each image sent to the model — Claude's vision API
    /// downscales anything beyond ~1568 px, so we scale ourselves with
    /// high-quality interpolation instead of letting the server do it blindly.
    private static let modelImageMaxLongEdge = 1568
    /// Horizontal overlap between close-up tiles so content straddling the
    /// midline appears whole in at least one tile.
    private static let tileOverlapFraction: CGFloat = 0.10
    /// Only the first few copy-adjacent frames get close-up tiles — they're
    /// 2 extra images each and the payload budget is load-bearing.
    private static let maxTiledCopyFrames = 3

    /// Produces the chronological labeled images for the analysis call.
    static func extractKeyframes(
        from demonstration: RecordedDemonstration
    ) async -> [WorkflowKeyframe] {
        var keyframes: [WorkflowKeyframe]
        if let videoFileURL = demonstration.videoFileURL {
            keyframes = await extractFromVideo(
                at: videoFileURL,
                moments: demonstration.moments,
                durationSeconds: demonstration.durationSeconds
            )
        } else {
            keyframes = []
        }

        // No movie (or decoding produced nothing): fall back to what the
        // screen looks like NOW, so analysis still has visual evidence.
        if keyframes.isEmpty {
            keyframes = await captureLiveScreenFallback(
                durationSeconds: demonstration.durationSeconds
            )
        }

        dumpKeyframesForDiagnosis(keyframes)
        let totalKilobytes = keyframes.reduce(0) { $0 + $1.jpegData.count } / 1024
        WorkflowDebugLog.log(
            "keyframeExtractor: \(keyframes.count) image(s), \(totalKilobytes) KB total"
        )
        return keyframes
    }

    // MARK: - Video frame extraction

    private static func extractFromVideo(
        at videoFileURL: URL,
        moments: [DemonstrationMoment],
        durationSeconds: TimeInterval
    ) async -> [WorkflowKeyframe] {
        let plan = WorkflowKeyframePlanner.planKeyframes(
            forMoments: moments, durationSeconds: durationSeconds
        )
        guard !plan.isEmpty else { return [] }

        let videoAsset = AVURLAsset(url: videoFileURL)
        let imageGenerator = AVAssetImageGenerator(asset: videoAsset)
        imageGenerator.appliesPreferredTrackTransform = true
        // One 10fps-frame of tolerance: exact-time decoding is slow and buys
        // nothing at this frame rate.
        imageGenerator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 10)
        imageGenerator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)

        var keyframes: [WorkflowKeyframe] = []
        var tiledCopyFrameCount = 0

        for planEntry in plan {
            let requestedTime = CMTime(
                seconds: planEntry.offsetSeconds, preferredTimescale: 600
            )
            guard let frameImage = try? await imageGenerator.image(at: requestedTime).image else {
                WorkflowDebugLog.log(
                    "keyframeExtractor: no frame at \(String(format: "%.1f", planEntry.offsetSeconds))s"
                )
                continue
            }

            let timestampLabel = String(format: "t=%.1fs", planEntry.offsetSeconds)
            guard let overviewData = scaledJPEGData(
                from: frameImage, maxLongEdge: modelImageMaxLongEdge
            ) else { continue }
            keyframes.append(WorkflowKeyframe(
                offsetSeconds: planEntry.offsetSeconds,
                jpegData: overviewData,
                label: "\(timestampLabel) — \(planEntry.reason)"
            ))

            // Close-up tiles where values must be legible (copy moments).
            let isCopyAdjacentFrame = planEntry.reason.contains("COPY")
            if isCopyAdjacentFrame && tiledCopyFrameCount < maxTiledCopyFrames {
                tiledCopyFrameCount += 1
                keyframes.append(contentsOf: makeCloseUpTiles(
                    from: frameImage, timestampLabel: timestampLabel
                ))
            }
        }
        return keyframes
    }

    /// Left/right halves of a frame, each scaled to the model's effective
    /// resolution — small text that is a smudge in the full-frame overview
    /// stays readable here. (Same approach the extraction era verified.)
    private static func makeCloseUpTiles(
        from frameImage: CGImage,
        timestampLabel: String
    ) -> [WorkflowKeyframe] {
        let fullWidth = frameImage.width
        let fullHeight = frameImage.height
        let overlapWidth = Int(CGFloat(fullWidth) * tileOverlapFraction)
        let halfWidth = fullWidth / 2

        var tiles: [WorkflowKeyframe] = []

        let leftRect = CGRect(x: 0, y: 0, width: halfWidth + overlapWidth, height: fullHeight)
        if let leftImage = frameImage.cropping(to: leftRect),
           let leftData = scaledJPEGData(from: leftImage, maxLongEdge: modelImageMaxLongEdge) {
            tiles.append(WorkflowKeyframe(
                offsetSeconds: 0,
                jpegData: leftData,
                label: "CLOSE-UP: left half of the \(timestampLabel) frame — read exact values here."
            ))
        }

        let rightRect = CGRect(
            x: max(halfWidth - overlapWidth, 0), y: 0,
            width: fullWidth - max(halfWidth - overlapWidth, 0), height: fullHeight
        )
        if let rightImage = frameImage.cropping(to: rightRect),
           let rightData = scaledJPEGData(from: rightImage, maxLongEdge: modelImageMaxLongEdge) {
            tiles.append(WorkflowKeyframe(
                offsetSeconds: 0,
                jpegData: rightData,
                label: "CLOSE-UP: right half of the \(timestampLabel) frame — read exact values here."
            ))
        }
        return tiles
    }

    // MARK: - Live screenshot fallback

    /// Captured near-native so small source text stays legible after tiling —
    /// the fallback frame is the ONLY visual evidence when video failed, so it
    /// gets the full overview + close-up-tiles treatment a copy frame would.
    private static let fallbackCaptureMaxDimension = 3024

    private static func captureLiveScreenFallback(
        durationSeconds: TimeInterval
    ) async -> [WorkflowKeyframe] {
        WorkflowDebugLog.log("keyframeExtractor: no video — falling back to a live screenshot")
        guard let screenCaptures = try? await CompanionScreenCaptureUtility
            .captureAllScreensAsJPEG(maxDimension: fallbackCaptureMaxDimension) else {
            return []
        }
        var keyframes: [WorkflowKeyframe] = []
        for capture in screenCaptures {
            let frameLabel = "the screen right after the demonstration ended "
                + "(no recording frames were available) — \(capture.label)"
            guard let fullImage = NSBitmapImageRep(data: capture.imageData)?.cgImage else {
                keyframes.append(WorkflowKeyframe(
                    offsetSeconds: durationSeconds,
                    jpegData: capture.imageData,
                    label: frameLabel
                ))
                continue
            }
            if let overviewData = scaledJPEGData(from: fullImage, maxLongEdge: modelImageMaxLongEdge) {
                keyframes.append(WorkflowKeyframe(
                    offsetSeconds: durationSeconds,
                    jpegData: overviewData,
                    label: "OVERVIEW of \(frameLabel)."
                ))
            }
            keyframes.append(contentsOf: makeCloseUpTiles(
                from: fullImage, timestampLabel: "post-demonstration"
            ))
        }
        return keyframes
    }

    // MARK: - Scaling

    /// High-quality downscale + JPEG encode. Returns the original encoding
    /// only after a no-op scale (image already within `maxLongEdge`).
    private static func scaledJPEGData(from cgImage: CGImage, maxLongEdge: Int) -> Data? {
        let longEdge = max(cgImage.width, cgImage.height)
        let scaleFactor = min(1.0, Double(maxLongEdge) / Double(longEdge))

        var imageToEncode = cgImage
        if scaleFactor < 1.0 {
            let targetWidth = Int(Double(cgImage.width) * scaleFactor)
            let targetHeight = Int(Double(cgImage.height) * scaleFactor)
            guard let drawingContext = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return nil }
            drawingContext.interpolationQuality = .high
            drawingContext.draw(
                imageToEncode,
                in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
            )
            guard let scaledImage = drawingContext.makeImage() else { return nil }
            imageToEncode = scaledImage
        }

        return NSBitmapImageRep(cgImage: imageToEncode)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    // MARK: - Diagnosis dump

    /// Writes the exact images sent to the model into
    /// `~/Library/Application Support/Perch/workflows/last-analysis-frames/`.
    /// Overwritten every run; disabled alongside the debug log.
    private static func dumpKeyframesForDiagnosis(_ keyframes: [WorkflowKeyframe]) {
        guard ProcessInfo.processInfo.environment["CLICKY_WORKFLOW_DEBUG_LOG_DISABLED"] == nil else {
            return
        }
        let dumpDirectory = PerchSupportPaths.directory("workflows")
            .appendingPathComponent("last-analysis-frames", isDirectory: true)
        do {
            try? FileManager.default.removeItem(at: dumpDirectory)
            try FileManager.default.createDirectory(at: dumpDirectory, withIntermediateDirectories: true)
            for (frameIndex, keyframe) in keyframes.enumerated() {
                let fileURL = dumpDirectory.appendingPathComponent("frame-\(frameIndex).jpg")
                try keyframe.jpegData.write(to: fileURL)
                let labelURL = dumpDirectory.appendingPathComponent("frame-\(frameIndex).label.txt")
                try keyframe.label.write(to: labelURL, atomically: true, encoding: .utf8)
            }
        } catch {
            WorkflowDebugLog.log("keyframeExtractor: diagnosis dump failed — \(error.localizedDescription)")
        }
    }
}
