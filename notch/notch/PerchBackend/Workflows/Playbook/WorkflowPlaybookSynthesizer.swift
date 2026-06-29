//
//  WorkflowPlaybookSynthesizer.swift
//  leanring-buddy
//
//  The analysis stage of the redesigned Workflows pipeline: takes everything
//  the recorder captured (keyframes cut from the demonstration video, the
//  moment timeline, the derived sources, AX tree snapshots) and asks Claude —
//  via the same Worker /chat proxy the voice flow uses — to write a
//  GENERALIZABLE markdown playbook: the observed pattern, the remaining work
//  as a concrete task list, AX-grounded step instructions, what's fixed vs
//  what varies per iteration, and verifiable done-criteria.
//
//  The playbook is persisted to ~/Library/Application Support/Perch/workflows/
//  as a durable, user-editable artifact, then handed to the agent loop.
//

import Foundation

enum WorkflowPlaybookSynthesizerError: Error, LocalizedError {
    case backendUnreachable(String)
    case emptyModelResponse

    var errorDescription: String? {
        switch self {
        case .backendUnreachable(let backendURL):
            return "Can't reach the Perch backend at \(backendURL) — is the local worker running?"
        case .emptyModelResponse:
            return "The model returned no playbook for that demonstration."
        }
    }
}

@MainActor
final class WorkflowPlaybookSynthesizer {

    /// Base URL of the Worker proxy, shared by the reachability preflight and
    /// the lazily-built ClaudeAPI client. Same Info.plist key CompanionManager
    /// reads for the voice flow; the env override exists for command-line
    /// harnesses, where there is no app bundle to read the key from.
    static let workerBaseURL = AppBundleConfiguration.stringValue(forKey: "WorkerBaseURL")
        ?? ProcessInfo.processInfo.environment["CLICKY_WORKER_BASE_URL"]
        ?? "https://your-worker-name.your-subdomain.workers.dev"

    /// Playbooks run ~1-3K tokens; leave generous headroom so a long remaining-
    /// work list is never truncated mid-table.
    private static let synthesisMaxTokens = 4096

    /// At most this many AX tree snapshots ride along — they're ~1-2K tokens
    /// each and the most recent ones near copy/paste matter most.
    private static let maxTreeSnapshotsSent = 8

    /// At most this many stored playbooks ride along as match candidates —
    /// recency-ordered, so the workflows the user actually repeats stay in the
    /// window even once the library grows.
    private static let maxExistingPlaybooksSent = 5

    /// Each candidate playbook's markdown is truncated to this many characters
    /// in the prompt — enough to judge "same task" and refine, without letting
    /// five playbooks swamp the token budget.
    private static let maxExistingPlaybookCharactersSent = 8000

    private let playbookStore: WorkflowPlaybookStore

    /// Built lazily so app start-up never constructs a network client / fires
    /// its TLS warm-up. Sonnet is vision-capable and the app's default model.
    private lazy var claudeAPI: ClaudeAPI = {
        ClaudeAPI(proxyURL: "\(Self.workerBaseURL)/chat", model: "claude-sonnet-4-6")
    }()

    init(playbookStore: WorkflowPlaybookStore = .standard()) {
        self.playbookStore = playbookStore
    }

    /// Extracts keyframes, runs the synthesis call, persists the markdown, and
    /// returns the playbook ready for the agent loop.
    func synthesizePlaybook(
        from demonstration: RecordedDemonstration
    ) async throws -> WorkflowPlaybook {
        try await Self.preflightBackendReachability()

        let keyframes = await WorkflowVideoKeyframeExtractor.extractKeyframes(from: demonstration)
        let labeledImages = keyframes.map { (data: $0.jpegData, label: $0.label) }

        // Stored playbooks are sent along as match candidates: if this
        // demonstration is the same task as one of them, the model refines
        // that playbook instead of writing a duplicate.
        let existingPlaybooks = Array(
            playbookStore.listAllPlaybooks().prefix(Self.maxExistingPlaybooksSent)
        )
        let userPrompt = Self.buildUserPrompt(
            for: demonstration, existingPlaybooks: existingPlaybooks
        )
        WorkflowDebugLog.log(
            "synthesizer: calling model via \(Self.workerBaseURL) — "
                + "\(labeledImages.count) image(s), prompt \(userPrompt.count) chars, "
                + "\(existingPlaybooks.count) existing playbook(s) as match candidates"
        )

        let (responseText, _) = try await claudeAPI.analyzeImageStreaming(
            images: labeledImages,
            systemPrompt: Self.systemPrompt,
            userPrompt: userPrompt,
            maxTokens: Self.synthesisMaxTokens,
            onTextChunk: { _ in }
        )

        let unfencedText = Self.stripCodeFence(from: responseText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let matchDirective = Self.parseMatchDirective(from: unfencedText)
        let markdown = matchDirective.remainingMarkdown
        guard !markdown.isEmpty else {
            throw WorkflowPlaybookSynthesizerError.emptyModelResponse
        }

        let playbook = try persistSynthesizedPlaybook(
            markdown: markdown, matchedSlug: matchDirective.matchedSlug
        )
        WorkflowDebugLog.log(
            "synthesizer: playbook \"\(playbook.title)\" → \(playbook.fileURL?.path ?? "?") "
                + "(\(markdown.count) chars)"
        )
        return playbook
    }

    /// Always saves the demonstration as a NEW read-only skill. A `MATCH: <slug>`
    /// from the model no longer rewrites that skill in place (a bad run would
    /// silently corrupt a working skill); it only routes the resemblance through
    /// the human-gated `proposeSkillUpdate` seam (logs only) before saving new.
    private func persistSynthesizedPlaybook(
        markdown: String, matchedSlug: String?
    ) throws -> WorkflowPlaybook {
        if let matchedSlug {
            // Flag the resemblance for human review — never an in-place rewrite.
            playbookStore.proposeSkillUpdate(slug: matchedSlug, suggestion: markdown)
        }

        let title = WorkflowPlaybookStore.extractTitle(fromMarkdown: markdown)
            ?? "Workflow \(Self.fallbackTitleDateFormatter.string(from: Date()))"
        let savedPlaybook = try playbookStore.save(markdown: markdown, title: title)
        let matchNote = matchedSlug.map { "resembles \($0)" } ?? "none"
        WorkflowDebugLog.log(
            "synthesizer: saved new read-only skill \(savedPlaybook.slug) (match: \(matchNote))"
        )
        return savedPlaybook
    }

    // MARK: - Prompt assembly

    private static func buildUserPrompt(
        for demonstration: RecordedDemonstration,
        existingPlaybooks: [WorkflowPlaybook]
    ) -> String {
        var promptSections: [String] = []

        promptSections.append("""
        The images above are keyframes from a screen recording of the user \
        demonstrating ONE iteration of a repetitive task, in chronological \
        order. CLOSE-UP tiles show halves of a frame at higher legibility — \
        read exact values from those; tiles overlap slightly, so content \
        appearing in both is the SAME content.
        """)

        let timelineLines = demonstration.moments.map { $0.renderTimelineLine() }
        promptSections.append(
            "EVENT TIMELINE (captured while recording):\n" + timelineLines.joined(separator: "\n")
        )

        let sourceLines = demonstration.sources.map { source -> String in
            var line = "- \(source.role.rawValue.uppercased()): \(source.applicationBundleIdentifier)"
            if let applicationName = source.applicationName { line += " (\(applicationName))" }
            if let windowTitle = source.windowTitle { line += " — window \"\(windowTitle)\"" }
            if let document = source.documentPathOrURL { line += " — \(document)" }
            return line
        }
        promptSections.append(
            "SOURCES (derived from the timeline — where the data came from, what it "
                + "passed through, where it ended up):\n" + sourceLines.joined(separator: "\n")
        )

        // The most recent snapshots are closest to the data flow; cap to keep
        // the token budget sane.
        let momentsWithSnapshots = demonstration.moments
            .filter { $0.focusedWindowTreeSnapshot != nil }
            .suffix(maxTreeSnapshotsSent)
        if !momentsWithSnapshots.isEmpty {
            var snapshotSections: [String] = []
            for moment in momentsWithSnapshots {
                guard let treeSnapshot = moment.focusedWindowTreeSnapshot else { continue }
                snapshotSections.append(
                    "At \(moment.renderTimelineLine()):\n"
                        + treeSnapshot.renderIndentedLines().joined(separator: "\n")
                )
            }
            promptSections.append(
                "ACCESSIBILITY TREE SNAPSHOTS (the UI structure — roles, labels, "
                    + "values, frames in screen points — at key moments; reference these "
                    + "elements in your steps):\n\n" + snapshotSections.joined(separator: "\n\n")
            )
        }

        promptSections.append("""
        Write the playbook now as a markdown document with EXACTLY this structure:

        # <A short imperative title for the task>
        <!-- perch-workflow; recorded \(ISO8601DateFormatter().string(from: demonstration.recordingStartedAt)); v1 -->

        ## Observed pattern
        One paragraph: what the user did once, and what repeating it for every \
        remaining item means.

        ## Sources
        Restate the origin / intermediaries / destination, naming the windows \
        and documents precisely.

        ## Remaining work
        A numbered list of the CONCRETE items still to process, read off the \
        keyframes — with exact field values. Skip anything the user already \
        processed (including the item they processed while demonstrating). \
        COMPLETENESS RULES:
        - The rows the user already completed in the destination define what a \
        COMPLETE record looks like (every column they filled, e.g. Name AND \
        Email AND Number). Include every one of those fields for each remaining \
        item — including fields the user filled by typing or that the source \
        lists but the copy/paste timeline doesn't show. New rows must end up as \
        complete as the demonstrated rows.
        - If the source list visibly CONTINUES beyond what the keyframes show \
        (a scrollable document, a cut-off list), say so explicitly at the end \
        of this section: "The source continues below the visible items — \
        scroll it and process every further item the same way."

        ## Steps for one iteration
        Numbered steps the executing agent follows for ONE item, each grounded \
        in accessibility elements (role + label, e.g. 'Click the AXButton \
        "Add"'), and each stating its expected post-state. If the destination \
        is Microsoft Excel, write cell values via AppleScript `set value of \
        range` — NEVER synthetic keystrokes (Excel silently discards them). \
        If the source continues beyond the visible items, add a final step: \
        scroll the source window to reveal more items, read their exact values \
        from the screen, and repeat the iteration steps for each — until the \
        source is exhausted.

        ## Fixed vs varying
        Bullets: what stays constant across iterations vs what changes per item.

        ## Done when
        Verifiable completion criteria the agent can check visually. If the \
        source continues beyond the visible region, completion requires the \
        source scrolled to its END with EVERY item entered — not merely the \
        items listed above.

        ACCURACY RULES — these values end up in the user's real documents:
        - Copy every value EXACTLY, character by character, as displayed.
        - If a value is not clearly legible in any keyframe, write [ILLEGIBLE] \
        instead. NEVER guess, complete a pattern, or invent a plausible value.
        - Do not normalize capitalization, punctuation, or digit grouping.

        Reply with ONLY the markdown document — no preamble, no code fence.
        """)

        if !existingPlaybooks.isEmpty {
            promptSections.append(renderExistingPlaybooksSection(existingPlaybooks))
        }

        return promptSections.joined(separator: "\n\n")
    }

    /// The match-candidate block appended when stored playbooks exist: the
    /// candidates themselves, plus the `MATCH:` first-line contract that tells
    /// the model to refine a matched playbook instead of duplicating it. When
    /// no playbooks exist this section is omitted and the prompt is identical
    /// to the original single-playbook prompt.
    private static func renderExistingPlaybooksSection(
        _ existingPlaybooks: [WorkflowPlaybook]
    ) -> String {
        var sectionLines: [String] = []
        sectionLines.append("""
        EXISTING PLAYBOOKS — the user has previously demonstrated the workflows \
        below. Decide whether THIS demonstration is the SAME TASK as one of them: \
        the same kind of work moving the same kind of data to the same \
        destination, even if the wording, the specific item values, or minor \
        details differ. A different task that merely uses the same apps is NOT \
        a match.
        """)

        for existingPlaybook in existingPlaybooks {
            let truncatedMarkdown = String(
                existingPlaybook.markdown.prefix(maxExistingPlaybookCharactersSent)
            )
            sectionLines.append(
                "--- existing playbook (slug: \(existingPlaybook.slug)) ---\n"
                    + truncatedMarkdown
            )
        }

        sectionLines.append("""
        MATCH DIRECTIVE — the FIRST line of your reply must be exactly one of:
        MATCH: <slug>   (this demonstration is the same task as that playbook)
        MATCH: none     (this is a new task)
        Use the slug verbatim from the list above. After that first line, write \
        the markdown document as instructed. If you declared a match, the \
        document must be the UPDATED version of the matched playbook: keep \
        everything it already got right, and fold in what this new \
        demonstration showed — refreshed remaining work with exact values, \
        corrected or clarified steps, and current done-criteria. If you \
        declared no match, write a fresh playbook exactly as instructed above.
        """)

        return sectionLines.joined(separator: "\n\n")
    }

    private static let systemPrompt = """
        You are a meticulous workflow analyst. You watched a user demonstrate \
        ONE iteration of a repetitive task on their screen, and you write a \
        markdown PLAYBOOK that a desktop automation agent will follow to finish \
        the remaining iterations on the same screen. The agent can click \
        accessibility elements, type, paste, press keys, and run AppleScript. \
        Be precise, grounded in what is actually visible, and explicit about \
        what varies per iteration versus what is fixed.
        """

    /// Splits the `MATCH: <slug>` / `MATCH: none` first line off the model's
    /// reply. Tolerant of case and surrounding whitespace; when the first line
    /// is not a match directive at all (older prompt shape, odd model output)
    /// the whole text is treated as the playbook with no match — graceful
    /// degradation, never a hard failure. Internal so the CLI harness and unit
    /// tests can exercise it directly.
    static func parseMatchDirective(
        from responseText: String
    ) -> (matchedSlug: String?, remainingMarkdown: String) {
        let trimmedText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = trimmedText.components(separatedBy: "\n")
        guard let firstLine = lines.first else {
            return (matchedSlug: nil, remainingMarkdown: trimmedText)
        }

        let matchDirectivePrefix = "match:"
        let trimmedFirstLine = firstLine.trimmingCharacters(in: .whitespaces)
        guard trimmedFirstLine.lowercased().hasPrefix(matchDirectivePrefix) else {
            return (matchedSlug: nil, remainingMarkdown: trimmedText)
        }

        let directiveValue = trimmedFirstLine.dropFirst(matchDirectivePrefix.count)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "`")))
        lines.removeFirst()
        let remainingMarkdown = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if directiveValue.isEmpty || directiveValue.lowercased() == "none" {
            return (matchedSlug: nil, remainingMarkdown: remainingMarkdown)
        }
        return (matchedSlug: directiveValue, remainingMarkdown: remainingMarkdown)
    }

    /// The model is told not to fence the document, but strip one anyway if it
    /// does — a fenced playbook is still a playbook.
    private static func stripCodeFence(from responseText: String) -> String {
        let trimmedText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.hasPrefix("```") else { return trimmedText }
        var lines = trimmedText.components(separatedBy: "\n")
        lines.removeFirst()
        if let lastFenceIndex = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "```" }) {
            lines.remove(at: lastFenceIndex)
        }
        return lines.joined(separator: "\n")
    }

    private static let fallbackTitleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    // MARK: - Backend preflight

    /// Fails fast (~3s) when the Worker proxy is down. The shared ClaudeAPI
    /// session uses `waitsForConnectivity = true` (a deliberate TLS fix for
    /// the voice path), which turns an unreachable backend into a silent
    /// multi-minute hang — this check surfaces it as an immediate, actionable
    /// failure instead. Any HTTP response (even an error status) counts as
    /// reachable; only transport-level failures throw.
    static func preflightBackendReachability() async throws {
        guard let backendURL = URL(string: workerBaseURL) else {
            throw WorkflowPlaybookSynthesizerError.backendUnreachable(workerBaseURL)
        }

        let preflightConfiguration = URLSessionConfiguration.ephemeral
        preflightConfiguration.timeoutIntervalForRequest = 3
        preflightConfiguration.timeoutIntervalForResource = 3
        preflightConfiguration.waitsForConnectivity = false
        let preflightSession = URLSession(configuration: preflightConfiguration)
        defer { preflightSession.finishTasksAndInvalidate() }

        var preflightRequest = URLRequest(url: backendURL)
        preflightRequest.httpMethod = "GET"
        do {
            _ = try await preflightSession.data(for: preflightRequest)
        } catch {
            WorkflowDebugLog.log("synthesizer: backend preflight FAILED — \(error.localizedDescription)")
            throw WorkflowPlaybookSynthesizerError.backendUnreachable(workerBaseURL)
        }
    }
}
