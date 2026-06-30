//
//  PerchEntitlement.swift
//  notch
//
//  The app-side mirror of the Worker's entitlement response: the account's plan
//  plus this month's usage and remaining allowance per feature. The Worker is the
//  source of truth and enforcer; this is a read-only snapshot the UI uses to show
//  plan state and an "approaching your free limit" nudge before the Worker gates.
//
//  Decoded from /register, /account/verify-confirm, and /account/entitlement.
//

import Foundation

/// The metered features. Raw values match the `X-Perch-Feature` header the app
/// sends and the `feature` keys in the Worker's caps/usage maps.
enum PerchFeature: String, CaseIterable {
    case dailyBrief = "daily_brief"
    case agentRun = "agent_run"
    case companion = "companion"
    case tts = "tts"
}

/// A read-only snapshot of the account's plan and usage. `caps`, `usage`, and
/// `remaining` are keyed by the `PerchFeature` raw value; missing keys read as 0.
struct PerchEntitlement: Codable, Equatable {
    let plan: String                  // "free" | "pro"
    let accountId: String?
    let email: String?
    let emailVerified: Bool
    let caps: [String: Int]
    let usage: [String: Int]
    let remaining: [String: Int]

    /// The free-plan default used before the first network response (so the UI
    /// never has to handle a nil entitlement).
    static let free = PerchEntitlement(
        plan: "free",
        accountId: nil,
        email: nil,
        emailVerified: false,
        caps: [:],
        usage: [:],
        remaining: [:]
    )

    var isPro: Bool { plan == "pro" }

    func remaining(for feature: PerchFeature) -> Int {
        remaining[feature.rawValue] ?? 0
    }

    func cap(for feature: PerchFeature) -> Int {
        caps[feature.rawValue] ?? 0
    }

    /// True when the user is at or over the free limit for a feature — the cue to
    /// surface an upgrade nudge. Always false on pro.
    func isAtLimit(for feature: PerchFeature) -> Bool {
        !isPro && remaining(for: feature) <= 0
    }
}
