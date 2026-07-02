//
//  WorkflowEventSource.swift
//  Perch
//
//  The seam that keeps the Workflows capture layer testable. Everything
//  downstream (the repetition detector, the capture manager) consumes a
//  `WorkflowEventSource`; it never knows whether the events came from a real
//  CGEvent tap or from a replayed fixture.
//
//  Two implementations exist:
//   • LiveEventSource (LiveEventSource.swift) — the thin, permission-gated part
//     that turns real OS input into normalized SemanticInputEvents.
//   • MockEventSource (below) — replays a hand-written JSONL fixture trace, so
//     the detector and capture manager are fully unit-testable with no signed
//     app and no Accessibility grant.
//
//  This file is deliberately AppKit-free.
//

import Foundation

/// Anything that emits normalized semantic input events.
///
/// `start(onEvent:)` begins emission; each event is delivered on the main
/// thread (the live tap callback already runs on the main run loop, and tests
/// drive the mock synchronously on the calling thread). `stop()` ends emission.
protocol WorkflowEventSource: AnyObject {
    func start(onEvent: @escaping (SemanticInputEvent) -> Void)
    func stop()
}

/// A terse, hand-authorable representation of one event for fixture files. Only
/// the fields that matter to detection are spelled out; `id` and `occurredAt`
/// are synthesized on decode so fixtures stay readable.
///
/// Example line:
/// `{"app":"com.apple.Numbers","action":"copy","role":"AXCell","label":"B","clipboardHash":"row1"}`
struct WorkflowEventFixtureLine: Codable {
    let app: String
    let action: WorkflowActionType
    var role: String?
    var label: String?
    var clipboardHash: String?
    var typedHash: String?

    func makeSemanticInputEvent(occurredAt: Date) -> SemanticInputEvent {
        SemanticInputEvent(
            applicationBundleIdentifier: app,
            actionType: action,
            targetAccessibilityRole: role,
            targetAccessibilityLabel: label,
            clipboardContentHash: clipboardHash,
            typedTextContentHash: typedHash,
            occurredAt: occurredAt
        )
    }
}

/// Replays a fixed list of events. Backs the fixture-driven tests and the
/// design-time preview of the proactive offer.
final class MockEventSource: WorkflowEventSource {

    let events: [SemanticInputEvent]

    init(events: [SemanticInputEvent]) {
        self.events = events
    }

    /// Decode a JSONL fixture (one `WorkflowEventFixtureLine` per non-empty
    /// line; `#`-prefixed lines are treated as comments). Events are spaced one
    /// second apart starting from a fixed reference date so ordering and
    /// day-bucketing are deterministic.
    static func fromJSONLines(_ jsonlContents: String) throws -> MockEventSource {
        let decoder = JSONDecoder()
        let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
        var decodedEvents: [SemanticInputEvent] = []

        let lines = jsonlContents.split(whereSeparator: \.isNewline)
        for (lineIndex, rawLine) in lines.enumerated() {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") { continue }
            guard let lineData = trimmedLine.data(using: .utf8) else { continue }
            let fixtureLine = try decoder.decode(WorkflowEventFixtureLine.self, from: lineData)
            decodedEvents.append(
                fixtureLine.makeSemanticInputEvent(
                    occurredAt: referenceDate.addingTimeInterval(TimeInterval(lineIndex))
                )
            )
        }

        return MockEventSource(events: decodedEvents)
    }

    static func fromJSONLinesFile(at fileURL: URL) throws -> MockEventSource {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try fromJSONLines(contents)
    }

    func start(onEvent: @escaping (SemanticInputEvent) -> Void) {
        for event in events {
            onEvent(event)
        }
    }

    func stop() {}
}
