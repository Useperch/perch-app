//
//  DesktopWorkflowPerceiver.swift
//  leanring-buddy
//
//  The live perception half of the workflow agent loop: captures what the
//  agent sees each turn — the cursor screen at the model's effective
//  resolution (1568 px long edge) with Perch's own windows excluded, plus the
//  focused window's identity and bounded AX tree.
//
//  Screenshot failure is non-fatal: the agent can still act on the AX context
//  alone for a turn (the decider notes the missing image in its prompt).
//

import AppKit
import Foundation

@MainActor
final class DesktopWorkflowPerceiver: WorkflowAgentPerceiving {

    private static let perceptionImageMaxLongEdge = 1568

    func perceive() async -> WorkflowAgentPerception {
        var screenshotJPEGData: Data?
        var screenshotWidthInPixels = 0
        var screenshotHeightInPixels = 0
        var displayFrame = CGRect.zero
        if let screenCaptures = try? await CompanionScreenCaptureUtility
            .captureAllScreensAsJPEG(maxDimension: Self.perceptionImageMaxLongEdge),
           let cursorScreenCapture = screenCaptures.first {
            screenshotJPEGData = cursorScreenCapture.imageData
            screenshotWidthInPixels = cursorScreenCapture.screenshotWidthInPixels
            screenshotHeightInPixels = cursorScreenCapture.screenshotHeightInPixels
            displayFrame = cursorScreenCapture.displayFrame
        }

        let windowContext = AccessibilityTreeSnapshotter.focusedWindowContext()
        var accessibilityContextLines: [String] = []
        var contextHeadline = "Focused: \(windowContext.applicationBundleIdentifier ?? "unknown app")"
        if let windowTitle = windowContext.windowTitle {
            contextHeadline += " — window \"\(windowTitle)\""
        }
        if let document = windowContext.documentPathOrURL {
            contextHeadline += " — \(document)"
        }
        accessibilityContextLines.append(contextHeadline)
        // Ref-aware snapshot: interactive elements get a stable `@eN` ref that the
        // agent targets exactly, resolved later via this map.
        var refResolutionMap: [String: ResolvedAccessibilityElement] = [:]
        if let refSnapshot = AccessibilityTreeSnapshotter.snapshotFocusedWindowWithRefs() {
            accessibilityContextLines.append(contentsOf: refSnapshot.snapshot.renderIndentedLines())
            refResolutionMap = refSnapshot.refResolutionMap
        }

        return WorkflowAgentPerception(
            screenshotJPEGData: screenshotJPEGData,
            screenshotWidthInPixels: screenshotWidthInPixels,
            screenshotHeightInPixels: screenshotHeightInPixels,
            displayFrame: displayFrame,
            accessibilityContext: accessibilityContextLines.joined(separator: "\n"),
            frontmostApplicationBundleIdentifier: windowContext.applicationBundleIdentifier,
            refResolutionMap: refResolutionMap
        )
    }
}
