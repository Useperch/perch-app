//
//  SystemFocusStatusMonitor.swift
//  notch
//
//  Reads macOS Focus / Do Not Disturb from the system (not a Perch setting).
//  When the user is focused, notch alerts are suppressed entirely.
//

import Combine
import Foundation
import Intents

@MainActor
final class SystemFocusStatusMonitor: ObservableObject {

    @Published private(set) var isFocusActive: Bool = false

    private let focusStatusCenter = INFocusStatusCenter.default
    private var pollTimer: Timer?

    func start() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFocusStatus()
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
        refreshFocusStatus()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refreshFocusStatus() {
        // Best-effort: if Focus-status sharing was never authorized, isFocused is
        // nil and we treat that as "not focused" so alerts still work.
        isFocusActive = focusStatusCenter.focusStatus.isFocused == true
    }
}