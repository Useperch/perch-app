//
//  RepetitionDetector.swift
//  Perch
//
//  The fully-local "Clippy radar" behind the proactive offer. It watches a
//  rolling window of SemanticInputEvents and fires a WorkflowOffer on one
//  dead-simple signal: a short action *shape* (≤3 actions, e.g. ⌘C → ⌘V across
//  two apps) repeated TWICE back-to-back with *different* content each time,
//  where every consecutive action lands ≤5s apart. Do it once and it's quiet;
//  do it twice, fast, and it offers. Slow, spread-out repetition is deliberate
//  work, not a loop — it stays silent.
//
//  Crucially this makes NO model calls — detection is cheap, local, and private.
//  An LLM is only involved later, once the user accepts the offer.
//
//  The matching itself lives in `nonisolated static` functions so it can be
//  unit-tested without constructing the main-actor stateful wrapper. The only
//  stateful guardrail is "don't re-offer a pattern the user already answered
//  this session" — held on the instance because it spans events.
//

import Foundation

/// Tunables for the simplified trigger. Defaults: fire at N=2 FAST repetitions
/// — a short cycle (≤3 actions, e.g. copy→paste) whose consecutive actions all
/// land ≤5s apart.
struct RepetitionDetectorConfiguration {
    /// N — how many back-to-back repetitions of a shape before we ARM (detect)
    /// the pattern. Detection at 2 keeps the radar primed; it does not by itself
    /// surface a banner (see `offerRepetitionThreshold`).
    var repetitionThreshold: Int = 2
    /// How many back-to-back repetitions before we actually OFFER (surface the
    /// banner). Higher than `repetitionThreshold` on purpose: a false
    /// interruption costs trust every time, while a missed catch is invisible —
    /// so the offer biases toward precision and waits for the 3rd fast,
    /// content-varying repetition (docs/DECISIONS.md D7).
    var offerRepetitionThreshold: Int = 3
    /// How many recent events to retain for matching.
    var rollingWindowMaximumEventCount: Int = 60
    /// Longest repeating unit we will consider. Manual iteration worth
    /// offering on is a SHORT loop — copy, (switch app), paste, maybe one
    /// click — so anything longer than 3 actions is not our trigger.
    var maximumCycleLength: Int = 3
    /// Require the repeating unit to contain a *committing* action (paste /
    /// click / type). Stops "the user keeps copying cells" — shape-same /
    /// content-different but not yet an actionable task — from tripping an offer.
    var requiresCommittingAction: Bool = true
    /// Max seconds between any two CONSECUTIVE events inside the matched span
    /// (including the gap between one pass's last action and the next pass's
    /// first). Rapid-fire ⌘C ⌘V iteration qualifies; pausing to think doesn't.
    var maximumSecondsBetweenConsecutiveActions: TimeInterval = 5

    init() {}
}

/// The raw result of scanning the window, before the stateful guardrails are
/// applied. `nonisolated` and value-typed so it is trivially testable.
struct RepeatingCycleMatch: Equatable {
    let repeatingActionShapes: WorkflowActionShapeSequence
    let observedRepetitionCount: Int
    /// True when at least one content-bearing position differed across the
    /// repetitions (the shape-same / content-different signal).
    let didContentVaryAcrossRepetitions: Bool
}

@MainActor
final class RepetitionDetector: ObservableObject {

    private let configuration: RepetitionDetectorConfiguration

    /// Most-recent-last rolling window of observed events.
    private var rollingEventWindow: [SemanticInputEvent] = []

    /// Patterns the user already answered ("Yes" or "Not now") this session,
    /// keyed by rotation-invariant key (see `rotationInvariantKey`) so a cycle
    /// and its phase-shifted forms count as one pattern. Once a pattern is in
    /// here we never re-offer it for the rest of the session — the single
    /// "don't pester me about the same thing twice" guard.
    private var suppressedPatternKeys: Set<WorkflowActionShapeSequence> = []

    /// Rotation-invariant key of the pattern we most recently surfaced an
    /// (unanswered) offer for, so continued iteration — which rotates the tail
    /// through phase-shifted forms of the same cycle — doesn't re-fire it.
    private var pendingOfferPatternKey: WorkflowActionShapeSequence?

    /// Persists patterns the user dismissed, so a dismissal sticks ACROSS runs
    /// (the session set above only spans one run). `nil` = no persistence — the
    /// default, so pure unit tests never touch disk; production injects
    /// `DismissedPatternStore.standard()`.
    private let dismissedPatternStore: DismissedPatternStore?

    init(
        configuration: RepetitionDetectorConfiguration = RepetitionDetectorConfiguration(),
        dismissedPatternStore: DismissedPatternStore? = nil
    ) {
        self.configuration = configuration
        self.dismissedPatternStore = dismissedPatternStore
    }

    // MARK: - Ingestion

    /// Feed one freshly-observed event. Returns a `WorkflowOffer` exactly when a
    /// fast, content-varying repetition crosses the threshold AND the pattern
    /// hasn't already been offered/answered this session; otherwise `nil`.
    func ingest(_ event: SemanticInputEvent) -> WorkflowOffer? {
        rollingEventWindow.append(event)
        if rollingEventWindow.count > configuration.rollingWindowMaximumEventCount {
            rollingEventWindow.removeFirst(rollingEventWindow.count - configuration.rollingWindowMaximumEventCount)
        }

        guard let match = Self.detectRepeatingCycle(in: rollingEventWindow, configuration: configuration) else {
            return nil
        }

        // The defining test: shape-same is not enough — content must vary, or
        // it's just ⌘C pressed twice.
        guard match.didContentVaryAcrossRepetitions else { return nil }

        // Detect-vs-offer split: `detectRepeatingCycle` ARMS the pattern at
        // `repetitionThreshold` (2), but we only surface a banner once it has
        // repeated `offerRepetitionThreshold` (3) times. A false interruption
        // costs trust every time; a missed catch is invisible — so bias toward
        // precision (docs/DECISIONS.md D7).
        guard match.observedRepetitionCount >= configuration.offerRepetitionThreshold else { return nil }

        let shapeSequence = match.repeatingActionShapes
        let patternKey = Self.rotationInvariantKey(of: shapeSequence)

        // Already offered this pattern (in any phase) and still waiting on the user.
        if pendingOfferPatternKey == patternKey { return nil }

        // Don't re-offer a pattern the user already answered — this session (the
        // in-memory set) OR in a past session (the persistent dismissal store).
        if suppressedPatternKeys.contains(patternKey)
            || dismissedPatternStore?.contains(Self.persistentDismissalKey(for: shapeSequence)) == true {
            WorkflowDebugLog.log("detector: pattern matched but already answered (this session or persisted) — suppressed")
            return nil
        }

        pendingOfferPatternKey = patternKey

        return WorkflowOffer(
            repeatingActionShapes: shapeSequence,
            observedRepetitionCount: match.observedRepetitionCount,
            involvedApplicationBundleIdentifiers: Self.distinctApplications(in: shapeSequence),
            offerLine: Self.composeOfferLine(for: shapeSequence),
            stepByStepRestatement: Self.composeStepByStepRestatement(for: shapeSequence)
        )
    }

    // MARK: - User responses (update guardrail state)

    /// The user said "Not now". Suppress this pattern for the rest of the
    /// session AND persist the dismissal so it stays suppressed across runs.
    func recordOfferDismissed(_ offer: WorkflowOffer) {
        suppressedPatternKeys.insert(Self.rotationInvariantKey(of: offer.repeatingActionShapes))
        dismissedPatternStore?.recordDismissed(Self.persistentDismissalKey(for: offer.repeatingActionShapes))
        clearPendingOffer(for: offer)
    }

    /// The user said "Yes". Do NOT add this pattern to the session suppression
    /// set: accepting kicks off a takeover run, during which passive capture is
    /// paused and the rolling window reset (`WorkflowCaptureManager.stopCapturing`
    /// → `resetRollingWindow`), so the pattern physically cannot re-fire mid-run.
    /// Once the run ends and capture resumes, if the user is STILL grinding the
    /// same loop by hand — evidence the takeover didn't relieve them — the offer
    /// SHOULD come back. Permanently suppressing on accept was silencing exactly
    /// those continuing iterations. Reset the window now so re-detection starts
    /// from a clean slate (it takes a fresh run of repetitions to re-offer).
    func recordOfferAccepted(_ offer: WorkflowOffer) {
        resetRollingWindow()
    }

    /// The offer went away WITHOUT the user answering it (e.g. an incidental
    /// click elsewhere while they kept working). Unlike an answer this does NOT
    /// suppress the pattern — if they keep iterating, the offer fires again.
    func recordOfferDeferred(_ offer: WorkflowOffer) {
        clearPendingOffer(for: offer)
    }

    /// Forget the rolling window (e.g. when an explicit recording starts, so the
    /// recorded actions don't immediately trip a proactive offer).
    func resetRollingWindow() {
        rollingEventWindow.removeAll(keepingCapacity: true)
        pendingOfferPatternKey = nil
    }

    private func clearPendingOffer(for offer: WorkflowOffer) {
        if pendingOfferPatternKey == Self.rotationInvariantKey(of: offer.repeatingActionShapes) {
            pendingOfferPatternKey = nil
        }
    }

    // MARK: - Pure matching (testable without the main-actor wrapper)

    /// Scan `events` (most-recent-last) for the smallest repeating cycle at the
    /// tail that repeats at least `repetitionThreshold` times. Returns the
    /// fundamental unit, the repetition count, and whether content varied.
    ///
    /// "Smallest cycle at the tail" is intentional: the fundamental iteration
    /// unit is the shortest sequence that tiles the recent activity, so we scan
    /// cycle lengths ascending and take the first that qualifies.
    nonisolated static func detectRepeatingCycle(
        in events: [SemanticInputEvent],
        configuration: RepetitionDetectorConfiguration
    ) -> RepeatingCycleMatch? {
        let threshold = max(2, configuration.repetitionThreshold)
        guard events.count >= threshold else { return nil }

        let shapes = events.map(WorkflowActionShape.init(from:))
        let largestCycleLengthToConsider = min(configuration.maximumCycleLength, events.count / threshold)
        guard largestCycleLengthToConsider >= 1 else { return nil }

        for cycleLength in 1...largestCycleLengthToConsider {
            let shapeRepetitionCount = tailRepetitionCount(of: cycleLength, in: shapes)
            guard shapeRepetitionCount >= threshold else { continue }

            // The trigger is FAST iteration: clamp the shape-equal blocks to
            // the trailing ones that also satisfy the timing rule, so an old
            // slow pass minutes ago neither fires nor disqualifies two fresh
            // fast passes.
            let timeQualifiedCount = timeQualifiedRepetitionCount(
                events: events,
                cycleLength: cycleLength,
                shapeRepetitionCount: shapeRepetitionCount,
                configuration: configuration
            )
            guard timeQualifiedCount >= threshold else { continue }

            let tailRange = (shapes.count - cycleLength)..<shapes.count
            let repeatingActionShapes = Array(shapes[tailRange])

            if configuration.requiresCommittingAction
                && !repeatingActionShapes.contains(where: { $0.actionType.isCommittingAction }) {
                continue
            }

            let didContentVary = didContentVaryAcrossRepetitions(
                events: events,
                cycleLength: cycleLength,
                repetitionCount: timeQualifiedCount
            )

            return RepeatingCycleMatch(
                repeatingActionShapes: repeatingActionShapes,
                observedRepetitionCount: timeQualifiedCount,
                didContentVaryAcrossRepetitions: didContentVary
            )
        }

        return nil
    }

    /// Of the `shapeRepetitionCount` shape-equal blocks at the tail, how many
    /// TRAILING blocks also satisfy the timing rule. Walking from the tail, the
    /// block preceding the qualified span joins only if every consecutive-event
    /// gap across the joined span — including the boundary between the two
    /// blocks — is ≤ `maximumSecondsBetweenConsecutiveActions`. That single
    /// "everything <5s apart" rule is the whole timing test. Always ≥ 1: a
    /// single block has no inter-event timing to violate.
    nonisolated static func timeQualifiedRepetitionCount(
        events: [SemanticInputEvent],
        cycleLength: Int,
        shapeRepetitionCount: Int,
        configuration: RepetitionDetectorConfiguration
    ) -> Int {
        guard shapeRepetitionCount >= 1 else { return 0 }

        var qualifiedBlockCount = 1
        while qualifiedBlockCount < shapeRepetitionCount {
            // The candidate block sits immediately before the qualified span.
            let candidateBlockStartIndex =
                events.count - (qualifiedBlockCount + 1) * cycleLength
            let followingBlockStartIndex = candidateBlockStartIndex + cycleLength

            // Every consecutive gap from the candidate block's first event
            // through the following block's events (the rest of the span was
            // already validated on earlier iterations).
            var everyConsecutiveGapIsTight = true
            let spanEndIndex = followingBlockStartIndex + cycleLength
            for eventIndex in candidateBlockStartIndex..<(spanEndIndex - 1) {
                let gap = events[eventIndex + 1].occurredAt
                    .timeIntervalSince(events[eventIndex].occurredAt)
                if gap > configuration.maximumSecondsBetweenConsecutiveActions {
                    everyConsecutiveGapIsTight = false
                    break
                }
            }
            guard everyConsecutiveGapIsTight else { break }

            qualifiedBlockCount += 1
        }
        return qualifiedBlockCount
    }

    /// How many consecutive equal blocks of `cycleLength` sit at the tail of
    /// `shapes` (always ≥ 1 when shapes is non-empty).
    private nonisolated static func tailRepetitionCount(
        of cycleLength: Int,
        in shapes: [WorkflowActionShape]
    ) -> Int {
        guard cycleLength >= 1, shapes.count >= cycleLength else { return 0 }
        let tailBlock = Array(shapes[(shapes.count - cycleLength)..<shapes.count])

        var repetitionCount = 1
        var blockEndIndex = shapes.count - cycleLength
        while blockEndIndex - cycleLength >= 0 {
            let precedingBlock = Array(shapes[(blockEndIndex - cycleLength)..<blockEndIndex])
            if precedingBlock == tailBlock {
                repetitionCount += 1
                blockEndIndex -= cycleLength
            } else {
                break
            }
        }
        return repetitionCount
    }

    /// For the `repetitionCount` blocks of length `cycleLength` at the tail,
    /// check whether any content-bearing position carries differing hashes
    /// across the blocks. A position with a `nil` hash in every block does not
    /// count; identical hashes everywhere => no variation (the ⌘C-twice case).
    private nonisolated static func didContentVaryAcrossRepetitions(
        events: [SemanticInputEvent],
        cycleLength: Int,
        repetitionCount: Int
    ) -> Bool {
        let totalEventsInRepetitions = cycleLength * repetitionCount
        let firstBlockStartIndex = events.count - totalEventsInRepetitions

        for positionWithinCycle in 0..<cycleLength {
            var observedHashesAtPosition: [String] = []
            var sawAnyContentAtPosition = false

            for blockIndex in 0..<repetitionCount {
                let eventIndex = firstBlockStartIndex + blockIndex * cycleLength + positionWithinCycle
                if let hash = events[eventIndex].contentHash {
                    sawAnyContentAtPosition = true
                    observedHashesAtPosition.append(hash)
                }
            }

            if sawAnyContentAtPosition && Set(observedHashesAtPosition).count > 1 {
                return true
            }
        }

        return false
    }

    /// A rotation-invariant identity for a cycle: the lexicographically-smallest
    /// rotation of its shapes. `copy→paste→click`, `paste→click→copy`, and
    /// `click→copy→paste` all map to the same key, so a single underlying
    /// workflow is recognized as one pattern no matter where the window's tail
    /// happens to fall.
    nonisolated static func rotationInvariantKey(
        of shapes: WorkflowActionShapeSequence
    ) -> WorkflowActionShapeSequence {
        let count = shapes.count
        guard count > 1 else { return shapes }

        func encodeRotation(startingAt startIndex: Int) -> String {
            (0..<count)
                .map { encodeShape(shapes[(startIndex + $0) % count]) }
                .joined(separator: "|")
        }

        var bestStartIndex = 0
        var bestEncoding = encodeRotation(startingAt: 0)
        for startIndex in 1..<count {
            let encoding = encodeRotation(startingAt: startIndex)
            if encoding < bestEncoding {
                bestEncoding = encoding
                bestStartIndex = startIndex
            }
        }
        return (0..<count).map { shapes[(bestStartIndex + $0) % count] }
    }

    private nonisolated static func encodeShape(_ shape: WorkflowActionShape) -> String {
        [
            shape.applicationBundleIdentifier,
            shape.actionType.rawValue,
            shape.targetAccessibilityRole ?? "",
            shape.targetAccessibilityLabel ?? "",
        ].joined(separator: "#")
    }

    /// A stable, on-disk-safe String identity for a cycle, used as the key in
    /// the persistent dismissal store. Built from the rotation-invariant key so
    /// a cycle and its phase-shifted forms persist as one pattern; reuses the
    /// same `encodeShape` encoding as the session-only key.
    nonisolated static func persistentDismissalKey(
        for shapes: WorkflowActionShapeSequence
    ) -> String {
        rotationInvariantKey(of: shapes).map(encodeShape).joined(separator: "|")
    }

    private nonisolated static func distinctApplications(
        in shapeSequence: WorkflowActionShapeSequence
    ) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for shape in shapeSequence where seen.insert(shape.applicationBundleIdentifier).inserted {
            ordered.append(shape.applicationBundleIdentifier)
        }
        return ordered
    }

    /// The quiet first line shown in the notch offer (step 1). Intentionally
    /// short and casual — it must NOT spell out the steps; that's the
    /// restatement's job once the user says yes. When a committing action
    /// carries a clear label (e.g. a button "Add") we hint at the task, else we
    /// stay generic. The LLM produces a nicer line once the offer is accepted.
    nonisolated static func composeOfferLine(
        for shapeSequence: WorkflowActionShapeSequence
    ) -> String {
        // A button label ("Add") describes the task better than a field label
        // ("Recipient"), so prefer a click target; fall back to any committing
        // action's label, then to a fully generic line.
        let clickLabel = shapeSequence
            .first(where: { $0.actionType == .click && $0.targetAccessibilityLabel != nil })?
            .targetAccessibilityLabel
        let committingLabel = shapeSequence
            .first(where: { $0.actionType.isCommittingAction && $0.targetAccessibilityLabel != nil })?
            .targetAccessibilityLabel
        if let label = clickLabel ?? committingLabel {
            return "looks like you're hitting '\(label)' for each one — want me to help out?"
        }
        return "looks like you're doing this for each one — want me to help out?"
    }

    /// The detailed step-by-step restatement (step 2 — the trust step). The LLM
    /// produces a nicer one; this is the immediate fallback.
    nonisolated static func composeStepByStepRestatement(
        for shapeSequence: WorkflowActionShapeSequence
    ) -> String {
        let steps = shapeSequence.map { $0.humanReadablePhrase }
        switch steps.count {
        case 0:
            return "repeat the same steps for each one."
        case 1:
            return steps[0] + "."
        default:
            return steps.dropLast().joined(separator: ", ") + ", then " + steps[steps.count - 1] + "."
        }
    }
}
