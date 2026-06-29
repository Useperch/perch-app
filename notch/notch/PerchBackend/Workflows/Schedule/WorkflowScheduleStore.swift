//
//  WorkflowScheduleStore.swift
//  leanring-buddy
//
//  Persists workflow repeat-schedules as JSON at
//  ~/Library/Application Support/Perch/workflow-schedules.json — the same
//  small append-mostly pattern as AgentRunHistoryStore. The storage file is
//  injectable so the CLI harness can round-trip into a temp dir.
//
//  Deliberately NOT @MainActor / ObservableObject: nothing renders the
//  schedule list in v1, the only consumers are the scheduler tick and the
//  schedule surface's confirm handler (both main-actor), and staying plain
//  lets the pure-logic harness compile it without a concurrency runtime.
//

import Foundation

final class WorkflowScheduleStore {

    private(set) var schedules: [WorkflowSchedule]

    private let storageFileURL: URL

    init(storageFileURL: URL) {
        self.storageFileURL = storageFileURL
        self.schedules = Self.loadSchedules(from: storageFileURL)
    }

    /// The app's real schedule file.
    static func standard() -> WorkflowScheduleStore {
        return WorkflowScheduleStore(
            storageFileURL: PerchSupportPaths.file("workflow-schedules.json")
        )
    }

    func add(_ schedule: WorkflowSchedule) {
        schedules = schedules + [schedule]
        persist()
    }

    func remove(scheduleId: UUID) {
        schedules = schedules.filter { $0.id != scheduleId }
        persist()
    }

    /// Advances the schedule's fired-anchor so due-ness is computed from the
    /// run that just started.
    func markFired(scheduleId: UUID, at firedAt: Date) {
        schedules = schedules.map { schedule in
            schedule.id == scheduleId ? schedule.markingFired(at: firedAt) : schedule
        }
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        do {
            let directoryURL = storageFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let encodedSchedules = try encoder.encode(schedules)
            try encodedSchedules.write(to: storageFileURL, options: .atomic)
        } catch {
            print("⚠️ WorkflowScheduleStore: failed to persist schedules: \(error)")
        }
    }

    private static func loadSchedules(from fileURL: URL) -> [WorkflowSchedule] {
        guard let storedData = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([WorkflowSchedule].self, from: storedData)
        } catch {
            print("⚠️ WorkflowScheduleStore: failed to decode stored schedules: \(error)")
            return []
        }
    }
}
