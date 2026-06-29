//
//  NotchAlertIngestionService.swift
//  notch
//
//  Polls connected integrations for raw alert candidates and hands them to the
//  coordinator for agent evaluation. Read-only — never actuates.
//

import Foundation

@MainActor
final class NotchAlertIngestionService {

    private static let pollIntervalSeconds: TimeInterval = 180
    /// Hard cap for calendar/eventkit candidates — only near-term starts are notch-worthy.
    private static let maxCalendarAlertLeadMinutes = 20
    private static let upcomingEventWindowMinutes = maxCalendarAlertLeadMinutes
    /// When a calendar event is this close, it owns the poll — no email dilution.
    private static let urgentMeetingWindowMinutes = maxCalendarAlertLeadMinutes

    private let coordinator: NotchAlertCoordinator
    private let dataService: DashboardDataService
    private let manifestReader: ComposioManifestReader
    private let focusMonitor: SystemFocusStatusMonitor

    private var pollTask: Task<Void, Never>?

    init(
        coordinator: NotchAlertCoordinator,
        dataService: DashboardDataService = .shared,
        manifestReader: ComposioManifestReader = .standard(),
        focusMonitor: SystemFocusStatusMonitor
    ) {
        self.coordinator = coordinator
        self.dataService = dataService
        self.manifestReader = manifestReader
        self.focusMonitor = focusMonitor
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.pollOnce()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.pollIntervalSeconds))
                guard !Task.isCancelled else { return }
                await self.pollOnce()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func pollOnce() async {
        guard !focusMonitor.isFocusActive else { return }

        let candidates = await gatherCandidates()
        guard !candidates.isEmpty else { return }

        await coordinator.ingestAndEvaluate(candidates: candidates)
    }

    private func gatherCandidates() async -> [NotchAlertCandidate] {
        let eventKitCandidates = await nativeEventKitCandidates()
        if let urgentMeeting = eventKitCandidates.first(where: isUrgentMeetingCandidate) {
            NSLog("[NotchAlert] urgent meeting candidate: \(urgentMeeting.title)")
            return [urgentMeeting]
        }

        var candidates: [NotchAlertCandidate] = []
        let manifest = manifestReader.currentState()
        let connectedSlugs = manifest.connectedToolkitSlugs

        if connectedSlugs.contains("gmail") {
            let emailPlan = DashboardWidgetFetchPlan(
                provider: .email,
                query: "is:important is:unread newer_than:1d",
                limit: 5,
                refreshCadenceSeconds: 180
            )
            let emailItems = await dataService.fetch(plan: emailPlan)
            candidates.append(contentsOf: emailItems.map { item in
                NotchAlertCandidate(
                    sourceFingerprint: "email|\(item.id)",
                    provider: "email",
                    title: item.title,
                    subtitle: item.subtitle,
                    detail: item.detail,
                    url: item.url,
                    timestamp: item.timestamp.map { ISO8601DateFormatter().string(from: $0) },
                    calendarName: nil
                )
            })
        }

        if connectedSlugs.contains("googlecalendar") {
            let calendarPlan = DashboardWidgetFetchPlan(
                provider: .calendar,
                query: "",
                limit: 8,
                refreshCadenceSeconds: 180
            )
            let calendarItems = await dataService.fetch(plan: calendarPlan)
            candidates.append(contentsOf: calendarItems.map { item in
                NotchAlertCandidate(
                    sourceFingerprint: "calendar|\(item.id)",
                    provider: "calendar",
                    title: item.title,
                    subtitle: item.subtitle,
                    detail: item.detail,
                    url: item.url,
                    timestamp: item.timestamp.map { ISO8601DateFormatter().string(from: $0) },
                    calendarName: nil
                )
            })
        }

        candidates.append(contentsOf: eventKitCandidates)

        var seenFingerprints = Set<String>()
        return candidates.filter { candidate in
            guard !seenFingerprints.contains(candidate.sourceFingerprint) else { return false }
            seenFingerprints.insert(candidate.sourceFingerprint)
            guard passesUrgencyGate(candidate) else { return false }
            return true
        }
    }

    /// Calendar items must start within the hard lead window; email/other providers
    /// still go through the agent evaluator.
    private func passesUrgencyGate(_ candidate: NotchAlertCandidate) -> Bool {
        let calendarProviders: Set<String> = ["eventkit", "calendar"]
        guard calendarProviders.contains(candidate.provider) else { return true }

        guard let timestamp = candidate.timestamp,
              let startDate = ISO8601DateFormatter().date(from: timestamp)
        else { return false }

        let minutesUntilStart = startDate.timeIntervalSinceNow / 60.0
        return minutesUntilStart >= 0
            && minutesUntilStart <= Double(Self.maxCalendarAlertLeadMinutes)
    }

    private func nativeEventKitCandidates() async -> [NotchAlertCandidate] {
        let calendarManager = CalendarManager.shared
        await calendarManager.checkCalendarAuthorization()
        await calendarManager.updateCurrentDate(Date.now)

        let now = Date()
        guard let windowEnd = Calendar.current.date(
            byAdding: .minute,
            value: Self.upcomingEventWindowMinutes,
            to: now
        ) else { return [] }

        let eventStartTimeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter
        }()

        let upcomingEvents = calendarManager.events
            .filter { event in
                event.start >= now && event.start <= windowEnd && !event.isAllDay
            }
            .sorted(by: { $0.start < $1.start })

        guard let nearestUpcomingEvent = upcomingEvents.first else { return [] }

        return [nearestUpcomingEvent].map { event in
                let startTimeLabel = eventStartTimeFormatter.string(from: event.start)
                let meetingDetail = event.isMeeting
                    ? "Meeting with \(event.participants.count) participant(s)"
                    : event.location
                return NotchAlertCandidate(
                    sourceFingerprint: "eventkit|\(event.id)",
                    provider: "eventkit",
                    title: event.title,
                    subtitle: startTimeLabel,
                    detail: meetingDetail ?? event.notes,
                    url: event.url?.absoluteString,
                    timestamp: ISO8601DateFormatter().string(from: event.start),
                    calendarName: event.calendar.title
                )
            }
    }

    private func isUrgentMeetingCandidate(_ candidate: NotchAlertCandidate) -> Bool {
        guard candidate.provider == "eventkit",
              let timestamp = candidate.timestamp,
              let startDate = ISO8601DateFormatter().date(from: timestamp)
        else { return false }

        let minutesUntilStart = startDate.timeIntervalSinceNow / 60.0
        return minutesUntilStart >= 0
            && minutesUntilStart <= Double(Self.urgentMeetingWindowMinutes)
    }
}