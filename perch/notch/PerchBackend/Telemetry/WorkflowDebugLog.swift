//
//  WorkflowDebugLog.swift
//  Perch
//
//  Developer diagnostic for the workflow-capture pipeline. Appends one line per
//  captured workflow event (and per fired offer) to `workflow-debug.log` in the
//  support directory so the live capture pipeline can be verified during a dry
//  run. Logs only event *shapes* (app + action + whether content was present) —
//  never raw clipboard or keystroke contents.
//
//  OFF by default so a shipping build never writes diagnostics on every event.
//  Opt in for local debugging by setting the `PERCH_DEBUG_LOGS` env var.
//

import Foundation

enum WorkflowDebugLog {

    private static let logFileURL: URL = PerchSupportPaths.file("workflow-debug.log")

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// OFF by default. Enabled only when `PERCH_DEBUG_LOGS` is set — and never when
    /// `PERCH_WORKFLOW_DEBUG_LOG_DISABLED` is set (the check-workflow-detector
    /// harness sets it so fixture runs don't append fake "OFFER FIRED" lines).
    private static let isEnabled: Bool = {
        if ProcessInfo.processInfo.environment["PERCH_WORKFLOW_DEBUG_LOG_DISABLED"] != nil {
            return false
        }
        return ProcessInfo.processInfo.environment["PERCH_DEBUG_LOGS"] != nil
    }()

    static func log(_ message: String) {
        guard isEnabled else { return }
        let line = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logFileURL)
        }
    }
}
