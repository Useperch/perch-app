import Foundation

/// Wire protocol shared with the Python browser subagent sidecar.
///
/// The transport is JSON-RPC 2.0 framed as newline-delimited JSON (NDJSON) over
/// a filesystem unix domain socket. Requests carry an `id` and expect a matching
/// response; events are notifications (no `id`). Because the payloads are
/// heterogeneous (and frames carry large base64 strings), messages are built and
/// parsed with `JSONSerialization` dictionaries rather than fought through
/// `Codable`. This file defines the typed event surface the rest of the app sees.

enum BrowserSubagentRequestMethod {
    static let spawn = "subagent.spawn"
    static let status = "subagent.status"
    static let cancel = "subagent.cancel"
    static let confirm = "subagent.confirm"
    static let loginComplete = "subagent.loginComplete"
    // Answers a connection gate: the app has finished driving the connect popup(s)
    // for the toolkits the sidecar asked for (some connected, some maybe declined).
    static let connectionComplete = "subagent.connectionComplete"
    static let setPreviewQuality = "subagent.setPreviewQuality"
    // The app's answers to a desktop step's two callbacks: the AX perceive
    // snapshot (up) and the actuation read-back (up). Each echoes the requestId
    // the matching event asked under, so the sidecar resolves the right future.
    static let desktopPerceiveResult = "subagent.desktopPerceiveResult"
    static let desktopActionResult = "subagent.desktopActionResult"
    // The app's answers to the dashboard family's three callbacks (create / edit /
    // snapshot). Each echoes the requestId the matching event asked under, so the
    // sidecar resolves the right future. See DashboardAgentApplier.
    static let dashboardCreateResult = "subagent.dashboardCreateResult"
    static let dashboardEditResult = "subagent.dashboardEditResult"
    static let dashboardSnapshotResult = "subagent.dashboardSnapshotResult"
    // Read-only data fetch for the Daily Dashboard's live widgets. Outside the
    // subagent lifecycle — never spawns a browser. See DashboardDataService.
    static let dashboardFetch = "dashboard.fetch"
    // Read-only notch alert importance filter (outside subagent lifecycle).
    static let notchAlertEvaluate = "notch.alert.evaluate"
    // Chrome record-and-replay. `recordStart` opens the headful recording window;
    // `recordStop` ends it, synthesizes the skill, and saves it; `recordCancel`
    // discards it. Independent of a subagent run — recording is a capture session.
    static let recordStart = "record.start"
    static let recordStop = "record.stop"
    static let recordCancel = "record.cancel"
}

enum BrowserSubagentEventMethod {
    static let state = "subagent.state"
    static let frame = "subagent.frame"
    static let confirmRequest = "subagent.confirmRequest"
    static let loginGate = "subagent.loginGate"
    // Asks the app to connect one or more Composio toolkits the task needs but the
    // user has not connected yet (params carry "toolkits": [slug]).
    static let connectionRequired = "subagent.connectionRequired"
    static let done = "subagent.done"
    static let error = "subagent.error"
    // The model needs a free-form answer from the user before it can finish (the
    // ask_user tool). Unlike `done` this makes no completion claim (params carry
    // "question"). The app speaks the question; the user replies on their next turn.
    static let needsInput = "subagent.needsInput"
    // A desktop step's two callbacks DOWN from the sidecar: PERCEIVE the focused
    // native app (answer with desktopPerceiveResult) and ACT one already-decided,
    // already-gated structured action (answer with desktopActionResult).
    static let desktopPerceive = "subagent.desktopPerceive"
    static let desktopAction = "subagent.desktopAction"
    // The dashboard family's callbacks DOWN from the sidecar: CREATE a widget on the
    // user's own Daily Dashboard, EDIT an existing one, or SNAPSHOT the board. The app
    // answers each with the matching dashboard*Result request, echoing requestId.
    static let dashboardCreate = "dashboard.create"
    static let dashboardEdit = "dashboard.edit"
    static let dashboardSnapshot = "dashboard.snapshot"
    // Chrome record-and-replay events (sidecar → app). `recordState` reports the
    // capture lifecycle; `recordFrame` streams a live preview JPEG of the recording
    // window; `recordSaved` carries the saved skill's slug/path/title; `recordError`
    // reports a synthesis failure.
    static let recordState = "record.state"
    static let recordFrame = "record.frame"
    static let recordSaved = "record.saved"
    static let recordError = "record.error"
}

/// The lifecycle states the sidecar reports, mirroring the Python state machine.
enum BrowserSubagentState: String {
    case idle
    case spawning
    case loginGate = "login_gate"
    case working
    case completing
    case handoff
    case done
    case error
    // The run ended by asking the user a free-form question (the sidecar's ask_user).
    // A local-only state the app assigns when it receives a `subagent.needsInput`
    // event; the sidecar reports it as that event, not as a `subagent.state`.
    case needsInput = "needs_input"

    /// Human-readable label shown in the preview panel's status badge.
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .spawning: return "Starting"
        case .loginGate: return "Waiting for login"
        case .working: return "Working"
        case .completing: return "Finishing"
        case .handoff: return "Opening window"
        case .done: return "Done"
        case .error: return "Error"
        case .needsInput: return "Needs you"
        }
    }
}

/// One entry in the tool-call trace a finished run reports: the tool the agent
/// invoked and whether that call succeeded. Carried on `done`/`error` events so
/// the app can log exactly what the agent did (older sidecars omit it → `nil`).
struct SubagentToolCall {
    let tool: String
    let ok: Bool

    /// Leniently decodes the sidecar's `toolCalls` payload
    /// (`[{"tool": "browser", "ok": true}, …]` or null). Missing/malformed → `nil`;
    /// individual malformed entries are dropped rather than failing the event.
    static func list(from params: [String: Any]) -> [SubagentToolCall]? {
        guard let rawCalls = params["toolCalls"] as? [[String: Any]] else { return nil }
        return rawCalls.compactMap { rawCall in
            guard let tool = rawCall["tool"] as? String else { return nil }
            return SubagentToolCall(tool: tool, ok: rawCall["ok"] as? Bool ?? false)
        }
    }
}

/// A typed event decoded from a sidecar notification.
enum BrowserSubagentEvent {
    case state(subagentId: String, state: BrowserSubagentState)
    case frame(subagentId: String, jpegBase64: String, timestamp: Double)
    case confirmRequest(subagentId: String, actionId: String, description: String, tier: String?)
    case loginGate(subagentId: String, message: String)
    // The task needs Composio toolkits the user hasn't connected. The app shows the
    // connect popup(s), then answers with connectionComplete.
    case connectionRequired(subagentId: String, toolkitSlugs: [String])
    case done(subagentId: String, handoffWindowReady: Bool, finalUrl: String?, resultSummary: String?, deliverableLabel: String?, toolCalls: [SubagentToolCall]?)
    case error(subagentId: String, message: String, toolCalls: [SubagentToolCall]?)
    // The task needs a free-form answer from the user (ask_user). The app speaks the
    // question and ends the run without claiming completion.
    case needsInput(subagentId: String, question: String)
    // Desktop step callbacks. The sidecar asks the app to perceive the focused
    // native app, then to actuate one decided action; the app answers each with
    // the matching desktop*Result request, echoing requestId.
    case desktopPerceive(subagentId: String, requestId: String)
    case desktopAction(subagentId: String, requestId: String, action: [String: Any])
    // Dashboard step callbacks. The sidecar asks the app to create/edit a widget on
    // the user's own Daily Dashboard, or to snapshot the board; the app answers each
    // with the matching dashboard*Result request, echoing requestId.
    case dashboardCreate(subagentId: String, requestId: String, widget: [String: Any])
    case dashboardEdit(subagentId: String, requestId: String, widgetId: String, patch: [String: Any])
    case dashboardSnapshot(subagentId: String, requestId: String)
    // Chrome record-and-replay events. These carry a `recordingId`, not a
    // `subagentId` — recording is independent of any subagent run.
    case recordState(recordingId: String, state: ChromeRecordingState)
    case recordFrame(recordingId: String, jpegBase64: String)
    case recordSaved(recordingId: String, slug: String, path: String, title: String)
    case recordError(recordingId: String, message: String)

    /// Decodes a sidecar notification dictionary into a typed event, or `nil`
    /// if the method is not a recognized event.
    static func from(method: String, params: [String: Any]) -> BrowserSubagentEvent? {
        let subagentId = params["subagentId"] as? String ?? ""
        switch method {
        case BrowserSubagentEventMethod.state:
            guard let rawState = params["state"] as? String,
                  let parsedState = BrowserSubagentState(rawValue: rawState) else { return nil }
            return .state(subagentId: subagentId, state: parsedState)

        case BrowserSubagentEventMethod.frame:
            guard let jpegBase64 = params["jpegBase64"] as? String else { return nil }
            let timestamp = params["ts"] as? Double ?? 0
            return .frame(subagentId: subagentId, jpegBase64: jpegBase64, timestamp: timestamp)

        case BrowserSubagentEventMethod.confirmRequest:
            guard let actionId = params["actionId"] as? String,
                  let description = params["description"] as? String else { return nil }
            // The risk tier ("external" | "destructive") is optional so older
            // sidecars that omit it still decode.
            let tier = params["tier"] as? String
            return .confirmRequest(subagentId: subagentId, actionId: actionId, description: description, tier: tier)

        case BrowserSubagentEventMethod.loginGate:
            let message = params["message"] as? String ?? "A Chrome window is open — sign in, then continue."
            return .loginGate(subagentId: subagentId, message: message)

        case BrowserSubagentEventMethod.connectionRequired:
            // Tolerate a missing/empty list — decode to an empty array so the
            // manager can no-op rather than fail to parse.
            let toolkitSlugs = (params["toolkits"] as? [String]) ?? []
            return .connectionRequired(subagentId: subagentId, toolkitSlugs: toolkitSlugs)

        case BrowserSubagentEventMethod.done:
            let handoffWindowReady = params["handoffWindowReady"] as? Bool ?? false
            let finalUrl = params["finalUrl"] as? String
            // A no-browser run (pure app-api/system plan) carries a spoken summary
            // here and reports handoffWindowReady == false: there is no window to open.
            let resultSummary = params["resultSummary"] as? String
            // A short noun for the artifact the run created ("Google Doc"), paired
            // with finalUrl so the Agents-tab card can label the link. Optional so
            // older sidecars that omit it still decode.
            let deliverableLabel = params["deliverableLabel"] as? String
            return .done(
                subagentId: subagentId,
                handoffWindowReady: handoffWindowReady,
                finalUrl: finalUrl,
                resultSummary: resultSummary,
                deliverableLabel: deliverableLabel,
                toolCalls: SubagentToolCall.list(from: params)
            )

        case BrowserSubagentEventMethod.error:
            let message = params["message"] as? String ?? "unknown error"
            return .error(
                subagentId: subagentId,
                message: message,
                toolCalls: SubagentToolCall.list(from: params)
            )

        case BrowserSubagentEventMethod.needsInput:
            let question = params["question"] as? String ?? "What would you like me to do?"
            return .needsInput(subagentId: subagentId, question: question)

        case BrowserSubagentEventMethod.desktopPerceive:
            guard let requestId = params["requestId"] as? String else { return nil }
            return .desktopPerceive(subagentId: subagentId, requestId: requestId)

        case BrowserSubagentEventMethod.desktopAction:
            guard let requestId = params["requestId"] as? String,
                  let action = params["action"] as? [String: Any] else { return nil }
            return .desktopAction(subagentId: subagentId, requestId: requestId, action: action)

        case BrowserSubagentEventMethod.dashboardCreate:
            guard let requestId = params["requestId"] as? String,
                  let widget = params["widget"] as? [String: Any] else { return nil }
            return .dashboardCreate(subagentId: subagentId, requestId: requestId, widget: widget)

        case BrowserSubagentEventMethod.dashboardEdit:
            guard let requestId = params["requestId"] as? String,
                  let widgetId = params["widgetId"] as? String,
                  let patch = params["patch"] as? [String: Any] else { return nil }
            return .dashboardEdit(
                subagentId: subagentId, requestId: requestId, widgetId: widgetId, patch: patch
            )

        case BrowserSubagentEventMethod.dashboardSnapshot:
            guard let requestId = params["requestId"] as? String else { return nil }
            return .dashboardSnapshot(subagentId: subagentId, requestId: requestId)

        case BrowserSubagentEventMethod.recordState:
            guard let recordingId = params["recordingId"] as? String,
                  let rawState = params["state"] as? String,
                  let parsedState = ChromeRecordingState(rawValue: rawState) else { return nil }
            return .recordState(recordingId: recordingId, state: parsedState)

        case BrowserSubagentEventMethod.recordFrame:
            guard let recordingId = params["recordingId"] as? String,
                  let jpegBase64 = params["jpeg"] as? String else { return nil }
            return .recordFrame(recordingId: recordingId, jpegBase64: jpegBase64)

        case BrowserSubagentEventMethod.recordSaved:
            guard let recordingId = params["recordingId"] as? String else { return nil }
            return .recordSaved(
                recordingId: recordingId,
                slug: params["slug"] as? String ?? "",
                path: params["path"] as? String ?? "",
                title: params["title"] as? String ?? ""
            )

        case BrowserSubagentEventMethod.recordError:
            guard let recordingId = params["recordingId"] as? String else { return nil }
            return .recordError(
                recordingId: recordingId,
                message: params["error"] as? String ?? "unknown error"
            )

        default:
            return nil
        }
    }
}

/// The lifecycle of a Chrome recording, mirroring the sidecar's `record.state`
/// values plus the app-side terminal states (`saved`/`failed`) the coordinator
/// sets when the stop RPC resolves.
enum ChromeRecordingState: String {
    case idle
    // The app has asked the sidecar to start — the headful Chrome window is opening.
    // Set synchronously when Record is pressed so the UI reacts instantly.
    case starting
    case recording
    case synthesizing
    case cancelled
    case saved
    case failed

    /// Human-readable label for the recording control.
    var displayName: String {
        switch self {
        case .idle: return "Not recording"
        case .starting: return "Opening Chrome…"
        case .recording: return "Recording…"
        case .synthesizing: return "Building skill…"
        case .cancelled: return "Cancelled"
        case .saved: return "Skill saved"
        case .failed: return "Failed"
        }
    }
}

/// A pending irreversible-action confirmation awaiting the user's decision.
struct PendingBrowserSubagentConfirmation: Identifiable, Equatable {
    let id: String          // the sidecar's actionId
    let subagentId: String
    let description: String
    // The risk tier this action was gated under ("external" | "destructive"), so
    // the confirm banner can word the prompt by severity. nil when unclassified.
    let tier: String?
}
