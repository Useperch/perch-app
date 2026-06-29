//
//  WorkflowAgentLoop.swift
//  leanring-buddy
//
//  The in-app desktop agent that EXECUTES a workflow playbook: a
//  perceive → decide → act → verify loop modeled on the browser subagent's
//  Python loop, but Swift-native and driving the user's real desktop.
//
//  Each turn the model gets the playbook (stable system-prompt suffix), a
//  fresh screenshot, the focused window's AX context, and the previous
//  action's result — and emits ONE action as JSON. Verification is the next
//  turn's screenshot: the prompt requires the observation to state whether the
//  previous action had its expected effect, and to try DIFFERENTLY (not
//  identically) when it didn't.
//
//  Hard guards: action budget, wall-clock timeout, and user cancellation are
//  polled every turn. Old screenshots are never resent — each prior turn
//  collapses to a text placeholder + the model's own JSON, keeping the token
//  budget flat as the run grows.
//
//  Perceiver / decider / actuator are injected behind the protocols in
//  WorkflowAgentModels.swift, so the CLI harness
//  (scripts/check-workflow-agent.sh) runs THIS loop with canned decisions and
//  a recording fake actuator. The live implementations are
//  DesktopWorkflowPerceiver / ClaudeWorkflowActionDecider /
//  WorkflowAgentActuator.
//

import Foundation

@MainActor
final class WorkflowAgentLoop {

    private let perceiver: any WorkflowAgentPerceiving
    private let decider: any WorkflowActionDeciding
    private let actuator: any WorkflowActionPerforming
    private let guardrails: WorkflowAgentGuardrails

    init(
        perceiver: any WorkflowAgentPerceiving,
        decider: any WorkflowActionDeciding,
        actuator: any WorkflowActionPerforming,
        guardrails: WorkflowAgentGuardrails = .standard
    ) {
        self.perceiver = perceiver
        self.decider = decider
        self.actuator = actuator
        self.guardrails = guardrails
    }

    /// Runs the playbook to completion or until a guard trips. `onStep`
    /// reports (stepDescription, actionsUsed) for the progress surface;
    /// `shouldCancel` is polled every turn.
    func run(
        playbook: WorkflowPlaybook,
        onStep: @MainActor (String, Int) -> Void,
        shouldCancel: @MainActor () -> Bool
    ) async -> WorkflowAgentRunResult {
        let runStartedAt = Date()
        var actionsUsed = 0
        var previousTurns: [(userPlaceholder: String, assistantResponse: String)] = []
        var previousActionResult: String?

        actuator.beginRun()
        defer { actuator.endRun() }

        WorkflowDebugLog.log("agentLoop: starting \"\(playbook.title)\"")

        while true {
            if shouldCancel() {
                WorkflowDebugLog.log("agentLoop: cancelled after \(actionsUsed) action(s)")
                return WorkflowAgentRunResult(outcome: .cancelled, actionsUsed: actionsUsed)
            }
            if actionsUsed >= guardrails.maxActions {
                WorkflowDebugLog.log("agentLoop: action budget exhausted")
                return WorkflowAgentRunResult(
                    outcome: .failed(reason: "Ran out of its \(guardrails.maxActions)-action budget before finishing."),
                    actionsUsed: actionsUsed
                )
            }
            if Date().timeIntervalSince(runStartedAt) > guardrails.maxRunDuration {
                WorkflowDebugLog.log("agentLoop: time budget exhausted")
                return WorkflowAgentRunResult(
                    outcome: .failed(reason: "Ran out of time (\(Int(guardrails.maxRunDuration))s) before finishing."),
                    actionsUsed: actionsUsed
                )
            }

            // Perceive.
            let perception = await perceiver.perceive()

            // Decide.
            let decision: WorkflowAgentDecision
            let rawResponse: String
            do {
                (decision, rawResponse) = try await decider.decide(
                    playbookMarkdown: playbook.markdown,
                    perception: perception,
                    previousTurns: previousTurns,
                    previousActionResult: previousActionResult
                )
            } catch {
                WorkflowDebugLog.log("agentLoop: decide failed — \(error.localizedDescription)")
                return WorkflowAgentRunResult(
                    outcome: .failed(reason: error.localizedDescription),
                    actionsUsed: actionsUsed
                )
            }

            // A cancel that landed while the model was thinking still wins —
            // never actuate after the user said stop.
            if shouldCancel() {
                WorkflowDebugLog.log("agentLoop: cancelled during decide")
                return WorkflowAgentRunResult(outcome: .cancelled, actionsUsed: actionsUsed)
            }

            WorkflowDebugLog.log(
                "agentLoop: turn \(previousTurns.count + 1) — \(decision.stepDescription.isEmpty ? "(no step)" : decision.stepDescription)"
            )

            // Collapse this turn for future context: placeholder instead of
            // the screenshot, plus the model's own response verbatim.
            var turnPlaceholder = "[screenshot at step \(previousTurns.count + 1)]"
            if let previousActionResult {
                turnPlaceholder += " Previous action result: \(previousActionResult)"
            }
            previousTurns.append((userPlaceholder: turnPlaceholder, assistantResponse: rawResponse))

            // Terminal decisions end the run without actuating.
            switch decision.action {
            case .done(let summary):
                WorkflowDebugLog.log("agentLoop: done — \(summary)")
                return WorkflowAgentRunResult(
                    outcome: .done(summary: summary), actionsUsed: actionsUsed
                )
            case .fail(let reason):
                WorkflowDebugLog.log("agentLoop: model gave up — \(reason)")
                return WorkflowAgentRunResult(
                    outcome: .failed(reason: reason), actionsUsed: actionsUsed
                )
            default:
                break
            }

            // Act.
            if !decision.stepDescription.isEmpty {
                onStep(decision.stepDescription, actionsUsed + 1)
            }
            let actionOutcome = await actuator.perform(decision.action, perception: perception)
            actionsUsed += 1
            previousActionResult = actionOutcome.resultDescription
            WorkflowDebugLog.log(
                "agentLoop: action \(actionsUsed) \(actionOutcome.succeeded ? "ok" : "FAILED") — \(actionOutcome.resultDescription.prefix(120))"
            )

            // Verify happens on the next turn's screenshot; give the UI a
            // beat to settle first.
            try? await Task.sleep(
                nanoseconds: UInt64(guardrails.perActionSettleDelay * 1_000_000_000)
            )
        }
    }
}
