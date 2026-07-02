//
//  ClaudeWorkflowActionDecider.swift
//  Perch
//
//  The live decision half of the workflow agent loop: one Claude call per
//  turn through the same Worker /chat proxy the rest of the app uses. The
//  playbook rides in the system prompt (stable across turns); the screenshot,
//  AX context, and previous-action result form the user turn; prior turns are
//  replayed as text only (placeholders instead of old screenshots).
//
//  Parse failures get exactly one retry with the parse error fed back so the
//  model can fix its own formatting.
//

import Foundation

@MainActor
final class ClaudeWorkflowActionDecider: WorkflowActionDeciding {

    // Kept modest to keep each call cheap (the single-line AppleScript actions
    // are short, and the parser tolerates the done/fail shorthand, so big
    // headroom isn't needed).
    private static let decisionMaxTokens = 1024

    private lazy var claudeAPI: ClaudeAPI = {
        ClaudeAPI(
            proxyURL: "\(WorkflowPlaybookSynthesizer.workerBaseURL)/chat",
            model: "claude-sonnet-4-6"
        )
    }()

    func decide(
        playbookMarkdown: String,
        perception: WorkflowAgentPerception,
        previousTurns: [(userPlaceholder: String, assistantResponse: String)],
        previousActionResult: String?
    ) async throws -> (decision: WorkflowAgentDecision, rawResponse: String) {
        // If the frontmost app has a per-app skill, inject its expertise between the
        // generic instructions and the playbook so the model knows that app's exact
        // shortcuts, formatting practices, and reusable AppleScript recipes.
        let appSkillSection: String
        if let appSkillMarkdown = AppSkillLibrary.skillMarkdown(
            forBundleIdentifier: perception.frontmostApplicationBundleIdentifier
        ) {
            appSkillSection = "\n\nAPP-SPECIFIC SKILL — you are operating inside this app "
                + "right now; follow its guidance precisely:\n\n" + appSkillMarkdown
            WorkflowDebugLog.log(
                "decider: loaded app skill for \(perception.frontmostApplicationBundleIdentifier ?? "?")"
            )
        } else {
            appSkillSection = ""
        }

        let systemPrompt = Self.agentInstructions
            + appSkillSection
            + "\n\nTHE PLAYBOOK YOU ARE EXECUTING:\n\n" + playbookMarkdown

        var images: [(data: Data, label: String)] = []
        if let screenshotJPEGData = perception.screenshotJPEGData {
            images.append((
                data: screenshotJPEGData,
                label: "The screen RIGHT NOW (\(perception.screenshotWidthInPixels)x\(perception.screenshotHeightInPixels) pixels)."
            ))
        }

        var promptSections: [String] = []
        if images.isEmpty {
            promptSections.append(
                "(No screenshot is available this turn — rely on the accessibility context.)"
            )
        }
        promptSections.append(
            "ACCESSIBILITY CONTEXT of the focused window:\n\(perception.accessibilityContext)"
        )
        if let previousActionResult {
            promptSections.append("RESULT OF YOUR PREVIOUS ACTION: \(previousActionResult)")
        }
        promptSections.append("Decide your next action. Respond with ONLY the JSON object.")
        let userPrompt = promptSections.joined(separator: "\n\n")

        let (responseText, _) = try await claudeAPI.analyzeImageStreaming(
            images: images,
            systemPrompt: systemPrompt,
            conversationHistory: previousTurns,
            userPrompt: userPrompt,
            maxTokens: Self.decisionMaxTokens,
            onTextChunk: { _ in }
        )

        do {
            return (try WorkflowAgentDecisionParser.parse(responseText), responseText)
        } catch {
            WorkflowDebugLog.log(
                "decider: parse failed (\(error.localizedDescription)) — retrying once"
            )
            let retryPrompt = userPrompt + """


            YOUR PREVIOUS REPLY COULD NOT BE PARSED: \(error.localizedDescription)
            Reply again with ONLY one valid JSON object in the exact documented shape.
            """
            let (retryText, _) = try await claudeAPI.analyzeImageStreaming(
                images: images,
                systemPrompt: systemPrompt,
                conversationHistory: previousTurns,
                userPrompt: retryPrompt,
                maxTokens: Self.decisionMaxTokens,
                onTextChunk: { _ in }
            )
            return (try WorkflowAgentDecisionParser.parse(retryText), retryText)
        }
    }

    private static let agentInstructions = """
        You are Perch's desktop automation agent. You are executing a workflow \
        playbook on the user's real Mac, one action per turn. Each turn you get \
        a fresh screenshot, the focused window's accessibility tree, and the \
        result of your previous action.

        Respond with ONLY one JSON object, no prose, no code fence:
        {"observation": "<what the screen shows, INCLUDING whether your previous \
        action had its expected effect>",
         "action": {<one action, see below>},
         "step": "<short progress line for the user, e.g. 'Filling row 6 with Dana Cho'>"}

        ACTIONS (exactly one per turn):
        - {"type": "click_element", "role": "AXButton", "label": "Add"} — click an \
        element from the accessibility tree. PREFER this over click_at.
        - {"type": "click_at", "x": 640, "y": 412} — click at PIXEL coordinates in \
        the current screenshot. Fallback only, when no accessibility element matches.
        - {"type": "type_text", "text": "..."} — type into the focused element.
        - {"type": "paste_text", "text": "..."} — clipboard-paste into the focused \
        element. Prefer over type_text for values with many characters.
        - {"type": "press_key", "key": "c", "modifiers": ["command"]} — press one \
        key with optional modifiers held. `key` is a single letter/digit (a-z, \
        0-9) OR a named key (tab|return|escape|delete|space|up|down|left|right|\
        pageup|pagedown|home|end); `modifiers` is any of \
        ["command","shift","option","control"] (omit for none). \
        TO COPY a selection, use {"key":"c","modifiers":["command"]} (⌘C); ⌘A \
        selects all. Do NOT use "key_combination" or "key_sequence" — only \
        press_key. For pasting known text prefer paste_text.
        - {"type": "scroll", "x": 640, "y": 412, "direction": "down", "amount": 15} — \
        scroll-wheel at PIXEL coordinates in the current screenshot. Routed to \
        whatever is under that point regardless of keyboard focus — the RELIABLE \
        way to reveal more of a source list (point it at the middle of the \
        source's content). Prefer this over pagedown for scrolling.
        - {"type": "applescript", "source": "..."} — run AppleScript. REQUIRED for \
        spreadsheet cell writes (apps like Microsoft Excel and Apple Numbers \
        silently discard synthetic keystrokes, so set cell values with AppleScript, \
        not type_text). The EXACT syntax for the app you are in is given in the \
        APP-SPECIFIC SKILL section above — use its reusable recipes verbatim and \
        fill in your values. Escape quotes and backslashes inside values. Keep the \
        source on ONE LINE (no line breaks) — a newline inside the JSON string makes \
        the whole reply invalid and the turn fails; use the one-line `tell \
        application "X" to <command>` form. Use AppleScript ONLY for these \
        spreadsheet cell writes and for `tell application "X" to activate` — NEVER \
        `do JavaScript` or other app scripting (not authorized, it will fail).
        - {"type": "run_shell", "command": "..."} — run a shell command in a repo \
        scratch directory; its combined stdout+stderr is returned to you so you \
        can read the result. This is the general code-execution path. Use it to \
        CREATE a new document by generating the file in its NATIVE format \
        (e.g. write a SpreadsheetML `.xml` or build an `.xlsx` with a script) and \
        then opening it (`open -a "<App>" <file>`) — never hand-build a new file \
        cell-by-cell when you can generate it. Configured keys from the repo \
        `.env` (e.g. an API key) are available to the command's environment. \
        Commands time out after 60s; keep them self-contained.
        - {"type": "done", "summary": "..."} — ONLY when the playbook's "Done when" \
        criteria are VISIBLY satisfied in the screenshot.
        - {"type": "fail", "reason": "..."} — LAST RESORT only, after you have \
        actually tried. Never fail merely because the source/destination window \
        isn't frontmost — activate it first (see the WRONG WINDOW rule below).

        RULES:
        - WRONG WINDOW IS NOT A DEAD END: a workflow always starts by bringing its \
        own apps forward, so if the playbook's source or destination window is not \
        frontmost or visible, that is EXPECTED on the first turns — it is NOT a \
        reason to fail. Your action is to ACTIVATE the app you need next: \
        {"type":"applescript","source":"tell application \"<App>\" to activate"} \
        using the exact app name from the playbook's Sources (e.g. \"Microsoft \
        Excel\", \"Microsoft Outlook\"). Bring the source app up to copy, then the \
        destination app up to paste. Only fail about a window if activating it \
        still does not bring it up after two tries.
        - Verify before proceeding: if the previous action did not have its \
        expected effect, do NOT repeat it identically — try a different approach.
        - If the same approach has failed twice, change strategy or fail.
        - Never act on Perch's own UI. Never enter anything into a password field.
        - Only use values from the playbook or the screen. NEVER invent values; \
        skip an item whose value is marked [ILLEGIBLE] and mention it in done's summary.
        - When the playbook says the source CONTINUES beyond its listed items: \
        after finishing the listed items, scroll the source (the scroll action, \
        pointed at the source's content), read each newly visible item's EXACT \
        values from the screenshot (use the accessibility tree to cross-check), \
        and process them the same way — repeat until the source is exhausted.
        - KNOW WHEN TO STOP: if 3 attempts to reveal, read, or verify something \
        have not produced visible progress, stop pursuing it — finish with \
        "done" and list exactly what you could not process in the summary. A \
        done with caveats is ALWAYS better than burning the action budget \
        re-trying. Likewise, once every item you can access is entered, say \
        "done" immediately — do not keep verifying.
        - PREFER EDITING over creating: when a file is already open, edit and \
        extend it in place — do not recreate it from scratch. Only create a new \
        file when none exists, and then GENERATE it in its native format via \
        run_shell (see that action) rather than hand-building it.
        - Stay within the playbook's scope — no exploring, no extra changes.
        """
}
