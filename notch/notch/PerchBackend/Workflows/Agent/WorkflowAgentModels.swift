//
//  WorkflowAgentModels.swift
//  Perch
//
//  Value types and seams for the in-app desktop agent loop that executes a
//  workflow playbook: the fixed action vocabulary the model may emit, the
//  per-turn decision shape, the tolerant JSON-in-text parser (the model
//  replies with a single JSON object, possibly wrapped in prose or a code
//  fence), the hard guardrails that bound a run, the perception/decision/
//  actuation protocols the loop is built against, and the run result.
//
//  Pure (Foundation + CoreGraphics only) so the CLI harness
//  (scripts/check-workflow-agent.sh) can compile the REAL loop against fake
//  seam implementations.
//

import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Action vocabulary

/// Every action the agent loop can take. One action per model turn.
enum WorkflowAgentAction: Equatable {
    /// Click an accessibility element in the focused window. Preferred targeting
    /// is by `ref` — the exact `@eN` token from the snapshot the agent saw. When
    /// no ref is given, falls back to matching `role` + `label`. (Preferred over
    /// coordinates either way — survives layout shifts.)
    case clickElement(ref: String?, role: String?, label: String?)
    /// Click at a position in the CURRENT screenshot's pixel space (fallback
    /// when no accessibility element matches).
    case clickAt(xPixels: Int, yPixels: Int)
    /// Type text character-by-character into the focused element.
    case typeText(String)
    /// Put text on the clipboard and paste it with ⌘V.
    case pasteText(String)
    /// Press a single key (a letter, digit, or named special key) with any
    /// combination of modifiers held — e.g. ⌘C to copy, ⌘A to select all, or a
    /// bare `tab`. One chord per turn.
    case pressKey(key: String, modifiers: Set<WorkflowAgentKeyModifier>)
    /// Scroll-wheel at a position in the CURRENT screenshot's pixel space.
    /// Routed by the window server to whatever is under that point, regardless
    /// of keyboard focus — the reliable way to reveal more of a source list.
    case scroll(xPixels: Int, yPixels: Int, scrollDown: Bool, lineCount: Int)
    /// Run an AppleScript (the required path for Excel cell writes — Excel
    /// silently discards synthesized keystrokes).
    case runAppleScript(source: String)
    /// Run a shell command in the repo scratch directory. The general
    /// code-execution escape hatch: generate a file in its native format (e.g.
    /// a SpreadsheetML `.xml` or an `.xlsx` built by a script) and `open` it, or
    /// run any other scripted task. The command's combined stdout+stderr is
    /// captured and returned to the model so it can react to the output.
    case runShell(command: String)
    /// The playbook's done-criteria are visibly satisfied.
    case done(summary: String)
    /// The agent cannot make progress.
    case fail(reason: String)

    /// Terminal actions end the run without actuating anything.
    var isTerminal: Bool {
        switch self {
        case .done, .fail: return true
        default: return false
        }
    }
}

/// Named special keys `pressKey` accepts (beyond plain letters/digits), mapped
/// to virtual key codes by the actuator.
enum WorkflowAgentPressableKey: String, CaseIterable {
    case tab, `return`, escape, delete, space
    case up, down, left, right
    /// Scrolling a source list that continues beyond the visible region.
    case pageup, pagedown, home, end
}

/// Modifiers that can be held while pressing a key, so the agent can express
/// chords like ⌘C (copy), ⌘A (select all), or ⇧⌥… combinations.
enum WorkflowAgentKeyModifier: String, CaseIterable {
    case command, shift, option, control
}

/// Normalizes and validates a requested key. Accepts a single letter `a–z` or
/// digit `0–9`, or one of the named special keys — returning the lowercased
/// canonical name. Returns `nil` for anything else, so the model still can't
/// smuggle arbitrary input (e.g. `F13`, multi-character junk).
func canonicalWorkflowAgentKey(_ rawKey: String) -> String? {
    let normalizedKey = rawKey.lowercased()
    if normalizedKey.count == 1,
       let singleCharacter = normalizedKey.first,
       singleCharacter.isLetter || singleCharacter.isNumber,
       singleCharacter.isASCII {
        return normalizedKey
    }
    if WorkflowAgentPressableKey(rawValue: normalizedKey) != nil {
        return normalizedKey
    }
    return nil
}

// MARK: - Decision

/// One parsed model turn: what it saw, what it does next, and the short
/// human-readable step line the progress UI shows.
struct WorkflowAgentDecision: Equatable {
    /// The model's read of the current screen — REQUIRED to state whether the
    /// previous action had its expected effect.
    let observation: String
    let action: WorkflowAgentAction
    /// e.g. "Filling row 6 with Dana Cho". Shown in the notch surface.
    let stepDescription: String
}

enum WorkflowAgentDecisionParseError: Error, LocalizedError, Equatable {
    case noJSONObjectFound
    case invalidJSON
    case missingOrUnknownActionType(String)
    case missingActionField(actionType: String, field: String)

    var errorDescription: String? {
        switch self {
        case .noJSONObjectFound:
            return "No JSON object found in the response."
        case .invalidJSON:
            return "The response's JSON could not be parsed."
        case .missingOrUnknownActionType(let actionType):
            return "Unknown or missing action type \"\(actionType)\"."
        case .missingActionField(let actionType, let field):
            return "Action \"\(actionType)\" is missing required field \"\(field)\"."
        }
    }
}

/// Parses the model's decision out of free text. Tolerant of prose and code
/// fences: slices from the first `{` to the last `}` (the same approach the
/// extraction pass used successfully).
enum WorkflowAgentDecisionParser {

    static func parse(_ responseText: String) throws -> WorkflowAgentDecision {
        guard let firstBrace = responseText.firstIndex(of: "{"),
              let lastBrace = responseText.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            throw WorkflowAgentDecisionParseError.noJSONObjectFound
        }
        let jsonSubstring = String(responseText[firstBrace...lastBrace])

        guard let jsonData = jsonSubstring.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw WorkflowAgentDecisionParseError.invalidJSON
        }

        let observation = (root["observation"] as? String) ?? ""
        let stepDescription = (root["step"] as? String) ?? ""

        // Tolerate the top-level done/fail shorthand the model sometimes emits
        // instead of the documented {"action":{"type":"done",...}} form, e.g.
        // {"done": true, "summary": "…"} or {"fail": true, "reason": "…"}.
        if root["action"] == nil {
            if root["done"] != nil {
                return WorkflowAgentDecision(
                    observation: observation,
                    action: .done(summary: (root["summary"] as? String) ?? "Done."),
                    stepDescription: stepDescription
                )
            }
            if root["fail"] != nil {
                return WorkflowAgentDecision(
                    observation: observation,
                    action: .fail(reason: (root["reason"] as? String) ?? "The agent gave up."),
                    stepDescription: stepDescription
                )
            }
        }

        guard let actionObject = root["action"] as? [String: Any],
              let actionType = actionObject["type"] as? String else {
            throw WorkflowAgentDecisionParseError.missingOrUnknownActionType(
                String(describing: root["action"])
            )
        }

        let action = try parseAction(type: actionType, from: actionObject)
        return WorkflowAgentDecision(
            observation: observation,
            action: action,
            stepDescription: stepDescription
        )
    }

    /// Decode one action object `{ "type": ..., ...fields }` into an action.
    ///
    /// The desktop tool reuses this so a Core-decided desktop action maps onto the
    /// exact, already-tested actuator primitives the workflow decider produces —
    /// no second action vocabulary to keep in sync.
    static func parseActionObject(
        _ actionObject: [String: Any]
    ) throws -> WorkflowAgentAction {
        guard let actionType = actionObject["type"] as? String else {
            throw WorkflowAgentDecisionParseError.missingOrUnknownActionType(
                String(describing: actionObject)
            )
        }
        return try parseAction(type: actionType, from: actionObject)
    }

    private static func parseAction(
        type actionType: String,
        from actionObject: [String: Any]
    ) throws -> WorkflowAgentAction {
        func requiredString(_ field: String) throws -> String {
            guard let value = actionObject[field] as? String, !value.isEmpty else {
                throw WorkflowAgentDecisionParseError.missingActionField(
                    actionType: actionType, field: field
                )
            }
            return value
        }
        func optionalString(_ field: String) -> String? {
            guard let value = actionObject[field] as? String, !value.isEmpty else {
                return nil
            }
            return value
        }
        func requiredInt(_ field: String) throws -> Int {
            // JSONSerialization may surface numbers as Int, Double, or NSNumber.
            if let intValue = actionObject[field] as? Int { return intValue }
            if let doubleValue = actionObject[field] as? Double { return Int(doubleValue) }
            throw WorkflowAgentDecisionParseError.missingActionField(
                actionType: actionType, field: field
            )
        }

        switch actionType {
        case "click_element":
            // Target by `ref` (exact) OR by `role` + `label` (fallback). At least
            // one complete form must be present.
            let ref = optionalString("ref")
            let role = optionalString("role")
            let label = optionalString("label")
            guard ref != nil || (role != nil && label != nil) else {
                throw WorkflowAgentDecisionParseError.missingActionField(
                    actionType: actionType, field: "ref (or both role and label)"
                )
            }
            return .clickElement(ref: ref, role: role, label: label)
        case "click_at":
            return .clickAt(xPixels: try requiredInt("x"), yPixels: try requiredInt("y"))
        case "type_text":
            return .typeText(try requiredString("text"))
        case "paste_text":
            return .pasteText(try requiredString("text"))
        // `press_key` is the one general hotkey primitive. We also accept the
        // variant type names the model reaches for (key_combination, etc.) and
        // route them here, so a chord like ⌘C executes instead of failing.
        case "press_key", "key_combination", "key_sequence", "hotkey", "keypress":
            guard let canonicalKey = canonicalWorkflowAgentKey(try requiredString("key")) else {
                let requestedKey = (actionObject["key"] as? String) ?? ""
                throw WorkflowAgentDecisionParseError.missingActionField(
                    actionType: actionType, field: "key (unknown: \(requestedKey))"
                )
            }
            return .pressKey(key: canonicalKey, modifiers: parseModifiers(from: actionObject))
        case "scroll":
            let direction = ((actionObject["direction"] as? String) ?? "down").lowercased()
            guard direction == "down" || direction == "up" else {
                throw WorkflowAgentDecisionParseError.missingActionField(
                    actionType: actionType, field: "direction (unknown: \(direction))"
                )
            }
            // Default a meaningful scroll; clamp so the model can't fling the
            // view arbitrarily far in one action.
            let requestedLineCount = (actionObject["amount"] as? Int)
                ?? Int(actionObject["amount"] as? Double ?? 10)
            return .scroll(
                xPixels: try requiredInt("x"),
                yPixels: try requiredInt("y"),
                scrollDown: direction == "down",
                lineCount: min(max(requestedLineCount, 1), 50)
            )
        case "applescript":
            return .runAppleScript(source: try requiredString("source"))
        case "run_shell", "shell", "run_code":
            return .runShell(command: try requiredString("command"))
        case "done":
            return .done(summary: (actionObject["summary"] as? String) ?? "Done.")
        case "fail":
            return .fail(reason: (actionObject["reason"] as? String) ?? "The agent gave up.")
        default:
            throw WorkflowAgentDecisionParseError.missingOrUnknownActionType(actionType)
        }
    }

    /// The set of modifiers a press_key action wants held. Reads the preferred
    /// `modifiers: ["command","shift",…]` array, and stays back-compatible with
    /// the legacy `command: true` boolean. Unknown modifier names are ignored.
    private static func parseModifiers(
        from actionObject: [String: Any]
    ) -> Set<WorkflowAgentKeyModifier> {
        var modifiers: Set<WorkflowAgentKeyModifier> = []
        if let modifierNames = actionObject["modifiers"] as? [String] {
            for modifierName in modifierNames {
                if let modifier = WorkflowAgentKeyModifier(rawValue: modifierName.lowercased()) {
                    modifiers.insert(modifier)
                }
            }
        }
        if (actionObject["command"] as? Bool) == true {
            modifiers.insert(.command)
        }
        return modifiers
    }
}

// MARK: - Guardrails

/// Hard bounds on a single agent run. The loop fails the run when any trips.
struct WorkflowAgentGuardrails {
    let maxActions: Int
    let maxRunDuration: TimeInterval
    /// Pause after each action before re-perceiving, so the UI settles.
    let perActionSettleDelay: TimeInterval

    static let standard = WorkflowAgentGuardrails(
        maxActions: 40,
        maxRunDuration: 300,
        perActionSettleDelay: 0.4
    )
}

// MARK: - Perception

/// Everything the loop perceived this turn. The actuator needs the screenshot
/// geometry to convert the model's pixel coordinates into screen points.
/// A live element the agent can target by its `@eN` ref, plus the role/label it
/// had at snapshot time so the actuator can confirm the element is still the one
/// the agent saw (stale-ref detection) and describe what it clicked.
struct ResolvedAccessibilityElement {
    let element: AXUIElement
    let role: String
    let label: String?
}

struct WorkflowAgentPerception {
    let screenshotJPEGData: Data?
    let screenshotWidthInPixels: Int
    let screenshotHeightInPixels: Int
    /// AppKit-coordinate frame (bottom-left origin) of the captured display —
    /// the same metadata CompanionScreenCapture carries.
    let displayFrame: CGRect
    /// The focused window's AX tree + context, rendered as indented lines.
    let accessibilityContext: String
    let frontmostApplicationBundleIdentifier: String?
    /// The bundle id of the app this task is supposed to act on — the one the user
    /// was looking at when the subagent spawned. The actuator keeps synthetic input
    /// on this app: if focus has drifted to another app, it brings the target back
    /// frontmost (or refuses) rather than pasting into the wrong window. `nil` for
    /// callers with no fixed target (the playbook/loop runners), which skips the guard.
    let targetApplicationBundleIdentifier: String?
    /// `@eN` ref → the live element it names, captured at snapshot time. Empty for
    /// the test fakes and any perception built without ref-aware snapshotting. In
    /// memory only — never encoded (the struct is not Codable).
    let refResolutionMap: [String: ResolvedAccessibilityElement]

    init(
        screenshotJPEGData: Data?,
        screenshotWidthInPixels: Int,
        screenshotHeightInPixels: Int,
        displayFrame: CGRect,
        accessibilityContext: String,
        frontmostApplicationBundleIdentifier: String?,
        targetApplicationBundleIdentifier: String? = nil,
        refResolutionMap: [String: ResolvedAccessibilityElement] = [:]
    ) {
        self.screenshotJPEGData = screenshotJPEGData
        self.screenshotWidthInPixels = screenshotWidthInPixels
        self.screenshotHeightInPixels = screenshotHeightInPixels
        self.displayFrame = displayFrame
        self.accessibilityContext = accessibilityContext
        self.frontmostApplicationBundleIdentifier = frontmostApplicationBundleIdentifier
        self.targetApplicationBundleIdentifier = targetApplicationBundleIdentifier
        self.refResolutionMap = refResolutionMap
    }
}

/// What one action did, fed back to the model on its next turn so it can
/// verify and adapt.
struct WorkflowAgentActionOutcome: Equatable {
    let succeeded: Bool
    let resultDescription: String
}

// MARK: - Loop seams

/// The loop's three injected dependencies: the real implementations are
/// DesktopWorkflowPerceiver / ClaudeWorkflowActionDecider /
/// WorkflowAgentActuator; the CLI harness substitutes fakes.

@MainActor
protocol WorkflowAgentPerceiving: AnyObject {
    func perceive() async -> WorkflowAgentPerception
}

@MainActor
protocol WorkflowActionDeciding: AnyObject {
    /// One model turn. `previousTurns` carries (placeholder, rawModelResponse)
    /// pairs — old screenshots are represented only by their placeholders.
    func decide(
        playbookMarkdown: String,
        perception: WorkflowAgentPerception,
        previousTurns: [(userPlaceholder: String, assistantResponse: String)],
        previousActionResult: String?
    ) async throws -> (decision: WorkflowAgentDecision, rawResponse: String)
}

@MainActor
protocol WorkflowActionPerforming: AnyObject {
    /// Called once before the first action (saves the user's clipboard).
    func beginRun()
    /// Called once after the last action (restores the user's clipboard).
    func endRun()
    func perform(
        _ action: WorkflowAgentAction,
        perception: WorkflowAgentPerception
    ) async -> WorkflowAgentActionOutcome
}

// MARK: - Run result

enum WorkflowAgentRunOutcome: Equatable {
    case done(summary: String)
    case failed(reason: String)
    case cancelled
}

struct WorkflowAgentRunResult: Equatable {
    let outcome: WorkflowAgentRunOutcome
    let actionsUsed: Int
}
