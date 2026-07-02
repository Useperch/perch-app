//
//  IntentGate.swift
//  Perch
//
//  The Intent Gate: the explicit answer / act / clarify split that sits at the
//  front of every request (docs/VISION.md "one brain, two lanes"; docs/DECISIONS.md
//  D2). The clarify lane is the safety valve for genuinely ambiguous intent — when
//  Perch can't confidently tell "show me" from "do it", it asks one short question
//  instead of guessing wrong.
//
//  The split is cheap by construction: Perch already makes ONE streaming Claude
//  call and tags the reply — a "go do it" reply ends with [BACKGROUND_TASK:…], an
//  "I'm not sure what you mean" reply ends with [CLARIFY:…]. The gate classifies
//  that ALREADY-RETURNED reply rather than making a second pre-classification call
//  — so the instant answer lane pays ZERO extra latency (no added round-trip),
//  exactly as D2 requires. The act lane hands off to the brain (today: the browser
//  subagent); the clarify lane just speaks the question and waits for the reply.
//
//  This type is intentionally self-contained (no CompanionManager dependency) so
//  the no-Xcode CLI check (scripts/check-intent-gate.sh) can compile it standalone.
//

import Foundation

/// Which lane a completed Claude reply routes to.
enum IntentLane: Equatable {
    /// Instant answer lane: stream text + TTS + optional on-screen [POINT:…].
    /// No planner, no autonomous agent — kept exactly as fast as today.
    case answer

    /// Autonomous act lane: hand the task off to the brain to run in the
    /// background. Today this is always the browser subagent; the desktop tool
    /// (Plan 09) will extend this case with a sub-type that selects the target.
    /// - task: the concise natural-language task description for the agent.
    /// - spokenConfirmation: the short reply (tag stripped) to speak before the
    ///   agent starts running.
    case act(task: String, spokenConfirmation: String)

    /// Dashboard lane: the user asked to add OR change a widget on their own Perch
    /// Daily Dashboard. This is a DO routed to the main agent's `dashboard` tool
    /// family (which decides the source + fetch plan + refresh cadence and applies it
    /// back to the board) — never the generic browser subagent.
    /// - spec: the plain-English request (what to add, or how to change a widget).
    /// - spokenConfirmation: the short reply (tag stripped) to speak before acting.
    case dashboardWidget(spec: String, spokenConfirmation: String)

    /// Clarify lane: the request was genuinely ambiguous (could be answer or act,
    /// or an act with a detail Perch shouldn't guess). Speak the one-line
    /// question and wait — do nothing else. No pointer, no autonomous run.
    /// - question: the short question to speak to the user.
    case clarify(question: String)
}

/// Classifies a completed Claude reply into the answer, act, or clarify lane.
enum IntentGate {
    /// Matches a [CLARIFY:<question>] tag anchored to the end of the reply: the
    /// signal that Perch was unsure and is asking before doing anything.
    private static let clarifyTagPattern = #"\[CLARIFY:([^\]]+)\]\s*$"#

    /// Matches a [BACKGROUND_TASK:<task>] tag anchored to the end of the reply.
    /// Same pattern Perch has always used to signal a "go do it" task.
    private static let backgroundTaskTagPattern = #"\[BACKGROUND_TASK:([^\]]+)\]\s*$"#

    /// Matches a [DASHBOARD:<request>] tag anchored to the end of the reply — the
    /// signal that the user wants to add OR change a widget on their own Perch Daily
    /// Dashboard, which routes to the main agent's dashboard tool family rather than
    /// the generic browser subagent.
    private static let dashboardWidgetTagPattern = #"\[DASHBOARD:([^\]]+)\]\s*$"#

    /// Classify a *completed* Claude reply into the answer, act, or clarify lane.
    ///
    /// Reuses the existing single-call signal: a reply ending in `[CLARIFY:…]`
    /// routes to the clarify lane; a reply ending in `[BACKGROUND_TASK:…]` (with a
    /// non-empty task) routes to the act lane; otherwise it stays on the instant
    /// answer lane. Because it inspects a reply Perch already has, the answer
    /// lane pays no extra latency.
    ///
    /// Clarify is checked first: an unsure model must ask before it acts, never
    /// fire off an autonomous run on a guess.
    ///
    /// `nonisolated static` so it unit-tests without a `@MainActor` instance
    /// (mirrors `RepetitionDetector.detectRepeatingCycle`).
    nonisolated static func classify(claudeReply: String) -> IntentLane {
        // Clarify takes priority over act.
        if let question = trailingTagPayload(in: claudeReply, pattern: clarifyTagPattern) {
            return .clarify(question: question)
        }

        // A dashboard request is a DO routed to the agent's dashboard family, so it
        // is recognized before the generic browser-subagent act tag.
        if let spec = trailingTagPayload(in: claudeReply, pattern: dashboardWidgetTagPattern) {
            let spokenConfirmation = textBeforeTrailingTag(in: claudeReply, pattern: dashboardWidgetTagPattern)
            return .dashboardWidget(spec: spec, spokenConfirmation: spokenConfirmation)
        }

        if let task = trailingTagPayload(in: claudeReply, pattern: backgroundTaskTagPattern) {
            let spokenConfirmation = textBeforeTrailingTag(in: claudeReply, pattern: backgroundTaskTagPattern)
            return .act(task: task, spokenConfirmation: spokenConfirmation)
        }

        return .answer
    }

    /// Returns the trimmed, non-empty payload captured by a trailing tag pattern,
    /// or `nil` if the tag is absent or wraps only whitespace. An empty payload is
    /// treated as no tag at all — Perch should not spawn an agent with nothing to
    /// do, nor speak an empty question.
    private static func trailingTagPayload(in reply: String, pattern: String) -> String? {
        guard let match = firstMatch(in: reply, pattern: pattern),
              let payloadRange = Range(match.range(at: 1), in: reply) else {
            return nil
        }
        let payload = String(reply[payloadRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return payload.isEmpty ? nil : payload
    }

    /// Returns the trimmed reply text that precedes a trailing tag — the part
    /// Perch speaks aloud before handing off.
    private static func textBeforeTrailingTag(in reply: String, pattern: String) -> String {
        guard let match = firstMatch(in: reply, pattern: pattern),
              let tagRange = Range(match.range, in: reply) else {
            return reply.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(reply[..<tagRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(in reply: String, pattern: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        return regex.firstMatch(in: reply, range: NSRange(reply.startIndex..., in: reply))
    }
}
