//
//  DesktopTool.swift
//  Perch
//
//  The "hands" half of the desktop tool family (Plan 09). The Python Core owns the
//  brain: it perceives the focused native app (by asking this tool), decides ONE
//  concrete action, safety-gates it in Core, then asks this tool to perform it. The
//  tool holds NO decision logic — it only:
//
//    • perceive()       — reuse DesktopWorkflowPerceiver to capture the focused
//                         app's AX tree (+ screenshot), serialized for the sidecar.
//    • performAction(_) — decode a Core-decided action with the SAME parser the
//                         workflow decider uses, actuate it with WorkflowAgentActuator,
//                         and return an AX read-back so Core can validate.
//
//  Both the perceiver and the actuator are injected so the logic is unit-testable
//  with no real Accessibility tree, screen capture, or synthetic events.
//

import Foundation

@MainActor
final class DesktopTool {

    private let perceiver: WorkflowAgentPerceiving
    private let actuator: WorkflowActionPerforming

    /// The app this desktop task targets — the one the user was looking at when the
    /// subagent spawned (set by `BrowserSubagentManager`). Threaded into each
    /// action's perception so the actuator keeps synthetic input on this app rather
    /// than whatever drifted into focus. `nil` until a run sets it.
    var targetApplicationBundleIdentifier: String?

    /// Whether the actuator's clipboard save is in effect for the current run. The
    /// user's clipboard is saved ONCE on the first action and restored ONCE when the
    /// run ends (`endClipboardRun`). It must NOT be saved/restored per action: the
    /// model often pastes in two steps — set the clipboard in one action, press ⌘V in
    /// the next — and a per-action restore in between would wipe the agent's text and
    /// paste the user's old clipboard instead (the "pasted the wrong thing" bug).
    private var clipboardRunActive = false

    /// The `@eN` → element map from the most recent `perceive()` — i.e. the
    /// snapshot the agent actually saw when it chose its action. Held across the
    /// perceive → act round trip because `performAction` re-perceives (for
    /// screenshot geometry) and a fresh capture would renumber the refs.
    private var mostRecentRefResolutionMap: [String: ResolvedAccessibilityElement] = [:]

    /// How much of the post-action AX context to send back as the read-back. The
    /// sidecar's text judge reasons over this; a few hundred chars is plenty and
    /// keeps the round-trip small.
    private static let readBackContextCharacterLimit = 1200

    /// Production wiring: the live screen-capture perceiver and the real actuator.
    /// (Built in the body rather than as default arguments because both are
    /// `@MainActor`-isolated, which default-argument evaluation can't satisfy.)
    init() {
        self.perceiver = DesktopWorkflowPerceiver()
        self.actuator = WorkflowAgentActuator()
    }

    /// Injectable wiring for tests — a fake perceiver and a recording actuator.
    init(perceiver: WorkflowAgentPerceiving, actuator: WorkflowActionPerforming) {
        self.perceiver = perceiver
        self.actuator = actuator
    }

    // MARK: - Perceive (up to Core)

    /// Capture the focused app's AX snapshot (+ screenshot) for the sidecar to
    /// reason over. Shape matches what `DesktopDecider` expects:
    /// `{ accessibility, screenshotJpegBase64?, app? }`.
    func perceive() async -> [String: Any] {
        let perception = await perceiver.perceive()
        // Remember the ref map from the snapshot the agent is about to reason over,
        // so the action it picks (which names a ref) resolves against this exact tree.
        mostRecentRefResolutionMap = perception.refResolutionMap
        var payload: [String: Any] = ["accessibility": perception.accessibilityContext]
        if let screenshotData = perception.screenshotJPEGData {
            payload["screenshotJpegBase64"] = screenshotData.base64EncodedString()
        }
        if let bundleIdentifier = perception.frontmostApplicationBundleIdentifier {
            payload["app"] = bundleIdentifier
        }
        return payload
    }

    // MARK: - Act (one Core-decided, Core-gated action) + read-back (up to Core)

    /// Perform one already-decided, already-gated structured action and return a
    /// read-back: `{ ok, methodUsed, readback }`. A parse failure is reported as a
    /// non-fatal `ok: false` read-back rather than throwing, so a malformed action
    /// surfaces to Core as a step result it can re-plan against.
    func performAction(_ actionObject: [String: Any]) async -> [String: Any] {
        let action: WorkflowAgentAction
        do {
            action = try WorkflowAgentDecisionParser.parseActionObject(actionObject)
        } catch {
            return [
                "ok": false,
                "methodUsed": "none",
                "readback": "could not parse desktop action: \(error.localizedDescription)",
            ]
        }

        // A fresh perception gives the actuator the screenshot geometry it needs to
        // map any pixel-space action (scroll / click_at fallback) onto the screen.
        // But ref resolution must use the map from the snapshot the agent SAW (a
        // fresh capture would renumber the refs), so overlay the saved map.
        let freshPerception = await perceiver.perceive()
        let perception = Self.perception(
            freshPerception,
            withRefResolutionMap: mostRecentRefResolutionMap,
            targetApplicationBundleIdentifier: targetApplicationBundleIdentifier
        )

        // Save the user's clipboard ONCE, on the first action of the run — never per
        // action (see `clipboardRunActive`). It is restored in `endClipboardRun()`
        // when the whole run ends, so the agent's pasted text survives across the
        // copy → ⌘V actions in between.
        if !clipboardRunActive {
            actuator.beginRun()
            clipboardRunActive = true
        }
        let outcome = await actuator.perform(action, perception: perception)

        // Read-back: re-perceive so Core sees the focused element's post-action
        // value/state and can validate the step against its done_criterion.
        let postPerception = await perceiver.perceive()
        let readBack = Self.composeReadBack(
            outcomeDescription: outcome.resultDescription,
            postAccessibilityContext: postPerception.accessibilityContext
        )

        return [
            "ok": outcome.succeeded,
            "methodUsed": Self.methodLabel(for: action),
            "readback": readBack,
        ]
    }

    /// Restore the user's clipboard at the end of a run (done / error / cancel /
    /// connection lost). Safe to call when no clipboard run is active — it no-ops, so
    /// it never clears a clipboard it didn't save. Idempotent across a run's exit
    /// paths.
    func endClipboardRun() {
        guard clipboardRunActive else { return }
        actuator.endRun()
        clipboardRunActive = false
    }

    // MARK: - Helpers

    /// A coarse label for which actuation path was taken, for Core's audit trail.
    /// The shipped actuator does not expose its internal fallback ladder rung, so
    /// this is derived from the action kind (fine-grained method tracking is a
    /// follow-up).
    /// A copy of `perception` carrying a specific ref map — used to resolve a
    /// ref-based click against the snapshot the agent saw, not the fresh capture.
    private static func perception(
        _ perception: WorkflowAgentPerception,
        withRefResolutionMap refResolutionMap: [String: ResolvedAccessibilityElement],
        targetApplicationBundleIdentifier: String?
    ) -> WorkflowAgentPerception {
        WorkflowAgentPerception(
            screenshotJPEGData: perception.screenshotJPEGData,
            screenshotWidthInPixels: perception.screenshotWidthInPixels,
            screenshotHeightInPixels: perception.screenshotHeightInPixels,
            displayFrame: perception.displayFrame,
            accessibilityContext: perception.accessibilityContext,
            frontmostApplicationBundleIdentifier: perception.frontmostApplicationBundleIdentifier,
            targetApplicationBundleIdentifier: targetApplicationBundleIdentifier,
            refResolutionMap: refResolutionMap
        )
    }

    private static func methodLabel(for action: WorkflowAgentAction) -> String {
        switch action {
        case .clickElement(let ref, _, _):
            // A ref click resolves the exact element; role+label is the fallback.
            return ref != nil ? "ax.ref" : "ax.match"
        case .clickAt: return "cgevent.click"
        case .typeText: return "cgevent.type"
        case .pasteText: return "clipboard.paste"
        case .pressKey: return "cgevent.key"
        case .scroll: return "cgevent.scroll"
        case .runAppleScript: return "applescript"
        case .runShell: return "shell"
        case .done, .fail: return "none"
        }
    }

    private static func composeReadBack(
        outcomeDescription: String,
        postAccessibilityContext: String
    ) -> String {
        let trimmedContext = String(
            postAccessibilityContext.prefix(readBackContextCharacterLimit)
        )
        if trimmedContext.isEmpty {
            return outcomeDescription
        }
        return "\(outcomeDescription)\n\nFocused app after the action:\n\(trimmedContext)"
    }
}
