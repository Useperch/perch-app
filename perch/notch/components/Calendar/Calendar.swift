//
//  Calendar.swift
//  notch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import AppKit
import Defaults
import SwiftUI

struct Config: Equatable {
    //    var count: Int = 10  // 3 days past + today + 7 days future
    var past: Int = 7
    var future: Int = 14
    var steps: Int = 1  // Each step is one day
    var spacing: CGFloat = 0
    var showsText: Bool = true
    var offset: Int = 2  // Number of dates to the left of the selected date
}

enum NotchCalendarDisplayMode {
    case expanded
    case compact
    case notificationCompact
}

private struct NotchCalendarDisplayModeKey: EnvironmentKey {
    static let defaultValue: NotchCalendarDisplayMode = .expanded
}

extension EnvironmentValues {
    var notchCalendarDisplayMode: NotchCalendarDisplayMode {
        get { self[NotchCalendarDisplayModeKey.self] }
        set { self[NotchCalendarDisplayModeKey.self] = newValue }
    }
}

struct WheelPicker: View {
    @Binding var selectedDate: Date
    let config: Config
    /// Compact = events are showing, so the date shrinks to a header. Big when
    /// it's the only thing in the notch.
    var compact: Bool = false
    var displayMode: NotchCalendarDisplayMode = .expanded

    // Drag / scroll state for the resisted carousel.
    @State private var dragResidual: CGFloat = 0   // input past the last committed step
    @State private var dragBaseline: CGFloat = 0   // drag translation at the last step
    @State private var haptics: Bool = false

    private var cal: Calendar { Calendar.current }
    private var baseDay: Date { cal.startOfDay(for: selectedDate) }

    private var isNotificationCompact: Bool { displayMode == .notificationCompact }

    private var numberSize: CGFloat {
        // Notification mode keeps today's date at full expanded size.
        if isNotificationCompact { return 48 }
        return compact ? 36 : 48
    }
    private var weekdaySize: CGFloat {
        if isNotificationCompact { return 11 }
        return compact ? 9 : 11
    }
    private var slot: CGFloat {
        if isNotificationCompact { return 68 }
        return compact ? 60 : 84
    }
    // Pull neighbours close to the big date but leave a small gap so they look
    // like they're about to touch it without actually touching.
    private var neighborTuck: CGFloat {
        if isNotificationCompact { return 58 }
        return compact ? 27 : 39
    }
    private var neighborScale: CGFloat { isNotificationCompact ? 0.5 : 0.6 }
    private var neighborOpacity: CGFloat { 0.4 }
    /// How far you must drag / scroll to flip a day. Bigger = more effort to snap.
    private var stepThreshold: CGFloat { compact ? 94 : 124 }

    /// Resisted visual travel: the strip barely moves near zero and eases toward a
    /// small maximum, so it never tracks the finger 1:1 — that's the resistance.
    private var visualOffset: CGFloat {
        let maxTravel = slot * 0.3
        return maxTravel * CGFloat(tanh(Double(dragResidual) / Double(stepThreshold * 0.85)))
    }

    /// The window of days drawn around the selection (yesterday/today/tomorrow,
    /// plus one hidden on each side so they slide in cleanly).
    private var visibleDates: [Date] {
        (-2...2).compactMap { cal.date(byAdding: .day, value: $0, to: baseDay) }
    }

    var body: some View {
        ZStack {
            ForEach(visibleDates, id: \.self) { date in
                dayCell(date: date)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 56 : 78)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: displayMode)
        .contentShape(Rectangle())
        .highPriorityGesture(dragGesture)
        .background(
            ScrollStepCatcher(
                stepThreshold: stepThreshold,
                onStep: { step($0) },
                onResidual: { dragResidual = $0 },
                onEnd: { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragResidual = 0 } }
            )
        )
        .sensoryFeedback(.alignment, trigger: haptics)
    }

    // MARK: - Gesture (click-drag)

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let raw = value.translation.width
                let past = raw - dragBaseline
                if past >= stepThreshold {
                    step(-1); dragBaseline += stepThreshold        // drag right → previous day
                } else if past <= -stepThreshold {
                    step(+1); dragBaseline -= stepThreshold         // drag left → next day
                }
                dragResidual = raw - dragBaseline
            }
            .onEnded { _ in
                dragBaseline = 0
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { dragResidual = 0 }
            }
    }

    /// Move the selection by `n` days with a snappy pop + haptic.
    private func step(_ n: Int) {
        guard let newDay = cal.date(byAdding: .day, value: n, to: baseDay) else { return }
        withAnimation(.snappy(duration: 0.18, extraBounce: 0.06)) {
            selectedDate = newDay
        }
        haptics.toggle()
    }

    // MARK: - Cell

    private func dayCell(date: Date) -> some View {
        let dayDelta = cal.dateComponents([.day], from: baseDay, to: date).day ?? 0
        let isSelected = dayDelta == 0
        let isNeighbor = abs(dayDelta) == 1
        let isToday = cal.isDateInToday(date)
        let tuck: CGFloat = isSelected ? 0 : (dayDelta < 0 ? neighborTuck : -neighborTuck)
        let cellWeekdaySize: CGFloat = {
            if isNotificationCompact && isNeighbor && !isSelected { return 8 }
            return weekdaySize
        }()
        let cellNumberSize: CGFloat = {
            if isNotificationCompact && isNeighbor && !isSelected { return 17 }
            return numberSize
        }()
        return VStack(spacing: 0) {
            Text(weekdayString(date).uppercased())
                .font(.system(size: cellWeekdaySize, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(isToday ? Color.effectiveAccent : Color(white: 0.55))
            Text("\(cal.component(.day, from: date))")
                .font(.system(size: cellNumberSize, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
        }
        // Today big & sharp; yesterday / tomorrow smaller, greyed, snug beside it;
        // anything further is hidden.
        .scaleEffect(isSelected ? 1.0 : neighborScale)
        .opacity(isSelected ? 1.0 : (isNeighbor ? neighborOpacity : 0))
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: displayMode)
        .blur(radius: isSelected ? 0 : 0.6)
        .offset(x: CGFloat(dayDelta) * slot + tuck + visualOffset)
        .zIndex(isSelected ? 1 : 0)
    }

    private func weekdayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

/// Catches trackpad / mouse-wheel scrolls over the carousel and turns them into
/// the same resisted, threshold-based day steps as the drag gesture.
private struct ScrollStepCatcher: NSViewRepresentable {
    let stepThreshold: CGFloat
    let onStep: (Int) -> Void
    let onResidual: (CGFloat) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.stepThreshold = stepThreshold
        context.coordinator.onStep = onStep
        context.coordinator.onResidual = onResidual
        context.coordinator.onEnd = onEnd
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(stepThreshold: stepThreshold, onStep: onStep, onResidual: onResidual, onEnd: onEnd)
    }

    @MainActor final class Coordinator: NSObject {
        var stepThreshold: CGFloat
        var onStep: (Int) -> Void
        var onResidual: (CGFloat) -> Void
        var onEnd: () -> Void
        private var monitor: Any?
        private var accum: CGFloat = 0
        private var baseline: CGFloat = 0
        private var endTask: Task<Void, Never>?

        init(stepThreshold: CGFloat, onStep: @escaping (Int) -> Void,
             onResidual: @escaping (CGFloat) -> Void, onEnd: @escaping () -> Void) {
            self.stepThreshold = stepThreshold
            self.onStep = onStep
            self.onResidual = onResidual
            self.onEnd = onEnd
        }

        func attach(to view: NSView) {
            detach()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window else { return event }
                let point = view.convert(event.locationInWindow, from: nil)
                if view.bounds.contains(point) { self.handle(event) }
                return event
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            endTask?.cancel()
        }

        private func handle(_ event: NSEvent) {
            // Day stepping is HORIZONTAL only — vertical scroll reveals/hides tasks.
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 6
            accum += event.scrollingDeltaX * scale
            let past = accum - baseline
            if past >= stepThreshold {
                onStep(-1); baseline += stepThreshold
            } else if past <= -stepThreshold {
                onStep(+1); baseline -= stepThreshold
            }
            onResidual(accum - baseline)
            scheduleEnd()
        }

        private func scheduleEnd() {
            endTask?.cancel()
            endTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(130))
                guard !Task.isCancelled else { return }
                accum = 0
                baseline = 0
                onEnd()
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

/// Catches VERTICAL trackpad scrolls over the calendar and toggles the task list:
/// scroll down past the threshold reveals it, scroll up hides it. The threshold
/// gives resistance so it takes a deliberate swipe.
private struct VerticalRevealCatcher: NSViewRepresentable {
    let threshold: CGFloat
    let onToggle: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.threshold = threshold
        context.coordinator.onToggle = onToggle
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(threshold: threshold, onToggle: onToggle)
    }

    @MainActor final class Coordinator: NSObject {
        var threshold: CGFloat
        var onToggle: () -> Void
        private var monitor: Any?
        private var accum: CGFloat = 0
        private var armed = true
        private var resetTask: Task<Void, Never>?

        init(threshold: CGFloat, onToggle: @escaping () -> Void) {
            self.threshold = threshold
            self.onToggle = onToggle
        }

        func attach(to view: NSView) {
            detach()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self, weak view] event in
                guard let self, let view, event.window === view.window else { return event }
                let point = view.convert(event.locationInWindow, from: nil)
                if view.bounds.contains(point) { self.handle(event) }
                return event
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            resetTask?.cancel()
        }

        private func handle(_ event: NSEvent) {
            // Vertical only — horizontal is day stepping. A deliberate vertical
            // swipe (EITHER direction) toggles the task list: reveal when hidden,
            // hide when shown. Direction-agnostic so it works regardless of the
            // trackpad's natural-scrolling setting. One toggle per swipe (re-armed
            // once the scroll goes idle).
            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return }
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 6
            accum += event.scrollingDeltaY * scale
            if armed && abs(accum) >= threshold {
                onToggle()
                armed = false
                accum = 0
            }
            scheduleReset()
        }

        private func scheduleReset() {
            resetTask?.cancel()
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                accum = 0
                armed = true
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

struct CalendarView: View {
    @EnvironmentObject var vm: ViewModel
    @ObservedObject var notchAlertCoordinator: NotchAlertCoordinator
    @Environment(\.notchCalendarDisplayMode) private var notchCalendarDisplayMode
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()
    /// Tasks are hidden by default (just the big date); scrolling down reveals them.
    @State private var tasksRevealed = false

    private var shouldShowDailyBriefButton: Bool {
        !tasksRevealed && notchAlertCoordinator.currentAlert == nil
    }

    var body: some View {
        let filteredEvents = EventListView.filteredEvents(
            events: calendarManager.events
        )
        let hasEvents = !filteredEvents.isEmpty
        VStack(spacing: 0) {
            if calendarManager.calendarAuthorizationStatus != .fullAccess {
                // Calendar access is deferred out of onboarding — until the user
                // grants it, the widget slot shows a connect prompt instead of
                // the (empty) date carousel.
                ConnectPromptCard(
                    icon: Image(systemName: "calendar"),
                    title: "See your schedule in Perch",
                    buttonLabel: "Connect Calendar",
                    onConnect: connectCalendar
                )
            } else if hasEvents && tasksRevealed {
                // Revealed: compact date header + the task list.
                dateCarousel(compact: true)
                EventListView(events: calendarManager.events)
            } else {
                // Default: big date with Daily Brief directly beneath it in this column only.
                Spacer(minLength: 0)
                VStack(spacing: 5) {
                    dateCarousel(compact: false)
                    if shouldShowDailyBriefButton {
                        DailyBriefButton()
                            .padding(.top, 6)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .animation(.snappy(duration: 0.28, extraBounce: 0.08), value: tasksRevealed)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: shouldShowDailyBriefButton)
        .listRowBackground(Color.clear)
        // Connected: fixed 120 so the calendar never stretches the open-HUD row
        // (which was warping the music player's layout). Unconnected: let the
        // "Connect Calendar" card fill the full row height so it centers
        // vertically in line with the music player's "Connect Music" card.
        .frame(
            minHeight: 120,
            maxHeight: calendarManager.calendarAuthorizationStatus == .fullAccess ? 120 : .infinity
        )
        .clipped()
        // Vertical scroll over the calendar toggles the tasks (reveal ⇄ hide).
        .background(
            VerticalRevealCatcher(threshold: 44) {
                if tasksRevealed {
                    withAnimation(.snappy(duration: 0.3, extraBounce: 0.12)) { tasksRevealed = false }
                } else if hasEvents {
                    withAnimation(.snappy(duration: 0.3, extraBounce: 0.12)) { tasksRevealed = true }
                }
            }
        )
        .onChange(of: selectedDate) {
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onChange(of: vm.notchState) { _, _ in
            // Default back to just the big date whenever the notch opens/closes.
            tasksRevealed = false
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
        .onAppear {
            Task {
                // Read (don't request) Calendar access so an unconnected user
                // sees the "Connect Calendar" prompt instead of an automatic
                // system dialog; when already granted, load today's events.
                await calendarManager.refreshCalendarAuthorization()
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
    }

    /// Runs the calendar connect prompt's button. Not-yet-asked → trigger the
    /// macOS permission request (which updates `calendarAuthorizationStatus`, so
    /// the card swaps to real events on grant). Previously denied → macOS won't
    /// re-prompt, so open the Privacy pane instead.
    private func connectCalendar() {
        switch calendarManager.calendarAuthorizationStatus {
        case .denied, .restricted:
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
            ) {
                NSWorkspace.shared.open(url)
            }
        default:
            Task { await calendarManager.checkCalendarAuthorization() }
        }
    }

    /// The full-width day carousel with black edge-fades so off-centre days
    /// dissolve at the sides. `compact` shrinks the date into a header when
    /// events are shown beneath it.
    private func dateCarousel(compact: Bool) -> some View {
        let wheelDisplayMode: NotchCalendarDisplayMode = {
            if notchCalendarDisplayMode == .notificationCompact { return .notificationCompact }
            return compact ? .compact : .expanded
        }()
        return ZStack(alignment: .top) {
            WheelPicker(
                selectedDate: $selectedDate,
                config: Config(),
                compact: compact,
                displayMode: wheelDisplayMode
            )
            // Notification mode keeps yesterday/tomorrow legible — skip the side fades.
            if wheelDisplayMode != .notificationCompact {
                HStack(alignment: .top) {
                    LinearGradient(
                        colors: [Color.black, .clear], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 28)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.black], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: 28)
                }
                .allowsHitTesting(false)
            }
        }
        // Hug the carousel's own height so the surrounding Spacers can centre it.
        .frame(height: compact ? 56 : 78)
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    let events: [EventModel]
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @Default(.showFullEventTitles) private var showFullEventTitles


    static func filteredEvents(events: [EventModel]) -> [EventModel] {
        events.filter { event in
            // Filter out all-day events if setting is enabled
            if event.isAllDay && Defaults[.hideAllDayEvents] {
                return false
            }
            return true
        }
    }

    private var filteredEvents: [EventModel] {
        Self.filteredEvents(events: events)
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        let now = Date()
        // Determine a single target using preferred search order:
        // 1) first non-all-day upcoming/in-progress event
        // 2) first all-day event
        // 3) last event (fallback)
        let nonAllDayUpcoming = filteredEvents.first(where: { !$0.isAllDay && $0.end > now })
        let firstAllDay = filteredEvents.first(where: { $0.isAllDay })
        let lastEvent = filteredEvents.last
        guard let target = nonAllDayUpcoming ?? firstAllDay ?? lastEvent else { return }

        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredEvents) { event in
                    Button(action: {
                        if let url = event.calendarAppURL() {
                            openURL(url)
                        }
                    }) {
                        eventRow(event)
                    }
                    .id(event.id)
                    .padding(.leading, -5)
                    .buttonStyle(PlainButtonStyle())
                    .listRowSeparator(.automatic)
                    .listRowSeparatorTint(.gray.opacity(0.2))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onAppear {
                scrollToRelevantEvent(proxy: proxy)
            }
            .onChange(of: filteredEvents) { _, _ in
                scrollToRelevantEvent(proxy: proxy)
            }
        }
        Spacer(minLength: 0)
    }

    private func eventRow(_ event: EventModel) -> some View {
        HStack(alignment: .top, spacing: 4) {
                    Rectangle()
                        .fill(Color(event.calendar.color))
                        .frame(width: 3)
                        .cornerRadius(1.5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 2)

                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.caption2)
                                .foregroundColor(Color(white: 0.65))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        if event.isAllDay {
                            Text("All-day")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        } else {
                            Text(event.start, style: .time)
                                .foregroundColor(.white)
                            Text(event.end, style: .time)
                                .foregroundColor(Color(white: 0.65))
                        }
                    }
                    .font(.caption2)
                    .frame(minWidth: 44, alignment: .trailing)
                }
                .opacity(
                    event.eventStatus == .ended && Calendar.current.isDateInToday(event.start)
                        ? 0.6 : 1.0)
    }
}

#Preview {
    CalendarView(
        notchAlertCoordinator: NotchAlertCoordinator(
            dismissedStore: DismissedNotchAlertsStore(
                storageFileURL: URL(fileURLWithPath: "/tmp/preview-dismissed-notch-alerts.json")
            ),
            evaluator: BrowserSubagentManager()
        )
    )
    .frame(width: 215, height: 130)
    .background(.black)
    .environmentObject(ViewModel())
}
