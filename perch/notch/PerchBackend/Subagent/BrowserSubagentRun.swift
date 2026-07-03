import AppKit
import SwiftUI

/// One entry in a run's status thread — a short human-readable line marking a
/// meaningful transition the agent passed through ("Working", "Needs you",
/// "Opening window"). Accumulated from the same lifecycle/gate events the manager
/// already routes, so the Agents-tab thread reflects real progress, not invented
/// narration. The most-recent entry is the current step.
struct AgentStep: Identifiable, Equatable {
    let id = UUID()
    let label: String
}

/// One in-flight browser-subagent run, owned by `BrowserSubagentManager`.
///
/// Perch can now have several background agents working at once (the user fires a
/// second task before the first finishes). Each concurrent run is isolated in one
/// of these objects so two runs never clobber each other's state: every sidecar
/// event carries a `subagentId`, and the manager routes it to the matching run by
/// that id. The top-right agent-swarm triangle and the hover preview panel for an
/// agent both observe THIS object, so each agent animates and previews on its own.
///
/// Everything here was previously a single flat field on `BrowserSubagentManager`;
/// moving it per-run is what makes parallel agents possible.
@MainActor
final class BrowserSubagentRun: ObservableObject, Identifiable {

    /// The sidecar's subagent id (e.g. `sa_1a2b3c…`). Stable for the run's whole
    /// life and used as both the SwiftUI identity and the swarm-indicator id, so a
    /// triangle, a preview panel, and the underlying run all share one key.
    let id: String

    /// The natural-language task this run is carrying out, kept so the completion
    /// wrap-up can name what was done ("all done — i finished <task>…").
    let taskDescription: String

    /// The originating turn's trace document. This run's lifecycle events and any
    /// AppleScript it executes are appended here so the turn that started the task
    /// captures everything the agent did, even after the user moves on.
    let runDocument: PerchRunLog.RunDocument?

    /// This run's OWN "hands" for desktop (AX/AppleScript) actuation. Per-run so two
    /// desktop tasks targeting different apps don't fight over a single shared
    /// `targetApplicationBundleIdentifier`, and each run's clipboard save/restore
    /// span stays its own. (Physical actuation across runs is still serialized by the
    /// manager's actuation lock — two agents can't type at once.)
    let desktopTool = DesktopTool()

    @Published private(set) var subagentState: BrowserSubagentState = .spawning
    @Published private(set) var latestFrame: NSImage?
    @Published private(set) var pendingConfirmation: PendingBrowserSubagentConfirmation?
    /// Set while the sidecar holds a headful Chrome window open for the user to sign
    /// into their accounts. The preview panel shows this and a "Done logging in"
    /// button that resolves the gate.
    @Published private(set) var pendingLoginGateMessage: String?
    /// Set while the sidecar is paused at a connection gate, holding the Composio
    /// toolkit slugs this task needs but the user has not connected yet. The
    /// `CompanionManager` observes this, drives the connect popup(s), then resolves
    /// the gate. `nil` when no connect is pending.
    @Published private(set) var pendingConnectionRequest: [String]?
    @Published private(set) var finalUrl: URL?
    /// True when the finished run opened a headed takeover window (a browser ran).
    /// False for a no-browser run, which finishes by speaking `resultSummary`.
    @Published private(set) var handoffWindowReady = false
    /// The spoken wrap-up the sidecar returned on `done` (set for no-browser runs so
    /// Perch can announce the result without a handoff window).
    @Published private(set) var resultSummary: String?
    /// A short noun for the artifact this run produced ("Google Doc", "Figma file"),
    /// paired with `finalUrl` so the Agents-tab card can label the deliverable link.
    @Published private(set) var deliverableLabel: String?

    /// True while the user is hovering THIS run's top-right swarm triangle. The
    /// cursor overlay (which polls the mouse, so it works regardless of window key
    /// state) drives this; this run's preview panel observes it to expand into the
    /// live browser view.
    @Published var isAgentIndicatorHovered = false

    /// True once this run has actually performed a desktop step (AX/AppleScript on a
    /// local app). Until then it's a pure web run, and the frontmost-app target that
    /// was pinned at spawn (for paste safety) must NOT drive the notch icon — that's
    /// what made a browser task show the incidental frontmost app (e.g. Ghostty). The
    /// manager flips this on the first desktop perceive/action so the icon switches to
    /// the real target app only when the run truly touches the desktop.
    @Published private(set) var hasActedOnDesktop = false

    /// The bundle id of a native app the agent brought to the FOREGROUND during this
    /// run — e.g. it ran "open -a Microsoft Excel" (a system step) and Excel came
    /// forward. This is the most faithful "what is it working in" signal for tasks
    /// that launch or switch to an app, since those run as model-composed AppleScript
    /// in the sidecar and never reach the in-app desktop hooks. The manager sets it by
    /// observing `NSWorkspace` activations while the run works. `nil` for a web run
    /// (nothing comes forward — the sub-browser is headless).
    @Published private(set) var foregroundedAppBundleIdentifier: String?

    /// The ordered status thread for this run — appended as the run passes through
    /// lifecycle states and gates (see `AgentStep`). The Agents-tab thread renders
    /// the tail of this; the last entry is the current step.
    @Published private(set) var steps: [AgentStep] = []

    init(
        id: String,
        taskDescription: String,
        runDocument: PerchRunLog.RunDocument?
    ) {
        self.id = id
        self.taskDescription = taskDescription
        self.runDocument = runDocument
    }

    /// True while this run is actively working — drives its cursor/triangle spinner.
    var isWorking: Bool {
        switch subagentState {
        case .spawning, .loginGate, .working, .completing, .handoff:
            return true
        case .idle, .done, .error, .needsInput:
            return false
        }
    }

    /// True once this run has reached a terminal state — the manager prunes it and
    /// `CompanionManager` runs the merge-away animation + completion wrap-up.
    var isTerminal: Bool {
        switch subagentState {
        case .done, .error, .needsInput:
            return true
        case .idle, .spawning, .loginGate, .working, .completing, .handoff:
            return false
        }
    }

    /// True while this run is paused waiting for the user to approve a gated action
    /// (the "needs you" state). Drives the amber treatment in the notch's agent UI.
    var needsUserConfirmation: Bool {
        pendingConfirmation != nil
    }

    /// The bundle identifier of the app this run is acting in, for the notch's
    /// app-icon. Resolves to whichever signal best reflects "what it's working in",
    /// and returns `nil` for a pure web run so the caller shows the Chrome icon:
    ///   1. An app the agent brought to the foreground (opened Excel, Spotify, …).
    ///   2. Otherwise, a desktop AX task acting on the already-frontmost app (its
    ///      pinned target), once it has actually touched the desktop.
    ///   3. Otherwise `nil` — a web run that launched no app → Chrome.
    var displayedAppBundleIdentifier: String? {
        if let foregroundedAppBundleIdentifier {
            return foregroundedAppBundleIdentifier
        }
        if hasActedOnDesktop,
           let targetBundleId = desktopTool.targetApplicationBundleIdentifier,
           targetBundleId != Bundle.main.bundleIdentifier {
            return targetBundleId
        }
        return nil
    }

    /// A short, human-readable description of what this run is doing right now,
    /// shown as the agent's "current step" line. Mirrors the music player's artist
    /// line: the task is the title, this is the subtitle.
    var currentStepLabel: String {
        if needsUserConfirmation { return "Needs you" }
        return subagentState.displayName
    }

    // MARK: - State mutation (called by BrowserSubagentManager on routed events)

    /// Appends a status-thread entry, collapsing consecutive duplicates so the thread
    /// reads as distinct steps rather than repeating the same label.
    private func appendStep(_ label: String) {
        guard steps.last?.label != label else { return }
        steps.append(AgentStep(label: label))
    }

    func update(state: BrowserSubagentState) {
        subagentState = state
        // The gate is over once the sidecar leaves login_gate (cancelled, errored,
        // or resolved from a driver).
        if state != .loginGate {
            pendingLoginGateMessage = nil
        }
        // Record the transition in the status thread (idle is not a user-facing step).
        if state != .idle {
            appendStep(state.displayName)
        }
    }

    func update(frame: NSImage) {
        latestFrame = frame
    }

    /// Marks that this run has performed a desktop step, so the notch icon switches
    /// from the browser glyph to the real target app's icon. Called by the manager on
    /// the first desktop perceive/action.
    func markDesktopActivity() {
        hasActedOnDesktop = true
    }

    /// Records that the agent brought a native app to the foreground during this run
    /// (e.g. opened Excel). Drives the notch icon to that app. Called by the manager's
    /// `NSWorkspace` activation observer.
    func noteForegroundedApp(bundleIdentifier: String) {
        foregroundedAppBundleIdentifier = bundleIdentifier
    }

    func setPendingConfirmation(_ confirmation: PendingBrowserSubagentConfirmation?) {
        pendingConfirmation = confirmation
        if confirmation != nil {
            appendStep("Needs you")
        }
    }

    func setPendingLoginGateMessage(_ message: String?) {
        pendingLoginGateMessage = message
    }

    func setPendingConnectionRequest(_ toolkitSlugs: [String]?) {
        pendingConnectionRequest = toolkitSlugs
        if let firstToolkitSlug = toolkitSlugs?.first {
            appendStep("Connecting \(firstToolkitSlug.capitalized)")
        }
    }

    func applyDone(
        handoffWindowReady: Bool,
        finalUrl: URL?,
        resultSummary: String?,
        deliverableLabel: String?
    ) {
        self.handoffWindowReady = handoffWindowReady
        if let finalUrl {
            self.finalUrl = finalUrl
        }
        self.resultSummary = resultSummary
        self.deliverableLabel = deliverableLabel
        subagentState = .done
        appendStep(deliverableLabel.map { "Created \($0)" } ?? "Done")
    }

    func markErrored() {
        subagentState = .error
        appendStep("Error")
    }

    /// The run ended by asking the user a free-form question (the sidecar's ask_user).
    /// Stores the question in `resultSummary` (the field the completion wrap-up reads)
    /// and moves to the terminal `.needsInput` state; `CompanionManager` speaks the
    /// question instead of an "all done" wrap-up.
    func applyNeedsInput(question: String) {
        self.resultSummary = question
        subagentState = .needsInput
        appendStep("Needs you")
    }
}

#if DEBUG
extension BrowserSubagentRun {
    /// Builds a fully-formed STALE mock run for previewing the Agents tab inside the
    /// real notch without a live sidecar. Gated to DEBUG + the `PERCH_PREVIEW_AGENTS`
    /// launch flag (see `BrowserSubagentManager`), so it never reaches a shipped build.
    /// Same-file access lets it seed the `private(set)` state directly.
    static func previewMock(
        id: String,
        task: String,
        steps stepLabels: [String],
        state: BrowserSubagentState,
        foregroundApp: String? = nil
    ) -> BrowserSubagentRun {
        let run = BrowserSubagentRun(id: id, taskDescription: task, runDocument: nil)
        run.steps = stepLabels.map { AgentStep(label: $0) }
        run.subagentState = state
        run.foregroundedAppBundleIdentifier = foregroundApp
        return run
    }
}
#endif
