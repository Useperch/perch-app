//
//  WorkflowScheduler.swift
//  Perch
//
//  Fires saved workflow repeat-schedules: one repeating 30-second Timer
//  checks every schedule for due-ness and hands a due playbook to
//  WorkflowRunCoordinator.runStoredPlaybook (origin .schedule, so the
//  finished surface shows no follow-up buttons).
//
//  Policies (kept deliberately simple):
//  - Due-ness anchors on `lastFiredAt`, so a machine asleep through several
//    slots fires exactly once on wake — never a backfill loop.
//  - If Perch is busy (a demonstration, another run, or an undismissed
//    finished surface), the schedule is SKIPPED without marking fired; the
//    next tick retries, so it runs as soon as Perch is free.
//  - A schedule whose playbook file was deleted removes itself.
//
//  Owned by CompanionManager (started in start(), stopped in stop()).
//

import Foundation

@MainActor
final class WorkflowScheduler {

    static let tickIntervalSeconds: TimeInterval = 30

    private let scheduleStore: WorkflowScheduleStore
    private let playbookStore: WorkflowPlaybookStore
    private let workflowRunCoordinator: WorkflowRunCoordinator
    private var tickTimer: Timer?

    init(
        scheduleStore: WorkflowScheduleStore,
        workflowRunCoordinator: WorkflowRunCoordinator,
        playbookStore: WorkflowPlaybookStore = .standard()
    ) {
        self.scheduleStore = scheduleStore
        self.workflowRunCoordinator = workflowRunCoordinator
        self.playbookStore = playbookStore
    }

    func start() {
        guard tickTimer == nil else { return }
        let timer = Timer(
            timeInterval: Self.tickIntervalSeconds, repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fireDueSchedules(now: Date())
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    /// Checks every schedule and starts AT MOST one run (the coordinator can
    /// only run one playbook at a time anyway); other due schedules retry on
    /// the next tick.
    func fireDueSchedules(now: Date) {
        for schedule in scheduleStore.schedules {
            let dueAnchor = schedule.lastFiredAt ?? schedule.createdAt
            let dueDate = schedule.nextFireDate(after: dueAnchor)
            guard dueDate <= now else { continue }

            let playbookFileURL = playbookStore.fileURL(forSlug: schedule.playbookSlug)
            guard FileManager.default.fileExists(atPath: playbookFileURL.path) else {
                WorkflowDebugLog.log(
                    "scheduler: playbook '\(schedule.playbookSlug)' deleted — removing schedule"
                )
                scheduleStore.remove(scheduleId: schedule.id)
                continue
            }

            guard workflowRunCoordinator.state == .idle else {
                WorkflowDebugLog.log(
                    "scheduler: '\(schedule.playbookSlug)' due but Perch is busy — retrying next tick"
                )
                return
            }

            WorkflowDebugLog.log(
                "scheduler: firing '\(schedule.playbookSlug)' (\(schedule.humanReadableDescription))"
            )
            scheduleStore.markFired(scheduleId: schedule.id, at: now)
            workflowRunCoordinator.runStoredPlaybook(
                slug: schedule.playbookSlug, origin: .schedule
            )
            return
        }
    }
}
