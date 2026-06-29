//
//  NotchAlertCoordinator.swift
//  notch
//
//  Policy brain for notch alerts: decides when an evaluated alert may appear,
//  owns dismiss/snooze state, and exposes the single alert the open-notch UI
//  renders. Modeled on ServiceConnectionOfferCoordinator.
//

import Combine
import Foundation

@MainActor
protocol NotchAlertEvaluating: AnyObject {
    func sendNotchAlertEvaluate(
        candidates: [NotchAlertCandidate],
        dismissedFingerprints: [String]
    ) async throws -> NotchAlert?
}

@MainActor
final class NotchAlertCoordinator: ObservableObject {

    static let maxAlertsPerSession = 3

    @Published private(set) var currentAlert: NotchAlert?

    var isNotchOpen: () -> Bool = { false }
    var isHigherPrioritySurfaceVisible: () -> Bool = { false }
    var isVoiceActive: () -> Bool = { false }
    var isFocusActive: () -> Bool = { false }

    private let dismissedStore: DismissedNotchAlertsStore
    private let evaluator: NotchAlertEvaluating

    private var alertsShownThisSession = 0

    init(
        dismissedStore: DismissedNotchAlertsStore,
        evaluator: NotchAlertEvaluating
    ) {
        self.dismissedStore = dismissedStore
        self.evaluator = evaluator
    }

    func ingestAndEvaluate(candidates: [NotchAlertCandidate]) async {
        guard !isFocusActive() else { return }
        guard !candidates.isEmpty else { return }
        // One alert at a time — ignore new candidates while something is showing.
        guard currentAlert == nil else { return }

        let filteredCandidates = candidates.filter {
            !dismissedStore.isDismissed($0.sourceFingerprint)
        }
        guard !filteredCandidates.isEmpty else {
            NSLog("[NotchAlert] all candidates dismissed/snoozed")
            return
        }

        do {
            guard let evaluatedAlert = try await evaluator.sendNotchAlertEvaluate(
                candidates: filteredCandidates,
                dismissedFingerprints: dismissedStore.activeDismissedFingerprints()
            ) else {
                NSLog("[NotchAlert] evaluator returned null")
                return
            }

            guard !dismissedStore.isDismissed(evaluatedAlert.sourceFingerprint) else { return }
            presentIfPossible(evaluatedAlert)
        } catch {
            NSLog("[NotchAlert] evaluate failed: \(error.localizedDescription)")
        }
    }

    func dismissCurrentAlert() {
        guard let alert = currentAlert else { return }
        dismissedStore.recordDismissed(alert.sourceFingerprint)
        currentAlert = nil
    }

    /// Hides the current alert without snoozing it — used when macOS Focus/DND
    /// turns on so the same item can surface again after focus ends.
    func clearCurrentAlertForSystemFocus() {
        currentAlert = nil
    }

    func handleActionCompleted() {
        dismissCurrentAlert()
    }

    func refreshPresentation() {
        // No queue — refresh only matters if we later add deferred presentation.
    }

    private var shouldBlockNewAlert: Bool {
        isFocusActive()
            || isVoiceActive()
            || isHigherPrioritySurfaceVisible()
            || alertsShownThisSession >= Self.maxAlertsPerSession
    }

    private func presentIfPossible(_ alert: NotchAlert) {
        if currentAlert?.alertId == alert.alertId { return }
        guard currentAlert == nil else { return }
        guard !shouldBlockNewAlert else {
            NSLog("[NotchAlert] evaluated but blocked (focus/voice/surface/session cap)")
            return
        }

        // Hold the alert even when the notch is closed — UI only renders once open.
        currentAlert = alert
        alertsShownThisSession += 1
    }
}