//
//  DailyBriefGenerator.swift
//  notch
//
//  The synthesis half of the Daily Brief: one Claude call that turns the morning's raw
//  context — priority emails, Slack messages, today's calendar — into the brief's prose
//  (the one-line summary, the catch-up triage bullets, and the priority checklist).
//
//  It reuses the app's existing Worker /chat proxy via `ClaudeAPI` (no new plumbing) and
//  follows the same JSON-reply + retry-once-on-parse-error pattern as
//  `ClaudeWorkflowActionDecider`. On total failure it returns `nil`, and the view falls
//  back to showing the raw fetched items — it never fabricates a brief.
//

import Foundation

@MainActor
final class DailyBriefGenerator {

    /// Headroom for the JSON reply (a summary + a handful of short bullets).
    private static let synthesisMaxTokens = 1024

    private lazy var claudeAPI: ClaudeAPI = {
        ClaudeAPI(
            proxyURL: "\(WorkflowPlaybookSynthesizer.workerBaseURL)/chat",
            model: "claude-sonnet-4-6"
        )
    }()

    /// Synthesize the brief from the day's context. Returns `nil` on a network or parse
    /// failure (after one retry) so the caller degrades to raw items.
    func synthesize(
        firstName: String,
        weekdayName: String,
        dateLine: String,
        emails: [DashboardWidgetItem],
        slackMessages: [DashboardWidgetItem],
        calendarEntries: [DashboardWidgetItem]
    ) async -> DailyBriefSynthesis? {
        let systemPrompt = Self.systemPrompt(firstName: firstName)
        let userPrompt = Self.userPrompt(
            weekdayName: weekdayName,
            dateLine: dateLine,
            emails: emails,
            slackMessages: slackMessages,
            calendarEntries: calendarEntries
        )

        do {
            let (responseText, _) = try await claudeAPI.analyzeImageStreaming(
                images: [],
                systemPrompt: systemPrompt,
                conversationHistory: [],
                userPrompt: userPrompt,
                maxTokens: Self.synthesisMaxTokens,
                onTextChunk: { _ in }
            )
            if let parsed = Self.parse(responseText) { return parsed }

            // One retry, feeding the format requirement back to the model.
            let retryPrompt = userPrompt + """


            YOUR PREVIOUS REPLY COULD NOT BE PARSED. Reply again with ONLY one valid JSON \
            object in the exact documented shape — no prose, no code fence.
            """
            let (retryText, _) = try await claudeAPI.analyzeImageStreaming(
                images: [],
                systemPrompt: systemPrompt,
                conversationHistory: [],
                userPrompt: retryPrompt,
                maxTokens: Self.synthesisMaxTokens,
                onTextChunk: { _ in }
            )
            return Self.parse(retryText)
        } catch {
            NSLog("[DailyBrief] synthesis failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Prompt construction

    private static func systemPrompt(firstName: String) -> String {
        """
        You are Perch, writing \(firstName)'s personal daily brief — a short, warm morning \
        note that helps them start the day oriented. You are given today's context: \
        priority emails, recent Slack messages, and today's calendar. Synthesize it.

        Respond with ONLY one JSON object, no prose, no code fence, in EXACTLY this shape:
        {
          "summary": "<one or two short, present-tense sentences capturing the shape of \
        the day. Warm and specific — name a standout event or theme if there is one. \
        Max ~30 words.>",
          "catchUp": ["<3-5 very short triage lines: what came in overnight that wants \
        attention, each a terse phrase, not a full sentence>"],
          "priorities": ["<3-5 concrete, actionable to-dos for today, derived from the \
        emails / messages / calendar. Each starts with a verb (e.g. 'Buy Sean's birthday \
        gift', 'Finish KPIs to send to Sara').>"]
        }

        RULES:
        - Use ONLY what the context supports. Never invent meetings, people, or tasks that \
        aren't grounded in the provided emails / Slack / calendar.
        - If a section has no real basis, return an empty array for it rather than padding.
        - Keep every line tight — this is a glanceable brief, not a report.
        - Refer to the user by first name where natural; never sign off or add pleasantries.
        """
    }

    private static func userPrompt(
        weekdayName: String,
        dateLine: String,
        emails: [DashboardWidgetItem],
        slackMessages: [DashboardWidgetItem],
        calendarEntries: [DashboardWidgetItem]
    ) -> String {
        var sections: [String] = []
        sections.append("TODAY: \(weekdayName), \(dateLine)")
        sections.append("PRIORITY EMAILS:\n\(itemize(emails))")
        sections.append("SLACK MESSAGES:\n\(itemize(slackMessages))")
        sections.append("TODAY'S CALENDAR:\n\(itemize(calendarEntries))")
        sections.append("Write the brief now. Respond with ONLY the JSON object.")
        return sections.joined(separator: "\n\n")
    }

    /// Render a provider item list as compact "- title — subtitle" lines for the prompt,
    /// or an explicit "(none)" so the model knows the source was empty, not omitted.
    private static func itemize(_ items: [DashboardWidgetItem]) -> String {
        guard !items.isEmpty else { return "(none)" }
        return items.map { item in
            if let subtitle = item.subtitle, !subtitle.isEmpty {
                return "- \(item.title) — \(subtitle)"
            }
            return "- \(item.title)"
        }.joined(separator: "\n")
    }

    // MARK: Parsing

    /// Parse the model's JSON reply into a synthesis, tolerating a stray code fence or
    /// leading/trailing prose around the object. Returns `nil` if the JSON or required
    /// keys are missing.
    private static func parse(_ rawResponse: String) -> DailyBriefSynthesis? {
        let cleaned = stripCodeFence(rawResponse)
        // Isolate the outermost { … } in case the model wrapped it in any prose.
        guard let firstBrace = cleaned.firstIndex(of: "{"),
              let lastBrace = cleaned.lastIndex(of: "}"),
              firstBrace < lastBrace else {
            return nil
        }
        let jsonSlice = String(cleaned[firstBrace...lastBrace])
        guard let jsonData = jsonSlice.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        let summary = (object["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let catchUp = stringArray(object["catchUp"])
        let priorities = stringArray(object["priorities"])

        // A reply with nothing usable is treated as a failure so the caller can fall back.
        guard !summary.isEmpty || !catchUp.isEmpty || !priorities.isEmpty else { return nil }
        return DailyBriefSynthesis(summary: summary, catchUp: catchUp, priorities: priorities)
    }

    /// Coerce a JSON value into a clean `[String]`, dropping empties.
    private static func stringArray(_ value: Any?) -> [String] {
        guard let rawArray = value as? [Any] else { return [] }
        return rawArray
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Strip a leading/trailing Markdown code fence (```json … ```), if present.
    private static func stripCodeFence(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        if let firstNewline = trimmed.firstIndex(of: "\n") {
            trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
        }
        if trimmed.hasSuffix("```") {
            trimmed = String(trimmed.dropLast(3))
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
