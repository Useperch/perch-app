//
//  WorkflowCaptureManager.swift
//  leanring-buddy
//
//  Owns the Workflows capture pipeline: it pulls normalized events from a
//  WorkflowEventSource, feeds them through the local RepetitionDetector, and
//  publishes a WorkflowOffer for the UI when the detector spots manual
//  iteration. CompanionManager holds one of these; the notch offer surface
//  observes `currentOffer`.
//
//  It depends only on the WorkflowEventSource *protocol*, so the entire
//  pipeline is exercised in tests with a MockEventSource — no CGEvent tap, no
//  Accessibility grant. Swapping in LiveEventSource at app startup is the only
//  difference in production.
//
//  This file is deliberately AppKit-free.
//

import Combine
import Foundation

@MainActor
final class WorkflowCaptureManager: ObservableObject {

    /// The offer currently awaiting the user's answer, or `nil`. The notch
    /// offer surface renders this; clearing it dismisses the surface.
    @Published private(set) var currentOffer: WorkflowOffer?

    /// Whether the capture pipeline is actively observing input.
    @Published private(set) var isCapturing = false

    private let eventSource: WorkflowEventSource
    private let repetitionDetector: RepetitionDetector

    init(
        eventSource: WorkflowEventSource,
        repetitionDetector: RepetitionDetector? = nil
    ) {
        self.eventSource = eventSource
        // Constructed here rather than as a default argument: RepetitionDetector
        // is @MainActor, and default-argument expressions evaluate in a
        // nonisolated context under Swift concurrency. The production detector
        // gets the real dismissal store so "Not now" persists across runs; the
        // CLI harness and tests inject their own detector instead.
        self.repetitionDetector = repetitionDetector
            ?? RepetitionDetector(dismissedPatternStore: .standard())
    }

    // MARK: - Lifecycle

    func startCapturing() {
        guard !isCapturing else { return }
        isCapturing = true
        eventSource.start { [weak self] event in
            // The live tap delivers on the main run loop and the mock delivers
            // synchronously; either way we hop to the main actor explicitly so
            // the @Published mutation is always isolated correctly.
            MainActor.assumeIsolated {
                self?.handleObservedEvent(event)
            }
        }
    }

    func stopCapturing() {
        guard isCapturing else { return }
        eventSource.stop()
        isCapturing = false
        // A pause means a recording or an agent run is taking over. The events
        // gathered so far belong to the user's pre-run activity — drop them, or
        // the first event after resume completes the stale cycle and fires a
        // phantom offer right under the finished surface.
        repetitionDetector.resetRollingWindow()
    }

    // MARK: - Event handling

    private func handleObservedEvent(_ event: SemanticInputEvent) {
        // Unlabeled clicks are pure noise for repetition matching: the live tap
        // can't ground them in an element (label is always nil), the user clicks
        // a variable number of times per iteration, and the click→app
        // attribution races the app switch (the same "click the Excel cell"
        // lands as Safari one iteration and Excel the next) — which breaks
        // cycle tiling. Clicks with a real label (e.g. an "Add" button) still
        // count; they ARE the workflow's committing action.
        if event.actionType == .click && event.targetAccessibilityLabel == nil { return }

        // Don't stack a new offer on top of one the user hasn't answered yet.
        guard currentOffer == nil else { return }
        if let offer = repetitionDetector.ingest(event) {
            WorkflowDebugLog.log(
                "🎯 OFFER FIRED — reps=\(offer.observedRepetitionCount) "
                    + "apps=\(offer.involvedApplicationBundleIdentifiers.joined(separator: ",")) "
                    + "line=\"\(offer.offerLine)\""
            )
            currentOffer = offer
        }
    }

    // MARK: - User responses to the offer

    /// The user accepted ("Yes"). Clears the surface; the caller proceeds to run
    /// the remaining iterations.
    func acceptCurrentOffer() {
        guard let offer = currentOffer else { return }
        repetitionDetector.recordOfferAccepted(offer)
        WorkflowDebugLog.log("offer accepted")
        currentOffer = nil
    }

    /// The offer surface was hidden without an answer (incidental click
    /// elsewhere, or another notch surface displaced it). The pattern stays
    /// offerable — continued iteration re-fires.
    func deferCurrentOffer() {
        guard let offer = currentOffer else { return }
        repetitionDetector.recordOfferDeferred(offer)
        WorkflowDebugLog.log("offer deferred (unanswered) — pattern stays offerable")
        currentOffer = nil
    }

    /// The user dismissed ("Not now"). Suppresses this pattern for the rest of
    /// the session.
    func dismissCurrentOffer() {
        guard let offer = currentOffer else { return }
        repetitionDetector.recordOfferDismissed(offer)
        WorkflowDebugLog.log("offer dismissed (Not now) — pattern suppressed")
        currentOffer = nil
    }
}
