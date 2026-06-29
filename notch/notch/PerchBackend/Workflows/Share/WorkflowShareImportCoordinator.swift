//
//  WorkflowShareImportCoordinator.swift
//  leanring-buddy
//
//  The receiving side of "Send this workflow": handles a `perch://import/<id>`
//  URL (delivered when the user clicks "Open in Perch" on the share landing
//  page), fetches the playbook from the Worker with the Perch secret header,
//  and publishes an incoming-share state that NotchPanelManager renders as an
//  offer surface ("Run it" / "Save for later") — a shared workflow is never
//  auto-run on someone's machine.
//
//  Owned by CompanionManager; runs route through
//  WorkflowRunCoordinator.runStoredPlaybook with origin .importedShare so the
//  finished surface shows no follow-up buttons.
//

import Combine
import Foundation

@MainActor
final class WorkflowShareImportCoordinator: ObservableObject {

    /// The incoming-share surface's phases. `.none` means no surface.
    enum IncomingShareState: Equatable {
        case none
        /// Fetching the playbook — shown immediately so the "Open in Perch"
        /// click never feels dead (an LSUIElement app gives no dock feedback).
        case fetching
        /// Fetched — offer to run or save.
        case offer(IncomingSharedWorkflow)
        /// Saved without running — brief confirmation, then auto-clears.
        case saved(title: String)
        case fetchFailed(message: String)
    }

    @Published private(set) var incomingShareState: IncomingShareState = .none

    private let workflowShareClient: WorkflowShareClient
    private let playbookStore: WorkflowPlaybookStore
    private let workflowRunCoordinator: WorkflowRunCoordinator
    private var fetchTask: Task<Void, Never>?

    init(
        workflowRunCoordinator: WorkflowRunCoordinator,
        workflowShareClient: WorkflowShareClient = WorkflowShareClient(),
        playbookStore: WorkflowPlaybookStore = .standard()
    ) {
        self.workflowRunCoordinator = workflowRunCoordinator
        self.workflowShareClient = workflowShareClient
        self.playbookStore = playbookStore
    }

    /// Entry point for every URL the app is opened with. Non-share URLs are
    /// ignored (the app registers only the `perch` scheme, but stay safe).
    func handleIncomingURL(_ url: URL) {
        guard let shareId = WorkflowShareImportURL.parseWorkflowShareId(fromImportURL: url) else {
            WorkflowDebugLog.log("share-import: ignored unrecognized URL \(url.absoluteString)")
            return
        }
        WorkflowDebugLog.log("share-import: fetching shared workflow \(shareId)")
        fetchTask?.cancel()
        incomingShareState = .fetching
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let incomingWorkflow = try await self.workflowShareClient
                    .fetchSharedPlaybook(shareId: shareId)
                self.incomingShareState = .offer(incomingWorkflow)
            } catch {
                self.incomingShareState = .fetchFailed(message: error.localizedDescription)
                WorkflowDebugLog.log("share-import: fetch FAILED — \(error.localizedDescription)")
            }
        }
    }

    /// "Run it": persist the playbook locally, then hand it to the run
    /// coordinator like any stored playbook.
    func runIncomingWorkflow() {
        guard case .offer(let incomingWorkflow) = incomingShareState else { return }
        do {
            let savedPlaybook = try playbookStore.save(
                markdown: incomingWorkflow.markdown, title: incomingWorkflow.title
            )
            incomingShareState = .none
            WorkflowDebugLog.log("share-import: running imported playbook '\(savedPlaybook.slug)'")
            workflowRunCoordinator.runStoredPlaybook(
                slug: savedPlaybook.slug, origin: .importedShare
            )
        } catch {
            incomingShareState = .fetchFailed(
                message: "I couldn't save that workflow: \(error.localizedDescription)"
            )
        }
    }

    /// "Save for later": persist only; the playbook is runnable from disk
    /// (and schedulable) later.
    func saveIncomingWorkflowForLater() {
        guard case .offer(let incomingWorkflow) = incomingShareState else { return }
        do {
            let savedPlaybook = try playbookStore.save(
                markdown: incomingWorkflow.markdown, title: incomingWorkflow.title
            )
            incomingShareState = .saved(title: savedPlaybook.title)
            WorkflowDebugLog.log("share-import: saved imported playbook '\(savedPlaybook.slug)'")
            // Let the confirmation linger briefly, then clear the surface.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, case .saved = self.incomingShareState else { return }
                self.incomingShareState = .none
            }
        } catch {
            incomingShareState = .fetchFailed(
                message: "I couldn't save that workflow: \(error.localizedDescription)"
            )
        }
    }

    /// "Not now" / click-outside — nothing is saved.
    func dismissIncomingWorkflow() {
        fetchTask?.cancel()
        incomingShareState = .none
    }
}
