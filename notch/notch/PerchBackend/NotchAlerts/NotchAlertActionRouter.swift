//
//  NotchAlertActionRouter.swift
//  notch
//
//  Routes an agent-chosen notch alert action to the correct Perch lane.
//

import AppKit
import Foundation

@MainActor
enum NotchAlertActionRouter {

    static func perform(
        action: NotchAlertAction,
        companionManager: CompanionManager,
        browserSubagentManager: BrowserSubagentManager,
        coordinator: NotchAlertCoordinator
    ) {
        switch action.kind {
        case "openURL":
            if let url = URL(string: action.payload) {
                NSWorkspace.shared.open(url)
            }
        case "voicePrompt":
            companionManager.sendTypedMessage(action.payload)
        case "backgroundTask":
            Task {
                await browserSubagentManager.startTask(action.payload)
            }
        case "dashboardRequest":
            NotificationCenter.default.post(name: .perchRevealDashboard, object: nil)
            Task {
                await browserSubagentManager.startTask(
                    "On my own Daily Dashboard: \(action.payload)"
                )
            }
        default:
            NSLog("[NotchAlert] unknown action kind: \(action.kind)")
        }

        coordinator.handleActionCompleted()
    }
}