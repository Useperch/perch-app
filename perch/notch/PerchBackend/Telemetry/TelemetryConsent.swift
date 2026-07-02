//
//  TelemetryConsent.swift
//  notch
//
//  The single gate that decides whether traces may be uploaded to the central
//  backend. Three conditions must ALL hold:
//
//    1. Local opt-in — the "Share diagnostics" switch (default OFF; privacy-
//       respecting opt-in, unlike the abilities which default ON).
//    2. Not the dev/eval kill switch — PERCH_RUN_LOG_DISABLED (when set there
//       are no local traces either, so there is nothing to ship).
//    3. Server kill switch — the owner's per-install `tracingEnabled` flag from
//       /register (read via PerchInstallIdentity.isServerTracingEnabled()).
//
//  This is read from the uploaders, which run off the main actor, so every
//  accessor is `nonisolated` and backed by thread-safe UserDefaults.
//

import Foundation

enum TelemetryConsent {
    /// UserDefaults key for the local opt-in. Namespaced like the capability toggles.
    static let shareDiagnosticsKey = "perch.telemetry.shareDiagnostics.enabled"

    /// The local opt-in switch. Defaults OFF — uploads only happen after the user
    /// explicitly turns diagnostics sharing on.
    nonisolated static func isLocallyEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: shareDiagnosticsKey)
    }

    nonisolated static func setLocallyEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: shareDiagnosticsKey)
    }

    /// The dev/eval kill switch: when PERCH_RUN_LOG_DISABLED is set, PerchRunLog
    /// writes nothing, so there is no trace to upload.
    nonisolated static var isRunLogDisabled: Bool {
        ProcessInfo.processInfo.environment["PERCH_RUN_LOG_DISABLED"] != nil
    }

    /// Whether a trace may be uploaded right now — all three conditions hold.
    nonisolated static func isUploadAllowed() -> Bool {
        !isRunLogDisabled
            && isLocallyEnabled()
            && PerchInstallIdentity.isServerTracingEnabled()
    }
}
