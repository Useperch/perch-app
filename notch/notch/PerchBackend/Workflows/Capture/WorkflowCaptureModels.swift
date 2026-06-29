//
//  WorkflowCaptureModels.swift
//  leanring-buddy
//
//  Value types shared by the Workflows capture layer and the repetition
//  detector. These are deliberately pure (Foundation only, no AppKit) so the
//  detection logic can be unit-tested in isolation and so nothing here couples
//  to the cursor overlay or the notch UI.
//
//  Privacy note: a SemanticInputEvent never carries raw keystrokes or raw
//  clipboard contents. Anything content-bearing (what was copied, what was
//  typed) is reduced to a *hash* — enough to tell "the content changed between
//  repetitions" apart from "the same thing happened twice", and nothing more.
//

import Foundation

/// The kind of thing the user did, normalized away from the raw OS event.
///
/// For the M0 hero flow (copy a cell, paste into a form field, click a button,
/// repeat) the meaningful actions are `copy`, `paste`, and `click`. The other
/// cases exist so the capture layer can record a faithful trace without the
/// detector having to special-case unknown input.
enum WorkflowActionType: String, Codable, Hashable {
    case copy
    case paste
    case click
    case typeText
    case keyboardShortcut

    /// Whether this action *commits* a unit of work (writes data or triggers an
    /// effect) as opposed to merely *gathering* it (copying, selecting). The
    /// repetition detector requires a committing action inside a cycle before it
    /// will offer to take over, so that "the user keeps copying cells" — which
    /// is shape-same/content-different but not yet an actionable task — does not
    /// trip the offer.
    var isCommittingAction: Bool {
        switch self {
        case .paste, .click, .typeText:
            return true
        case .copy, .keyboardShortcut:
            return false
        }
    }
}

/// One observed user action, captured locally. The grounding fields
/// (`targetAccessibilityRole` / `targetAccessibilityLabel`) come from the
/// frontmost app's accessibility tree where available; they are what lets the
/// detector tell "click the Add button" apart from "click somewhere".
struct SemanticInputEvent: Codable, Identifiable, Equatable {
    let id: UUID
    /// The app the action happened in, e.g. "com.apple.Numbers".
    let applicationBundleIdentifier: String
    let actionType: WorkflowActionType
    /// Accessibility role of the targeted element, e.g. "AXButton", "AXTextField".
    let targetAccessibilityRole: String?
    /// Accessibility label/title of the targeted element, e.g. "Add", "Recipient".
    let targetAccessibilityLabel: String?
    /// Hash of the clipboard contents at a copy/paste boundary. Never the raw
    /// content. `nil` for actions that do not touch the clipboard.
    let clipboardContentHash: String?
    /// Hash of text the user typed. Never the raw text. `nil` for non-typing
    /// actions and always `nil` for secure-input fields (which are elided
    /// upstream and never reach this struct).
    let typedTextContentHash: String?
    let occurredAt: Date

    init(
        id: UUID = UUID(),
        applicationBundleIdentifier: String,
        actionType: WorkflowActionType,
        targetAccessibilityRole: String? = nil,
        targetAccessibilityLabel: String? = nil,
        clipboardContentHash: String? = nil,
        typedTextContentHash: String? = nil,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.actionType = actionType
        self.targetAccessibilityRole = targetAccessibilityRole
        self.targetAccessibilityLabel = targetAccessibilityLabel
        self.clipboardContentHash = clipboardContentHash
        self.typedTextContentHash = typedTextContentHash
        self.occurredAt = occurredAt
    }

    /// The single content hash this event carries, if any. Used by the detector
    /// to decide whether content *varied* across repetitions.
    var contentHash: String? {
        clipboardContentHash ?? typedTextContentHash
    }
}

/// The content-free signature of a single action: same app, same kind of
/// action, same target element — regardless of *what data* flowed through it.
/// Two events with the same shape but different `contentHash` are the
/// fingerprint of manual iteration.
struct WorkflowActionShape: Codable, Hashable {
    let applicationBundleIdentifier: String
    let actionType: WorkflowActionType
    let targetAccessibilityRole: String?
    let targetAccessibilityLabel: String?

    init(from event: SemanticInputEvent) {
        self.applicationBundleIdentifier = event.applicationBundleIdentifier
        self.actionType = event.actionType
        self.targetAccessibilityRole = event.targetAccessibilityRole
        self.targetAccessibilityLabel = event.targetAccessibilityLabel
    }

    /// A short human-readable phrase for this single step, used to compose the
    /// offer's fallback restatement (the LLM produces a nicer one later).
    var humanReadablePhrase: String {
        let appName = WorkflowActionShape.friendlyApplicationName(for: applicationBundleIdentifier)
        let elementName = targetAccessibilityLabel.map { "'\($0)'" }
        switch actionType {
        case .copy:
            return "copy from \(appName)"
        case .paste:
            if let elementName {
                return "paste into the \(elementName) field in \(appName)"
            }
            return "paste into \(appName)"
        case .click:
            if let elementName {
                return "click \(elementName) in \(appName)"
            }
            return "click in \(appName)"
        case .typeText:
            if let elementName {
                return "type into the \(elementName) field in \(appName)"
            }
            return "type into \(appName)"
        case .keyboardShortcut:
            return "use a keyboard shortcut in \(appName)"
        }
    }

    /// Best-effort friendly app name from a bundle identifier (last path
    /// component, e.g. "com.apple.Numbers" → "Numbers"). The capture layer can
    /// supply a better localized name later; this keeps the model pure.
    static func friendlyApplicationName(for bundleIdentifier: String) -> String {
        bundleIdentifier.split(separator: ".").last.map(String.init) ?? bundleIdentifier
    }
}

/// An ordered repeating unit of action shapes (e.g. copy → paste → click).
typealias WorkflowActionShapeSequence = [WorkflowActionShape]

/// What the detector hands to the UI when it spots a repetition worth offering
/// to take over. Carries two distinct strings — the short `offerLine` (step 1)
/// and the detailed `stepByStepRestatement` (step 2) — so their tone can be
/// reviewed and refined independently.
struct WorkflowOffer: Identifiable, Equatable {
    let id: UUID
    /// The fundamental repeating unit that was observed.
    let repeatingActionShapes: WorkflowActionShapeSequence
    /// How many times the unit was observed back-to-back (≥ the threshold).
    let observedRepetitionCount: Int
    /// The distinct apps the cycle spans, in first-seen order.
    let involvedApplicationBundleIdentifiers: [String]
    /// The quiet, short first line shown in the notch offer (step 1 of the
    /// flow), e.g. "looks like you're doing this for each one — want me to help
    /// out?". Deliberately NOT a step-by-step.
    let offerLine: String
    /// The detailed step-by-step restatement (step 2 — the trust step shown
    /// once the user says yes), e.g. "copy from Numbers, paste into the
    /// 'Recipient' field in Safari, then click 'Add'.".
    let stepByStepRestatement: String

    init(
        id: UUID = UUID(),
        repeatingActionShapes: WorkflowActionShapeSequence,
        observedRepetitionCount: Int,
        involvedApplicationBundleIdentifiers: [String],
        offerLine: String,
        stepByStepRestatement: String
    ) {
        self.id = id
        self.repeatingActionShapes = repeatingActionShapes
        self.observedRepetitionCount = observedRepetitionCount
        self.involvedApplicationBundleIdentifiers = involvedApplicationBundleIdentifiers
        self.offerLine = offerLine
        self.stepByStepRestatement = stepByStepRestatement
    }
}
