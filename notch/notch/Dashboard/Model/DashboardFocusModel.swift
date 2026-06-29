//
//  DashboardFocusModel.swift
//  leanring-buddy
//
//  The brain of the Focus widget: a real countdown timer the user can start, pause, and
//  reset. The widget's ring and readout render straight from this state. The chosen
//  session length is persisted (`support/dashboard/focus.json`) so it survives a relaunch;
//  the in-flight countdown itself is deliberately ephemeral (a relaunch starts fresh).
//
//  Main-actor and async/await: the per-second tick is a cancellable `Task` loop rather
//  than an AppKit `Timer`, so it stays on the main actor and cleans up on pause/reset/deinit.
//

import Foundation

/// The Codable on-disk shape — just the user's preferred session length.
private struct DashboardFocusPreferences: Codable, Equatable {
    var totalSeconds: Int
}

@MainActor
final class DashboardFocusModel: ObservableObject {

    /// Shared so the dashboard window and (later) the agent path drive the same timer.
    static let shared = DashboardFocusModel()

    /// The full session length in seconds (the user's chosen duration; default 25 min).
    @Published private(set) var totalSeconds: Int
    /// Seconds left in the current session. Counts down to zero while running.
    @Published private(set) var remainingSeconds: Int
    /// Whether the countdown is actively ticking.
    @Published private(set) var isRunning: Bool = false

    private let storageFileURL: URL
    /// The cancellable per-second tick; non-nil only while running.
    private var tickTask: Task<Void, Never>?

    /// Default Pomodoro-style session length when nothing is persisted yet.
    private static let defaultTotalSeconds = 25 * 60

    init() {
        storageFileURL = PerchSupportPaths
            .directory("dashboard")
            .appendingPathComponent("focus.json")
        let persistedTotal = Self.load(from: storageFileURL)?.totalSeconds ?? Self.defaultTotalSeconds
        totalSeconds = persistedTotal
        remainingSeconds = persistedTotal
    }

    deinit {
        tickTask?.cancel()
    }

    // MARK: Derived display state

    /// Fraction of the session still remaining (1 at the start, 0 at the end). The ring
    /// trims `0...progress` so it visibly depletes as the session runs down.
    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, Double(remainingSeconds) / Double(totalSeconds)))
    }

    /// `mm:ss` readout of the time left.
    var readout: String {
        let clampedRemaining = max(0, remainingSeconds)
        return String(format: "%02d:%02d", clampedRemaining / 60, clampedRemaining % 60)
    }

    /// The label for the start/pause call-to-action, reflecting the current state.
    var callToActionLabel: String {
        if isRunning { return "Pause" }
        if remainingSeconds == totalSeconds { return "Begin a session" }
        if remainingSeconds == 0 { return "Start again" }
        return "Resume"
    }

    // MARK: Controls

    /// Start or resume the countdown. Tapping the CTA while running pauses instead.
    func start() {
        guard !isRunning else { return }
        // A finished session restarts from the top rather than sitting at 0.
        if remainingSeconds <= 0 { remainingSeconds = totalSeconds }
        isRunning = true
        startTicking()
    }

    /// Pause the countdown, holding the remaining time in place.
    func pause() {
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
    }

    /// Toggle between running and paused — the Focus widget's single tappable control.
    func toggle() {
        isRunning ? pause() : start()
    }

    /// Stop and refill the timer back to a full session.
    func reset() {
        pause()
        remainingSeconds = totalSeconds
    }

    /// Choose a new session length (persisted). Resets a not-yet-started timer to the new
    /// full length; leaves an in-flight countdown's remaining time alone.
    func setTotalSeconds(_ newTotalSeconds: Int) {
        let clampedTotal = max(60, newTotalSeconds)
        guard clampedTotal != totalSeconds else { return }
        let wasAtFullSession = !isRunning && remainingSeconds == totalSeconds
        totalSeconds = clampedTotal
        if wasAtFullSession { remainingSeconds = clampedTotal }
        persistPreferences()
    }

    // MARK: Tick loop

    private func startTicking() {
        tickTask?.cancel()
        // The model is @MainActor, so this Task inherits the main actor — the per-second
        // decrement runs on the main thread without an extra hop.
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1s
                guard !Task.isCancelled else { return }
                self?.advanceOneSecond()
            }
        }
    }

    /// One tick: decrement, and stop cleanly when the session reaches zero.
    private func advanceOneSecond() {
        guard isRunning else { return }
        if remainingSeconds <= 1 {
            remainingSeconds = 0
            pause()
        } else {
            remainingSeconds -= 1
        }
    }

    // MARK: Persistence (chosen duration only)

    private func persistPreferences() {
        let preferences = DashboardFocusPreferences(totalSeconds: totalSeconds)
        do {
            try FileManager.default.createDirectory(
                at: storageFileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preferences).write(to: storageFileURL, options: .atomic)
        } catch {
            NSLog("[Dashboard] Failed to persist focus preferences: \(error.localizedDescription)")
        }
    }

    private static func load(from fileURL: URL) -> DashboardFocusPreferences? {
        guard let storedData = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DashboardFocusPreferences.self, from: storedData)
    }
}
