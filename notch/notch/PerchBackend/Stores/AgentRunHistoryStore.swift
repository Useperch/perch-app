//
//  AgentRunHistoryStore.swift
//  leanring-buddy
//
//  Persists completed browser-subagent runs so the notch panel's Agents tab
//  can show a history of past agent work (matching HeyPerch's colored agent
//  cards). Stored as JSON in Application Support — small, append-mostly data.
//

import Foundation

/// One completed (or failed) background browser-agent run, or a completed
/// desktop workflow run (which additionally carries its playbook slug so the
/// Agents tab card can offer Schedule / Send).
struct AgentRunRecord: Codable, Identifiable, Equatable {
    let id: UUID
    /// The task Perch was asked to do, e.g. "create a Figma mockup".
    let taskDescription: String
    /// Short wrap-up summary spoken/shown when the run finished.
    let resultSummary: String
    /// Where the handoff window landed, if anywhere.
    let finalUrlString: String?
    let completedAt: Date
    /// Index into the agent-card tint rotation (navy/green/maroon).
    let tintIndex: Int
    let didSucceed: Bool
    /// Set only for desktop workflow runs: the persisted playbook's slug,
    /// enabling the card's Schedule / Send actions. Optional so records
    /// saved before this field existed still decode.
    let workflowPlaybookSlug: String?
    /// A short noun for the artifact this run created ("Google Doc", "Figma file"),
    /// paired with `finalUrlString` so the card can label the deliverable link
    /// instead of the generic "Open Agent". Optional so older records still decode.
    let deliverableLabel: String?
}

/// Loads and saves the agent run history. All access is main-actor because the
/// only consumers are SwiftUI views and CompanionManager.
@MainActor
final class AgentRunHistoryStore: ObservableObject {

    @Published private(set) var runs: [AgentRunRecord] = []

    private static let maximumStoredRuns = 50

    private let storageFileURL: URL

    init() {
        storageFileURL = PerchSupportPaths.file("agent-runs.json")
        runs = Self.loadRuns(from: storageFileURL)
    }

    /// Appends a finished run and persists. Newest runs are kept first.
    /// `workflowPlaybookSlug` is set only for desktop workflow runs.
    func recordRun(
        taskDescription: String,
        resultSummary: String,
        finalUrl: URL?,
        didSucceed: Bool,
        workflowPlaybookSlug: String? = nil,
        deliverableLabel: String? = nil
    ) {
        let record = AgentRunRecord(
            id: UUID(),
            taskDescription: taskDescription,
            resultSummary: resultSummary,
            finalUrlString: finalUrl?.absoluteString,
            completedAt: Date(),
            tintIndex: runs.count % 3,
            didSucceed: didSucceed,
            workflowPlaybookSlug: workflowPlaybookSlug,
            deliverableLabel: deliverableLabel
        )
        var updatedRuns = [record] + runs
        if updatedRuns.count > Self.maximumStoredRuns {
            updatedRuns = Array(updatedRuns.prefix(Self.maximumStoredRuns))
        }
        runs = updatedRuns
        persist()
    }

    /// Removes a run from history (the card's X button) and persists.
    func deleteRun(id runId: UUID) {
        let updatedRuns = runs.filter { $0.id != runId }
        guard updatedRuns.count != runs.count else { return }
        runs = updatedRuns
        persist()
    }

    // MARK: - Date sectioning (YESTERDAY / THIS WEEK / EARLIER groups)

    struct RunSection: Identifiable {
        let id: String
        let title: String
        let runs: [AgentRunRecord]
    }

    /// Groups runs into the date buckets the Agents tab renders as small-caps
    /// section headers, newest bucket first.
    var dateSections: [RunSection] {
        let calendar = Calendar.current
        var todayRuns: [AgentRunRecord] = []
        var yesterdayRuns: [AgentRunRecord] = []
        var thisWeekRuns: [AgentRunRecord] = []
        var earlierRuns: [AgentRunRecord] = []

        for run in runs {
            if calendar.isDateInToday(run.completedAt) {
                todayRuns.append(run)
            } else if calendar.isDateInYesterday(run.completedAt) {
                yesterdayRuns.append(run)
            } else if calendar.isDate(run.completedAt, equalTo: Date(), toGranularity: .weekOfYear) {
                thisWeekRuns.append(run)
            } else {
                earlierRuns.append(run)
            }
        }

        var sections: [RunSection] = []
        if !todayRuns.isEmpty { sections.append(RunSection(id: "today", title: "TODAY", runs: todayRuns)) }
        if !yesterdayRuns.isEmpty { sections.append(RunSection(id: "yesterday", title: "YESTERDAY", runs: yesterdayRuns)) }
        if !thisWeekRuns.isEmpty { sections.append(RunSection(id: "thisWeek", title: "THIS WEEK", runs: thisWeekRuns)) }
        if !earlierRuns.isEmpty { sections.append(RunSection(id: "earlier", title: "EARLIER", runs: earlierRuns)) }
        return sections
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
            let encodedRuns = try encoder.encode(runs)
            try encodedRuns.write(to: storageFileURL, options: .atomic)
        } catch {
            print("⚠️ AgentRunHistoryStore: failed to persist runs: \(error)")
        }
    }

    private static func loadRuns(from fileURL: URL) -> [AgentRunRecord] {
        guard let storedData = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([AgentRunRecord].self, from: storedData)
        } catch {
            print("⚠️ AgentRunHistoryStore: failed to decode stored runs: \(error)")
            return []
        }
    }
}
