//
//  WorkflowRunCoordinator.swift
//  leanring-buddy
//
//  Orchestrates "Show Perch once" end to end: record one demonstration
//  (screen video + moment timeline + sources) → synthesize the markdown
//  playbook with Claude → hand the playbook to the in-app agent loop to
//  execute. Owned by CompanionManager; NotchPanelManager observes `state` to
//  drive the record / progress surface.
//
//  It PAUSES the passive capture pipeline for the whole run. Otherwise the
//  live event tap would (a) re-fire a proactive offer from the user's own
//  demonstration keystrokes and (b) see the agent's SYNTHESIZED events and
//  trip yet another offer. Passive detection resumes when the run ends.
//
//  Runs can start three ways — a fresh demonstration, a saved repeat
//  schedule, or a workflow shared from another Perch — tracked as
//  `WorkflowRunOrigin`. Only demonstration runs are "first time", so only
//  they retain the finished playbook and offer the Repeat / Send follow-ups.
//

import AppKit
import Combine
import Foundation

/// How the current run was started. Decides whether the finished surface
/// offers the Repeat / Send follow-ups (demonstration runs only).
enum WorkflowRunOrigin: Equatable {
    /// The user accepted a proactive offer and demonstrated the task — the
    /// playbook is brand new, so this is by construction a first-time run.
    case demonstration
    /// A saved repeat-schedule re-ran a stored playbook.
    case schedule
    /// A workflow shared from another Perch install was run.
    case importedShare
}

/// The "Send this workflow" upload's lifecycle, rendered by the finished
/// surface (idle buttons → "Making your link…" → the copied link / an error).
enum WorkflowShareStatus: Equatable {
    case none
    case uploading
    case copied(linkString: String)
    case failed(message: String)
}

/// The phases the run moves through. The notch surface renders each.
enum WorkflowRunState: Equatable {
    case idle
    /// Recording the single demonstration; waiting for the user to press Stop.
    case recording
    /// Turning the demonstration into a playbook (keyframes + Claude).
    case analyzing
    /// The agent loop is executing the playbook.
    case acting(stepDescription: String, actionsUsed: Int)
    /// Done — the agent's own summary of what it accomplished.
    case finished(summary: String)
    case failed(message: String)
}

@MainActor
final class WorkflowRunCoordinator: ObservableObject {

    @Published private(set) var state: WorkflowRunState = .idle

    /// The playbook a just-finished DEMONSTRATION run produced — the handle
    /// the finished surface's "Repeat this" / "Send this workflow" buttons
    /// act on. Kept OUTSIDE the state enum so the existing state-equality
    /// guards and animations stay untouched. Always nil for schedule and
    /// imported-share runs ("first time only").
    @Published private(set) var finishedDemonstrationPlaybook: WorkflowPlaybook?

    /// Lifecycle of the "Send this workflow" upload, shown on the finished
    /// surface.
    @Published private(set) var shareStatus: WorkflowShareStatus = .none

    private(set) var currentRunOrigin: WorkflowRunOrigin = .demonstration

    private let demonstrationRecorder = WorkflowDemonstrationRecorder()
    private let playbookSynthesizer = WorkflowPlaybookSynthesizer()
    private let playbookStore = WorkflowPlaybookStore.standard()
    private let workflowShareClient: WorkflowShareClient
    /// Where completed workflow runs land as Agents-tab cards (with their
    /// playbook slug, enabling the card's Schedule / Send actions). Nil in
    /// harness/test construction.
    private weak var agentRunHistoryStore: AgentRunHistoryStore?

    /// How many actions the agent may take — surfaced in the progress detail.
    let agentActionBudget = WorkflowAgentGuardrails.standard.maxActions

    /// The passive capture pipeline we pause/resume around a run.
    private let workflowCaptureManager: WorkflowCaptureManager

    private var isCancelled = false
    private var runTask: Task<Void, Never>?
    private var shareTask: Task<Void, Never>?

    init(
        workflowCaptureManager: WorkflowCaptureManager,
        workflowShareClient: WorkflowShareClient = WorkflowShareClient(),
        agentRunHistoryStore: AgentRunHistoryStore? = nil
    ) {
        self.workflowCaptureManager = workflowCaptureManager
        self.workflowShareClient = workflowShareClient
        self.agentRunHistoryStore = agentRunHistoryStore
    }

    // MARK: - User-driven transitions

    /// The user accepted the offer → start recording their one demonstration.
    func beginRecording() {
        runTask?.cancel()
        isCancelled = false
        currentRunOrigin = .demonstration
        clearFollowUpArtifacts()
        // Pause passive detection so the demonstration (and later the agent's
        // synthesized events) don't trip another offer.
        workflowCaptureManager.stopCapturing()
        state = .recording
        WorkflowDebugLog.log("coordinator: recording")
        runTask = Task { [weak self] in
            await self?.demonstrationRecorder.start()
        }
    }

    /// The user pressed Stop → analyze the demonstration and run the playbook.
    func stopRecording() {
        guard case .recording = state else { return }
        state = .analyzing
        runTask = Task { [weak self] in
            await self?.analyzeAndExecute()
        }
    }

    /// Re-runs a previously persisted playbook — the entry point for saved
    /// repeat-schedules and workflows shared from another Perch. Skips
    /// recording/analyzing and goes straight to the agent loop.
    func runStoredPlaybook(slug: String, origin: WorkflowRunOrigin) {
        guard state == .idle else {
            WorkflowDebugLog.log("coordinator: runStoredPlaybook(\(slug)) skipped — run already active")
            return
        }
        runTask?.cancel()
        isCancelled = false
        currentRunOrigin = origin
        clearFollowUpArtifacts()

        let playbook: WorkflowPlaybook
        do {
            playbook = try playbookStore.load(slug: slug)
        } catch {
            WorkflowDebugLog.log("coordinator: runStoredPlaybook(\(slug)) failed to load — \(error)")
            state = .failed(message: "I couldn't find that workflow anymore.")
            scheduleReturnToIdle()
            return
        }

        // Same passive-capture pause as a demonstration run: the agent's
        // synthesized events must not trip a new proactive offer.
        workflowCaptureManager.stopCapturing()
        state = .acting(stepDescription: "Getting started…", actionsUsed: 0)
        WorkflowDebugLog.log("coordinator: running stored playbook '\(slug)' (origin=\(origin))")
        runTask = Task { [weak self] in
            await self?.executePlaybook(playbook)
        }
    }

    /// Best-effort: bring the workflow's recorded source ("ORIGIN") app
    /// frontmost so the agent loop's first perceive captures the right window.
    /// The origin bundle identifier lives in the playbook's "Sources" section,
    /// e.g. ``- ORIGIN: Microsoft Excel (`com.microsoft.Excel`) — window …``.
    /// If it can't be parsed or the app isn't running, this is a no-op and the
    /// agent's own activate-the-window logic still recovers.
    private func activateOriginApp(fromPlaybookMarkdown markdown: String) async {
        guard let originBundleIdentifier = Self.originBundleIdentifier(
            fromMarkdown: markdown
        ) else { return }
        guard let runningOriginApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: originBundleIdentifier
        ).first else {
            WorkflowDebugLog.log(
                "coordinator: origin app \(originBundleIdentifier) not running — skipping pre-activation"
            )
            return
        }
        runningOriginApp.activate(options: [.activateAllWindows])
        WorkflowDebugLog.log(
            "coordinator: pre-activated origin app \(originBundleIdentifier)"
        )
        // Let the window server bring it forward before the first screenshot.
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    /// Pulls the ORIGIN app's bundle identifier out of a playbook's markdown
    /// "Sources" line. Returns nil when the line/format is absent.
    static func originBundleIdentifier(fromMarkdown markdown: String) -> String? {
        let pattern = "ORIGIN:[^(]*\\(`([^`]+)`\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let fullRange = NSRange(markdown.startIndex..., in: markdown)
        guard let match = regex.firstMatch(in: markdown, range: fullRange),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: markdown) else {
            return nil
        }
        return String(markdown[captureRange])
    }

    /// Cancel from a Stop button during any phase (or bail recording).
    func cancel() {
        isCancelled = true
        runTask?.cancel()
        if case .recording = state {
            Task { [weak self] in
                _ = await self?.demonstrationRecorder.stop()
            }
        }
        resumePassiveCapture()
        clearFollowUpArtifacts()
        state = .idle
        WorkflowDebugLog.log("coordinator: cancelled")
    }

    /// Explicit dismissal of the finished surface (the "Done" pill). A
    /// finished demonstration run never auto-dismisses — the follow-up
    /// buttons own the surface until the user acts.
    func returnToIdle() {
        clearFollowUpArtifacts()
        state = .idle
    }

    // MARK: - Sharing ("Send this workflow")

    /// Uploads the finished demonstration's playbook to the Worker, copies
    /// the returned share link to the clipboard, and lingers briefly before
    /// clearing the surface. Safe relative to the agent run's clipboard
    /// save/restore: the actuator restores the user's clipboard before the
    /// loop returns, i.e. before `.finished` is ever published.
    func shareFinishedPlaybook() {
        guard case .finished = state,
              let playbook = finishedDemonstrationPlaybook,
              shareStatus != .uploading else { return }

        shareStatus = .uploading
        WorkflowDebugLog.log("coordinator: sharing playbook '\(playbook.slug)'")
        shareTask = Task { [weak self] in
            guard let self else { return }
            do {
                let shareLink = try await self.workflowShareClient.uploadPlaybook(
                    markdown: playbook.markdown, title: playbook.title
                )
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shareLink.urlString, forType: .string)
                // Show the sender the landing page right away — the link is
                // also on the clipboard for pasting into a message.
                if let shareURL = URL(string: shareLink.urlString) {
                    NSWorkspace.shared.open(shareURL)
                }
                self.shareStatus = .copied(linkString: shareLink.urlString)
                WorkflowDebugLog.log("coordinator: share link copied — \(shareLink.urlString)")
                // Let the "link copied" confirmation linger, then clear.
                self.scheduleReturnToIdle(after: 8)
            } catch {
                self.shareStatus = .failed(message: error.localizedDescription)
                WorkflowDebugLog.log("coordinator: share FAILED — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - The run

    private func analyzeAndExecute() async {
        let demonstration = await demonstrationRecorder.stop()
        if isCancelled { resumePassiveCapture(); state = .idle; return }

        guard !demonstration.moments.isEmpty else {
            finish(withFailure: "I didn't catch any actions in that demonstration. Try again.")
            return
        }
        if isCancelled { resumePassiveCapture(); state = .idle; return }

        let playbook: WorkflowPlaybook
        do {
            playbook = try await playbookSynthesizer.synthesizePlaybook(from: demonstration)
        } catch {
            finish(withFailure: error.localizedDescription)
            return
        }
        if isCancelled { resumePassiveCapture(); state = .idle; return }

        state = .acting(stepDescription: "Getting started…", actionsUsed: 0)
        await executePlaybook(playbook)
    }

    /// Runs the agent loop on a playbook — shared by demonstration runs and
    /// stored-playbook (schedule / imported-share) runs.
    private func executePlaybook(_ playbook: WorkflowPlaybook) async {
        // Bring the playbook's recorded source app frontmost BEFORE the loop's
        // first perceive. Otherwise turn 1 screenshots whatever is in front
        // (often Perch's own UI right after the user triggered the run), the
        // model sees neither the source nor destination window, and gives up
        // with "the needed window is not visible or focused" — the exact way a
        // copy/paste workflow silently died on turn 1.
        await activateOriginApp(fromPlaybookMarkdown: playbook.markdown)

        // A single agent executes the whole playbook sequentially
        // (perceive → decide → act → verify). The loop owns the clipboard
        // save/restore around the run.
        let agentLoop = WorkflowAgentLoop(
            perceiver: DesktopWorkflowPerceiver(),
            decider: ClaudeWorkflowActionDecider(),
            actuator: WorkflowAgentActuator()
        )
        let runResult = await agentLoop.run(
            playbook: playbook,
            onStep: { [weak self] stepDescription, actionsUsed in
                self?.state = .acting(stepDescription: stepDescription, actionsUsed: actionsUsed)
            },
            shouldCancel: { [weak self] in self?.isCancelled ?? true }
        )

        switch runResult.outcome {
        case .cancelled:
            resumePassiveCapture()
            state = .idle
        case .failed(let reason):
            finish(withFailure: reason)
        case .done(let summary):
            finish(withSuccess: summary, playbook: playbook)
        }
    }

    // MARK: - Terminal states

    private func finish(withSuccess summary: String, playbook: WorkflowPlaybook) {
        resumePassiveCapture()
        // Save the workflow as an Agents-tab card. Scheduled re-runs are
        // skipped — the card represents the workflow, and an hourly schedule
        // must not pile up a card per run.
        if currentRunOrigin != .schedule {
            agentRunHistoryStore?.recordRun(
                taskDescription: playbook.title,
                resultSummary: summary,
                finalUrl: nil,
                didSucceed: true,
                workflowPlaybookSlug: playbook.slug
            )
        }
        if currentRunOrigin == .demonstration {
            // First-time run: retain the playbook so the finished surface can
            // offer Repeat / Send, and do NOT auto-dismiss — the follow-up
            // buttons own dismissal.
            finishedDemonstrationPlaybook = playbook
            state = .finished(summary: summary)
        } else {
            state = .finished(summary: summary)
            scheduleReturnToIdle()
        }
        WorkflowDebugLog.log("coordinator: finished — \(summary)")
    }

    private func finish(withFailure message: String) {
        resumePassiveCapture()
        state = .failed(message: message)
        WorkflowDebugLog.log("coordinator: failed — \(message)")
        scheduleReturnToIdle()
    }

    /// Let the result/error surface linger briefly, then clear it.
    private func scheduleReturnToIdle(after lingerSeconds: TimeInterval = 5) {
        let stateAtScheduleTime = state
        DispatchQueue.main.asyncAfter(deadline: .now() + lingerSeconds) { [weak self] in
            guard let self, self.state == stateAtScheduleTime else { return }
            self.clearFollowUpArtifacts()
            self.state = .idle
        }
    }

    private func clearFollowUpArtifacts() {
        finishedDemonstrationPlaybook = nil
        shareStatus = .none
    }

    private func resumePassiveCapture() {
        workflowCaptureManager.startCapturing()
    }
}
