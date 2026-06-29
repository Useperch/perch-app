//
//  WorkflowDemonstrationModels.swift
//  leanring-buddy
//
//  Value types for the redesigned Workflows pipeline: the user demonstrates ONE
//  iteration while Perch records a screen VIDEO plus a timestamped timeline of
//  significant moments (copy/paste/click/app-switch…), each grounded in the
//  accessibility tree. From the timeline we derive the demonstration's SOURCES —
//  where the data came from (origin), what it passed through (intermediaries,
//  usually none), and where it ended up (destination). Keyframes cut from the
//  video at moment timestamps + this metadata go to Claude, which writes a
//  generalizable markdown PLAYBOOK that the in-app agent loop then executes.
//
//  Deliberately pure (Foundation + CoreGraphics only) so source derivation,
//  keyframe planning, and AX-tree rendering can be unit-tested in the CLI
//  harness (scripts/check-workflow-agent.sh) without AppKit or a live screen.
//

import CoreGraphics
import Foundation

// MARK: - Sources

/// Where a source sits in the data's journey across the demonstration.
enum WorkflowSourceRole: String, Codable, Equatable {
    case origin
    case intermediary
    case destination
}

/// One app/document/URL the demonstration touched. Identity is the bundle id
/// plus whatever window-level detail the accessibility API exposed.
struct WorkflowSourceDescriptor: Codable, Equatable {
    let role: WorkflowSourceRole
    let applicationBundleIdentifier: String
    let applicationName: String?
    let windowTitle: String?
    /// The focused window's AXDocument path or AXURL, best-effort. For a
    /// browser this is the page URL; for a document app, the file path.
    let documentPathOrURL: String?
}

// MARK: - Accessibility tree snapshot

/// One node of the bounded focused-window accessibility tree captured at a
/// significant moment — the desktop equivalent of a DOM snapshot.
struct AccessibilityNodeSnapshot: Codable, Equatable {
    let role: String
    let label: String?
    /// Truncated to 80 characters at capture time; always nil for secure
    /// text fields.
    let value: String?
    /// Screen frame in points, when the element exposed one.
    let frame: CGRect?
    /// Stable per-snapshot reference token (e.g. "e3") for interactive elements,
    /// rendered as `@e3` so the agent can target this exact element instead of
    /// matching by an ambiguous role+label. Nil for non-interactive nodes and for
    /// the ref-less demonstration snapshot.
    let ref: String?
    let children: [AccessibilityNodeSnapshot]

    init(
        role: String,
        label: String? = nil,
        value: String? = nil,
        frame: CGRect? = nil,
        ref: String? = nil,
        children: [AccessibilityNodeSnapshot] = []
    ) {
        self.role = role
        self.label = label
        self.value = value
        self.frame = frame
        self.ref = ref
        self.children = children
    }

    /// Renders the tree as indented `role "label" = value [x,y wxh]` lines —
    /// far cheaper in tokens than JSON, and what both the playbook synthesizer
    /// and the agent loop put in front of the model.
    func renderIndentedLines(indentLevel: Int = 0) -> [String] {
        var line = String(repeating: "  ", count: indentLevel) + role
        if let label, !label.isEmpty {
            line += " \"\(label)\""
        }
        // The `@eN` ref is the agent's exact click target — placed right after the
        // label (and before value/frame) so it reads as the element's identity.
        if let ref, !ref.isEmpty {
            line += " @\(ref)"
        }
        if let value, !value.isEmpty {
            line += " = \(value)"
        }
        if let frame {
            line += " [\(Int(frame.origin.x)),\(Int(frame.origin.y)) \(Int(frame.width))x\(Int(frame.height))]"
        }
        var lines = [line]
        for child in children {
            lines.append(contentsOf: child.renderIndentedLines(indentLevel: indentLevel + 1))
        }
        return lines
    }
}

// MARK: - Demonstration moments

/// The kinds of significant moment the demonstration recorder timestamps.
enum DemonstrationMomentKind: String, Codable, Equatable {
    case copy
    case paste
    case click
    case appSwitch
    case typingBurst
    case navigationKey

    /// Moments that anchor the data flow — keyframes at these are never
    /// dropped when the keyframe plan is over budget.
    var isDataFlowAnchor: Bool {
        switch self {
        case .copy, .paste, .click, .appSwitch:
            return true
        case .typingBurst, .navigationKey:
            return false
        }
    }
}

/// One significant moment during the demonstration, timestamped against the
/// video's start so a keyframe can be cut at it.
struct DemonstrationMoment: Codable, Equatable {
    /// Seconds since the recording (video) started.
    let offsetSeconds: TimeInterval
    let kind: DemonstrationMomentKind
    let applicationBundleIdentifier: String?
    let applicationName: String?
    let windowTitle: String?
    /// AXDocument path or AXURL of the focused window at this moment.
    let documentPathOrURL: String?
    /// Kind-specific payload: the copied string for `.copy`, the key name for
    /// `.navigationKey`, a character count summary for `.typingBurst`.
    let detail: String?
    /// Accessibility grounding of the element involved (clicked / focused).
    let focusedElementRole: String?
    let focusedElementLabel: String?
    /// Bounded tree of the focused window, captured for copy/paste/click
    /// moments (debounced); nil otherwise.
    let focusedWindowTreeSnapshot: AccessibilityNodeSnapshot?

    init(
        offsetSeconds: TimeInterval,
        kind: DemonstrationMomentKind,
        applicationBundleIdentifier: String? = nil,
        applicationName: String? = nil,
        windowTitle: String? = nil,
        documentPathOrURL: String? = nil,
        detail: String? = nil,
        focusedElementRole: String? = nil,
        focusedElementLabel: String? = nil,
        focusedWindowTreeSnapshot: AccessibilityNodeSnapshot? = nil
    ) {
        self.offsetSeconds = offsetSeconds
        self.kind = kind
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.documentPathOrURL = documentPathOrURL
        self.detail = detail
        self.focusedElementRole = focusedElementRole
        self.focusedElementLabel = focusedElementLabel
        self.focusedWindowTreeSnapshot = focusedWindowTreeSnapshot
    }

    /// A compact single-line rendering for the analysis prompt, e.g.
    /// `[00:03.2] COPY "Marcus Bell" in com.apple.Safari — "Conference Attendees"`.
    func renderTimelineLine() -> String {
        let minutes = Int(offsetSeconds) / 60
        let seconds = offsetSeconds - Double(minutes * 60)
        var line = String(format: "[%02d:%04.1f] %@", minutes, seconds, kind.rawValue.uppercased())
        if let detail, !detail.isEmpty {
            line += " \"\(detail)\""
        }
        if let applicationBundleIdentifier {
            line += " in \(applicationBundleIdentifier)"
        }
        if let windowTitle, !windowTitle.isEmpty {
            line += " — \"\(windowTitle)\""
        }
        if let focusedElementRole {
            line += " (\(focusedElementRole)"
            if let focusedElementLabel, !focusedElementLabel.isEmpty {
                line += " \"\(focusedElementLabel)\""
            }
            line += ")"
        }
        return line
    }
}

// MARK: - Recorded demonstration

/// Everything `WorkflowDemonstrationRecorder.stop()` hands the analysis stage.
struct RecordedDemonstration {
    /// nil when video recording failed or is unavailable — analysis then runs
    /// on whatever keyframes the recorder could produce another way.
    let videoFileURL: URL?
    let recordingStartedAt: Date
    let durationSeconds: TimeInterval
    let moments: [DemonstrationMoment]
    let sources: [WorkflowSourceDescriptor]
}

/// Derives the demonstration's sources from its moment timeline:
///   • origin       = the app of the first `.copy` (where the data came from)
///   • destination  = the app(s) the user pasted into
///   • intermediary = every other app the demonstration touched
/// Each descriptor carries the richest window detail seen for that app across
/// the timeline. Pure function so the CLI harness can assert it on canned
/// timelines.
enum WorkflowSourceDerivation {

    static func deriveSources(from moments: [DemonstrationMoment]) -> [WorkflowSourceDescriptor] {
        // Richest-known window detail per app, last writer wins per field.
        var applicationNameByBundleIdentifier: [String: String] = [:]
        var windowTitleByBundleIdentifier: [String: String] = [:]
        var documentByBundleIdentifier: [String: String] = [:]
        var bundleIdentifiersInAppearanceOrder: [String] = []

        for moment in moments {
            guard let bundleIdentifier = moment.applicationBundleIdentifier else { continue }
            if !bundleIdentifiersInAppearanceOrder.contains(bundleIdentifier) {
                bundleIdentifiersInAppearanceOrder.append(bundleIdentifier)
            }
            if let applicationName = moment.applicationName, !applicationName.isEmpty {
                applicationNameByBundleIdentifier[bundleIdentifier] = applicationName
            }
            if let windowTitle = moment.windowTitle, !windowTitle.isEmpty {
                windowTitleByBundleIdentifier[bundleIdentifier] = windowTitle
            }
            if let document = moment.documentPathOrURL, !document.isEmpty {
                documentByBundleIdentifier[bundleIdentifier] = document
            }
        }

        let originBundleIdentifier = moments
            .first(where: { $0.kind == .copy && $0.applicationBundleIdentifier != nil })?
            .applicationBundleIdentifier
            ?? bundleIdentifiersInAppearanceOrder.first

        var destinationBundleIdentifiers: [String] = []
        for moment in moments where moment.kind == .paste {
            guard let bundleIdentifier = moment.applicationBundleIdentifier else { continue }
            if !destinationBundleIdentifiers.contains(bundleIdentifier) {
                destinationBundleIdentifiers.append(bundleIdentifier)
            }
        }
        // A demonstration with no paste (e.g. data re-typed by hand) still has
        // an end: the last app that wasn't the origin.
        if destinationBundleIdentifiers.isEmpty,
           let lastDistinctBundleIdentifier = bundleIdentifiersInAppearanceOrder.last,
           lastDistinctBundleIdentifier != originBundleIdentifier {
            destinationBundleIdentifiers = [lastDistinctBundleIdentifier]
        }

        func descriptor(for bundleIdentifier: String, role: WorkflowSourceRole) -> WorkflowSourceDescriptor {
            WorkflowSourceDescriptor(
                role: role,
                applicationBundleIdentifier: bundleIdentifier,
                applicationName: applicationNameByBundleIdentifier[bundleIdentifier],
                windowTitle: windowTitleByBundleIdentifier[bundleIdentifier],
                documentPathOrURL: documentByBundleIdentifier[bundleIdentifier]
            )
        }

        var sources: [WorkflowSourceDescriptor] = []
        if let originBundleIdentifier {
            sources.append(descriptor(for: originBundleIdentifier, role: .origin))
        }
        for bundleIdentifier in bundleIdentifiersInAppearanceOrder
        where bundleIdentifier != originBundleIdentifier
            && !destinationBundleIdentifiers.contains(bundleIdentifier) {
            sources.append(descriptor(for: bundleIdentifier, role: .intermediary))
        }
        // The origin can legitimately also be a destination (paste back into
        // the same app) — list it under both roles in that case.
        for bundleIdentifier in destinationBundleIdentifiers {
            sources.append(descriptor(for: bundleIdentifier, role: .destination))
        }
        return sources
    }
}

// MARK: - Keyframes

/// One image cut from the demonstration, abstracted from how it was produced
/// (video frame extraction or a live screenshot fallback).
struct WorkflowKeyframe {
    let offsetSeconds: TimeInterval
    let jpegData: Data
    /// What the model is told about this frame, e.g.
    /// `"t=12.4s — just after COPY in com.apple.Safari"`.
    let label: String
}

/// One planned extraction timestamp, before any video decoding happens.
struct WorkflowKeyframePlanEntry: Equatable {
    let offsetSeconds: TimeInterval
    let reason: String
    /// Anchors (copy/paste/click/appSwitch) survive the budget cap; periodic
    /// samples and low-signal moments are dropped first.
    let isDataFlowAnchor: Bool
}

/// Plans WHICH timestamps to cut keyframes at — pure logic, separated from the
/// AVFoundation decoding so the CLI harness can assert selection and budget
/// behavior directly.
enum WorkflowKeyframePlanner {

    /// The on-screen *effect* of a moment (pasted text appearing, a page having
    /// loaded) trails the input event slightly; sample just after it.
    static let momentEffectDelaySeconds: TimeInterval = 0.3
    /// Periodic context samples between moments.
    static let periodicSampleIntervalSeconds: TimeInterval = 5.0
    /// Two planned frames closer than this collapse into one.
    static let deduplicationWindowSeconds: TimeInterval = 0.5
    /// Hard cap on frames sent to the model (payload + token budget).
    static let maximumKeyframeCount = 14

    static func planKeyframes(
        forMoments moments: [DemonstrationMoment],
        durationSeconds: TimeInterval
    ) -> [WorkflowKeyframePlanEntry] {
        guard durationSeconds > 0 else { return [] }

        var plannedEntries: [WorkflowKeyframePlanEntry] = []

        for moment in moments {
            let sampleOffset = min(moment.offsetSeconds + momentEffectDelaySeconds, durationSeconds)
            var reason = "just after \(moment.kind.rawValue.uppercased())"
            if let bundleIdentifier = moment.applicationBundleIdentifier {
                reason += " in \(bundleIdentifier)"
            }
            plannedEntries.append(WorkflowKeyframePlanEntry(
                offsetSeconds: sampleOffset,
                reason: reason,
                isDataFlowAnchor: moment.kind.isDataFlowAnchor
            ))
        }

        var periodicOffset = periodicSampleIntervalSeconds
        while periodicOffset < durationSeconds {
            plannedEntries.append(WorkflowKeyframePlanEntry(
                offsetSeconds: periodicOffset,
                reason: "periodic context sample",
                isDataFlowAnchor: false
            ))
            periodicOffset += periodicSampleIntervalSeconds
        }

        plannedEntries.sort { $0.offsetSeconds < $1.offsetSeconds }

        // Dedupe near-coincident frames; an anchor absorbs a non-anchor.
        var dedupedEntries: [WorkflowKeyframePlanEntry] = []
        for entry in plannedEntries {
            if let lastEntry = dedupedEntries.last,
               entry.offsetSeconds - lastEntry.offsetSeconds < deduplicationWindowSeconds {
                if entry.isDataFlowAnchor && !lastEntry.isDataFlowAnchor {
                    dedupedEntries[dedupedEntries.count - 1] = entry
                }
                continue
            }
            dedupedEntries.append(entry)
        }

        // Over budget: drop non-anchors (periodic first by construction — they
        // are the only entries besides typing/navigation that are non-anchors),
        // keeping chronological order. Anchors are never dropped, even if that
        // exceeds the cap — a copy moment missing from the evidence is worse
        // than a slightly bigger payload.
        guard dedupedEntries.count > maximumKeyframeCount else { return dedupedEntries }

        let anchorEntries = dedupedEntries.filter { $0.isDataFlowAnchor }
        var remainingBudget = maximumKeyframeCount - anchorEntries.count
        var cappedEntries: [WorkflowKeyframePlanEntry] = []
        for entry in dedupedEntries {
            if entry.isDataFlowAnchor {
                cappedEntries.append(entry)
            } else if remainingBudget > 0 {
                cappedEntries.append(entry)
                remainingBudget -= 1
            }
        }
        return cappedEntries
    }
}

// MARK: - Playbook

/// The durable artifact of analysis: a generalizable markdown document another
/// agent (the in-app loop) can follow. Only the title is structured; the
/// markdown itself is opaque to code and user-editable on disk.
struct WorkflowPlaybook: Equatable {
    let title: String
    let slug: String
    let markdown: String
    let fileURL: URL?
}
