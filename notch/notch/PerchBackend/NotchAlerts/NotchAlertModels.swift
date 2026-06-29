//
//  NotchAlertModels.swift
//  notch
//
//  Shared models for the agent-driven notch alert pipeline: raw candidates
//  gathered from integrations, and the compact alert surface the evaluator
//  returns for display in the open-notch home row.
//

import Foundation

// MARK: - Character limits (enforced in Python + Swift UI)

enum NotchAlertCopyLimits {
    static let headerMaxCharacters = 32
    static let subheaderMaxCharacters = 56
    static let buttonLabelMaxCharacters = 28
}

// MARK: - Ingestion candidate

struct NotchAlertCandidate: Codable, Equatable, Sendable {
    let sourceFingerprint: String
    let provider: String
    let title: String
    let subtitle: String?
    let detail: String?
    let url: String?
    let timestamp: String?
    let calendarName: String?

    func asDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "sourceFingerprint": sourceFingerprint,
            "provider": provider,
            "title": title,
        ]
        if let subtitle { dictionary["subtitle"] = subtitle }
        if let detail { dictionary["detail"] = detail }
        if let url { dictionary["url"] = url }
        if let timestamp { dictionary["timestamp"] = timestamp }
        if let calendarName { dictionary["calendarName"] = calendarName }
        return dictionary
    }
}

// MARK: - Evaluated alert

struct NotchAlert: Codable, Equatable, Identifiable {
    let alertId: String
    let sourceFingerprint: String
    let header: String
    let subheader: String
    let buttonLabel: String
    let action: NotchAlertAction

    var id: String { alertId }

    static func fromDictionary(_ raw: [String: Any]) -> NotchAlert? {
        guard let alertId = raw["alertId"] as? String,
              let sourceFingerprint = raw["sourceFingerprint"] as? String,
              let header = raw["header"] as? String,
              let subheader = raw["subheader"] as? String,
              let buttonLabel = raw["buttonLabel"] as? String,
              let actionRaw = raw["action"] as? [String: Any],
              let action = NotchAlertAction.fromDictionary(actionRaw)
        else { return nil }

        return NotchAlert(
            alertId: alertId,
            sourceFingerprint: sourceFingerprint,
            header: String(header.prefix(NotchAlertCopyLimits.headerMaxCharacters)),
            subheader: String(subheader.prefix(NotchAlertCopyLimits.subheaderMaxCharacters)),
            buttonLabel: String(buttonLabel.prefix(NotchAlertCopyLimits.buttonLabelMaxCharacters)),
            action: action
        )
    }
}

// MARK: - Agent-chosen action (not a hardcoded alert type)

struct NotchAlertAction: Codable, Equatable {
    let kind: String
    let payload: String

    static func fromDictionary(_ raw: [String: Any]) -> NotchAlertAction? {
        guard let kind = raw["kind"] as? String,
              let payload = raw["payload"] as? String,
              !kind.isEmpty,
              !payload.isEmpty
        else { return nil }
        return NotchAlertAction(kind: kind, payload: payload)
    }
}