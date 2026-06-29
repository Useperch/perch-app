//
//  WorkflowDebugLog.swift
//  leanring-buddy
//
//  TEMPORARY demo-time diagnostic. Appends one line per captured workflow event
//  (and per fired offer) to
//  ~/Library/Application Support/Perch/workflow-debug.log so the live capture
//  pipeline can be verified during a dry run before filming. Logs only event
//  *shapes* (app + action + whether content was present) — never raw clipboard
//  or keystroke contents.
//
//  Remove this file (and the `WorkflowDebugLog.log(...)` call sites in
//  LiveEventSource.swift and WorkflowCaptureManager.swift) once the trigger is
//  confirmed working for the demo.
//

import Foundation

enum WorkflowDebugLog {

    private static let logFileURL: URL = PerchSupportPaths.file("workflow-debug.log")

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// Set by the check-workflow-detector harness so fixture runs don't append
    /// fake "OFFER FIRED" lines into the real app's diagnostic log.
    private static let isDisabledByEnvironment =
        ProcessInfo.processInfo.environment["CLICKY_WORKFLOW_DEBUG_LOG_DISABLED"] != nil

    static func log(_ message: String) {
        guard !isDisabledByEnvironment else { return }
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
