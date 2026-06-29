//
//  PerchAnalytics.swift
//  notch (ported from leanring-buddy)
//
//  No-op analytics shim. The original was a PostHog wrapper; PostHog is a 3rd-party SPM
//  package the notch host doesn't bundle, and analytics is non-essential to the
//  ported backend — so every method here is a no-op that preserves the exact call surface
//  the backend uses. Wire up a real provider later by filling these in (and adding the SDK).
//

import Foundation

enum PerchAnalytics {

    // MARK: - Setup
    static func configure() {}

    // MARK: - App Lifecycle
    static func trackAppOpened() {}

    // MARK: - Onboarding
    static func trackOnboardingStarted() {}
    static func trackOnboardingReplayed() {}
    static func trackOnboardingVideoCompleted() {}
    static func trackOnboardingDemoTriggered() {}

    // MARK: - Permissions
    static func trackAllPermissionsGranted() {}
    static func trackPermissionGranted(permission: String) {}

    // MARK: - Voice Interaction
    static func trackPushToTalkStarted() {}
    static func trackPushToTalkReleased() {}
    static func trackUserMessageSent(transcript: String) {}
    static func trackAIResponseReceived(response: String) {}
    static func trackElementPointed(elementLabel: String?) {}

    // MARK: - Errors
    static func trackResponseError(error: String) {}
    static func trackTTSError(error: String) {}

    // MARK: - Identity (was PostHog identify)
    /// No-op stand-in for the former PostHog `identify`. Kept so the email-submit path
    /// compiles unchanged.
    static func identify(_ distinctId: String, userProperties: [String: Any]? = nil) {}
}
