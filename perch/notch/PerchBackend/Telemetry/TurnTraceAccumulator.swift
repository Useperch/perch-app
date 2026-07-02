//
//  TurnTraceAccumulator.swift
//  notch
//
//  Captures one companion turn as a STRUCTURED trace for upload, in lockstep
//  with the markdown PerchRunLog. It taps the exact same append/appendBlock
//  calls (PerchRunLog forwards every event here), so there are no new logging
//  call sites in CompanionManager — the structured fields are derived from the
//  events at finalize time by matching the stable category/title shapes.
//
//  It is a reference type on purpose: PerchRunLog.RunDocument is a value type
//  passed across async boundaries (and handed to the browser subagent), so the
//  accumulator must be shared by reference for late appends to land in the same
//  trace.
//

import Foundation

/// A single recorded event, mirroring one PerchRunLog line.
struct TurnTraceEvent {
    let timestampMillis: Int
    let category: String   // INPUT | PLAN | ACTION | SPEAK | ERROR | STATE
    let title: String
    let body: String
}

/// The structured turn trace handed to the uploader once a turn ends. Named
/// fields are derived from the event stream; `events` keeps the full ordered log.
struct StructuredTurnTrace {
    let clientRunId: String
    let inputKind: String
    let input: String
    let startedAt: Date
    let endedAt: Date

    var systemPrompt: String?
    var conversationHistory: String?
    var userPrompt: String?
    var modelResponse: String?
    var intentGate: String?
    var spokenText: String?
    var error: String?

    let events: [TurnTraceEvent]
}

/// Thread-safe, append-only collector for one turn's events.
final class TurnTraceAccumulator {
    private let clientRunId: String
    private let inputKind: String
    private let input: String
    private let startedAt: Date

    private let lock = NSLock()
    private var events: [TurnTraceEvent] = []
    private var isFinalized = false

    init(clientRunId: String, inputKind: String, input: String, startedAt: Date) {
        self.clientRunId = clientRunId
        self.inputKind = inputKind
        self.input = input
        self.startedAt = startedAt
    }

    /// Records one event. Mirrors a PerchRunLog append (body empty) or appendBlock.
    func record(category: String, title: String, body: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinalized else { return }
        let millisSinceStart = Int(Date().timeIntervalSince(startedAt) * 1000)
        events.append(TurnTraceEvent(
            timestampMillis: millisSinceStart,
            category: category,
            title: title,
            body: body
        ))
    }

    /// Finalizes the trace exactly once. A second call returns nil so endRun is
    /// safe to invoke from multiple terminal paths.
    func finalize(endedAt: Date) -> StructuredTurnTrace? {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinalized else { return nil }
        isFinalized = true

        var trace = StructuredTurnTrace(
            clientRunId: clientRunId,
            inputKind: inputKind,
            input: input,
            startedAt: startedAt,
            endedAt: endedAt,
            events: events
        )

        // Derive the named fields from the stable category/title shapes the
        // pipeline already logs. Matching by prefix tolerates the dynamic
        // suffixes (e.g. "conversation history sent to claude (3 exchange(s))").
        for event in events {
            let lowercasedTitle = event.title.lowercased()
            switch event.category {
            case PerchDebugCategory.plan.rawValue:
                if lowercasedTitle.hasPrefix("system prompt sent to") {
                    trace.systemPrompt = event.body
                } else if lowercasedTitle.hasPrefix("conversation history sent to") {
                    trace.conversationHistory = event.body
                } else if lowercasedTitle.hasPrefix("user prompt sent to") {
                    trace.userPrompt = event.body
                } else if lowercasedTitle == "model full reply" {
                    trace.modelResponse = event.body
                } else if let decision = Self.intentGateDecision(from: event.title) {
                    trace.intentGate = decision
                }
            case PerchDebugCategory.speak.rawValue:
                // speakResponse logs the spoken text verbatim as the message.
                trace.spokenText = event.body.isEmpty ? event.title : event.body
            case PerchDebugCategory.error.rawValue:
                let message = event.body.isEmpty ? event.title : event.body
                trace.error = trace.error.map { "\($0)\n\(message)" } ?? message
            default:
                break
            }
        }

        return trace
    }

    /// Extracts the decision word from an "intent gate → ACT: …" plan line.
    private static func intentGateDecision(from title: String) -> String? {
        guard let arrowRange = title.range(of: "intent gate →") else { return nil }
        let afterArrow = title[arrowRange.upperBound...]
        let decision = afterArrow
            .split(separator: ":", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        return (decision?.isEmpty == false) ? decision : nil
    }
}
